#!/usr/bin/env bash

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/test.sh
source "$test_dir/../lib/test.sh"
# shellcheck source=../core/util_scripts.sh
source "$test_dir/../core/util_scripts.sh"
template_dir=$(cd -- "$test_dir/../../util-scripts" && pwd)
unset test_dir

temporary_dir=$(mktemp -d)
trap 'rm -rf -- "$temporary_dir"' EXIT
UTIL_SCRIPTS_BIN_DIR="$temporary_dir/bin"
UTIL_SCRIPTS_CACHE_DIR="$temporary_dir/cache"
UTIL_SCRIPTS_SHARE_DIR="$temporary_dir/share"
mkdir -p -- "$UTIL_SCRIPTS_BIN_DIR"

privileged_commands=()
fail_hook=''
system_run_privileged() {
   local hook

   privileged_commands+=("$*")
   if [[ "$1" == bash && "$3" == */*install.sh ]]; then
      hook=$(basename -- "$3" .sh)
      printf '%s %s %s\n' "$hook" "$(basename -- "$(dirname -- "$3")")" "$4" >>"$temporary_dir/hooks.log"
      [[ "$fail_hook" != "$hook" ]]
      return
   fi
   "$@"
}
last_hooks() {
   tail -n "$1" "$temporary_dir/hooks.log" | paste -sd '|'
}

# Build a scripts repository with the template plus scripts covering each layout.
source_repo="$temporary_dir/source"
cp -R -- "$template_dir" "$source_repo"
mkdir -p -- "$source_repo/hello" "$source_repo/bad name" "$source_repo/empty"
printf '#!/usr/bin/env bash\n[[ "$1" == --help ]] && echo "hello help"\n' >"$source_repo/hello/hello.sh"
git -C "$source_repo" init --quiet
git -C "$source_repo" config core.autocrlf false
git -C "$source_repo" add -A
git -C "$source_repo" -c user.name=test -c user.email=test@example.com commit --quiet -m init

test_run 'Accept https repository' util_scripts_validate_repo https://github.com/user/scripts
test_run 'Accept SSH repository' util_scripts_validate_repo git@github.com:user/scripts.git
test_assert_status 'Reject option-like repository' 1 util_scripts_validate_repo '--upload-pack=touch'
test_assert_status 'Reject local repository path' 1 util_scripts_validate_repo /tmp/scripts
test_assert_status 'Reject repository with spaces' 1 util_scripts_validate_repo 'https://github.com/a b'
test_assert_status 'Reject path traversal name' 1 util_scripts_validate_name ../fan-speed
settings[UTIL_SCRIPTS_REPO]=''
test_assert_status 'Require a repository setting' 2 util_scripts_sync
settings[UTIL_SCRIPTS_REPO]='not a url'
test_assert_status 'Reject invalid repository setting' 2 util_scripts_sync

test_run 'Clone scripts repository' util_scripts_fetch "file://$source_repo" "$UTIL_SCRIPTS_CACHE_DIR"
test_assert_equal 'List repository scripts' $'fan-speed\nhello' "$(util_scripts_available)"
test_assert_equal 'Find main file without extension' "$UTIL_SCRIPTS_CACHE_DIR/fan-speed/fan-speed" \
   "$(util_scripts_main_file "$UTIL_SCRIPTS_CACHE_DIR/fan-speed" fan-speed)"
test_assert_equal 'Report missing script' 'missing' "$(util_scripts_status fan-speed)"
test_run 'Show documentation file' grep -q '^Usage:' <(util_scripts_doc fan-speed)
test_assert_equal 'Fall back to --help output' 'hello help' "$(util_scripts_doc hello)"

printf 'changed\n' >>"$source_repo/hello/hello.sh"
git -C "$source_repo" -c user.name=test -c user.email=test@example.com commit --quiet -am update
printf 'local edit\n' >"$UTIL_SCRIPTS_CACHE_DIR/stray"
test_run 'Update existing clone' util_scripts_fetch "file://$source_repo" "$UTIL_SCRIPTS_CACHE_DIR"
test_run 'Pull latest repository commit' grep -q '^changed$' "$UTIL_SCRIPTS_CACHE_DIR/hello/hello.sh"
test_run 'Discard stray cache files' test ! -e "$UTIL_SCRIPTS_CACHE_DIR/stray"

fan_speed_target="$UTIL_SCRIPTS_BIN_DIR/fan-speed"
fan_speed_record="$UTIL_SCRIPTS_SHARE_DIR/fan-speed"
test_run 'Install fan-speed' util_scripts_install fan-speed
test_assert_equal 'Copy fan-speed script' "$(<"$UTIL_SCRIPTS_CACHE_DIR/fan-speed/fan-speed")" "$(<"$fan_speed_target")"
test_run 'Keep install record with hooks' test -f "$fan_speed_record/uninstall.sh"
test_assert_equal 'Run install.sh after install' "install fan-speed $fan_speed_target" "$(last_hooks 1)"
test_assert_equal 'Report installed script' 'installed' "$(util_scripts_status fan-speed)"
test_assert_equal 'List installed scripts' 'fan-speed' "$(util_scripts_installed)"
chmod 700 -- "$UTIL_SCRIPTS_CACHE_DIR/hello"
test_run 'Install script without hooks' util_scripts_install hello
test_run 'Make install record readable to all users' test "$(stat -c %a -- "$UTIL_SCRIPTS_SHARE_DIR/hello")" = 755
test_assert_equal 'Install script with .sh layout' "$(<"$UTIL_SCRIPTS_CACHE_DIR/hello/hello.sh")" "$(<"$UTIL_SCRIPTS_BIN_DIR/hello")"

test_run 'Update installed script' util_scripts_install fan-speed
test_assert_equal 'Uninstall old version before installing new' \
   "uninstall fan-speed.mytool-old $fan_speed_target|install fan-speed $fan_speed_target" "$(last_hooks 2)"

printf 'old version\n' >"$fan_speed_target"
printf '# old\n' >>"$fan_speed_record/install.sh"
test_assert_equal 'Report outdated script' 'outdated' "$(util_scripts_status fan-speed)"
fail_hook=install
test_assert_status 'Fail update when install.sh fails' 1 util_scripts_install fan-speed
test_assert_equal 'Restore previous script after failure' 'old version' "$(<"$fan_speed_target")"
test_run 'Restore previous install record' grep -q '^# old$' "$fan_speed_record/install.sh"
test_assert_equal 'Reinstall previous version after failure' "install fan-speed $fan_speed_target" "$(last_hooks 1)"
test_run 'Remove staged install record' test ! -e "$fan_speed_record.mytool-new"
test_run 'Remove backup install record' test ! -e "$fan_speed_record.mytool-old"
fail_hook=uninstall
test_assert_status 'Fail update when old uninstall.sh fails' 1 util_scripts_install fan-speed
test_assert_equal 'Keep installed script when uninstall fails' 'old version' "$(<"$fan_speed_target")"
test_run 'Keep install record when uninstall fails' grep -q '^# old$' "$fan_speed_record/install.sh"
fail_hook=''

sync_calls=0
util_scripts_sync() { sync_calls=$((sync_calls + 1)); }
test_run 'Update installed scripts' util_scripts_update_installed
test_assert_equal 'Update outdated script on refresh' 'installed' "$(util_scripts_status fan-speed)"

printf 'system command\n' >"$UTIL_SCRIPTS_BIN_DIR/other"
mkdir -p -- "$UTIL_SCRIPTS_CACHE_DIR/other"
cp -- "$UTIL_SCRIPTS_CACHE_DIR/hello/hello.sh" "$UTIL_SCRIPTS_CACHE_DIR/other/other"
test_assert_status 'Refuse to overwrite unmanaged command' 1 util_scripts_install other
test_assert_equal 'Keep unmanaged command' 'system command' "$(<"$UTIL_SCRIPTS_BIN_DIR/other")"

rm -rf -- "$UTIL_SCRIPTS_CACHE_DIR/fan-speed"
test_assert_equal 'Report script removed from repository' 'removed' "$(util_scripts_status fan-speed)"
test_run 'Show installed documentation after removal' grep -q '^Usage:' <(util_scripts_doc fan-speed)
privileged_commands=()
test_run 'Update skips removed scripts' util_scripts_update_installed
test_assert_equal 'Keep removed script installed' 'removed' "$(util_scripts_status fan-speed)"

test_run 'Uninstall removed script' util_scripts_uninstall fan-speed
test_assert_equal 'Run uninstall.sh before removal' "uninstall fan-speed $fan_speed_target" "$(last_hooks 1)"
test_run 'Remove uninstalled script' test ! -e "$fan_speed_target"
test_run 'Remove install record' test ! -e "$fan_speed_record"
test_assert_status 'Reject uninstalling unknown script' 2 util_scripts_uninstall fan-speed
util_scripts_uninstall hello
sync_calls=0
test_run 'Refresh with nothing installed' util_scripts_refresh
test_assert_equal 'Skip sync with nothing installed' 0 "$sync_calls"

# fan-speed's own install.sh and uninstall.sh, run with fake system commands.
fake_bin="$temporary_dir/fake-bin"
sudoers_dir="$temporary_dir/sudoers.d"
mkdir -p -- "$fake_bin"
printf '#!/usr/bin/env bash\n[[ "$2" == sudo ]]\n' >"$fake_bin/getent"
printf '#!/usr/bin/env bash\necho "visudo $*" >>"%s"\n[[ -z "$FAIL_VISUDO" ]]\n' "$temporary_dir/commands.log" >"$fake_bin/visudo"
printf '#!/usr/bin/env bash\necho "apt-get $*" >>"%s"\n' "$temporary_dir/commands.log" >"$fake_bin/apt-get"
chmod +x -- "$fake_bin"/*
run_fan_speed_hook() {
   local hook="$1"
   shift
   PATH="$fake_bin:$PATH" MYTOOL_SUDOERS_DIR="$sudoers_dir" bash "$template_dir/fan-speed/$hook.sh" "$@"
}
test_run 'Run fan-speed install.sh' run_fan_speed_hook install /usr/local/bin/fan-speed
test_assert_equal 'Allow sudo group without password' \
   $'# Managed by mytool: lets sudoers run /usr/local/bin/fan-speed without a password.\n%sudo ALL=(root) NOPASSWD: /usr/local/bin/fan-speed' \
   "$(<"$sudoers_dir/mytool-fan-speed")"
if ! command -v ipmitool >/dev/null; then
   test_run 'Install missing ipmitool' grep -q '^apt-get install -y ipmitool$' "$temporary_dir/commands.log"
fi
test_run 'Validate sudoers rule' grep -q '^visudo -cqf ' "$temporary_dir/commands.log"
rm -f -- "$sudoers_dir/mytool-fan-speed"
FAIL_VISUDO=1 test_assert_status 'Fail install.sh on invalid sudoers rule' 1 run_fan_speed_hook install /usr/local/bin/fan-speed
test_run 'Write no rejected sudoers rule' test ! -e "$sudoers_dir/mytool-fan-speed"
test_assert_status 'Reject unsafe sudoers path' 2 run_fan_speed_hook install '/usr/local/bin/x ALL'
test_run 'Run fan-speed install.sh again' run_fan_speed_hook install /usr/local/bin/fan-speed
test_run 'Remove rule on uninstall' run_fan_speed_hook uninstall /usr/local/bin/fan-speed
test_run 'Delete sudoers rule' test ! -e "$sudoers_dir/mytool-fan-speed"

fan_speed_source="$template_dir/fan-speed/fan-speed"
printf '#!/usr/bin/env bash\nprintf "sudo %%s\\n" "$*"\n' >"$fake_bin/sudo"
chmod +x -- "$fake_bin/sudo"
if ((EUID != 0)); then
   test_assert_equal 'Elevate fan-speed through sudo' "sudo -- $fan_speed_source 8" \
      "$(PATH="$fake_bin:$PATH" bash "$fan_speed_source" 08)"
fi
test_assert_status 'Reject fan speed above 100' 1 bash "$fan_speed_source" 101
test_assert_status 'Reject non-numeric fan speed' 1 bash "$fan_speed_source" fast
test_assert_status 'Reject negative fan speed' 1 bash "$fan_speed_source" -1
test_assert_status 'Require one fan speed argument' 1 bash "$fan_speed_source"

test_finish
