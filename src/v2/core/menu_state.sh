#!/bin/bash
# Menu State Management - Navigation stack, selection tracking, and state persistence

# Navigation state
declare -ga MENU_STACK=()           # Stack of menu function names
declare -gi MENU_SELECTION=0        # Current selected option index
declare -gi MENU_TOP_VISIBLE=0      # Top visible option index (for scrolling)
declare -gi MENU_MAX_VISIBLE=10     # Maximum visible options (dynamic)
declare -gi MENU_LAST_SELECTION=-1  # Previous selection (for optimization)
declare -gi MENU_LAST_TOP_VISIBLE=-1 # Previous top visible (for optimization)

# Menu display state
declare -gi MENU_WIDTH=50
declare -gi MENU_HEIGHT=15
declare -gi MENU_LEFT=2
declare -gi MENU_TOP=2

# Configuration
declare -gA MENU_CONFIG=(
    [MIN_WIDTH]=30
    [MAX_WIDTH]=80
    [MIN_HEIGHT]=8
    [MAX_HEIGHT]=25
    [SCROLL_MARGIN]=2
    [BORDER_STYLE]="light"  # light, heavy, or simple
    [SHOW_INDICES]=false
    [ANIMATION]=false
)

# Initialize menu state
menu_state_init() {
    MENU_STACK=()
    MENU_SELECTION=0
    MENU_TOP_VISIBLE=0
    MENU_LAST_SELECTION=-1
    MENU_LAST_TOP_VISIBLE=-1
    
    # Auto-detect terminal size and set reasonable defaults
    local term_cols term_rows
    term_cols=$(tput cols 2>/dev/null || echo 80)
    term_rows=$(tput lines 2>/dev/null || echo 24)
    
    # Calculate optimal menu size
    MENU_WIDTH=$(( term_cols * 60 / 100 ))  # 60% of terminal width
    MENU_HEIGHT=$(( term_rows * 70 / 100 )) # 70% of terminal height
    
    # Apply constraints
    (( MENU_WIDTH < MENU_CONFIG[MIN_WIDTH] )) && MENU_WIDTH=${MENU_CONFIG[MIN_WIDTH]}
    (( MENU_WIDTH > MENU_CONFIG[MAX_WIDTH] )) && MENU_WIDTH=${MENU_CONFIG[MAX_WIDTH]}
    (( MENU_HEIGHT < MENU_CONFIG[MIN_HEIGHT] )) && MENU_HEIGHT=${MENU_CONFIG[MIN_HEIGHT]}
    (( MENU_HEIGHT > MENU_CONFIG[MAX_HEIGHT] )) && MENU_HEIGHT=${MENU_CONFIG[MAX_HEIGHT]}
    
    # Center menu on screen
    MENU_LEFT=$(( (term_cols - MENU_WIDTH) / 2 ))
    MENU_TOP=$(( (term_rows - MENU_HEIGHT) / 2 ))
    
    # Calculate max visible options (menu height - borders - title - footer)
    MENU_MAX_VISIBLE=$(( MENU_HEIGHT - 5 ))
    (( MENU_MAX_VISIBLE < 3 )) && MENU_MAX_VISIBLE=3
}

# Push a menu onto the navigation stack
menu_stack_push() {
    local menu_func="$1"
    MENU_STACK+=("$menu_func")
    
    # Reset selection when entering new menu
    MENU_SELECTION=0
    MENU_TOP_VISIBLE=0
    MENU_LAST_SELECTION=-1
    MENU_LAST_TOP_VISIBLE=-1
}

# Pop the last menu from the navigation stack
menu_stack_pop() {
    local stack_size=${#MENU_STACK[@]}
    if (( stack_size > 0 )); then
        unset 'MENU_STACK[-1]'
        # Reset selection when returning to previous menu
        MENU_SELECTION=0
        MENU_TOP_VISIBLE=0
        MENU_LAST_SELECTION=-1
        MENU_LAST_TOP_VISIBLE=-1
        return 0
    else
        return 1  # Stack is empty
    fi
}

# Get current menu function name
menu_stack_current() {
    local stack_size=${#MENU_STACK[@]}
    if (( stack_size > 0 )); then
        echo "${MENU_STACK[-1]}"
    else
        echo ""
    fi
}

# Check if we can go back
menu_can_go_back() {
    (( ${#MENU_STACK[@]} > 1 ))
}

# Update selection with bounds checking and scrolling
menu_update_selection() {
    local new_selection="$1"
    local option_count
    option_count=$(menu_option_count)
    
    # Bounds checking with wrapping
    if (( new_selection < 0 )); then
        new_selection=$(( option_count - 1 ))
    elif (( new_selection >= option_count )); then
        new_selection=0
    fi
    
    MENU_LAST_SELECTION=$MENU_SELECTION
    MENU_SELECTION=$new_selection
    
    # Update scrolling
    menu_update_scrolling
}

# Update scrolling window based on current selection
menu_update_scrolling() {
    local option_count
    option_count=$(menu_option_count)
    local scroll_margin=${MENU_CONFIG[SCROLL_MARGIN]}
    
    # Don't scroll if all options fit
    if (( option_count <= MENU_MAX_VISIBLE )); then
        MENU_LAST_TOP_VISIBLE=$MENU_TOP_VISIBLE
        MENU_TOP_VISIBLE=0
        return
    fi
    
    MENU_LAST_TOP_VISIBLE=$MENU_TOP_VISIBLE
    
    # Scroll up if selection is too close to top
    if (( MENU_SELECTION < MENU_TOP_VISIBLE + scroll_margin )); then
        MENU_TOP_VISIBLE=$(( MENU_SELECTION - scroll_margin ))
        (( MENU_TOP_VISIBLE < 0 )) && MENU_TOP_VISIBLE=0
    fi
    
    # Scroll down if selection is too close to bottom
    local bottom_visible=$(( MENU_TOP_VISIBLE + MENU_MAX_VISIBLE - 1 ))
    if (( MENU_SELECTION > bottom_visible - scroll_margin )); then
        MENU_TOP_VISIBLE=$(( MENU_SELECTION - MENU_MAX_VISIBLE + scroll_margin + 1 ))
        local max_top=$(( option_count - MENU_MAX_VISIBLE ))
        (( MENU_TOP_VISIBLE > max_top )) && MENU_TOP_VISIBLE=$max_top
    fi
}

# Check if scrolling display should be optimized (only redraw changed items)
menu_needs_full_redraw() {
    (( MENU_LAST_TOP_VISIBLE != MENU_TOP_VISIBLE ))
}

# Get visible option range (start_index, end_index)
menu_get_visible_range() {
    local option_count
    option_count=$(menu_option_count)
    local end_visible=$(( MENU_TOP_VISIBLE + MENU_MAX_VISIBLE - 1 ))
    (( end_visible >= option_count )) && end_visible=$(( option_count - 1 ))
    echo "$MENU_TOP_VISIBLE $end_visible"
}

# Reset state tracking (call after redraw)
menu_state_reset_tracking() {
    MENU_LAST_SELECTION=$MENU_SELECTION
    MENU_LAST_TOP_VISIBLE=$MENU_TOP_VISIBLE
}