#!/usr/bin/env bash

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export LC_ALL="${LC_ALL:-C.UTF-8}"

tests=(ansi pad settings menu reverse_proxy application)
status=0

for test_name in "${tests[@]}"; do
   printf '\n== %s ==\n' "$test_name"
   if ! bash "$test_dir/$test_name.sh"; then
      status=1
   fi
done

exit "$status"
