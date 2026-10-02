#!/usr/bin/env bash

self_update_module_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if ! declare -F system_install_file >/dev/null; then
   # shellcheck source=../lib/system.sh
   source "$self_update_module_dir/../lib/system.sh"
fi
unset self_update_module_dir

self_update_bin_dir() {
   printf '%s' "${SELF_UPDATE_BIN_DIR:-/usr/local/bin}"
}

self_update_launcher() {
   printf '%s/mytool' "$(self_update_bin_dir)"
}

self_update_is_checkout() {
   [[ -e "$1/.git" ]]
}

# Run git as the current user when possible so git does not reject the checkout's ownership.
self_update_git() {
   local repository="$1"
   shift

   if [[ -w "$repository/.git" ]]; then
      git -C "$repository" "$@"
   else
      system_run_privileged git -C "$repository" "$@"
   fi
}

self_update_pull() {
   local repository="$1"

   if ! command -v git >/dev/null; then
      printf 'git is required to update mytool.\n' >&2
      return 1
   fi
   if ! self_update_is_checkout "$repository"; then
      printf '%s is not a git checkout; reinstall mytool with install.sh.\n' "$repository" >&2
      return 2
   fi
   self_update_git "$repository" pull --ff-only
}

self_update_launcher_content() {
   printf '#!/usr/bin/env bash\n# Installed by mytool.\nexec bash %q "$@"\n' "$1/src/mytool"
}

# Install a wrapper rather than a symlink so mytool keeps resolving its own libraries.
self_update_install_launcher() {
   local repository="$1"
   local launcher temporary_file
   local status=0

   [[ -f "$repository/src/mytool" ]] || return 2
   launcher=$(self_update_launcher)
   temporary_file=$(mktemp) || return 1
   if ! self_update_launcher_content "$repository" >"$temporary_file"; then
      status=1
   elif ! cmp -s -- "$temporary_file" "$launcher"; then
      system_install_file "$temporary_file" "$launcher" 755 || status=1
   fi
   rm -f -- "$temporary_file"
   return "$status"
}
