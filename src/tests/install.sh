#!/usr/bin/env bash

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/test.sh
source "$test_dir/../lib/test.sh"
# Loading system.sh first keeps the checkout's self_update.sh from replacing the stub below.
# shellcheck source=../core/self_update.sh
source "$test_dir/../core/self_update.sh"
# shellcheck source=../../install.sh
source "$test_dir/../../install.sh"
src_dir=$(cd -- "$test_dir/.." && pwd)
unset test_dir

if ! command -v git >/dev/null; then
   test_print_name 'Install from a git repository'
   printf '[%sSKIP%s]\n' "$DIM" "$RESET"
   test_finish
   exit
fi

temporary_dir=$(mktemp -d)
trap 'rm -rf -- "$temporary_dir"' EXIT
source_repo="$temporary_dir/source repo"
MYTOOL_REPO_URL="$source_repo"
MYTOOL_INSTALL_DIR="$temporary_dir/opt/mytool"
SELF_UPDATE_BIN_DIR="$temporary_dir/bin"

fixture_git() {
   git -C "$source_repo" -c init.defaultBranch=main -c user.name=test -c user.email=test@example.com \
      -c commit.gpgsign=false "$@" &>/dev/null
}

mkdir -p -- "$source_repo/src/core" "$source_repo/src/lib"
cp -- "$src_dir/core/self_update.sh" "$source_repo/src/core/"
cp -- "$src_dir/lib/system.sh" "$source_repo/src/lib/"
printf '#!/usr/bin/env bash\n' >"$source_repo/src/mytool"
fixture_git init
fixture_git add -A
fixture_git commit -m initial

privileged_commands=()
system_run_privileged() {
   privileged_commands+=("$*")
   case "$1" in
   install | mkdir | mv | rm) "$@" ;;
   esac
}
# The stub above stands in for root and sudo.
install_check_privileges() {
   :
}

test_assert_status 'Install into a new directory' 0 install_main
test_run 'Clone the repository' test -d "$MYTOOL_INSTALL_DIR/.git"
test_assert_equal 'Create the missing parent directory' "mkdir -p -- $temporary_dir/opt" "${privileged_commands[0]-}"
test_assert_equal 'Clone as the user into a writable parent' 0 "$(printf '%s\n' "${privileged_commands[@]}" | grep -c '^git ')"
test_assert_equal 'Install the launcher' "$(self_update_launcher_content "$MYTOOL_INSTALL_DIR")" "$(<"$SELF_UPDATE_BIN_DIR/mytool")"

printf 'new\n' >"$source_repo/NEW"
fixture_git add -A
fixture_git commit -m update
test_assert_status 'Reinstall over an existing checkout' 0 install_main
test_run 'Pull the existing checkout' test -f "$MYTOOL_INSTALL_DIR/NEW"

mkdir -p -- "$temporary_dir/occupied"
printf 'data\n' >"$temporary_dir/occupied/file"
test_assert_status 'Refuse a directory that is not a checkout' 2 install_checkout "$temporary_dir/occupied"
test_run 'Leave the occupied directory alone' test ! -e "$temporary_dir/occupied/.git"
MYTOOL_INSTALL_DIR=relative/mytool test_assert_status 'Reject a relative install directory' 2 install_main

mkdir -p -- "$temporary_dir/no-git" "$temporary_dir/apt"
no_git_status=0
PATH="$temporary_dir/no-git" install_require_git &>/dev/null || no_git_status=$?
test_assert_equal 'Fail without git or apt-get' 1 "$no_git_status"
printf '#!/bin/sh\n' >"$temporary_dir/apt/apt-get"
chmod +x -- "$temporary_dir/apt/apt-get"
privileged_commands=()
apt_status=0
PATH="$temporary_dir/apt" install_require_git &>/dev/null || apt_status=$?
test_assert_equal 'Install git with apt-get' $'apt-get update\napt-get install -y -- git' "$(printf '%s\n' "${privileged_commands[@]}")"
test_assert_equal 'Fail when git is still missing' 1 "$apt_status"

test_finish
