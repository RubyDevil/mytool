#!/usr/bin/env bash
# Install mytool:
#   curl -fsSL https://raw.githubusercontent.com/RubyDevil/mytool/main/install.sh | bash
#
# Clones mytool into MYTOOL_INSTALL_DIR (default /opt/mytool), or pulls an existing checkout,
# then installs the mytool command. Update MyTool keeps the checkout current afterwards.

# Checked in POSIX syntax so `| sh` explains itself instead of failing on Bash syntax.
if [ -z "${BASH_VERSION:-}" ]; then
   printf 'mytool requires Bash. Run the installer with: curl -fsSL <url> | bash\n' >&2
   exit 1
fi

install_repo_url() {
   printf '%s' "${MYTOOL_REPO_URL:-https://github.com/RubyDevil/mytool.git}"
}

install_dir() {
   printf '%s' "${MYTOOL_INSTALL_DIR:-/opt/mytool}"
}

install_error() {
   printf 'Error: %s\n' "$1" >&2
}

# Mirrors src/lib/system.sh, which does not exist until the checkout is cloned.
system_run_privileged() {
   if ((EUID == 0)); then
      "$@"
   else
      sudo -- "$@"
   fi
}

install_check_privileges() {
   if ((EUID != 0)) && ! command -v sudo >/dev/null; then
      install_error 'run the installer as root or install sudo.'
      return 1
   fi
}

install_check_bash() {
   if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3))); then
      install_error "mytool requires Bash 4.3 or newer; this is Bash $BASH_VERSION."
      return 1
   fi
}

install_require_git() {
   command -v git >/dev/null && return 0
   if ! command -v apt-get >/dev/null; then
      install_error 'git is required. Install git, then run the installer again.'
      return 1
   fi
   printf 'Installing git\n'
   system_run_privileged apt-get update </dev/null &&
      system_run_privileged apt-get install -y -- git </dev/null
   if ! command -v git >/dev/null; then
      install_error 'could not install git.'
      return 1
   fi
}

# Run git as the current user when the target is writable, like self_update_git.
install_git() {
   local writable_path="$1"
   shift

   if [[ -w "$writable_path" ]]; then
      git "$@" </dev/null
   else
      system_run_privileged git "$@" </dev/null
   fi
}

install_checkout() {
   local directory="$1"
   local parent

   if [[ -e "$directory/.git" ]]; then
      printf 'Updating the mytool checkout at %s\n' "$directory"
      install_git "$directory/.git" -C "$directory" pull --ff-only
      return
   fi
   if [[ -e "$directory" ]] && [[ ! -d "$directory" || -n "$(ls -A -- "$directory")" ]]; then
      install_error "$directory already exists and is not a mytool checkout."
      return 2
   fi

   parent=$(dirname -- "$directory")
   if [[ ! -d "$parent" ]] && ! system_run_privileged mkdir -p -- "$parent"; then
      install_error "could not create $parent."
      return 1
   fi
   printf 'Cloning %s into %s\n' "$(install_repo_url)" "$directory"
   install_git "$parent" clone --quiet -- "$(install_repo_url)" "$directory"
}

# Use the launcher code from the checkout so it matches what Update MyTool installs.
install_launcher() {
   local directory="$1"

   # shellcheck source=src/core/self_update.sh
   source "$directory/src/core/self_update.sh" || return 1
   printf 'Installing the mytool command at %s\n' "$(self_update_launcher)"
   self_update_install_launcher "$directory"
}

install_main() {
   local directory

   install_check_bash || return 1
   directory=$(install_dir)
   if [[ "$directory" != /* ]]; then
      install_error 'MYTOOL_INSTALL_DIR must be an absolute path.'
      return 2
   fi
   install_check_privileges || return 1
   install_require_git || return 1
   if ! install_checkout "$directory"; then
      install_error 'mytool was not installed.'
      return 1
   fi
   if ! install_launcher "$directory"; then
      install_error 'the mytool command could not be installed.'
      return 1
   fi
   printf '\nmytool is installed. Run it from anywhere with: mytool\n'
}

# Keep this last so a truncated download runs nothing. BASH_SOURCE is empty when piped to bash.
if [[ -z "${BASH_SOURCE[0]-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
   install_main "$@"
fi
