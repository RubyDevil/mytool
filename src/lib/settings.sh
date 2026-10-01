#!/usr/bin/env bash

settings_file="${MYTOOL_SETTINGS_FILE:-$HOME/.mytool.conf}"

declare -gA default_settings=(
   [NGINX_CONFIG_DIR]="/etc/nginx/conf.d"
   [MENU_BORDER_TYPE]="LIGHT"
   [MENU_BORDER_COLOR]="WHITE"
   [MENU_POINTER_COLOR]="WHITE"
   [MENU_POINTER_TYPE]=">"
   [UTIL_SCRIPTS_REPO]=""
)
declare -gA settings=()

settings_reset() {
   local key

   settings=()
   for key in "${!default_settings[@]}"; do
      settings["$key"]="${default_settings[$key]}"
   done
}

settings_is_valid_key() {
   [[ "${1-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

settings_escape_value() {
   local value="${1-}"
   local result=""
   local char
   local -i index

   for ((index = 0; index < ${#value}; index++)); do
      char=${value:index:1}
      case "$char" in
      '\') result+='\\' ;;
      $'\n') result+='\n' ;;
      $'\r') result+='\r' ;;
      *) result+="$char" ;;
      esac
   done

   printf '%s' "$result"
}

settings_unescape_value() {
   local escaped="${1-}"
   local output_name="${2-}"
   local result=""
   local char next
   local -i index

   for ((index = 0; index < ${#escaped}; index++)); do
      char=${escaped:index:1}
      if [[ "$char" != '\' ]] || ((index + 1 >= ${#escaped})); then
         result+="$char"
         continue
      fi

      index=$((index + 1))
      next=${escaped:index:1}
      case "$next" in
      n) result+=$'\n' ;;
      r) result+=$'\r' ;;
      '\') result+='\' ;;
      *) result+="\\${next}" ;;
      esac
   done

   if [[ -n "$output_name" ]]; then
      printf -v "$output_name" '%s' "$result"
   else
      printf '%s' "$result"
   fi
}

# Load settings without executing the configuration file.
settings_load_from_file() {
   local file="${1:-$settings_file}"
   local line key value
   local -i status=0

   settings_reset
   [[ -f "$file" ]] || return 0

   while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "$line" == \#* || "$line" == "declare -A settings" ]] && continue

      if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
         key=${BASH_REMATCH[1]}
         value=${BASH_REMATCH[2]}
      elif [[ "$line" =~ ^settings\[\"([A-Za-z_][A-Za-z0-9_]*)\"\]=\"(.*)\"$ ]]; then
         key=${BASH_REMATCH[1]}
         value=${BASH_REMATCH[2]}
      else
         printf 'Ignoring malformed setting in %s: %s\n' "$file" "$line" >&2
         status=1
         continue
      fi

      settings_unescape_value "$value" value
      settings["$key"]="$value"
   done <"$file"

   return "$status"
}

# Save settings in a deterministic, non-executable format.
settings_save_to_file() {
   local file="${1:-$settings_file}"
   local directory temporary_file key
   local -a keys=()

   directory=$(dirname -- "$file")
   if [[ ! -d "$directory" ]]; then
      printf 'Settings directory does not exist: %s\n' "$directory" >&2
      return 1
   fi

   temporary_file=$(mktemp "${file}.tmp.XXXXXX") || return 1
   mapfile -t keys < <(printf '%s\n' "${!settings[@]}" | LC_ALL=C sort)

   if ! (
      umask 077
      printf '# mytool settings\n'
      for key in "${keys[@]}"; do
         settings_is_valid_key "$key" || continue
         printf '%s=%s\n' "$key" "$(settings_escape_value "${settings[$key]}")"
      done
   ) >"$temporary_file"; then
      rm -f -- "$temporary_file"
      return 1
   fi

   if ! mv -f -- "$temporary_file" "$file"; then
      rm -f -- "$temporary_file"
      return 1
   fi
}

settings_reset
unset key
