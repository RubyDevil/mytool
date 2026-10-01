#!/usr/bin/env bash

vps_setup_validate_ssh_port() {
   local port="${1-}"
   [[ "$port" =~ ^[0-9]{1,5}$ ]] && ((10#$port >= 1 && 10#$port <= 65535))
}

vps_setup_validate_ssh_handle() {
   local handle="${1-}"
   [[ "$handle" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$ ]]
}

vps_setup_validate_public_key() {
   local key="${1-}"
   [[ "$key" != *$'\n'* && "$key" != *$'\r'* && "$key" =~ ^(ssh-(rsa|ed25519)|ecdsa-sha2-nistp(256|384|521))[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]]
}

vps_setup_current_user() {
   id -un
}

vps_setup_ip_address() {
   hostname -I 2>/dev/null | awk '{print $1}'
}

vps_setup_ssh_port() {
   local config_file="${VPS_SETUP_SSHD_CONFIG:-/etc/ssh/sshd_config}"
   local port

   port=$(awk 'tolower($1) == "port" && $2 ~ /^[0-9]+$/ { print $2; exit }' "$config_file" 2>/dev/null)
   printf '%s' "${port:-22}"
}

vps_setup_append_public_key() {
   local public_key="$1"
   local home_directory
   local ssh_directory
   local authorized_keys

   vps_setup_validate_public_key "$public_key" || return 2
   home_directory=$(getent passwd "$(vps_setup_current_user)" | cut -d: -f6) || return 1
   [[ -n "$home_directory" ]] || return 1
   ssh_directory="$home_directory/.ssh"
   authorized_keys="$ssh_directory/authorized_keys"
   umask 077
   mkdir -p -- "$ssh_directory" || return 1
   chmod 700 -- "$ssh_directory" || return 1
   touch -- "$authorized_keys" || return 1
   chmod 600 -- "$authorized_keys" || return 1
   grep -Fqx -- "$public_key" "$authorized_keys" || printf '%s\n' "$public_key" >>"$authorized_keys"
}

vps_setup_generate_key() {
   local key_type="$1"
   local key_path="$2"

   case "$key_type" in
   rsa | ecdsa | ed25519) ;;
   *) return 2 ;;
   esac
   [[ -n "$key_path" && "$key_path" != *$'\n'* && "$key_path" != *$'\r'* ]] || return 2
   ssh-keygen -t "$key_type" -f "$key_path"
}

vps_setup_run_privileged() {
   if ((EUID == 0)); then
      "$@"
   else
      sudo -- "$@"
   fi
}

vps_setup_set_sshd_option() {
   local option="$1"
   local value="$2"
   local config_file="${VPS_SETUP_SSHD_CONFIG:-/etc/ssh/sshd_config}"
   local temporary_file

   [[ "$option" =~ ^[A-Za-z]+$ && "$value" =~ ^[A-Za-z0-9]+$ ]] || return 2
   temporary_file=$(mktemp) || return 1
   awk -v option="$option" -v value="$value" '
      BEGIN { changed = 0 }
      tolower($1) == tolower(option) && !changed {
         print option " " value
         changed = 1
         next
      }
      { print }
      END { if (!changed) print option " " value }
   ' "$config_file" >"$temporary_file" || {
      rm -f -- "$temporary_file"
      return 1
   }
   if ! vps_setup_run_privileged cp -- "$temporary_file" "$config_file"; then
      rm -f -- "$temporary_file"
      return 1
   fi
   rm -f -- "$temporary_file"
}

vps_setup_reload_ssh() {
   if command -v systemctl >/dev/null; then
      vps_setup_run_privileged systemctl reload ssh 2>/dev/null ||
         vps_setup_run_privileged systemctl reload sshd
   else
      vps_setup_run_privileged service ssh reload 2>/dev/null ||
         vps_setup_run_privileged service sshd reload
   fi
}

vps_setup_update_sshd_option() {
   local option="$1"
   local value="$2"
   local config_file="${VPS_SETUP_SSHD_CONFIG:-/etc/ssh/sshd_config}"
   local backup_file

   backup_file=$(mktemp) || return 1
   vps_setup_run_privileged cp -- "$config_file" "$backup_file" || {
      rm -f -- "$backup_file"
      return 1
   }
   if ! vps_setup_set_sshd_option "$option" "$value" ||
      ! vps_setup_run_privileged sshd -t -f "$config_file" || ! vps_setup_reload_ssh; then
      vps_setup_run_privileged cp -- "$backup_file" "$config_file"
      vps_setup_reload_ssh || true
      rm -f -- "$backup_file"
      return 1
   fi
   rm -f -- "$backup_file"
}

vps_setup_package_manager() {
   command -v apt-get >/dev/null && printf '%s' apt-get
}

vps_setup_update_packages() {
   vps_setup_run_privileged apt-get update && vps_setup_run_privileged apt-get upgrade -y
}

vps_setup_install_software() {
   local software="$1"
   local reinstall="${2:-0}"
   local package

   case "$software" in
   nginx) package=nginx ;;
   docker) package=docker.io ;;
   node) package=nodejs ;;
   mongodb) vps_setup_install_mongodb "$reinstall"; return ;;
   nvm) curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash; return ;;
   pm2) command -v npm >/dev/null && npm install -g pm2; return ;;
   *) return 2 ;;
   esac
   if [[ "$reinstall" == 1 ]]; then
      vps_setup_run_privileged apt-get remove -y -- "$package" &&
         vps_setup_run_privileged apt-get install -y -- "$package"
   else
      vps_setup_run_privileged apt-get install -y -- "$package"
   fi
}

vps_setup_os_release_value() {
   local key="$1"

   awk -F= -v key="$key" '
      $1 == key {
         value = substr($0, length(key) + 2)
         gsub(/^["\047]|["\047]$/, "", value)
         print value
         exit
      }
   ' "${VPS_SETUP_OS_RELEASE:-/etc/os-release}" 2>/dev/null
}

vps_setup_architecture() {
   dpkg --print-architecture 2>/dev/null
}

vps_setup_cpu_supports_avx() {
   grep -qw avx -- "${VPS_SETUP_CPUINFO:-/proc/cpuinfo}" 2>/dev/null
}

vps_setup_download_key() {
   local url="$1"
   local destination="$2"
   local armored_key
   local status

   armored_key=$(mktemp) || return 1
   curl -fsSL -o "$armored_key" "$url" &&
      gpg --batch --yes --dearmor -o "$destination" "$armored_key"
   status=$?
   rm -f -- "$armored_key"
   return "$status"
}

vps_setup_mongodb_repo_line() {
   local distribution="$1"
   local codename="$2"
   local architecture="$3"
   local keyring="$4"
   local version="$5"
   local component

   case "$distribution" in
   ubuntu) component=multiverse ;;
   debian) component=main ;;
   *) return 2 ;;
   esac
   [[ "$codename" =~ ^[a-z]+$ && "$architecture" =~ ^(amd64|arm64)$ ]] || return 2
   printf 'deb [ arch=%s signed-by=%s ] https://repo.mongodb.org/apt/%s %s/mongodb-org/%s %s\n' \
      "$architecture" "$keyring" "$distribution" "$codename" "$version" "$component"
}

vps_setup_restore_file() {
   local backup_file="$1"
   local destination="$2"

   if [[ -n "$backup_file" ]]; then
      vps_setup_run_privileged install -m 644 -- "$backup_file" "$destination"
   else
      vps_setup_run_privileged rm -f -- "$destination"
   fi
}

vps_setup_configure_mongodb_repository() {
   local repo_line="$1"
   local key_url="$2"
   local keyring="$3"
   local sources_list="$4"
   local temporary_keyring
   local temporary_list
   local keyring_backup=''
   local list_backup=''
   local status=0

   temporary_keyring=$(mktemp) || return 1
   temporary_list=$(mktemp) || {
      rm -f -- "$temporary_keyring"
      return 1
   }
   if [[ -f "$keyring" ]]; then
      keyring_backup=$(mktemp) && cp -- "$keyring" "$keyring_backup" || status=1
   fi
   if [[ -f "$sources_list" ]]; then
      list_backup=$(mktemp) && cp -- "$sources_list" "$list_backup" || status=1
   fi

   if ((status != 0)); then
      printf 'Could not back up the existing MongoDB APT sources.\n' >&2
   else
      if ! vps_setup_download_key "$key_url" "$temporary_keyring"; then
         printf 'Could not download the MongoDB signing key.\n' >&2
         status=1
      elif ! printf '%s\n' "$repo_line" >"$temporary_list" ||
         ! vps_setup_run_privileged install -D -m 644 -- "$temporary_keyring" "$keyring" ||
         ! vps_setup_run_privileged install -D -m 644 -- "$temporary_list" "$sources_list" ||
         ! vps_setup_run_privileged apt-get update; then
         printf 'Enabling the MongoDB repository or updating APT failed; the previous APT sources were restored.\n' >&2
         vps_setup_restore_file "$list_backup" "$sources_list"
         vps_setup_restore_file "$keyring_backup" "$keyring"
         status=1
      fi
   fi
   rm -f -- "$temporary_keyring" "$temporary_list" ${keyring_backup:+"$keyring_backup"} ${list_backup:+"$list_backup"}
   return "$status"
}

vps_setup_start_mongodb() {
   command -v systemctl >/dev/null || return 0
   vps_setup_run_privileged systemctl daemon-reload &&
      vps_setup_run_privileged systemctl enable --now mongod
}

vps_setup_install_mongodb() {
   local reinstall="${1:-0}"
   local version=9.0
   local key_url=https://pgp.mongodb.com/server-9.asc
   local keyring="${VPS_SETUP_APT_KEYRING_DIR:-/usr/share/keyrings}/mongodb-server-9.gpg"
   local sources_list="${VPS_SETUP_APT_SOURCES_DIR:-/etc/apt/sources.list.d}/mongodb-org-$version.list"
   local distribution
   local codename
   local architecture
   local repo_line
   local -a packages=(mongodb-org mongodb-org-database mongodb-org-server mongodb-org-mongos
      mongodb-org-tools mongodb-org-database-tools-extra mongodb-mongosh mongodb-database-tools)

   distribution=$(vps_setup_os_release_value ID)
   codename=$(vps_setup_os_release_value VERSION_CODENAME)
   architecture=$(vps_setup_architecture)
   if [[ "$distribution" != ubuntu && "$distribution" != debian ]]; then
      printf 'MongoDB installation requires Ubuntu or Debian.\n' >&2
      return 2
   fi
   if [[ "$architecture" != amd64 && "$architecture" != arm64 ]]; then
      printf 'MongoDB requires an amd64 or arm64 system; found %s.\n' "${architecture:-unknown}" >&2
      return 2
   fi
   if [[ "$architecture" == amd64 ]] && ! vps_setup_cpu_supports_avx; then
      printf 'MongoDB %s requires a CPU with AVX support, which this server does not report.\n' "$version" >&2
      return 2
   fi
   repo_line=$(vps_setup_mongodb_repo_line "$distribution" "$codename" "$architecture" "$keyring" "$version") || {
      printf 'Could not determine the release codename for this system.\n' >&2
      return 2
   }

   vps_setup_run_privileged apt-get install -y -- ca-certificates curl gnupg || return 1
   vps_setup_configure_mongodb_repository "$repo_line" "$key_url" "$keyring" "$sources_list" || return 1
   if [[ "$reinstall" == 1 ]]; then
      vps_setup_run_privileged apt-get remove -y -- "${packages[@]}" || return 1
   fi
   vps_setup_run_privileged apt-get install -y -- mongodb-org || return 1
   vps_setup_start_mongodb
}
