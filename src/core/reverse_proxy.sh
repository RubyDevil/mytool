#!/usr/bin/env bash

reverse_proxy_core_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if ! declare -p settings &>/dev/null; then
   # shellcheck source=../lib/settings.sh
   source "$reverse_proxy_core_dir/../lib/settings.sh"
fi
unset reverse_proxy_core_dir

declare -gA domains_and_ports=()
declare -gA reverse_proxy_files=()

reverse_proxy_validate_domain() {
   local domain="${1-}"
   ((${#domain} <= 253)) &&
      [[ "$domain" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]
}

reverse_proxy_validate_port() {
   local port="${1-}"
   [[ "$port" =~ ^[0-9]{1,5}$ ]] && ((10#$port >= 1 && 10#$port <= 65535))
}

reverse_proxy_config_path() {
   local domain="$1"
   reverse_proxy_validate_domain "$domain" || return 2
   printf '%s/%s.conf' "${settings[NGINX_CONFIG_DIR]}" "$domain"
}

reverse_proxy_parse_config() {
   local file="$1"
   local domain port

   domain=$(awk '
      $1 == "server_name" {
         value = $2
         sub(/;.*/, "", value)
         print value
         exit
      }
   ' "$file")
   port=$(awk '
      /^[[:space:]]*proxy_pass[[:space:]]+http:\/\/(localhost|127\.[0-9]+\.[0-9]+\.[0-9]+):[0-9]+[[:space:]]*;/ {
         value = $0
         sub(/^.*:/, "", value)
         sub(/[;[:space:]].*$/, "", value)
         print value
         exit
      }
   ' "$file")

   reverse_proxy_validate_domain "$domain" || return 1
   reverse_proxy_validate_port "$port" || return 1
   printf '%s\t%s' "$domain" "$port"
}

reverse_proxy_load_configs() {
   local directory="${settings[NGINX_CONFIG_DIR]}"
   local file parsed domain port
   local -a files=()
   local -i status=0
   local nullglob_was_set=0

   domains_and_ports=()
   reverse_proxy_files=()

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

      IFS=$'\t' read -r domain port <<<"$parsed"
      domains_and_ports["$domain"]="$port"
      reverse_proxy_files["$domain"]="$file"
   done

   return "$status"
}

reverse_proxy_render_config() {
   local domain="$1"
   local port="$2"

   reverse_proxy_validate_domain "$domain" || return 2
   reverse_proxy_validate_port "$port" || return 2

   printf 'server {\n'
   printf '    listen 80;\n'
   printf '    server_name %s;\n' "$domain"
   printf '\n'
   printf '    location / {\n'
   printf '        proxy_pass http://localhost:%s;\n' "$port"
   printf '        proxy_set_header Host $host;\n'
   printf '        proxy_set_header X-Real-IP $remote_addr;\n'
   printf '        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n'
   printf '        proxy_set_header X-Forwarded-Proto $scheme;\n'
   printf '    }\n'
   printf '}\n'
}

reverse_proxy_save_config() {
   local domain="$1"
   local port="$2"
   local directory="${settings[NGINX_CONFIG_DIR]}"
   local config_file temporary_file

   reverse_proxy_validate_domain "$domain" || {
      printf 'Invalid domain: %s\n' "$domain" >&2
      return 2
   }
   reverse_proxy_validate_port "$port" || {
      printf 'Invalid port: %s\n' "$port" >&2
      return 2
   }
   [[ -d "$directory" ]] || {
      printf 'Nginx configuration directory does not exist: %s\n' "$directory" >&2
      return 1
   }

   config_file=$(reverse_proxy_config_path "$domain") || return
   temporary_file=$(mktemp "$directory/.mytool.${domain}.XXXXXX") || return 1
   if ! (umask 022; reverse_proxy_render_config "$domain" "$port" >"$temporary_file"); then
      rm -f -- "$temporary_file"
      return 1
   fi
   if ! mv -f -- "$temporary_file" "$config_file"; then
      rm -f -- "$temporary_file"
      return 1
   fi
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

   nginx -t && systemctl reload nginx
}

reverse_proxy_apply_config() {
   local domain="$1"
   local port="$2"
   local config_file backup_file=""

   config_file=$(reverse_proxy_config_path "$domain") || return
   if [[ -f "$config_file" ]]; then
      backup_file=$(mktemp) || return 1
      cp -p -- "$config_file" "$backup_file" || {
         rm -f -- "$backup_file"
         return 1
      }
   fi

   if ! reverse_proxy_save_config "$domain" "$port"; then
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
   domains_and_ports["$domain"]="$port"
   reverse_proxy_files["$domain"]="$config_file"
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
   unset 'domains_and_ports[$domain]'
   unset 'reverse_proxy_files[$domain]'
}
