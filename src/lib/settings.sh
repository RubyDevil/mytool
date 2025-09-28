#!/bin/bash

# This file contains utility functions for managing loading, saving, and modifying settings.
# Settings are stored in an associative array called settings.

settings_file="$HOME/.mytool.conf"

# Declare the settings associative array
declare -A default_settings
default_settings["NGINX_CONFIG_DIR"]="/etc/nginx/conf.d"
default_settings["MENU_BORDER_TYPE"]="LIGHT"
default_settings["MENU_BORDER_COLOR"]="WHITE"
default_settings["MENU_POINTER_COLOR"]="WHITE"
# TODO: Make menu pointer type configurable

declare -A settings
for key in "${!default_settings[@]}"; do
   settings["$key"]="${default_settings[$key]}"
done

# Load settings from file
settings_load_from_file() {
   local file="${1:-$settings_file}"

   # Check if the file exists
   if [ -f "$file" ]; then
      # Load the settings array from the file
      # shellcheck source=/dev/null
      source "$file"
      # echo "Settings loaded from $file"
      # for key in "${!default_settings[@]}"; do
      #    echo "  $key=${settings[$key]:-${default_settings[$key]}}"
      # done
   fi
}

# Save settings to file
settings_save_to_file() {
   local file="${1:-$settings_file}"

   # Save line to empty the settings array
   echo "declare -A settings" >"$file"
   # Save the settings array to a file
   for key in "${!settings[@]}"; do
      echo "settings[\"$key\"]=\"${settings[$key]}\"" >>"$file"
   done
}
