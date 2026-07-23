#!/usr/bin/env bash

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/test.sh
source "$test_dir/../lib/test.sh"
# shellcheck source=../lib/menu.sh
source "$test_dir/../lib/menu.sh"
unset test_dir

capture_argument() {
   captured_argument="$1"
}

marker=$(mktemp -u)
menu_clear 'Test'
menu_add 'One' capture_argument "argument with spaces; touch $marker"
menu_add "${RED}Styled${RESET}" capture_argument two
menu_add 'Three' capture_argument three

test_run 'Invoke typed callback' menu_invoke 0
test_assert_equal 'Preserve callback argument' "argument with spaces; touch $marker" "$captured_argument"
test_run 'Do not execute callback argument' test ! -e "$marker"

MENU_HEIGHT=8
rendered=$(menu_render)
first_line=$(printf '%s\n' "$rendered" | head -n 1)
test_assert_equal 'Render terminal-height frame' '8' "$(printf '%s\n' "$rendered" | wc -l)"
test_assert_equal 'Render stable frame width' '16' "$(slen "$first_line")"
plain_first_line=$(strip_ansi "$first_line")
test_assert_equal 'Render light border' '┌' "${plain_first_line:0:1}"

settings[MENU_BORDER_TYPE]=HEAVY
heavy_render=$(menu_render)
heavy_first_line=$(printf '%s\n' "$heavy_render" | head -n 1)
plain_heavy_first_line=$(strip_ansi "$heavy_first_line")
test_assert_equal 'Render heavy border' '┏' "${plain_heavy_first_line:0:1}"

menu_prepare_layout
menu_move_up
test_assert_equal 'Wrap upward and scroll' '2:1' "$selected_index:$top_option"
menu_move_down
test_assert_equal 'Wrap downward to first' '0:0' "$selected_index:$top_option"
test_assert_status 'Reject command-string callback' 2 menu_add Bad 'echo unsafe'

test_finish
