#!/bin/bash

# This file contains utility functions for managing loading, saving, and modifying settings.
# Settings are stored in an associative array called settings.

# Declare the settings associative array
declare -A settings

# Load settings from file
settings_load_from_file() {
   local file="$1"

   # Check if the file exists
   if [ -f "$file" ]; then
      # Load the settings array from the file
      # shellcheck source=/dev/null
      source "$file"
   fi
}

# Save settings to file
settings_save_to_file() {
   local file="$1"

   # Save line to empty the settings array
   echo "declare -A settings" >"$file"
   # Save the settings array to a file
   for key in "${!settings[@]}"; do
      echo "settings[\"$key\"]=\"${settings[$key]}\"" >>"$file"
   done
}
