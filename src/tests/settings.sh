#!/usr/bin/env bash

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/test.sh
source "$test_dir/../lib/test.sh"
# shellcheck source=../lib/settings.sh
source "$test_dir/../lib/settings.sh"
unset test_dir

temporary_dir=$(mktemp -d)
settings_path="$temporary_dir/settings.conf"
marker="$temporary_dir/executed"
trap 'rm -rf -- "$temporary_dir"' EXIT

printf -v complex_value 'line 1\nline 2\nC:\\tools'
settings[COMPLEX_VALUE]="$complex_value"
settings[COMMAND_TEXT]="\$(touch \"$marker\")"
test_run 'Save settings' settings_save_to_file "$settings_path"

settings=()
test_run 'Load settings' settings_load_from_file "$settings_path"
test_assert_equal 'Round-trip multiline and backslashes' "$complex_value" "${settings[COMPLEX_VALUE]}"
test_assert_equal 'Merge missing defaults' 'LIGHT' "${settings[MENU_BORDER_TYPE]}"
test_run 'Do not execute setting text' test ! -e "$marker"
test_assert_equal 'Private file permissions' '600' "$(stat -c '%a' "$settings_path")"

printf 'declare -A settings\nsettings["legacy_key"]="legacy value"\n' >"$settings_path"
test_run 'Load legacy settings format' settings_load_from_file "$settings_path"
test_assert_equal 'Read legacy value' 'legacy value' "${settings[legacy_key]}"

printf 'unknown_escape=\\q\n' >"$settings_path"
test_run 'Load unknown escape literally' settings_load_from_file "$settings_path"
test_assert_equal 'Preserve unknown escape' '\q' "${settings[unknown_escape]}"

printf 'not valid settings syntax\n' >"$settings_path"
test_assert_status 'Report malformed settings' 1 settings_load_from_file "$settings_path"
test_assert_equal 'Keep defaults after malformed file' 'LIGHT' "${settings[MENU_BORDER_TYPE]}"

test_finish
