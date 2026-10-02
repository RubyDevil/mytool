#!/usr/bin/env bash

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/test.sh
source "$test_dir/../lib/test.sh"
# shellcheck source=../lib/pad.sh
source "$test_dir/../lib/pad.sh"
unset test_dir

test_assert_equal 'Pad right' 'foo..' "$(pad_right foo 5 .)"
test_assert_equal 'Pad left' '..foo' "$(pad_left foo 5 .)"
test_assert_equal 'Pad between strings' 'foo...bar' "$(pad_center foo bar 9 .)"
test_assert_equal 'Center keeps both strings when full' 'foobar' "$(pad_center foo bar 5 .)"
test_assert_equal 'Pad both sides with odd remainder' '.foo..' "$(pad_sides foo 6 .)"
test_assert_equal 'Styled text uses visible width' "${RED}foo${RESET}.." "$(pad_right "${RED}foo${RESET}" 5 .)"
test_assert_equal 'Unicode fill has width one' 'foo──' "$(pad_right foo 5 '─')"
test_assert_status 'Reject non-numeric width' 2 pad_right foo nope
test_assert_status 'Reject multi-character fill' 2 pad_right foo 5 '..'
test_assert_equal 'Ampersand fill stays literal' 'foo&&' "$(pad_right foo 5 '&')"
test_assert_equal 'Backslash fill stays literal' '\\foo' "$(pad_left foo 5 '\')"
test_assert_equal 'Overlong string is not padded' 'foobar' "$(pad_sides foobar 3 .)"
test_assert_into_names 'Pad right into any variable' "${RED}foo${RESET}──" pad_right_into "${RED}foo${RESET}" 5 '─'
test_assert_into_names 'Pad left into any variable' '&&foo' pad_left_into foo 5 '&'
test_assert_into_names 'Pad center into any variable' 'foo...bar' pad_center_into foo bar 9 .
test_assert_into_names 'Pad sides into any variable' '.foo..' pad_sides_into foo 6 .
test_assert_into_names 'Repeat a fill into any variable' '───' _pad_repeat_into '─' 3
test_assert_into_names 'Repeat nothing for a zero count' '' _pad_repeat_into . 0
test_assert_into_names 'Repeat nothing for a negative count' '' _pad_repeat_into . -3
test_assert_equal 'Pad into the inner helper prefix' 'foo..' "$(_test_receive _prp_padding pad_right_into foo 5 .)"
padded=kept
pad_right_into padded foo nope 2>/dev/null
test_assert_equal 'Keep the variable on invalid width' '2:kept' "$?:$padded"

test_finish
