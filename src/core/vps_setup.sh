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

vps_setup_set_sshd_option() {
   local option="$1"
   local value="$2"
   local config_file="${VPS_SETUP_SSHD_CONFIG:-/etc/ssh/sshd_config}"
   local temporary_file

   [[ "$option" =~ ^[A-Za-z]+$ && "$value" =~ ^[A-Za-z0-9]+$ ]] || return 2
   temporary_file=$(mktemp "${config_file}.XXXXXX") || return 1
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
   chmod --reference="$config_file" "$temporary_file" 2>/dev/null || true
   mv -- "$temporary_file" "$config_file"
}

vps_setup_reload_ssh() {
   if command -v systemctl >/dev/null; then
      systemctl reload ssh 2>/dev/null || systemctl reload sshd
   else
      service ssh reload 2>/dev/null || service sshd reload
   fi
}

vps_setup_update_sshd_option() {
   local option="$1"
   local value="$2"
   local config_file="${VPS_SETUP_SSHD_CONFIG:-/etc/ssh/sshd_config}"
   local backup_file

   backup_file=$(mktemp "${config_file}.backup.XXXXXX") || return 1
   cp -- "$config_file" "$backup_file" || {
      rm -f -- "$backup_file"
      return 1
   }
   if ! vps_setup_set_sshd_option "$option" "$value" || ! sshd -t -f "$config_file" || ! vps_setup_reload_ssh; then
      mv -- "$backup_file" "$config_file"
      vps_setup_reload_ssh || true
      return 1
   fi
   rm -f -- "$backup_file"
}

vps_setup_package_manager() {
   command -v apt-get >/dev/null && printf '%s' apt-get
}

vps_setup_run_privileged() {
   if ((EUID == 0)); then
      "$@"
   else
      sudo -- "$@"
   fi
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