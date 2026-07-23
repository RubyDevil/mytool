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

test_finish
