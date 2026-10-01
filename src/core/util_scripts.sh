#!/usr/bin/env bash

util_scripts_module_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if ! declare -F system_install_file >/dev/null; then
   # shellcheck source=../lib/system.sh
   source "$util_scripts_module_dir/../lib/system.sh"
fi
if ! declare -p settings &>/dev/null; then
   # shellcheck source=../lib/settings.sh
   source "$util_scripts_module_dir/../lib/settings.sh"
fi
unset util_scripts_module_dir

# Scripts come from the UTIL_SCRIPTS_REPO repository, one directory per script:
#   <name>/<name> (or <name>.sh), plus optional install.sh, uninstall.sh, and documentation.md

util_scripts_bin_dir() {
   printf '%s' "${UTIL_SCRIPTS_BIN_DIR:-/usr/local/bin}"
}

# Local clone of the scripts repository.
util_scripts_cache_dir() {
   printf '%s' "${UTIL_SCRIPTS_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/mytool/util-scripts}"
}

# Copies of installed script directories, kept so updates and uninstall run the installed uninstall.sh.
util_scripts_share_dir() {
   printf '%s' "${UTIL_SCRIPTS_SHARE_DIR:-/usr/local/share/mytool/util-scripts}"
}

util_scripts_validate_name() {
   [[ "${1-}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$ ]]
}

util_scripts_validate_repo() {
   [[ "${1-}" =~ ^(https://[A-Za-z0-9.-]+(:[0-9]+)?/[A-Za-z0-9._~/-]+|git@[A-Za-z0-9.-]+:[A-Za-z0-9._~/-]+)$ ]]
}

util_scripts_target() {
   printf '%s/%s' "$(util_scripts_bin_dir)" "$1"
}

util_scripts_record() {
   printf '%s/%s' "$(util_scripts_share_dir)" "$1"
}

# Print the main file of a script directory.
util_scripts_main_file() {
   local directory="$1"
   local name="$2"

   if [[ -f "$directory/$name" ]]; then
      printf '%s' "$directory/$name"
   elif [[ -f "$directory/$name.sh" ]]; then
      printf '%s' "$directory/$name.sh"
   else
      return 1
   fi
}

util_scripts_list_directory() {
   local directory="$1"
   local path name

   [[ -d "$directory" ]] || return 0
   for path in "$directory"/*/; do
      name=$(basename -- "$path")
      util_scripts_validate_name "$name" || continue
      util_scripts_main_file "$directory/$name" "$name" >/dev/null || continue
      printf '%s\n' "$name"
   done | LC_ALL=C sort
}

# Scripts offered by the synced repository.
util_scripts_available() {
   util_scripts_list_directory "$(util_scripts_cache_dir)"
}

# Scripts installed by mytool.
util_scripts_installed() {
   util_scripts_list_directory "$(util_scripts_share_dir)"
}

util_scripts_all() {
   {
      util_scripts_available
      util_scripts_installed
   } | LC_ALL=C sort -u
}

util_scripts_is_available() {
   util_scripts_validate_name "$1" &&
      util_scripts_main_file "$(util_scripts_cache_dir)/$1" "$1" >/dev/null
}

util_scripts_is_installed() {
   util_scripts_validate_name "$1" && [[ -d "$(util_scripts_record "$1")" ]]
}

# Print installed, outdated, removed (installed but gone from the repository), or missing.
util_scripts_status() {
   local name="$1"
   local source

   util_scripts_validate_name "$name" || return 2
   if ! util_scripts_is_installed "$name"; then
      printf 'missing'
   elif ! source=$(util_scripts_main_file "$(util_scripts_cache_dir)/$name" "$name"); then
      printf 'removed'
   elif cmp -s -- "$source" "$(util_scripts_target "$name")"; then
      printf 'installed'
   else
      printf 'outdated'
   fi
}

# Clone the repository, or bring an existing clone to the remote's latest commit.
util_scripts_fetch() {
   local repository="$1"
   local cache="$2"

   if [[ -d "$cache/.git" && "$(git -C "$cache" remote get-url origin 2>/dev/null)" == "$repository" ]]; then
      git -C "$cache" fetch --quiet --depth 1 origin &&
         git -C "$cache" reset --quiet --hard FETCH_HEAD &&
         git -C "$cache" clean -qfdx
   else
      rm -rf -- "$cache" &&
         mkdir -p -- "$(dirname -- "$cache")" &&
         git clone --quiet --depth 1 -- "$repository" "$cache"
   fi
}

util_scripts_sync() {
   local repository="${settings[UTIL_SCRIPTS_REPO]-}"

   if [[ -z "$repository" ]]; then
      printf 'Set UTIL_SCRIPTS_REPO in the settings to install utility scripts.\n' >&2
      return 2
   fi
   if ! util_scripts_validate_repo "$repository"; then
      printf 'UTIL_SCRIPTS_REPO is not a valid https:// or git@ repository URL.\n' >&2
      return 2
   fi
   if ! command -v git >/dev/null; then
      printf 'git is required to download utility scripts.\n' >&2
      return 1
   fi
   util_scripts_fetch "$repository" "$(util_scripts_cache_dir)"
}

# Print documentation.md, or the script's --help output when there is none.
util_scripts_doc() {
   local name="$1"
   local directory main_file output

   util_scripts_validate_name "$name" || return 2
   for directory in "$(util_scripts_cache_dir)/$name" "$(util_scripts_record "$name")"; do
      if [[ -f "$directory/documentation.md" ]]; then
         cat -- "$directory/documentation.md"
         return
      fi
   done
   main_file=$(util_scripts_main_file "$(util_scripts_cache_dir)/$name" "$name") ||
      main_file=$(util_scripts_target "$name")
   if [[ -f "$main_file" ]] && output=$(util_scripts_help "$main_file"); then
      printf '%s\n' "$output" | head -n 200
   else
      printf 'No documentation available.\n'
   fi
}

util_scripts_help() {
   local main_file="$1"
   local output

   if [[ -x "$main_file" ]]; then
      output=$(timeout 5 "$main_file" --help </dev/null 2>&1)
   else
      output=$(timeout 5 bash -- "$main_file" --help </dev/null 2>&1)
   fi
   [[ -n "$output" ]] || return 1
   printf '%s\n' "$output"
}

# Run a script directory's install.sh or uninstall.sh as root with the installed path.
util_scripts_run_hook() {
   local directory="$1"
   local hook="$2"
   local target="$3"

   [[ -f "$directory/$hook.sh" ]] || return 0
   system_run_privileged bash -- "$directory/$hook.sh" "$target"
}

util_scripts_restore() {
   local target="$1"
   local backup_file="$2"

   if [[ -n "$backup_file" ]]; then
      system_install_file "$backup_file" "$target" 755
   else
      system_run_privileged rm -f -- "$target"
   fi
}

# Install or update a script from the synced repository.
# An update runs the installed version's uninstall.sh before the new install.sh;
# on failure the previous version is restored and its install.sh runs again.
util_scripts_install() {
   local name="$1"
   local source_directory main_file target record staged previous
   local backup_file=''

   util_scripts_validate_name "$name" || return 2
   source_directory="$(util_scripts_cache_dir)/$name"
   if ! main_file=$(util_scripts_main_file "$source_directory" "$name"); then
      printf '%s is not in the scripts repository.\n' "$name" >&2
      return 2
   fi
   target=$(util_scripts_target "$name")
   record=$(util_scripts_record "$name")
   staged="$record.mytool-new"
   previous="$record.mytool-old"
   if [[ -e "$target" ]] && ! util_scripts_is_installed "$name"; then
      printf '%s already exists and is not managed by mytool.\n' "$target" >&2
      return 1
   fi
   if [[ -f "$target" ]]; then
      backup_file=$(mktemp) && cp -- "$target" "$backup_file" || {
         rm -f -- ${backup_file:+"$backup_file"}
         return 1
      }
   fi

   if ! system_run_privileged rm -rf -- "$staged" "$previous" ||
      ! system_run_privileged mkdir -p -- "$(util_scripts_share_dir)" ||
      ! system_run_privileged cp -R -- "$source_directory" "$staged" ||
      ! system_run_privileged chmod -R a+rX,go-w -- "$staged" ||
      { [[ -d "$record" ]] && ! system_run_privileged mv -- "$record" "$previous"; }; then
      printf 'Could not prepare %s; the installed version was kept.\n' "$name" >&2
      system_run_privileged rm -rf -- "$staged"
      rm -f -- ${backup_file:+"$backup_file"}
      return 1
   fi
   if [[ -d "$previous" ]] && ! util_scripts_run_hook "$previous" uninstall "$target"; then
      printf 'The installed uninstall.sh for %s failed; the installed version was kept.\n' "$name" >&2
      system_run_privileged mv -- "$previous" "$record"
      system_run_privileged rm -rf -- "$staged"
      rm -f -- ${backup_file:+"$backup_file"}
      return 1
   fi

   if system_run_privileged mv -- "$staged" "$record" &&
      system_install_file "$main_file" "$target" 755 &&
      util_scripts_run_hook "$record" install "$target"; then
      system_run_privileged rm -rf -- "$previous"
      rm -f -- ${backup_file:+"$backup_file"}
      return 0
   fi

   printf 'Installing %s failed; restoring the previous state.\n' "$name" >&2
   system_run_privileged rm -rf -- "$staged" "$record"
   util_scripts_restore "$target" "$backup_file"
   if [[ -d "$previous" ]]; then
      system_run_privileged mv -- "$previous" "$record" &&
         util_scripts_run_hook "$record" install "$target"
   fi
   rm -f -- ${backup_file:+"$backup_file"}
   return 1
}

util_scripts_uninstall() {
   local name="$1"
   local record target

   util_scripts_is_installed "$name" || return 2
   record=$(util_scripts_record "$name")
   target=$(util_scripts_target "$name")
   util_scripts_run_hook "$record" uninstall "$target" &&
      system_run_privileged rm -f -- "$target" &&
      system_run_privileged rm -rf -- "$record"
}

# Reinstall every installed script that the synced repository still provides.
util_scripts_update_installed() {
   local name
   local status=0

   while IFS= read -r name; do
      util_scripts_is_available "$name" || continue
      util_scripts_install "$name" || status=1
   done < <(util_scripts_installed)
   return "$status"
}

# Pull the repository and update installed scripts; nothing to do when none are installed.
util_scripts_refresh() {
   [[ -n "$(util_scripts_installed)" ]] || return 0
   util_scripts_sync && util_scripts_update_installed
}
