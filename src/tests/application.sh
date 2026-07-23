#!/usr/bin/env bash

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/test.sh
source "$test_dir/../lib/test.sh"
# shellcheck source=../mytool
source "$test_dir/../mytool"
unset test_dir

build_menu_main
test_assert_equal 'Build main menu header' 'Main Menu' "$menu_header"
test_assert_equal 'Build main menu items' '3' "${#menu_labels[@]}"
test_assert_equal 'Keep main menu hierarchy' 'Tools' "$(strip_ansi "${menu_labels[1]}")"

test_run 'Navigate to tools builder' menu_invoke 1
test_assert_equal 'Build tools menu header' 'Tools' "$menu_header"
test_assert_equal 'Keep reverse proxy tool entry' 'RPM (Reverse Proxy Manager)' "$(strip_ansi "${menu_labels[1]}")"

build_menu_settings
test_assert_equal 'Build settings menu items' '6' "${#menu_labels[@]}"
test_assert_equal 'Sort setting entries' 'MENU_BORDER_COLOR (current: WHITE)' "$(strip_ansi "${menu_labels[1]}")"
test_run 'Accept configured heavy border' settings_validate_value MENU_BORDER_TYPE heavy
test_assert_status 'Reject unknown border' 1 settings_validate_value MENU_BORDER_TYPE rounded
test_assert_status 'Reject wide pointer' 1 settings_validate_value MENU_POINTER_TYPE '>>'

temporary_dir=$(mktemp -d)
trap 'rm -rf -- "$temporary_dir"' EXIT
settings[NGINX_CONFIG_DIR]="$temporary_dir"
reverse_proxy_save_config z.example 9000
reverse_proxy_save_config a.example 8000
build_menu_reverse_proxy
test_assert_equal 'Build proxy menu items' '4' "${#menu_labels[@]}"
test_assert_equal 'Sort proxy entries' 'a.example (port: 8000)' "$(strip_ansi "${menu_labels[2]}")"

MENU_HEIGHT=10
rendered=$(menu_render)
test_assert_equal 'Render application menu height' '10' "$(printf '%s\n' "$rendered" | wc -l)"

test_finish
