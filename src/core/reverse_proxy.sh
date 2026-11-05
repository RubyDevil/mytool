#!/usr/bin/env bash

reverse_proxy_core_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if ! declare -p settings &>/dev/null; then
   # shellcheck source=../lib/settings.sh
   source "$reverse_proxy_core_dir/../lib/settings.sh"
fi
unset reverse_proxy_core_dir

declare -gA reverse_proxy_destinations=()
declare -gA reverse_proxy_files=()
# domain -> "certificate<TAB>key" for domains served over HTTPS; absent for HTTP only.
declare -gA reverse_proxy_tls=()
# Directory Nginx serves for ACME HTTP-01 challenges (certbot --webroot).
reverse_proxy_acme_webroot=/var/www/html

reverse_proxy_run_config_command() {
   local directory="${settings[NGINX_CONFIG_DIR]}"

   if [[ -w "$directory" ]] || ((EUID == 0)); then
      "$@"
   else
      sudo -- "$@"
   fi
}

reverse_proxy_ensure_config_directory() {
   local directory="${settings[NGINX_CONFIG_DIR]}"
   local parent_directory

   [[ -d "$directory" ]] && return 0
   parent_directory=$(dirname -- "$directory")
   if [[ -w "$parent_directory" ]] || ((EUID == 0)); then
      mkdir -p -- "$directory"
   else
      sudo -- mkdir -p -- "$directory"
   fi
}

reverse_proxy_validate_domain() {
   local domain="${1-}"
   [[ -n "$domain" ]] && ((${#domain} <= 253)) &&
      [[ "$domain" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]
}

reverse_proxy_validate_port() {
   local port="${1-}"
   [[ "$port" =~ ^[0-9]{1,5}$ ]] && ((10#$port >= 1 && 10#$port <= 65535))
}

# A destination is host[:port], where host is a domain, an IPv4 address or a
# bracketed IPv6 address. Without a port, Nginx uses the default HTTP port.
reverse_proxy_validate_destination() {
   local destination="${1-}"
   local host port=""

   if [[ "$destination" =~ ^\[([0-9A-Fa-f:.]+)\](:([0-9]+))?$ ]]; then
      port="${BASH_REMATCH[3]}"
      [[ "${BASH_REMATCH[1]}" == *:* ]] || return 1
   elif [[ "$destination" =~ ^([^:]+)(:([0-9]+))?$ ]]; then
      host="${BASH_REMATCH[1]}"
      port="${BASH_REMATCH[3]}"
      reverse_proxy_validate_domain "$host" || return 1
   else
      return 1
   fi

   [[ -z "$port" ]] || reverse_proxy_validate_port "$port"
}

# A certificate/key path is interpolated into an Nginx config, so allow only a
# conservative absolute-path character set with no traversal components.
reverse_proxy_validate_tls_path() {
   local path="${1-}"
   [[ -n "$path" ]] && ((${#path} <= 4096)) &&
      [[ "$path" =~ ^/[A-Za-z0-9._/@+-]+$ ]] &&
      [[ "$path" != *'/../'* && "$path" != */.. ]]
}

reverse_proxy_default_certificate_path() {
   reverse_proxy_validate_domain "$1" || return 2
   printf '/etc/letsencrypt/live/%s/fullchain.pem' "$1"
}

reverse_proxy_default_certificate_key_path() {
   reverse_proxy_validate_domain "$1" || return 2
   printf '/etc/letsencrypt/live/%s/privkey.pem' "$1"
}

reverse_proxy_config_path() {
   local domain="$1"
   reverse_proxy_validate_domain "$domain" || return 2
   printf '%s/%s.conf' "${settings[NGINX_CONFIG_DIR]}" "$domain"
}

reverse_proxy_parse_config() {
   local file="$1"
   local domain destination certificate certificate_key

   domain=$(awk '
      $1 == "server_name" {
         value = $2
         sub(/;.*/, "", value)
         print value
         exit
      }
   ' "$file")
   destination=$(awk '
      /^[[:space:]]*proxy_pass[[:space:]]+http:\/\/[^[:space:];\/]+[[:space:]]*;/ {
         value = $0
         sub(/^[[:space:]]*proxy_pass[[:space:]]+http:\/\//, "", value)
         sub(/[[:space:]]*;.*$/, "", value)
         print value
         exit
      }
   ' "$file")

   certificate=$(awk '
      $1 == "ssl_certificate" {
         value = $2
         sub(/;.*/, "", value)
         print value
         exit
      }
   ' "$file")
   certificate_key=$(awk '
      $1 == "ssl_certificate_key" {
         value = $2
         sub(/;.*/, "", value)
         print value
         exit
      }
   ' "$file")

   reverse_proxy_validate_domain "$domain" || return 1
   reverse_proxy_validate_destination "$destination" || return 1
   if [[ -n "$certificate" || -n "$certificate_key" ]]; then
      reverse_proxy_validate_tls_path "$certificate" || return 1
      reverse_proxy_validate_tls_path "$certificate_key" || return 1
   else
      certificate=- certificate_key=-
   fi
   # Fields are never empty so that a tab-delimited read keeps them aligned.
   printf '%s	%s	%s	%s' "$domain" "$destination" "$certificate" "$certificate_key"
}

reverse_proxy_load_configs() {
   local directory="${settings[NGINX_CONFIG_DIR]}"
   local file parsed domain destination certificate certificate_key
   local -a files=()
   local -i status=0
   local nullglob_was_set=0

   reverse_proxy_destinations=()
   reverse_proxy_files=()
   reverse_proxy_tls=()

   if [[ ! -d "$directory" ]]; then
      printf 'Nginx configuration directory does not exist: %s\n' "$directory" >&2
      return 1
   fi

   shopt -q nullglob && nullglob_was_set=1
   shopt -s nullglob
   files=("$directory"/*.conf)
   ((nullglob_was_set)) || shopt -u nullglob

   for file in "${files[@]}"; do
      if ! parsed=$(reverse_proxy_parse_config "$file"); then
         printf 'Ignoring unsupported Nginx configuration: %s\n' "$file" >&2
         status=1
         continue
      fi

      IFS=$'	' read -r domain destination certificate certificate_key <<<"$parsed"
      reverse_proxy_destinations["$domain"]="$destination"
      reverse_proxy_files["$domain"]="$file"
      if [[ "$certificate" != - ]]; then
         reverse_proxy_tls["$domain"]="$certificate"$'\t'"$certificate_key"
      fi
   done

   return "$status"
}

reverse_proxy_render_config() {
   local domain="$1"
   local destination="$2"
   local certificate="${3-}"
   local certificate_key="${4-}"
   local acme_bootstrap="${5-}"

   reverse_proxy_validate_domain "$domain" || return 2
   reverse_proxy_validate_destination "$destination" || return 2

   if [[ -n "$certificate" || -n "$certificate_key" ]]; then
      reverse_proxy_validate_tls_path "$certificate" || return 2
      reverse_proxy_validate_tls_path "$certificate_key" || return 2

      printf 'server {\n'
      printf '    listen 80;\n'
      printf '    server_name %s;\n' "$domain"
      printf '\n'
      printf '    location /.well-known/acme-challenge/ {\n'
      printf '        root %s;\n' "$reverse_proxy_acme_webroot"
      printf '    }\n'
      printf '\n'
      printf '    location / {\n'
      printf '        return 301 https://$host$request_uri;\n'
      printf '    }\n'
      printf '}\n'
      printf '\n'
      printf 'server {\n'
      printf '    listen 443 ssl;\n'
      printf '    server_name %s;\n' "$domain"
      printf '\n'
      printf '    ssl_certificate %s;\n' "$certificate"
      printf '    ssl_certificate_key %s;\n' "$certificate_key"
   else
      printf 'server {\n'
      printf '    listen 80;\n'
      printf '    server_name %s;\n' "$domain"
      if [[ "$acme_bootstrap" == acme ]]; then
         printf '\n'
         printf '    location /.well-known/acme-challenge/ {\n'
         printf '        root %s;\n' "$reverse_proxy_acme_webroot"
         printf '    }\n'
      fi
   fi
   printf '\n'
   printf '    location / {\n'
   printf '        proxy_pass http://%s;\n' "$destination"
   printf '        proxy_set_header Host $host;\n'
   printf '        proxy_set_header X-Real-IP $remote_addr;\n'
   printf '        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n'
   printf '        proxy_set_header X-Forwarded-Proto $scheme;\n'
   printf '    }\n'
   printf '}\n'
}

reverse_proxy_save_config() {
   local domain="$1"
   local destination="$2"
   local certificate="${3-}"
   local certificate_key="${4-}"
   local acme_bootstrap="${5-}"
   local directory="${settings[NGINX_CONFIG_DIR]}"
   local config_file temporary_file privileged_temporary_file

   reverse_proxy_validate_domain "$domain" || {
      printf 'Invalid domain: %s\n' "$domain" >&2
      return 2
   }
   reverse_proxy_validate_destination "$destination" || {
      printf 'Invalid destination: %s\n' "$destination" >&2
      return 2
   }
   if [[ -n "$certificate" || -n "$certificate_key" ]]; then
      reverse_proxy_validate_tls_path "$certificate" &&
         reverse_proxy_validate_tls_path "$certificate_key" || {
         printf 'Invalid certificate or key path.\n' >&2
         return 2
      }
   fi
   reverse_proxy_ensure_config_directory || return 1

   config_file=$(reverse_proxy_config_path "$domain") || return
   temporary_file=$(mktemp) || return 1
   if ! (umask 022; reverse_proxy_render_config "$domain" "$destination" "$certificate" "$certificate_key" "$acme_bootstrap" >"$temporary_file"); then
      rm -f -- "$temporary_file"
      return 1
   fi
   privileged_temporary_file=$(reverse_proxy_run_config_command mktemp "$directory/.mytool.${domain}.XXXXXX") || {
      rm -f -- "$temporary_file"
      return 1
   }
   if ! reverse_proxy_run_config_command install -m 644 -- "$temporary_file" "$privileged_temporary_file" ||
      ! reverse_proxy_run_config_command mv -f -- "$privileged_temporary_file" "$config_file"; then
      reverse_proxy_run_config_command rm -f -- "$privileged_temporary_file" || true
      rm -f -- "$temporary_file"
      return 1
   fi
   rm -f -- "$temporary_file"
}

reverse_proxy_delete_config() {
   local config_file
   config_file=$(reverse_proxy_config_path "$1") || return
   rm -f -- "$config_file"
}

reverse_proxy_reload_nginx() {
   if ! command -v nginx >/dev/null; then
      printf 'nginx is not installed or is not in PATH.\n' >&2
      return 1
   fi
   if ! command -v systemctl >/dev/null; then
      printf 'systemctl is not installed or is not in PATH.\n' >&2
      return 1
   fi

   if ((EUID == 0)); then
      nginx -t && systemctl reload nginx
   else
      sudo -- nginx -t && sudo -- systemctl reload nginx
   fi
}

reverse_proxy_apply_config() {
   local domain="$1"
   local destination="$2"
   local certificate="${3-}"
   local certificate_key="${4-}"
   local acme_bootstrap="${5-}"
   local config_file backup_file=""

   config_file=$(reverse_proxy_config_path "$domain") || return
   if [[ -f "$config_file" ]]; then
      backup_file=$(mktemp) || return 1
      cp -p -- "$config_file" "$backup_file" || {
         rm -f -- "$backup_file"
         return 1
      }
   fi

   if ! reverse_proxy_save_config "$domain" "$destination" "$certificate" "$certificate_key" "$acme_bootstrap"; then
      [[ -n "$backup_file" ]] && rm -f -- "$backup_file"
      return 1
   fi

   if ! reverse_proxy_reload_nginx; then
      if [[ -n "$backup_file" ]]; then
         mv -f -- "$backup_file" "$config_file"
      else
         rm -f -- "$config_file"
      fi
      reverse_proxy_reload_nginx &>/dev/null || true
      return 1
   fi

   [[ -n "$backup_file" ]] && rm -f -- "$backup_file"
   reverse_proxy_destinations["$domain"]="$destination"
   reverse_proxy_files["$domain"]="$config_file"
   if [[ -n "$certificate" ]]; then
      reverse_proxy_tls["$domain"]="$certificate"$'\t'"$certificate_key"
   else
      unset 'reverse_proxy_tls[$domain]'
   fi
}

reverse_proxy_remove_config() {
   local domain="$1"
   local config_file temporary_file

   config_file=$(reverse_proxy_config_path "$domain") || return
   [[ -f "$config_file" ]] || return 0
   temporary_file=$(mktemp "${config_file}.deleted.XXXXXX") || return 1
   rm -f -- "$temporary_file"
   mv -- "$config_file" "$temporary_file" || return 1

   if ! reverse_proxy_reload_nginx; then
      mv -- "$temporary_file" "$config_file"
      reverse_proxy_reload_nginx &>/dev/null || true
      return 1
   fi

   rm -f -- "$temporary_file"
   unset 'reverse_proxy_destinations[$domain]'
   unset 'reverse_proxy_files[$domain]'
   unset 'reverse_proxy_tls[$domain]'
}

# Validates the optional contact address passed to certbot (never written to a config).
reverse_proxy_validate_email() {
   local email="${1-}"
   [[ -z "$email" ]] || {
      ((${#email} <= 254)) && [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
   }
}

reverse_proxy_run_certbot() {
   local domain="$1"
   local email="${2-}"
   local -a arguments=(
      certonly --webroot -w "$reverse_proxy_acme_webroot" -d "$domain"
      --non-interactive --agree-tos --keep-until-expiring
   )

   if [[ -n "$email" ]]; then
      arguments+=(--email "$email")
   else
      arguments+=(--register-unsafely-without-email)
   fi

   if ((EUID == 0)); then
      certbot "${arguments[@]}"
   else
      sudo -- certbot "${arguments[@]}"
   fi
}

reverse_proxy_ensure_acme_webroot() {
   local parent_directory

   [[ -d "$reverse_proxy_acme_webroot" ]] && return 0
   parent_directory=$(dirname -- "$reverse_proxy_acme_webroot")
   if [[ -w "$parent_directory" ]] || ((EUID == 0)); then
      mkdir -p -- "$reverse_proxy_acme_webroot"
   else
      sudo -- mkdir -p -- "$reverse_proxy_acme_webroot"
   fi
}

# Restores the pre-certbot state of a domain's config (or removes it when there
# was none), reloads Nginx and refreshes the cache from disk.
reverse_proxy_restore_config() {
   local config_file="$1"
   local backup_file="${2-}"

   if [[ -n "$backup_file" ]]; then
      reverse_proxy_run_config_command mv -f -- "$backup_file" "$config_file"
   else
      reverse_proxy_run_config_command rm -f -- "$config_file"
   fi
   reverse_proxy_reload_nginx &>/dev/null || true
   reverse_proxy_load_configs &>/dev/null || true
}

# Serves the domain over HTTPS with a free Let's Encrypt certificate:
#  1. apply an HTTP config that answers ACME challenges, 2. run certbot,
#  3. apply the final HTTPS config. Any failure restores the previous config.
reverse_proxy_apply_config_with_certbot() {
   local domain="$1"
   local destination="$2"
   local email="${3-}"
   local config_file backup_file=""

   config_file=$(reverse_proxy_config_path "$domain") || return
   reverse_proxy_validate_destination "$destination" || return 2
   reverse_proxy_validate_email "$email" || {
      printf 'Invalid email address: %s\n' "$email" >&2
      return 2
   }
   if ! command -v certbot >/dev/null; then
      printf 'certbot is not installed. Install it first (for example: sudo apt install certbot).\n' >&2
      return 1
   fi
   reverse_proxy_ensure_acme_webroot || return 1

   if [[ -f "$config_file" ]]; then
      backup_file=$(mktemp) || return 1
      cp -p -- "$config_file" "$backup_file" || {
         rm -f -- "$backup_file"
         return 1
      }
   fi

   if ! reverse_proxy_apply_config "$domain" "$destination" '' '' acme; then
      [[ -n "$backup_file" ]] && rm -f -- "$backup_file"
      return 1
   fi
   if ! reverse_proxy_run_certbot "$domain" "$email"; then
      printf 'certbot could not issue a certificate. Check that the domain points at this server and port 80 is reachable.\n' >&2
      reverse_proxy_restore_config "$config_file" "$backup_file"
      return 1
   fi
   if ! reverse_proxy_apply_config "$domain" "$destination" \
      "$(reverse_proxy_default_certificate_path "$domain")" \
      "$(reverse_proxy_default_certificate_key_path "$domain")"; then
      reverse_proxy_restore_config "$config_file" "$backup_file"
      return 1
   fi

   [[ -n "$backup_file" ]] && rm -f -- "$backup_file"
   return 0
}
