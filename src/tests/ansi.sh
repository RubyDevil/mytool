#!/usr/bin/env bash

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/test.sh
source "$test_dir/../lib/test.sh"
unset test_dir

test_assert_equal 'Strip rendered ANSI' 'red' "$(strip_ansi "${RED}red${RESET}")"
test_assert_equal 'Strip legacy literal ANSI' 'red' "$(strip_ansi '\e[31mred\e[0m')"
test_assert_equal 'Visible styled length' '3' "$(slen "${BOLD}foo${RESET}")"
test_assert_equal 'Unicode character length' '1' "$(slen '─')"
test_assert_equal 'Uppercase ANSI lookup' "$RED" "${ANSI[RED]}"
test_assert_equal 'Lowercase ANSI lookup' "$RED" "${ANSI[red]}"
test_run 'Bell constant is defined' test -n "$BEEP"
test_assert_equal 'Keep backslashes that are not escapes' 'C:\path\to' "$(strip_ansi 'C:\path\to')"
test_assert_into_names 'Strip styled text into any variable' 'red' strip_ansi_into "${RED}red${RESET}"
test_assert_into_names 'Strip literal escapes into any variable' 'red' strip_ansi_into '\e[31mred\e[0m'
test_assert_into_names 'Store plain text unchanged' 'plain text' strip_ansi_into 'plain text'
test_assert_into_names 'Store visible length in any variable' '3' stripped_length_into "${BOLD}foo${RESET}"
test_assert_into_names 'Store slen in any variable' '1' slen_into '─'
test_assert_equal 'Store length into the inner helper prefix' '3' "$(_test_receive _sai_text stripped_length_into "${BOLD}foo${RESET}")"

test_finish
