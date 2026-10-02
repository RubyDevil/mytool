#!/usr/bin/env bash

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/test.sh
source "$test_dir/../lib/test.sh"
# shellcheck source=../mytool
source "$test_dir/../mytool"
unset test_dir

build_menu_main
test_assert_equal 'Build main menu header' 'Main Menu' "$menu_header"
test_assert_equal 'Build main menu items' '4' "${#menu_labels[@]}"
test_assert_equal 'Keep main menu hierarchy' 'Tools' "$(strip_ansi "${menu_labels[0]}")"
test_assert_equal 'Add Utility Scripts category' 'Utility Scripts' "$(strip_ansi "${menu_labels[1]}")"
test_assert_equal 'Add Update MyTool action' 'Update MyTool' "$(strip_ansi "${menu_labels[2]}")"
test_assert_equal 'Wire Update MyTool task' 'task_update_mytool' "${menu_callbacks[2]}"
test_assert_equal 'Exit from main menu with Esc or q' 'task_exit:exit' "$menu_back_callback:$menu_back_label"

test_run 'Navigate to tools builder' menu_invoke 0
test_assert_equal 'Build tools menu header' 'Tools' "$menu_header"
test_assert_equal 'Keep reverse proxy tool entry' 'RPM (Reverse Proxy Manager)' "$(strip_ansi "${menu_labels[0]}")"
test_assert_equal 'Add VPS Setup tool entry' 'VPS Setup' "$(strip_ansi "${menu_labels[1]}")"
test_run 'Go back from tools menu' menu_go_back
test_assert_equal 'Return to main menu' 'Main Menu' "$menu_header"
menu_invoke 0

test_run 'Navigate to VPS Setup builder' menu_invoke 1
test_assert_equal 'Build VPS Setup menu header' 'VPS Setup' "$menu_header"
test_assert_equal 'Offer Security Setup' 'Security Setup' "$(strip_ansi "${menu_labels[0]}")"
test_assert_equal 'Offer Software Management' 'Software Management' "$(strip_ansi "${menu_labels[1]}")"

test_run 'Build security menu' menu_invoke 0
test_assert_equal 'Build security menu header' 'Security Setup' "$menu_header"
test_assert_equal 'Enable security multi-select' '1' "$menu_multi_select"
test_assert_equal 'Keep destructive SSH action red' 'Disable SSH password login' "$(strip_ansi "${menu_labels[3]}")"
test_assert_equal 'Offer Tailscale setup' 'Setup Tailscale:task_vps_setup_tailscale' "$(strip_ansi "${menu_labels[5]}"):${menu_callbacks[5]}"
test_assert_equal 'Go back from security menu' 'build_menu_vps_setup' "$menu_back_callback"

build_menu_vps_software
test_assert_equal 'Build software menu header' 'Software Management' "$menu_header"
test_assert_equal 'Enable software multi-select' '1' "$menu_multi_select"
test_assert_equal 'Preselect package updates' '1' "${menu_selected[0]}"
test_assert_equal 'Keep reinstall option selectable' '1' "${menu_selectable[1]}"
test_assert_equal 'Preselect Nginx' '1' "${menu_selected[2]}"
test_assert_equal 'Preselect Node.js' '1' "${menu_selected[4]}"
test_assert_equal 'Describe NVM' 'Install NVM (Node Version Manager)' "$(strip_ansi "${menu_labels[5]}")"
test_assert_equal 'Describe MongoDB' 'Install MongoDB (mongod, mongosh, database tools)' "$(strip_ansi "${menu_labels[7]}")"
test_assert_equal 'Keep MongoDB optional' '0' "${menu_selected[7]:-0}"
test_assert_equal 'Describe Tailscale' 'Install Tailscale (private VPN network)' "$(strip_ansi "${menu_labels[8]}")"
test_assert_equal 'Keep Tailscale optional' '0' "${menu_selected[8]:-0}"
test_assert_equal 'Clear before software batch' 'task_vps_software_start' "$menu_selected_start_callback"
test_assert_equal 'Pause after software batch' 'task_vps_software_complete' "$menu_selected_complete_callback"

utility_dir=$(mktemp -d)
UTIL_SCRIPTS_BIN_DIR="$utility_dir/bin"
UTIL_SCRIPTS_CACHE_DIR="$utility_dir/cache"
UTIL_SCRIPTS_SHARE_DIR="$utility_dir/share"
build_menu_main
test_run 'Navigate to Utility Scripts builder' menu_invoke 1
test_assert_equal 'Build Utility Scripts header' 'Utility Scripts' "$menu_header"
test_assert_equal 'Offer Show Scripts' 'Show Scripts' "$(strip_ansi "${menu_labels[0]}")"
test_assert_equal 'Offer Install Scripts' 'Install Scripts' "$(strip_ansi "${menu_labels[1]}")"
test_assert_equal 'Offer Uninstall Scripts' 'Uninstall Scripts' "$(strip_ansi "${menu_labels[2]}")"
test_assert_equal 'Offer Update Scripts' 'Update Scripts' "$(strip_ansi "${menu_labels[3]}")"

build_menu_util_scripts_install
test_assert_equal 'Explain empty repository' 'No scripts found; check UTIL_SCRIPTS_REPO in the settings' "$(strip_ansi "${menu_labels[0]}")"
test_assert_equal 'Go back to Utility Scripts' 'build_menu_util_scripts' "$menu_back_callback"
cp -R -- "$(dirname -- "${BASH_SOURCE[0]}")/../../util-scripts" "$UTIL_SCRIPTS_CACHE_DIR"
build_menu_util_scripts_install
test_assert_equal 'Enable install multi-select' '1' "$menu_multi_select"
test_assert_equal 'List fan-speed status' 'fan-speed (not installed)' "$(strip_ansi "${menu_labels[0]}")"
test_assert_equal 'Pass script name as argument' 'fan-speed' "${menu_arguments[0:0]}"
test_assert_equal 'Refresh install menu after batch' 'task_util_scripts_install_complete' "$menu_selected_complete_callback"

build_menu_util_scripts_uninstall
test_assert_equal 'Explain empty uninstall list' 'No scripts are installed' "$(strip_ansi "${menu_labels[0]}")"
test_assert_equal 'Keep empty uninstall notice unselectable' '0' "${menu_selectable[0]}"
mkdir -p -- "$UTIL_SCRIPTS_BIN_DIR" "$UTIL_SCRIPTS_SHARE_DIR"
cp -R -- "$UTIL_SCRIPTS_CACHE_DIR/fan-speed" "$UTIL_SCRIPTS_SHARE_DIR/fan-speed"
printf 'old\n' >"$UTIL_SCRIPTS_BIN_DIR/fan-speed"
build_menu_util_scripts_uninstall
test_assert_equal 'List installed scripts for removal' 'fan-speed (update available)' "$(strip_ansi "${menu_labels[0]}")"

described=$(util_scripts_describe fan-speed)
test_assert_equal 'Describe script status' 'Status: (update available)' "$(strip_ansi "$(head -n 1 <<<"$described")")"
test_run 'Include script documentation' grep -q 'Usage:' <<<"$described"
settings[UTIL_SCRIPTS_REPO]=''
test_assert_status 'Allow an empty scripts repository' 0 settings_validate_value UTIL_SCRIPTS_REPO ''
test_assert_status 'Reject a local scripts repository' 1 settings_validate_value UTIL_SCRIPTS_REPO /tmp/scripts
rm -rf -- "$utility_dir"
unset UTIL_SCRIPTS_BIN_DIR UTIL_SCRIPTS_CACHE_DIR UTIL_SCRIPTS_SHARE_DIR

hook_calls=()
first_hook() { hook_calls+=(first); return 1; }
second_hook() { hook_calls+=(second); }
mytool_post_update_hooks=(first_hook second_hook)
clear() { :; }
wait_for_key() { :; }
task_post_update &>/dev/null
test_assert_equal 'Run every post-update hook' 'first second' "${hook_calls[*]}"
test_assert_equal 'Register defined post-update hooks' 'post_update_install_launcher post_update_refresh_util_scripts' "$(
   source "$(dirname -- "${BASH_SOURCE[0]}")/../mytool"
   for hook in "${mytool_post_update_hooks[@]}"; do
      declare -F "$hook"
   done | paste -sd ' '
)"

build_menu_settings
test_assert_equal 'Build settings menu items' '6' "${#menu_labels[@]}"
test_assert_equal 'Sort setting entries' 'MENU_BORDER_COLOR (current: WHITE)' "$(strip_ansi "${menu_labels[0]}")"
test_run 'Accept configured heavy border' settings_validate_value MENU_BORDER_TYPE heavy
test_assert_status 'Reject unknown border' 1 settings_validate_value MENU_BORDER_TYPE rounded
test_assert_status 'Reject wide pointer' 1 settings_validate_value MENU_POINTER_TYPE '>>'

build_menu_settings MENU_BORDER_TYPE
test_assert_equal 'Offer a border choice action' 'Choose value' "$(strip_ansi "${menu_labels[1]}")"
test_run 'Open border choices' menu_invoke 1
test_assert_equal 'Build border choice menu' 'Choose MENU_BORDER_TYPE' "$menu_header"
test_assert_equal 'List light border choice' 'LIGHT (current)' "$(strip_ansi "${menu_labels[0]}")"
test_assert_equal 'List heavy border choice' 'HEAVY' "$(strip_ansi "${menu_labels[1]}")"
test_run 'Go back from border choices' menu_go_back
test_assert_equal 'Return to the edited setting' 'Edit Setting:MENU_BORDER_TYPE' "$menu_header:${menu_arguments[0:0]}"

clear_called=0
clear() { clear_called=1; }
prompt_confirm() { return 1; }
wait_for_key() { :; }
test_run 'Clear choice menu before confirmation' task_apply_settings_value MENU_BORDER_TYPE HEAVY &>/dev/null
test_assert_equal 'Clear choice menu before confirmation' '1' "$clear_called"

build_menu_settings NGINX_CONFIG_DIR
test_assert_equal 'Keep free-text setting modifier' 'Modify' "$(strip_ansi "${menu_labels[1]}")"

temporary_dir=$(mktemp -d)
trap 'rm -rf -- "$temporary_dir"' EXIT
settings[NGINX_CONFIG_DIR]="$temporary_dir"
reverse_proxy_save_config z.example 9000
reverse_proxy_save_config a.example 8000
domains_and_ports[invalid]=invalid
build_menu_reverse_proxy
test_assert_equal 'Build proxy menu items' '3' "${#menu_labels[@]}"
test_assert_equal 'Sort proxy entries' 'a.example (port: 8000)' "$(strip_ansi "${menu_labels[1]}")"
test_assert_equal 'Skip invalid proxy cache entry' 'z.example (port: 9000)' "$(strip_ansi "${menu_labels[2]}")"
test_assert_equal 'Go back from proxies to Tools' 'build_menu_tools' "$menu_back_callback"

MENU_HEIGHT=10
rendered=$(menu_render)
test_assert_equal 'Render application menu height' '10' "$(printf '%s\n' "$rendered" | wc -l)"

test_finish
