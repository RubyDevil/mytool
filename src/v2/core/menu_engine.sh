#!/bin/bash
# Menu Engine - Main menu system that coordinates all components

# Source all menu components
_engine_script_dir=$(dirname "${BASH_SOURCE[0]}")
source "$_engine_script_dir/menu_def.sh"
source "$_engine_script_dir/menu_state.sh"
source "$_engine_script_dir/menu_render.sh"
source "$_engine_script_dir/menu_input.sh"

# Engine state
declare -g MENU_ENGINE_INITIALIZED=false

# Initialize the complete menu system
menu_init() {
    if [[ "$MENU_ENGINE_INITIALIZED" == "true" ]]; then
        return 0
    fi
    
    # Initialize all subsystems
    menu_state_init
    menu_render_init
    menu_input_init
    
    # Set box drawing style from config
    local style=${MENU_CONFIG[BORDER_STYLE]:-"light"}
    box_set_style "$style"
    
    MENU_ENGINE_INITIALIZED=true
}

# Start menu system with a root menu function
menu_start() {
    local root_menu_func="$1"
    
    if [[ -z "$root_menu_func" ]]; then
        echo "Error: No root menu function specified" >&2
        return 1
    fi
    
    # Initialize if not already done
    menu_init
    
    # Call the root menu and start the stack
    menu_call "$root_menu_func"
    
    # Start the input loop
    menu_input_loop
}

# Call a menu function and update the system state
menu_call() {
    local menu_func="$1"
    shift
    
    if ! declare -F "$menu_func" >/dev/null; then
        echo "Error: Menu function '$menu_func' not found" >&2
        return 1
    fi
    
    # Clear option keybinds from previous menu
    menu_clear_option_keybinds
    
    # Push menu onto stack and call it
    menu_stack_push "$menu_func"
    "$menu_func" "$@"
    
    # Register option keybinds from the newly defined menu
    menu_register_current_keybinds
    
    # Render the menu
    menu_render_full
}

# Register keybinds for all options in current menu
menu_register_current_keybinds() {
    local option_count
    option_count=$(menu_option_count)
    
    for (( i = 0; i < option_count; i++ )); do
        local option_data
        option_data=$(menu_get_option "$i")
        local keybind="${option_data##* }"
        local action_and_key="${option_data#* }"
        local action=${action_and_key%% *}
        
        # Only register if keybind is different from action (meaning it was specified)
        if [[ "$keybind" != "$action" && -n "$keybind" ]]; then
            menu_register_option_keybind "$keybind" "$i"
        fi
    done
}

# Utility function to create menu options easily
menu_create_options() {
    local -a options=()
    
    while (( $# > 0 )); do
        case "$1" in
            --option)
                shift
                local display="$1"; shift
                local action="$1"; shift
                local keybind="${1:-}"; [[ -n "$1" ]] && shift
                options+=("$(menu_option "$display" "$action" "$keybind")")
                ;;
            --submenu)
                shift
                local display="$1"; shift
                local submenu_func="$1"; shift
                local keybind="${1:-}"; [[ -n "$1" ]] && shift
                options+=("$(menu_submenu "$display" "$submenu_func" "$keybind")")
                ;;
            --separator)
                shift
                options+=("$(menu_option "────────────────" ":" "")")
                ;;
            *)
                echo "Error: Unknown option type '$1'" >&2
                return 1
                ;;
        esac
    done
    
    # Return options as a string that can be eval'd into an array
    printf '%s\n' "${options[@]}"
}

# Helper to create a simple menu with standard options
menu_simple() {
    local title="$1"
    shift
    
    local -a menu_opts=()
    while IFS= read -r line; do
        menu_opts+=("$line")
    done < <(menu_create_options "$@")
    
    menu_define "$title" menu_opts
}

# Configuration helpers
menu_configure() {
    local setting="$1"
    local value="$2"
    
    case "$setting" in
        border_style)
            MENU_CONFIG[BORDER_STYLE]="$value"
            if [[ "$MENU_ENGINE_INITIALIZED" == "true" ]]; then
                box_set_style "$value"
            fi
            ;;
        width|min_width|max_width|height|min_height|max_height)
            local key="${setting^^}"
            if [[ "$key" == "WIDTH" ]]; then key="MAX_WIDTH"; fi
            if [[ "$key" == "HEIGHT" ]]; then key="MAX_HEIGHT"; fi
            MENU_CONFIG["$key"]="$value"
            ;;
        scroll_margin)
            MENU_CONFIG[SCROLL_MARGIN]="$value"
            ;;
        show_indices)
            MENU_CONFIG[SHOW_INDICES]="$value"
            ;;
        animation)
            MENU_CONFIG[ANIMATION]="$value"
            ;;
        *)
            echo "Error: Unknown menu setting '$setting'" >&2
            return 1
            ;;
    esac
}

# Debug function to show current menu state
menu_debug() {
    echo "=== Menu Engine Debug ==="
    echo "Initialized: $MENU_ENGINE_INITIALIZED"
    echo "Current Title: $MENU_CURRENT_TITLE"
    echo "Option Count: $(menu_option_count)"
    echo "Selection: $MENU_SELECTION"
    echo "Top Visible: $MENU_TOP_VISIBLE"
    echo "Stack Size: ${#MENU_STACK[@]}"
    echo "Stack: ${MENU_STACK[*]}"
    echo "Dimensions: ${MENU_WIDTH}x${MENU_HEIGHT} at (${MENU_LEFT},${MENU_TOP})"
    echo "========================="
}

# Shutdown menu system
menu_shutdown() {
    menu_input_cleanup
    menu_render_cleanup
    MENU_ENGINE_INITIALIZED=false
}