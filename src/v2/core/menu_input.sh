#!/bin/bash
# Menu Input Handling - Custom keybinds and input processing

# Input configuration
declare -gA MENU_KEYBINDS=(
    # Navigation
    [up]="k|UP"
    [down]="j|DOWN"
    [select]="ENTER|SPACE"
    [back]="CTRL_B|b|BACKSPACE"
    [exit]="CTRL_C|q|Q"
    [home]="HOME|g"
    [end]="END|G"
    [page_up]="PAGE_UP|u"
    [page_down]="PAGE_DOWN|d"
)

# Custom keybind registry for menu options
declare -gA MENU_OPTION_KEYBINDS=()

# Input processing state
declare -g MENU_INPUT_ACTIVE=false

# Initialize input system
menu_input_init() {
    # Set terminal to raw mode
    stty -icanon -echo
    MENU_INPUT_ACTIVE=true
    
    # Set up cleanup
    trap 'menu_input_cleanup' EXIT INT TERM
}

# Cleanup input system
menu_input_cleanup() {
    if [[ "$MENU_INPUT_ACTIVE" == "true" ]]; then
        stty icanon echo
        MENU_INPUT_ACTIVE=false
    fi
}

# Read a single key with special key detection
menu_read_key() {
    local key=""
    local char=""
    
    # Read first character
    IFS= read -rsn1 char
    
    # Handle escape sequences
    if [[ "$char" == $'\x1b' ]]; then
        # Read next character to see if it's an escape sequence
        IFS= read -rsn1 -t 0.1 char
        if [[ "$char" == "[" ]]; then
            # Arrow keys and function keys
            IFS= read -rsn1 char
            case "$char" in
                "A") key="UP" ;;
                "B") key="DOWN" ;;
                "C") key="RIGHT" ;;
                "D") key="LEFT" ;;
                "H") key="HOME" ;;
                "F") key="END" ;;
                "1"|"7") key="HOME" ;;
                "4"|"8") key="END" ;;
                "5")
                    IFS= read -rsn1 char  # Read the ~
                    key="PAGE_UP"
                    ;;
                "6")
                    IFS= read -rsn1 char  # Read the ~
                    key="PAGE_DOWN"
                    ;;
                "3")
                    IFS= read -rsn1 char  # Read the ~
                    key="DELETE"
                    ;;
                *)
                    key="ESC_$char"
                    ;;
            esac
        else
            # Alt+ combinations or single escape
            if [[ -n "$char" ]]; then
                key="ALT_$char"
            else
                key="ESC"
            fi
        fi
    else
        # Regular character or control sequence
        case "$char" in
            $'\x00') key="CTRL_SPACE" ;;
            $'\x01') key="CTRL_A" ;;
            $'\x02') key="CTRL_B" ;;
            $'\x03') key="CTRL_C" ;;
            $'\x04') key="CTRL_D" ;;
            $'\x05') key="CTRL_E" ;;
            $'\x06') key="CTRL_F" ;;
            $'\x07') key="CTRL_G" ;;
            $'\x08') key="BACKSPACE" ;;
            $'\x09') key="TAB" ;;
            $'\x0a') key="ENTER" ;;
            $'\x0b') key="CTRL_K" ;;
            $'\x0c') key="CTRL_L" ;;
            $'\x0d') key="ENTER" ;;
            $'\x0e') key="CTRL_N" ;;
            $'\x0f') key="CTRL_O" ;;
            $'\x10') key="CTRL_P" ;;
            $'\x11') key="CTRL_Q" ;;
            $'\x12') key="CTRL_R" ;;
            $'\x13') key="CTRL_S" ;;
            $'\x14') key="CTRL_T" ;;
            $'\x15') key="CTRL_U" ;;
            $'\x16') key="CTRL_V" ;;
            $'\x17') key="CTRL_W" ;;
            $'\x18') key="CTRL_X" ;;
            $'\x19') key="CTRL_Y" ;;
            $'\x1a') key="CTRL_Z" ;;
            $'\x7f') key="BACKSPACE" ;;
            " ") key="SPACE" ;;
            *) key="$char" ;;
        esac
    fi
    
    echo "$key"
}

# Check if a key matches a keybind pattern
menu_key_matches() {
    local key="$1"
    local pattern="$2"
    
    # Split pattern by | and check each alternative
    local IFS="|"
    local alternatives=($pattern)
    
    for alt in "${alternatives[@]}"; do
        if [[ "$key" == "$alt" ]]; then
            return 0
        fi
    done
    
    return 1
}

# Get action for a key press
menu_get_key_action() {
    local key="$1"
    
    # Check standard navigation keybinds
    for action in "${!MENU_KEYBINDS[@]}"; do
        if menu_key_matches "$key" "${MENU_KEYBINDS[$action]}"; then
            echo "$action"
            return 0
        fi
    done
    
    # Check option-specific keybinds
    for option_key in "${!MENU_OPTION_KEYBINDS[@]}"; do
        if menu_key_matches "$key" "$option_key"; then
            echo "select_option:${MENU_OPTION_KEYBINDS[$option_key]}"
            return 0
        fi
    done
    
    # No action found
    echo "unknown"
    return 1
}

# Register keybind for menu option
menu_register_option_keybind() {
    local keybind="$1"
    local option_index="$2"
    
    if [[ -n "$keybind" && "$keybind" != "" ]]; then
        MENU_OPTION_KEYBINDS["$keybind"]="$option_index"
    fi
}

# Clear all option keybinds (call when menu changes)
menu_clear_option_keybinds() {
    MENU_OPTION_KEYBINDS=()
}

# Process navigation action
menu_process_navigation() {
    local action="$1"
    local option_count
    option_count=$(menu_option_count)
    
    case "$action" in
        "up")
            menu_update_selection $((MENU_SELECTION - 1))
            menu_render_partial
            ;;
        "down")
            menu_update_selection $((MENU_SELECTION + 1))
            menu_render_partial
            ;;
        "home")
            menu_update_selection 0
            menu_render_partial
            ;;
        "end")
            menu_update_selection $((option_count - 1))
            menu_render_partial
            ;;
        "page_up")
            local new_sel=$((MENU_SELECTION - MENU_MAX_VISIBLE))
            (( new_sel < 0 )) && new_sel=0
            menu_update_selection "$new_sel"
            menu_render_partial
            ;;
        "page_down")
            local new_sel=$((MENU_SELECTION + MENU_MAX_VISIBLE))
            (( new_sel >= option_count )) && new_sel=$((option_count - 1))
            menu_update_selection "$new_sel"
            menu_render_partial
            ;;
        "select")
            menu_execute_selection
            ;;
        "back")
            menu_go_back
            ;;
        "exit")
            menu_exit
            ;;
        "select_option:"*)
            local option_index="${action#select_option:}"
            menu_update_selection "$option_index"
            menu_render_partial
            menu_execute_selection
            ;;
        *)
            # Unknown action - could show a brief status message
            return 1
            ;;
    esac
    
    return 0
}

# Main input loop
menu_input_loop() {
    while true; do
        local key
        key=$(menu_read_key)
        
        local action
        action=$(menu_get_key_action "$key")
        
        if ! menu_process_navigation "$action"; then
            # Handle unknown key - could provide feedback
            continue
        fi
    done
}

# Execute currently selected menu option
menu_execute_selection() {
    local option_data
    option_data=$(menu_get_option "$MENU_SELECTION")
    local display=${option_data%% *}
    local action_and_key="${option_data#* }"
    local action=${action_and_key%% *}
    
    # Temporarily restore terminal for action execution
    menu_input_cleanup
    
    # Execute the action
    if menu_is_submenu "$action"; then
        local submenu_func
        submenu_func=$(menu_extract_submenu "$action")
        menu_call "$submenu_func"
    else
        # Execute command/function
        eval "$action"
    fi
    
    # Restore input mode
    menu_input_init
    
    # Redraw menu
    menu_render_full
}

# Navigate back in menu stack
menu_go_back() {
    if menu_stack_pop; then
        local current_menu
        current_menu=$(menu_stack_current)
        if [[ -n "$current_menu" ]]; then
            "$current_menu"
            menu_render_full
        else
            menu_exit
        fi
    else
        menu_exit
    fi
}

# Exit the menu system
menu_exit() {
    menu_input_cleanup
    menu_render_cleanup
    exit 0
}