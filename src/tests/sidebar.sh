#!/usr/bin/env bash

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/test.sh
source "$test_dir/../lib/test.sh"
# shellcheck source=../lib/sidebar.sh
source "$test_dir/../lib/sidebar.sh"
unset test_dir

describe_item() {
   printf 'Documentation for %s\n' "$1"
   if [[ "$1" == long ]]; then
      printf 'word %.0s' {1..12}
      printf '\n  '
      printf 'indented %.0s' {1..4}
      printf '\n'
   elif [[ "$1" == tall ]]; then
      printf 'line\n%.0s' {1..20}
   fi
}

rendered_line() {
   strip_ansi "$(sed -n "${1}p" <<<"$rendered")"
}

test_assert_status 'Reject unsafe content callback' 2 sidebar_clear 'Items' 'describe_item; true'
sidebar_clear 'Scripts' describe_item
sidebar_add alpha
sidebar_add long
sidebar_add tall

MENU_HEIGHT=10
SIDEBAR_WIDTH=40
rendered=$(sidebar_render)
test_assert_equal 'Render terminal-height frame' '10' "$(printf '%s\n' "$rendered" | wc -l)"
widths=$(while IFS= read -r line; do slen "$line"; printf '\n'; done <<<"$rendered" | sort -u)
test_assert_equal 'Render every line at full width' '40' "$widths"
test_assert_equal 'Join sidebar and content borders' '┌─────────┬────────────────────────────┐' "$(rendered_line 1)"
test_assert_equal 'Show selected item title' '│ Scripts │ alpha                      │' "$(rendered_line 2)"
test_assert_equal 'Point at selected item' '│ > alpha │ Documentation for alpha    │' "$(rendered_line 4)"
test_assert_equal 'Close sidebar above footer' '├─────────┴────────────────────────────┤' "$(rendered_line 8)"

sidebar_move_down
rendered=$(sidebar_render)
test_assert_equal 'Highlight next item' '│ > long  │ word word word word word   │' "$(rendered_line 5)"
test_assert_equal 'Wrap long documentation' '│   tall  │ word word word word word   │' "$(rendered_line 6)"
test_assert_equal 'Keep indentation when wrapping' '2' "$(sidebar_content_lines 26 | grep -c '^  indented indented $')"

sidebar_move_down
rendered=$(sidebar_render)
test_assert_equal 'Mark truncated documentation' '│         │ ... (PgDn for more)        │' "$(rendered_line 7)"
sidebar_scroll_by 100
sidebar_render >/dev/null
rendered=$(sidebar_render)
test_assert_equal 'Clamp scroll to the last page' '17' "$sidebar_scroll"
test_assert_equal 'Show last documentation line' '│         │ line                       │' "$(rendered_line 7)"
sidebar_scroll_by -100
test_assert_equal 'Stop scrolling at the top' '0' "$sidebar_scroll"
sidebar_scroll_by 5
sidebar_move_up
test_assert_equal 'Reset scroll when changing item' '0' "$sidebar_scroll"
sidebar_move_down

sidebar_move_down
test_assert_equal 'Wrap downward to first item' '0' "$sidebar_index"
sidebar_move_up
test_assert_equal 'Wrap upward to last item' '2' "$sidebar_index"

sidebar_index=0
sidebar_render >/dev/null
test_assert_no_processes 'Render a viewed item without starting processes' sidebar_render
test_assert_into_names 'Store sidebar width in any variable' '40' sidebar_terminal_columns_into
test_assert_into_names 'Store border line in any variable' "┌─────┬──────┐$FG_DEFAULT" \
   sidebar_border_line_into 0110 '┬' 0011 3 4 '─' ''

callback_log=$(mktemp)
trap 'rm -f -- "$callback_log"' EXIT
log_item() {
   printf '%s\n' "$1" >>"$callback_log"
   [[ "$1" == quiet ]] && return
   printf 'Documentation for %s\n' "$1"
   printf 'line\n%.0s' {1..20}
}
logged_calls() {
   local -a calls=()
   mapfile -t calls <"$callback_log"
   printf '%s' "${calls[*]}"
}
sidebar_clear 'Scripts' log_item
sidebar_add first
sidebar_add quiet
sidebar_render >/dev/null
sidebar_render >/dev/null
sidebar_scroll_by 5
sidebar_render >/dev/null
sidebar_move_down
sidebar_render >/dev/null
sidebar_render >/dev/null
sidebar_move_up
sidebar_render >/dev/null
SIDEBAR_WIDTH=60
sidebar_render >/dev/null
test_assert_equal 'Run content callback once per item' 'first quiet' "$(logged_calls)"
test_assert_equal 'Rewrap cached content for a new width' "│ > first │ $(pad_right 'Documentation for first' 46) │" \
   "$(rendered=$(sidebar_render) && rendered_line 4)"
sidebar_clear 'Scripts' log_item
sidebar_add first
sidebar_render >/dev/null
test_assert_equal 'Run content callback again after clearing' 'first quiet first' "$(logged_calls)"

wrap_item() {
   case "$1" in
   word) printf 'abcdefghijklmnopqrstuvwxyz0123456789\n' ;;
   blank) printf 'aaaaa b\n' ;;
   crlf) printf 'one two\r\nthree\r\n' ;;
   esac
}
wrapped() {
   sidebar_index=$1
   sidebar_load_content "$2"
   local IFS='|'
   printf '%s' "${sidebar_lines[*]}"
}
sidebar_clear 'Wrap' wrap_item
sidebar_add word
sidebar_add blank
sidebar_add crlf
test_assert_equal 'Break a word without blanks at the width' 'abcdefghij|klmnopqrst|uvwxyz0123|456789' "$(wrapped 0 10)"
test_assert_equal 'Start a line with a blank past the width' 'aaaaa| b' "$(wrapped 1 5)"
test_assert_equal 'Drop carriage returns from content' 'one two|three' "$(wrapped 2 26)"
wrap_at_zero() {
   sidebar_content_lines 0 >/dev/null
}
test_run 'Wrap at width zero without hanging' wrap_at_zero

test_finish
