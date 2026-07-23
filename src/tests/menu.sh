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

multi_calls=()
record_multi_call() {
   multi_calls+=("$1:$2")
}

rebuild_during_multi_call() {
   multi_calls+=("$1:$2")
   menu_clear 'Rebuilt'
   menu_add Replacement capture_argument replacement
}

fail_multi_call() {
   multi_calls+=("failure:$1")
   return 1
}

menu_clear_multi 'Multi Test'
menu_add_selected First record_multi_call first 'one value'
menu_add Second rebuild_during_multi_call second 'two; value'
menu_add Third record_multi_call third ''
menu_add Failure fail_multi_call four
menu_add Last record_multi_call fifth done
menu_add_action Unselected record_multi_call sixth skipped
test_assert_equal 'Enable multi-select menu' '1' "$menu_multi_select"
test_assert_equal 'Pre-select menu item' '1' "${menu_selected[0]}"
test_run 'Select third item first' menu_toggle_selected 2
test_run 'Deselect pre-selected item' menu_toggle_selected 0
test_run 'Reselect pre-selected item' menu_toggle_selected 0
test_run 'Select rebuilding item' menu_toggle_selected 1
test_run 'Select failing item' menu_toggle_selected 3
test_run 'Select final item' menu_toggle_selected 4
test_run 'Deselect final item' menu_toggle_selected 4
test_run 'Reselect final item' menu_toggle_selected 4
test_assert_status 'Reject toggling immediate action' 1 menu_toggle_selected 5

MENU_HEIGHT=12
multi_rendered=$(menu_render)
plain_multi_rendered=$(strip_ansi "$multi_rendered")
action_line=$(grep -F 'Unselected' <<<"$plain_multi_rendered")
checked_line=$(grep -F '[x] First' <<<"$plain_multi_rendered")
test_assert_equal 'Align immediate action with checkbox column' "${checked_line%%\[*}" "${action_line%%Unselected*}"
test_run 'Render checked multi-select marker' grep -Fq '[x] First' <<<"$(strip_ansi "$multi_rendered")"
test_assert_status 'Report selected callback failure' 1 menu_invoke_selected
test_assert_equal 'Execute selected callbacks in menu order' 'first:one value|second:two; value|third:|failure:four|fifth:done' "$(IFS='|'; printf '%s' "${multi_calls[*]}")"
test_assert_equal 'Use snapshot when callback rebuilds menu' 'Rebuilt:1' "$menu_header:${#menu_labels[@]}"

menu_clear_multi 'Empty Multi'
test_assert_status 'Reject empty multi-selection' 1 menu_invoke_selected

completion_calls=0
complete_multi_call() {
   completion_calls=$((completion_calls + 1))
   multi_calls+=(complete)
}

menu_clear_multi 'Completion Test'
menu_add_selected Selected record_multi_call selected
menu_set_selected_complete_callback complete_multi_call
test_run 'Run selected completion callback' menu_invoke_selected
test_assert_equal 'Run completion after selected callbacks' 'complete' "${multi_calls[${#multi_calls[@]} - 1]}"
test_assert_equal 'Run completion once per batch' '1' "$completion_calls"

menu_clear 'Single Test'
test_assert_equal 'Reset multi-select mode' '0' "$menu_multi_select"

test_finish
