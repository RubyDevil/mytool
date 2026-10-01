#!/usr/bin/env bash

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/test.sh
source "$test_dir/../lib/test.sh"
# shellcheck source=../core/self_update.sh
source "$test_dir/../core/self_update.sh"
unset test_dir

temporary_dir=$(mktemp -d)
trap 'rm -rf -- "$temporary_dir"' EXIT
SELF_UPDATE_BIN_DIR="$temporary_dir/bin"
repository="$temporary_dir/my repo"
mkdir -p -- "$repository/src" "$repository/.git"
printf '#!/usr/bin/env bash\n' >"$repository/src/mytool"

privileged_commands=()
system_run_privileged() {
   privileged_commands+=("$*")
   case "$1" in
   install | mv | rm) "$@" ;;
   esac
}
git_commands=()
self_update_git() {
   git_commands+=("$*")
}

expected_launcher=$'#!/usr/bin/env bash\n# Installed by mytool.\nexec bash '"$(printf '%q' "$repository/src/mytool")"' "$@"'
test_assert_equal 'Render launcher wrapper' "$expected_launcher" "$(self_update_launcher_content "$repository")"
test_run 'Install launcher' self_update_install_launcher "$repository"
test_assert_equal 'Write launcher file' "$expected_launcher" "$(<"$SELF_UPDATE_BIN_DIR/mytool")"
privileged_commands=()
test_run 'Keep current launcher' self_update_install_launcher "$repository"
test_assert_equal 'Skip unchanged launcher' 0 "${#privileged_commands[@]}"
test_assert_status 'Reject launcher without mytool' 2 self_update_install_launcher "$temporary_dir/missing"

test_run 'Pull update from git checkout' self_update_pull "$repository"
test_assert_equal 'Fast-forward only' "$repository pull --ff-only" "${git_commands[0]-}"
git_commands=()
test_assert_status 'Reject directory that is not a checkout' 2 self_update_pull "$temporary_dir"
test_assert_equal 'Run no git command outside a checkout' 0 "${#git_commands[@]}"

test_finish
