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

MENU_HEIGHT=10
rendered=$(menu_render)
first_line=$(printf '%s\n' "$rendered" | head -n 1)
test_assert_equal 'Render terminal-height frame' '10' "$(printf '%s\n' "$rendered" | wc -l)"
test_assert_equal 'Widen frame to fit footer' '23' "$(slen "$first_line")"
test_assert_equal 'Render footer hints' '│    Enter: select    │' "$(strip_ansi "$(sed -n 9p <<<"$rendered")")"
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

MENU_HEIGHT=14
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

back_calls=()
record_back() {
   back_calls+=("$#:$*")
}
test_assert_status 'Fail back without a target' 1 menu_go_back
test_assert_status 'Reject command-string back callback' 2 menu_set_back 'record_back; true'
test_run 'Set back target' menu_set_back record_back 'value with spaces' ''
test_assert_equal 'Show back hint in footer' 'Enter: select   Esc/q: back' "$(menu_footer)"
test_run 'Go back' menu_go_back
test_assert_equal 'Pass back arguments losslessly' '2:value with spaces ' "${back_calls[0]}"
test_run 'Set exit target' menu_set_exit record_back
test_assert_equal 'Show exit hint in footer' 'Enter: select   Esc/q: exit' "$(menu_footer)"
menu_clear_multi 'Multi Back'
test_assert_equal 'Clear back target' '' "$menu_back_callback"
menu_set_back record_back
test_assert_equal 'Show multi-select hints in footer' 'Space: toggle   Enter: run   Esc/q: back' "$(menu_footer)"
test_assert_into_names 'Store footer in any variable' 'Space: toggle   Enter: run   Esc/q: back' menu_footer_into

settings[MENU_BORDER_TYPE]=LIGHT
menu_add_selected Chosen capture_argument chosen
test_assert_into_names 'Store display label in any variable' '[x] Chosen' menu_display_label_into 0
test_assert_into_names 'Store resolved color in any variable' "$RED" menu_resolve_color_into red
test_assert_into_names 'Store border character in any variable' '┼' menu_border_char_into 1111
MENU_HEIGHT=12
test_assert_into_names 'Store menu height in any variable' '12' menu_terminal_rows_into

terminal_size_with() {
   local stty_output="$1"
   local tput_lines="$2"
   local tput_cols="$3"
   (
      stty() { printf '%s\n' "$stty_output"; }
      tput() {
         case "$1" in
         lines) printf '%s\n' "$tput_lines" ;;
         cols) printf '%s\n' "$tput_cols" ;;
         esac
      }
      unset MENU_HEIGHT
      menu_terminal_size_known=0
      menu_terminal_rows_into rows
      printf '%sx%s:%s' "$rows" "$menu_terminal_columns" "$menu_terminal_size_known"
   )
}
test_assert_equal 'Read terminal size from stty' '40x100:1' "$(terminal_size_with '40 100' 30 90)"
test_assert_equal 'Fall back to tput for a zero stty size' '30x90:1' "$(terminal_size_with '0 0' 30 90)"
test_assert_equal 'Fall back to 24x80 without a size' '24x80:1' "$(terminal_size_with '' '' '')"

menu_clear 'Draw Test'
menu_add First capture_argument first
menu_add Second capture_argument second
settings[MENU_POINTER_TYPE]='>'
menu_prepare_layout
selected_index=0
drawn_selected=$(menu_draw_option 0)
drawn_other=$(menu_draw_option 1)
test_assert_equal 'Position selected option with one cursor move' $'\033[5;4H' "${drawn_selected:0:6}"
test_assert_equal 'Draw pointer before selected option' "> $(pad_right First "$content_width")" "$(strip_ansi "${drawn_selected:6}")"
test_assert_equal 'Clear pointer column of other options' $'\033[6;4H  '"$(pad_right Second "$content_width")" "$(strip_ansi "$drawn_other")"
draw_both_options() {
   menu_draw_option 0
   menu_draw_option 1
}
test_assert_no_processes 'Redraw options without starting processes' draw_both_options
test_assert_no_processes 'Render menu without starting processes' menu_render

test_finish
