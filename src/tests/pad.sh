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

test_finish
