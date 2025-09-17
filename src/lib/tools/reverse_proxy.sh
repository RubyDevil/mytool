#!/bin/bash
# Reverse Proxy Manager tools (extracted from main script)
# Provides functions & menu builder for managing per-domain nginx reverse proxy configs.

# Depends on: settings.sh (settings[]), ansi.sh (colors), menu.sh (menu system), utils.sh (wait_for_key)
script_dir=$(dirname "${BASH_SOURCE[0]}")
source "$script_dir/../utils.sh"

# Associative array mapping domain -> port
declare -g -A domains_and_ports

# Load existing reverse proxy configurations from Nginx directory
reverse_proxy_load_configs() {
   local dir="${settings["NGINX_CONFIG_DIR"]}"
   if [ ! -d "$dir" ]; then
      echo -e "${RED}Nginx configuration directory does not exist: $dir${RESET}"
      return
   fi
   # Clear previous to avoid stale entries
   domains_and_ports=()
   for config_file in "$dir"/*.conf; do
      [ -f "$config_file" ] || continue
      local domain port
      domain=$(grep -oP 'server_name\s+\K[^\s;]+' "$config_file" | head -n1)
      port=$(grep -oP 'proxy_pass\s+http://(127.0.0.1|localhost):\K[0-9]+' "$config_file" | head -n1)
      if [[ -n $domain && -n $port ]]; then
         domains_and_ports["$domain"]="$port"
      else
         echo -e "${YELLOW}Skipping invalid config:${RESET} $config_file" >&2
      fi
   done
}

# Persist or update a single reverse proxy config
reverse_proxy_save_config() {
   local domain=$1 port=$2
   local file="${settings["NGINX_CONFIG_DIR"]}/$domain.conf"
   cat >"$file" <<EOF
server {
    listen 80;
    server_name $domain;

    location / {
        proxy_pass http://localhost:$port;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
}


# Tasks ------------------------------------------------------------------------------------------

task_add_reverse_proxy() {
   clear
   echo -e "${DIM}Add a new reverse proxy configuration${RESET}"; echo
   read -p "Enter domain: " domain
   if [ -n "${domains_and_ports[$domain]}" ]; then
      echo -e "${RED}Domain already exists.${RESET}"; wait_for_key; return
   fi
   read -p "Enter port: " port
   if ! [[ $port =~ ^[0-9]+$ ]] || [ $port -lt 1 ] || [ $port -gt 65535 ]; then
      echo -e "${RED}Invalid port.${RESET}"; wait_for_key; return
   fi
   echo -e "${DIM}Saving...${RESET}"; reverse_proxy_save_config "$domain" "$port"
   echo -e "${DIM}Reloading Nginx...${RESET}"; systemctl reload nginx
   echo -e "${DIM}Reloading configs...${RESET}"; reverse_proxy_load_configs >/dev/null 2>&1
   echo -e "${GREEN}Added.${RESET}"; build_menu_reverse_proxy ""; wait_for_key
}

task_modify_reverse_proxy() {
   local domain=$1; local port=${domains_and_ports[$domain]}
   clear
   echo -e "${DIM}Modify reverse proxy: ${RESET}$domain (current port: $port)"; echo
   read -p "Enter port [$port]: " new_port; new_port=${new_port:-$port}
   if ! [[ $new_port =~ ^[0-9]+$ ]] || [ $new_port -lt 1 ] || [ $new_port -gt 65535 ]; then
      echo -e "${RED}Invalid port.${RESET}"; wait_for_key; return
   fi
   if [ "$new_port" -eq "$port" ]; then echo -e "${RED}No change.${RESET}"; wait_for_key; return; fi
   echo -e "${DIM}Saving...${RESET}"; reverse_proxy_save_config "$domain" "$new_port"
   echo -e "${DIM}Reloading Nginx...${RESET}"; systemctl reload nginx
   reverse_proxy_load_configs >/dev/null 2>&1
   echo -e "${GREEN}Updated.${RESET}"; build_menu_reverse_proxy ""; wait_for_key
}

task_delete_reverse_proxy() {
   local domain=$1
   clear
   echo -e "${DIM}Delete reverse proxy: ${RESET}$domain"; echo
   read -p "Are you sure? [y/N] " -n1 ans; echo
   if [[ $ans =~ ^[Yy]$ ]]; then
      echo -e "${DIM}Deleting config...${RESET}"; rm -f "${settings["NGINX_CONFIG_DIR"]}/$domain.conf"
      echo -e "${DIM}Reloading Nginx...${RESET}"; systemctl reload nginx
      reverse_proxy_load_configs >/dev/null 2>&1
      echo -e "${GREEN}Deleted.${RESET}";
   else
      echo -e "${RED}Canceled.${RESET}"; echo -n "$BEEP"
   fi
   build_menu_reverse_proxy ""; wait_for_key
}

# Menu builder -----------------------------------------------------------------------------------

build_menu_reverse_proxy() {
   if [ -n "$1" ]; then
      menu_header="Edit Reverse Proxy"
      menu=(
         "${RED}Back${RESET}" "build_menu_reverse_proxy"
         "${YELLOW}Modify${RESET}" "task_modify_reverse_proxy $1"
         "${RED}Delete${RESET}" "task_delete_reverse_proxy $1"
      )
      return
   fi
   menu_header="Reverse Proxy Manager"
   menu=(
      "${RED}Back${RESET}" "build_menu_tools"
      "${GREEN}Add new reverse proxy${RESET}" "task_add_reverse_proxy"
   )
   reverse_proxy_load_configs >/dev/null 2>&1
   for domain in "${!domains_and_ports[@]}"; do
      menu+=("${domain}${INVERSE_OFF}${DIM} (port: ${domains_and_ports[$domain]})${RESET}" "build_menu_reverse_proxy $domain")
   done
}
