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

# Print the value an _into helper stores in a caller variable with the given name.
_test_receive() {
   local "$1"
   "$2" "$1" "${@:3}"
   printf '%s' "${!1}"
}

# Assert that an _into helper stores its result whatever the caller's variable is named.
test_assert_into_names() {
   local name="$1"
   local expected="$2"
   shift 2
   local receiver
   local expected_all=""
   local actual=""

   for receiver in text stripped length rows columns name key char fill padded label line; do
      expected_all+="$receiver=$expected;"
      actual+="$receiver=$(_test_receive "$receiver" "$@");"
   done
   test_assert_equal "$name" "$expected_all" "$actual"
}

# Store the most recently allocated process ID in the named variable; fails without /proc/loadavg.
_test_last_pid_into() {
   local _tlp_load1 _tlp_load5 _tlp_load15 _tlp_tasks _tlp_pid

   [[ -r /proc/loadavg ]] || return 1
   read -r _tlp_load1 _tlp_load5 _tlp_load15 _tlp_tasks _tlp_pid </proc/loadavg || return 1
   [[ "$_tlp_pid" =~ ^[0-9]+$ ]] || return 1
   printf -v "$1" '%s' "$_tlp_pid"
}

# Assert that a command starts no processes, retrying to absorb unrelated system activity.
test_assert_no_processes() {
   local name="$1"
   shift
   local -i attempt before after

   if ! _test_last_pid_into before; then
      test_print_name "$name"
      printf '[%sSKIP%s]\n' "$DIM" "$RESET"
      return 0
   fi
   for ((attempt = 0; attempt < 3; attempt++)); do
      _test_last_pid_into before
      "$@" >/dev/null
      _test_last_pid_into after
      ((after == before)) && break
   done
   test_assert_equal "$name" '0' "$((after - before))"
}

test_finish() {
   printf '\n%d tests, %d failures\n' "$test_count" "$test_failures"
   ((test_failures == 0))
}
