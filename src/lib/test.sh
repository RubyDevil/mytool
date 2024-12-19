#!/bin/bash

test_print_name() {
   local width="${2:-35}" # Set the width to $2 if it's provided, otherwise use 35
   echo -e -n "${DIM}[TEST] ${RESET}"
   printf "%-${width}s" "$1:"
}

test_print_result() {
   if [ "$1" -eq 0 ]; then
      echo -e "[${FG_GREEN}PASS${RESET}]"
   else
      echo -e "[${FG_RED}FAIL${RESET}]"
   fi
}
