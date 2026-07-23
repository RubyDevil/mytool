#!/usr/bin/env bash

test_lib_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if ! declare -F strip_ansi >/dev/null; then
   # shellcheck source=ansi.sh
   source "$test_lib_dir/ansi.sh"
fi
unset test_lib_dir

declare -gi test_count=0
declare -gi test_failures=0

test_print_name() {
   local name="$1"
   local width="${2:-48}"
   printf '%s[TEST] %s%-*s%s' "$DIM" "$RESET" "$width" "$name:" "$RESET"
}

test_print_result() {
   local status="$1"

   ((test_count += 1))
   if ((status == 0)); then
      printf '[%sPASS%s]\n' "$GREEN" "$RESET"
   else
      ((test_failures += 1))
      printf '[%sFAIL%s]\n' "$RED" "$RESET"
   fi
}

test_run() {
   local name="$1"
   shift

   test_print_name "$name"
   "$@"
   local status=$?
   test_print_result "$status"
   return 0
}

test_assert_equal() {
   local name="$1"
   local expected="$2"
   local actual="$3"

   test_print_name "$name"
   if [[ "$actual" == "$expected" ]]; then
      test_print_result 0
   else
      test_print_result 1
      printf '       expected: %q\n' "$expected"
      printf '         actual: %q\n' "$actual"
   fi
}

test_assert_status() {
   local name="$1"
   local expected_status="$2"
   shift 2

   "$@" &>/dev/null
   local actual_status=$?
   test_assert_equal "$name" "$expected_status" "$actual_status"
}

test_finish() {
   printf '\n%d tests, %d failures\n' "$test_count" "$test_failures"
   ((test_failures == 0))
}
