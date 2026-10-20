#!/bin/bash
# Menu Rendering Engine - Optimized drawing with incremental updates

# Source dependencies
_render_script_dir=$(dirname "${BASH_SOURCE[0]}")
source "$_render_script_dir/../utils/box_drawing.sh"
source "$_render_script_dir/../../lib/ansi.sh"
source "$_render_script_dir/../../lib/pad.sh"

# Rendering state
declare -g MENU_LAST_RENDERED_TITLE=""
declare -ga MENU_LAST_RENDERED_OPTIONS=()
declare -gi MENU_LAST_RENDERED_SELECTION=-1

# Initialize rendering system
menu_render_init() {
    # Set up terminal
    tput civis  # Hide cursor
    trap 'menu_render_cleanup' EXIT INT TERM
    
    # Clear state
    MENU_LAST_RENDERED_TITLE=""
    MENU_LAST_RENDERED_OPTIONS=()
    MENU_LAST_RENDERED_SELECTION=-1
}

# Cleanup rendering system
menu_render_cleanup() {
    tput cnorm  # Show cursor
    tput sgr0   # Reset attributes
    clear
}

# Full menu redraw
menu_render_full() {
    local option_count
    option_count=$(menu_option_count)
    
    # Clear screen and position cursor
    clear
    
    # Draw border and title
    menu_render_frame
    
    # Draw all visible options
    local visible_range
    visible_range=$(menu_get_visible_range)
    local start_idx=${visible_range% *}
    local end_idx=${visible_range#* }
    
    for (( i = start_idx; i <= end_idx; i++ )); do
        menu_render_option "$i" false
    done
    
    # Highlight selected option
    if (( MENU_SELECTION >= start_idx && MENU_SELECTION <= end_idx )); then
        menu_render_option "$MENU_SELECTION" true
    fi
    
    # Draw footer with hotkeys
    menu_render_footer
    
    # Update render state
    MENU_LAST_RENDERED_TITLE="$MENU_CURRENT_TITLE"
    MENU_LAST_RENDERED_OPTIONS=("${MENU_CURRENT_OPTIONS[@]}")
    MENU_LAST_RENDERED_SELECTION=$MENU_SELECTION
    
    menu_state_reset_tracking
}

# Optimized partial redraw (only changed elements)
menu_render_partial() {
    local visible_range
    visible_range=$(menu_get_visible_range)
    local start_idx=${visible_range% *}
    local end_idx=${visible_range#* }
    
    # If we need full redraw (scrolling changed), do it
    if menu_needs_full_redraw; then
        menu_render_full
        return
    fi
    
    # Only redraw selection changes
    if (( MENU_LAST_SELECTION != MENU_SELECTION )); then
        # Un-highlight previous selection if visible
        if (( MENU_LAST_SELECTION >= start_idx && MENU_LAST_SELECTION <= end_idx )); then
            menu_render_option "$MENU_LAST_SELECTION" false
        fi
        
        # Highlight new selection if visible
        if (( MENU_SELECTION >= start_idx && MENU_SELECTION <= end_idx )); then
            menu_render_option "$MENU_SELECTION" true
        fi
        
        MENU_LAST_RENDERED_SELECTION=$MENU_SELECTION
    fi
    
    menu_state_reset_tracking
}

# Draw menu frame (border and title)
menu_render_frame() {
    local content_width=$(( MENU_WIDTH - 4 ))  # Account for borders and padding
    
    # Top border
    tput cup $MENU_TOP $MENU_LEFT
    echo -n "$(box_top_border "$MENU_WIDTH")"
    
    # Title line
    tput cup $((MENU_TOP + 1)) $MENU_LEFT
    local title_display="$MENU_CURRENT_TITLE"
    if (( ${#title_display} > content_width )); then
        title_display="${title_display:0:$((content_width-1))}…"
    fi
    echo -n "$(box_side_border)$(padc "$title_display" " " "$content_width")$(box_side_border)"
    
    # Title separator
    tput cup $((MENU_TOP + 2)) $MENU_LEFT
    echo -n "$(box_middle_border "$MENU_WIDTH")"
}

# Draw a single menu option
menu_render_option() {
    local option_index="$1"
    local is_selected="$2"
    
    local option_data
    option_data=$(menu_get_option "$option_index")
    local display=${option_data%% *}
    local action_and_key="${option_data#* }"
    local action=${action_and_key%% *}
    local keybind="${option_data##* }"
    [[ "$keybind" == "$action" ]] && keybind=""  # No keybind specified
    
    # Calculate position
    local visible_range
    visible_range=$(menu_get_visible_range)
    local start_idx=${visible_range% *}
    local visual_row=$(( MENU_TOP + 3 + option_index - start_idx ))
    local content_width=$(( MENU_WIDTH - 4 ))
    
    # Position cursor
    tput cup $visual_row $MENU_LEFT
    
    # Prepare display text
    local prefix="  "
    local suffix=""
    if [[ -n "$keybind" && "$keybind" != "" ]]; then
        suffix=" ${DIM}($keybind)${RESET}"
    fi
    
    local full_text="${prefix}${display}${suffix}"
    if (( ${#full_text} > content_width )); then
        local available=$(( content_width - ${#prefix} - ${#suffix} ))
        display="${display:0:$((available-1))}…"
        full_text="${prefix}${display}${suffix}"
    fi
    
    # Apply selection highlighting
    if [[ "$is_selected" == "true" ]]; then
        prefix="${INVERSE}> ${RESET}${INVERSE}"
        full_text="${prefix}${display}${suffix}${INVERSE_OFF}"
        # Pad to full width for complete highlight
        full_text="$(padr "$full_text" "$content_width")"
    fi
    
    # Draw the option
    echo -n "$(box_side_border)$(padr "$full_text" "$content_width")$(box_side_border)"
}

# Draw footer with hotkey hints
menu_render_footer() {
    local footer_row=$(( MENU_TOP + MENU_HEIGHT - 1 ))
    local content_width=$(( MENU_WIDTH - 4 ))
    
    # Bottom border
    tput cup $footer_row $MENU_LEFT
    echo -n "$(box_bottom_border "$MENU_WIDTH")"
    
    # Footer content
    local footer_text="Exit: Ctrl+C"
    if menu_can_go_back; then
        footer_text="$footer_text | Back: Ctrl+B"
    fi
    
    tput cup $((footer_row - 1)) $MENU_LEFT
    echo -n "$(box_side_border)${DIM}$(padc "$footer_text" " " "$content_width")${RESET}$(box_side_border)"
}

# Render loading indicator
menu_render_loading() {
    local message="${1:-Loading...}"
    local row=$(( MENU_TOP + MENU_HEIGHT / 2 ))
    local content_width=$(( MENU_WIDTH - 4 ))
    
    tput cup $row $MENU_LEFT
    echo -n "$(box_side_border)$(padc "$message" " " "$content_width")$(box_side_border)"
}

# Quick status message (temporary overlay)
menu_render_status() {
    local message="$1"
    local duration="${2:-2}"
    local status_row=$(( MENU_TOP + MENU_HEIGHT - 2 ))
    local content_width=$(( MENU_WIDTH - 4 ))
    
    # Save current line
    tput sc
    
    # Show message
    tput cup $status_row $MENU_LEFT
    echo -n "$(box_side_border)${YELLOW}$(padc "$message" " " "$content_width")${RESET}$(box_side_border)"
    
    # Auto-clear after duration
    if (( duration > 0 )); then
        (
            sleep "$duration"
            tput cup $status_row $MENU_LEFT
            echo -n "$(box_side_border)$(padc "" " " "$content_width")$(box_side_border)"
        ) &
    fi
    
    # Restore cursor
    tput rc
}