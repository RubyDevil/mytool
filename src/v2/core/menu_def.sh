#!/bin/bash
# Menu Definition System - Declarative menu creation with recursive support

# Menu definition structure:
# - Each menu is a function that calls menu_define
# - menu_define takes: title, options_array_name, [parent_menu_function]
# - Options are: "display_text" "action_or_submenu_function" [keybind]

# Current menu state
declare -g MENU_CURRENT_DEF=""
declare -g MENU_CURRENT_TITLE=""
declare -g MENU_CURRENT_OPTIONS=()
declare -g MENU_PARENT_FUNCTION=""

# Menu definition registry (for recursive calls)
declare -gA MENU_REGISTRY=()

# Define a menu
# Usage: menu_define "title" options_array_name [parent_function]
menu_define() {
    local title="$1"
    local options_var="$2"
    local parent_func="${3:-}"
    
    MENU_CURRENT_TITLE="$title"
    MENU_PARENT_FUNCTION="$parent_func"
    
    # Copy options array
    local -n options_ref="$options_var"
    MENU_CURRENT_OPTIONS=("${options_ref[@]}")
    
    # Register this menu definition
    local caller_func="${FUNCNAME[1]}"
    MENU_REGISTRY["$caller_func"]="$title"
}

# Create a menu option
# Usage: menu_option "display" "action" [keybind]
menu_option() {
    echo "$1" "$2" "${3:-}"
}

# Create a submenu option that calls another menu function
# Usage: menu_submenu "display" submenu_function [keybind]
menu_submenu() {
    echo "$1" "menu_call $2" "${3:-}"
}

# Get menu option count
menu_option_count() {
    echo $(( ${#MENU_CURRENT_OPTIONS[@]} / 3 ))
}

# Get menu option at index (returns: display action keybind)
menu_get_option() {
    local index="$1"
    local base=$((index * 3))
    echo "${MENU_CURRENT_OPTIONS[$base]}" "${MENU_CURRENT_OPTIONS[$((base + 1))]}" "${MENU_CURRENT_OPTIONS[$((base + 2))]}"
}

# Check if an option is a submenu call
menu_is_submenu() {
    local action="$1"
    [[ "$action" =~ ^menu_call\ .* ]]
}

# Extract submenu function name from action
menu_extract_submenu() {
    local action="$1"
    echo "${action#menu_call }"
}