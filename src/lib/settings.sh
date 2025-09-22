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
# Newly added menu layout / behavior defaults
default_settings["MENU_POINTER_TYPE"]=">"          # Character used to point at selected item
default_settings["MENU_TOP"]="0"                    # Top row of menu
default_settings["MENU_LEFT"]="0"                   # Left column of menu
default_settings["MENU_MIN_WIDTH"]="0"              # 0 = auto
default_settings["MENU_MAX_WIDTH"]="0"              # 0 = unlimited
default_settings["MENU_MIN_HEIGHT"]="0"             # 0 = auto
default_settings["MENU_MAX_HEIGHT"]="0"             # 0 = fit terminal

# --- Settings metadata -------------------------------------------------------------------------
# Types: enum | bool | int | string
declare -A settings_types
settings_types["NGINX_CONFIG_DIR"]="string"
settings_types["MENU_BORDER_TYPE"]="enum"
settings_types["MENU_BORDER_COLOR"]="enum"
settings_types["MENU_POINTER_COLOR"]="enum"
settings_types["MENU_POINTER_TYPE"]="enum"
settings_types["MENU_TOP"]="int"
settings_types["MENU_LEFT"]="int"
settings_types["MENU_MIN_WIDTH"]="int"
settings_types["MENU_MAX_WIDTH"]="int"
settings_types["MENU_MIN_HEIGHT"]="int"
settings_types["MENU_MAX_HEIGHT"]="int"

# Enumerated values (space-separated lists)
declare -A settings_enums
settings_enums["MENU_BORDER_TYPE"]="LIGHT HEAVY"
settings_enums["MENU_BORDER_COLOR"]="FG_DEFAULT FG_WHITE FG_RED FG_GREEN FG_YELLOW FG_BLUE FG_MAGENTA FG_CYAN"
settings_enums["MENU_POINTER_COLOR"]="FG_DEFAULT FG_WHITE FG_RED FG_GREEN FG_YELLOW FG_BLUE FG_MAGENTA FG_CYAN"
settings_enums["MENU_POINTER_TYPE"]="> ▶ ➤ → *"
# Boolean is treated as enum 0/1 for simplicity

# Groupings
MENU_SETTINGS_KEYS=(
   MENU_BORDER_TYPE
   MENU_BORDER_COLOR
   MENU_POINTER_COLOR
   MENU_POINTER_TYPE
   MENU_TOP
   MENU_LEFT
   MENU_MIN_WIDTH
   MENU_MAX_WIDTH
   MENU_MIN_HEIGHT
   MENU_MAX_HEIGHT
)

# Helper to get type (defaults to string)
settings_get_type() { local k=$1; echo -n "${settings_types[$k]:-string}"; }
settings_is_enum() { local k=$1; local t=$(settings_get_type "$k"); [[ $t == enum || $t == bool ]] && return 0 || return 1; }
settings_get_enum_values() { local k=$1; echo -n "${settings_enums[$k]}"; }

# ================= Settings Interactive UI (built-in) ======================
# These functions build and edit the Settings menu (moved from main script).

# Prompt editor for string/int settings
settings_ui_edit_prompt() {
   local key=$1
   local old_value=${settings[$key]}
   # Show basic info
   clear 2>/dev/null || true
   echo -e "${DIM:-}Edit setting:${RESET:-} $key"
   echo -e "Current value: ${CYAN:-}$old_value${RESET:-}"
   echo
   read -p "New value: " new_value
   if [[ $(settings_get_type "$key") == int ]]; then
      if [[ ! $new_value =~ ^[0-9]+$ ]]; then
         echo -e "${RED:-}Invalid integer.${RESET:-}"; read -p "Press enter"; return
      fi
   fi
   echo
   echo -e "Change $key: $old_value -> $new_value"
   read -p "Confirm? [y/N] " -n1 reply; echo
   if [[ $reply =~ ^[Yy]$ ]]; then
      settings[$key]="$new_value"
      settings_save_to_file ""
      echo -e "${GREEN:-}Updated.${RESET:-}"
   else
      echo -e "${RED:-}Canceled.${RESET:-}"
   fi
   read -p "Press enter" _
}

# Build enum selection submenu
settings_ui_enum_menu() {
   local key=$1
   local values=( $(settings_get_enum_values "$key") )
   menu_header="Setting: $key"
   menu=(
      "${RED:-}Back${RESET:-}" "build_menu_settings"
   )
   for v in "${values[@]}"; do
      local marker=""
      if [[ ${settings[$key]} == "$v" ]]; then marker="${GREEN:-}*${RESET:-} "; fi
      menu+=("${marker}${CYAN:-}$v${RESET:-}" "settings_ui_apply_enum $key $v")
   done
}

settings_ui_apply_enum() {
   local key=$1; shift; local value=$1
   settings[$key]="$value"
   settings_save_to_file ""
   build_menu_settings
}

settings_ui_dispatch_edit() {
   local key=$1
   if settings_is_enum "$key"; then
      settings_ui_enum_menu "$key"
   else
      settings_ui_edit_prompt "$key"
      build_menu_settings
   fi
}

# Main settings menu builder (used by application)
build_menu_settings() {
   local arg="$1"
   # If arg matches a setting key, edit it
   if [ -n "$arg" ] && [ -n "${settings[$arg]+x}" ]; then
      settings_ui_dispatch_edit "$arg"; return
   fi
   # If arg is 'menu', open submenu of menu-related keys
   if [ "$arg" = "menu" ]; then
      menu_header="Menu Settings"
      menu=(
         "${RED:-}Back${RESET:-}" "build_menu_settings"
      )
      for key in "${MENU_SETTINGS_KEYS[@]}"; do
         local t=$(settings_get_type "$key")
         local val="${settings[$key]}"; (( ${#val} > 30 )) && val="${val:0:27}..."
         menu+=("${CYAN:-}$key${RESET:-} ${DIM:-}[$t]${RESET:-} ${DIM:-}(${val})${RESET:-}" "build_menu_settings $key")
      done
      return
   fi
   # Root settings (excluding menu group keys, replaced with single entry)
   menu_header="Settings"
   menu=(
      "${RED:-}Back${RESET:-}" "build_menu_main"
      "${BLUE:-}Menu Settings${RESET:-}" "build_menu_settings menu"
   )
   local keys=( )
   for k in "${!settings[@]}"; do
      skip=false
      for mk in "${MENU_SETTINGS_KEYS[@]}"; do
         if [ "$k" = "$mk" ]; then skip=true; break; fi
      done
      $skip && continue
      keys+=("$k")
   done
   IFS=$'\n' keys=( $(printf '%s\n' "${keys[@]}" | sort) ); unset IFS
   for key in "${keys[@]}"; do
      local t=$(settings_get_type "$key")
      local val="${settings[$key]}"; (( ${#val} > 30 )) && val="${val:0:27}..."
      menu+=("${CYAN:-}$key${RESET:-} ${DIM:-}[$t]${RESET:-} ${DIM:-}(${val})${RESET:-}" "build_menu_settings $key")
   done
}

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
   fi

   # Backfill any new defaults missing from loaded settings
   for key in "${!default_settings[@]}"; do
      if [ -z "${settings[$key]+__DEFINED__}" ]; then
         settings[$key]="${default_settings[$key]}"
      fi
   done

   # Remove deprecated settings
   unset 'settings[MENU_CLEAR_SCREEN]'
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
