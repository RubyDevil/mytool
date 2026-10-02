#!/bin/bash
# Reverse Proxy Manager Menu - Integration with existing RPM functionality

# Source dependencies
_rpm_script_dir=$(dirname "${BASH_SOURCE[0]}")
source "$_rpm_script_dir/../../lib/tools/reverse_proxy.sh"
source "$_rpm_script_dir/../../lib/ansi.sh"
source "$_rpm_script_dir/../core/menu_engine.sh"

# Main reverse proxy menu
menu_reverse_proxy() {
    # Load current configurations
    reverse_proxy_load_configs
    
    local -a rpm_options=(
        "$(menu_option "${GREEN}List Proxies${RESET}" "rpm_list_proxies" "l")"
        "$(menu_option "${BLUE}Add New Proxy${RESET}" "rpm_add_proxy" "a")"
        "$(menu_option "${YELLOW}Edit Proxy${RESET}" "rpm_edit_proxy" "e")"
        "$(menu_option "${RED}Remove Proxy${RESET}" "rpm_remove_proxy" "r")"
        "$(menu_option "────────────────" ":" "")"
        "$(menu_option "${DIM}Reload Nginx${RESET}" "rpm_reload_nginx" "n")"
        "$(menu_option "${DIM}Test Configuration${RESET}" "rpm_test_config" "t")"
    )
    
    menu_define "Reverse Proxy Manager" rpm_options
}

# Enhanced wrapper functions that work better with the new menu system
rpm_list_proxies() {
    clear
    echo -e "${BLUE}Current Reverse Proxy Configurations${RESET}"
    echo -e "${DIM}======================================${RESET}"
    echo ""
    
    if [[ ${#domains_and_ports[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No reverse proxy configurations found.${RESET}"
        echo ""
        echo -e "${DIM}Configuration directory: ${settings["NGINX_CONFIG_DIR"]}${RESET}"
    else
        printf "%-30s %s\n" "Domain" "Port"
        printf "%-30s %s\n" "------" "----"
        for domain in "${!domains_and_ports[@]}"; do
            printf "%-30s %d\n" "$domain" "${domains_and_ports[$domain]}"
        done
    fi
    
    echo ""
    echo -e "${DIM}Press any key to continue...${RESET}"
    read -rsn1
}

rpm_add_proxy() {
    # Temporarily restore terminal for input
    menu_input_cleanup
    
    clear
    echo -e "${BLUE}Add New Reverse Proxy${RESET}"
    echo -e "${DIM}=====================${RESET}"
    echo ""
    
    local domain port
    
    echo -n "Enter domain name: "
    read -r domain
    
    if [[ -z "$domain" ]]; then
        echo -e "${RED}Error: Domain name cannot be empty${RESET}"
        sleep 2
        menu_input_init
        return
    fi
    
    echo -n "Enter port number: "
    read -r port
    
    if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        echo -e "${RED}Error: Invalid port number${RESET}"
        sleep 2
        menu_input_init
        return
    fi
    
    echo ""
    echo -e "${YELLOW}Creating reverse proxy configuration...${RESET}"
    
    # Call the original function
    if reverse_proxy_create_config "$domain" "$port"; then
        echo -e "${GREEN}Successfully created configuration for $domain -> localhost:$port${RESET}"
        domains_and_ports["$domain"]="$port"
    else
        echo -e "${RED}Failed to create configuration${RESET}"
    fi
    
    echo ""
    echo -e "${DIM}Press any key to continue...${RESET}"
    read -rsn1
    
    # Restore menu input mode
    menu_input_init
}

rpm_edit_proxy() {
    if [[ ${#domains_and_ports[@]} -eq 0 ]]; then
        menu_render_status "No proxies to edit" 2
        return
    fi
    
    # Create a submenu with existing domains
    local -a edit_options=()
    for domain in "${!domains_and_ports[@]}"; do
        edit_options+=("$(menu_option "$domain (port ${domains_and_ports[$domain]})" "rpm_edit_single_proxy '$domain'" "")")
    done
    
    menu_define "Select Proxy to Edit" edit_options
    menu_render_full
}

rpm_edit_single_proxy() {
    local domain="$1"
    local current_port="${domains_and_ports[$domain]}"
    
    # Temporarily restore terminal for input
    menu_input_cleanup
    
    clear
    echo -e "${BLUE}Edit Reverse Proxy: $domain${RESET}"
    echo -e "${DIM}Current port: $current_port${RESET}"
    echo ""
    
    local new_port
    echo -n "Enter new port number (or press Enter to keep $current_port): "
    read -r new_port
    
    if [[ -z "$new_port" ]]; then
        new_port="$current_port"
    elif [[ ! "$new_port" =~ ^[0-9]+$ ]] || (( new_port < 1 || new_port > 65535 )); then
        echo -e "${RED}Error: Invalid port number${RESET}"
        sleep 2
        menu_input_init
        menu_go_back
        return
    fi
    
    if [[ "$new_port" != "$current_port" ]]; then
        echo ""
        echo -e "${YELLOW}Updating configuration...${RESET}"
        
        if reverse_proxy_create_config "$domain" "$new_port"; then
            echo -e "${GREEN}Successfully updated $domain -> localhost:$new_port${RESET}"
            domains_and_ports["$domain"]="$new_port"
        else
            echo -e "${RED}Failed to update configuration${RESET}"
        fi
    else
        echo -e "${DIM}No changes made.${RESET}"
    fi
    
    echo ""
    echo -e "${DIM}Press any key to continue...${RESET}"
    read -rsn1
    
    # Restore menu input mode and go back
    menu_input_init
    menu_go_back
}

rpm_remove_proxy() {
    if [[ ${#domains_and_ports[@]} -eq 0 ]]; then
        menu_render_status "No proxies to remove" 2
        return
    fi
    
    # Similar to edit, create a submenu
    local -a remove_options=()
    for domain in "${!domains_and_ports[@]}"; do
        remove_options+=("$(menu_option "$domain (port ${domains_and_ports[$domain]})" "rpm_remove_single_proxy '$domain'" "")")
    done
    
    menu_define "Select Proxy to Remove" remove_options
    menu_render_full
}

rpm_remove_single_proxy() {
    local domain="$1"
    
    # Temporarily restore terminal for input
    menu_input_cleanup
    
    clear
    echo -e "${RED}Remove Reverse Proxy: $domain${RESET}"
    echo -e "${DIM}This will delete the Nginx configuration file.${RESET}"
    echo ""
    
    local confirm
    echo -n "Are you sure? (y/N): "
    read -r confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${YELLOW}Removing configuration...${RESET}"
        
        local config_file="${settings["NGINX_CONFIG_DIR"]}/${domain}.conf"
        if [[ -f "$config_file" ]] && rm "$config_file"; then
            echo -e "${GREEN}Successfully removed configuration for $domain${RESET}"
            unset domains_and_ports["$domain"]
        else
            echo -e "${RED}Failed to remove configuration${RESET}"
        fi
    else
        echo -e "${DIM}Cancelled.${RESET}"
    fi
    
    echo ""
    echo -e "${DIM}Press any key to continue...${RESET}"
    read -rsn1
    
    # Restore menu input mode and go back
    menu_input_init
    menu_go_back
}

rpm_reload_nginx() {
    menu_render_status "Reloading Nginx..." 1
    
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl reload nginx 2>/dev/null; then
            menu_render_status "Nginx reloaded successfully" 2
        else
            menu_render_status "Failed to reload Nginx (check permissions)" 3
        fi
    elif command -v service >/dev/null 2>&1; then
        if service nginx reload 2>/dev/null; then
            menu_render_status "Nginx reloaded successfully" 2
        else
            menu_render_status "Failed to reload Nginx (check permissions)" 3
        fi
    else
        menu_render_status "Cannot find systemctl or service command" 3
    fi
}

rpm_test_config() {
    menu_render_status "Testing Nginx configuration..." 1
    
    if command -v nginx >/dev/null 2>&1; then
        if nginx -t 2>/dev/null; then
            menu_render_status "Nginx configuration is valid" 2
        else
            menu_render_status "Nginx configuration has errors" 3
        fi
    else
        menu_render_status "Nginx command not found" 3
    fi
}