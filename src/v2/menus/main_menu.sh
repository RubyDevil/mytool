#!/bin/bash
# Main Menu - Root menu for the application

# Source dependencies
_main_menu_script_dir=$(dirname "${BASH_SOURCE[0]}")
source "$_main_menu_script_dir/../core/menu_engine.sh"
source "$_main_menu_script_dir/../../lib/ansi.sh"

# Main menu definition
menu_main() {
    local -a main_options=(
        "$(menu_option "${BLUE}Tools${RESET}" "menu_call menu_tools" "t")"
        "$(menu_option "${DIM}Settings${RESET}" "menu_call menu_settings" "s")"
        "$(menu_option "────────────────" ":" "")"
        "$(menu_option "${DIM}About${RESET}" "show_about" "a")"
    )
    
    menu_define "Main Menu" main_options
}

# Tools submenu
menu_tools() {
    local -a tools_options=(
        "$(menu_option "${BLUE}Reverse Proxy Manager${RESET} ${DIM}(RPM)${RESET}" "menu_call menu_reverse_proxy" "r")"
        "$(menu_option "${GREEN}Network Tools${RESET}" "menu_call menu_network" "n")"
        "$(menu_option "${YELLOW}System Tools${RESET}" "menu_call menu_system" "y")"
    )
    
    menu_define "Tools" tools_options
}

# Settings submenu (will be replaced by proper settings integration)
menu_settings() {
    local -a settings_options=(
        "$(menu_option "Menu Border Style" "change_border_style" "b")"
        "$(menu_option "Menu Size" "change_menu_size" "m")"
        "$(menu_option "Animation" "toggle_animation" "a")"
        "$(menu_option "────────────────" ":" "")"
        "$(menu_option "Reset to Defaults" "reset_settings" "r")"
    )
    
    menu_define "Settings" settings_options
}

# Placeholder menus for demonstration
menu_reverse_proxy() {
    local -a rpm_options=(
        "$(menu_option "List Proxies" "echo 'Listing proxies...' && sleep 2" "l")"
        "$(menu_option "Add Proxy" "echo 'Adding proxy...' && sleep 2" "a")"
        "$(menu_option "Remove Proxy" "echo 'Removing proxy...' && sleep 2" "r")"
    )
    
    menu_define "Reverse Proxy Manager" rpm_options
}

menu_network() {
    local -a network_options=(
        "$(menu_option "Ping Test" "ping -c 3 google.com" "p")"
        "$(menu_option "Port Scanner" "echo 'Port scanning not implemented' && sleep 2" "s")"
        "$(menu_option "DNS Lookup" "echo 'DNS lookup not implemented' && sleep 2" "d")"
    )
    
    menu_define "Network Tools" network_options
}

menu_system() {
    local -a system_options=(
        "$(menu_option "System Info" "uname -a && sleep 3" "i")"
        "$(menu_option "Disk Usage" "df -h && sleep 3" "d")"
        "$(menu_option "Memory Usage" "free -h && sleep 3" "m")"
    )
    
    menu_define "System Tools" system_options
}

# Action functions
show_about() {
    clear
    echo -e "${BLUE}MyTool v2.0${RESET}"
    echo -e "${DIM}A completely redesigned menu system${RESET}"
    echo ""
    echo "Features:"
    echo "• Custom keybinds instead of navigation buttons"
    echo "• Optimized rendering with incremental updates"
    echo "• Recursive menu definitions"
    echo "• Modern Unicode box drawing"
    echo "• Configurable appearance"
    echo ""
    echo -e "${DIM}Press any key to continue...${RESET}"
    read -rsn1
}

change_border_style() {
    local current_style=${MENU_CONFIG[BORDER_STYLE]}
    local styles=("light" "heavy" "simple")
    local next_style=""
    
    for (( i = 0; i < ${#styles[@]}; i++ )); do
        if [[ "${styles[i]}" == "$current_style" ]]; then
            next_style="${styles[$(( (i + 1) % ${#styles[@]} ))]}"
            break
        fi
    done
    
    menu_configure "border_style" "$next_style"
    menu_render_status "Border style changed to: $next_style" 2
}

change_menu_size() {
    local current_width=${MENU_CONFIG[MAX_WIDTH]}
    local sizes=(50 60 70 80)
    local next_size=""
    
    for (( i = 0; i < ${#sizes[@]}; i++ )); do
        if (( sizes[i] == current_width )); then
            next_size="${sizes[$(( (i + 1) % ${#sizes[@]} ))]}"
            break
        fi
    done
    
    menu_configure "max_width" "$next_size"
    menu_state_init  # Recalculate layout
    menu_render_status "Menu width changed to: $next_size" 2
}

toggle_animation() {
    local current=${MENU_CONFIG[ANIMATION]}
    local new_value="true"
    [[ "$current" == "true" ]] && new_value="false"
    
    menu_configure "animation" "$new_value"
    menu_render_status "Animation: $new_value" 2
}

reset_settings() {
    menu_configure "border_style" "light"
    menu_configure "max_width" "50"
    menu_configure "animation" "false"
    menu_state_init  # Recalculate layout
    menu_render_status "Settings reset to defaults" 2
}