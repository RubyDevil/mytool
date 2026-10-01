#!/usr/bin/env bash

system_run_privileged() {
   if ((EUID == 0)); then
      "$@"
   else
      sudo -- "$@"
   fi
}

# Install a file with root privileges, replacing the destination atomically.
system_install_file() {
   local source="$1"
   local destination="$2"
   local mode="$3"
   local temporary_file="$destination.mytool-new"

   [[ "$mode" =~ ^[0-7]{3,4}$ && "$destination" == /* ]] || return 2
   if ! system_run_privileged install -D -m "$mode" -- "$source" "$temporary_file" ||
      ! system_run_privileged mv -f -- "$temporary_file" "$destination"; then
      system_run_privileged rm -f -- "$temporary_file"
      return 1
   fi
}
