#!/bin/bash
# Box Drawing Utilities - Unicode box drawing with different styles

# Box drawing character sets
declare -gA BOX_LIGHT=(
    [h]="─"    # horizontal
    [v]="│"    # vertical
    [tl]="┌"   # top-left
    [tr]="┐"   # top-right
    [bl]="└"   # bottom-left
    [br]="┘"   # bottom-right
    [cross]="┼" # cross
    [t_down]="┬" # T pointing down
    [t_up]="┴"   # T pointing up
    [t_right]="├" # T pointing right
    [t_left]="┤"  # T pointing left
)

declare -gA BOX_HEAVY=(
    [h]="━"    # horizontal
    [v]="┃"    # vertical
    [tl]="┏"   # top-left
    [tr]="┓"   # top-right
    [bl]="┗"   # bottom-left
    [br]="┛"   # bottom-right
    [cross]="╋" # cross
    [t_down]="┳" # T pointing down
    [t_up]="┻"   # T pointing up
    [t_right]="┣" # T pointing right
    [t_left]="┫"  # T pointing left
)

declare -gA BOX_SIMPLE=(
    [h]="-"    # horizontal
    [v]="|"    # vertical
    [tl]="+"   # top-left
    [tr]="+"   # top-right
    [bl]="+"   # bottom-left
    [br]="+"   # bottom-right
    [cross]="+" # cross
    [t_down]="+" # T pointing down
    [t_up]="+"   # T pointing up
    [t_right]="+" # T pointing right
    [t_left]="+"  # T pointing left
)

# Current box style
declare -g BOX_CURRENT_STYLE="light"

# Set box drawing style
box_set_style() {
    local style="$1"
    case "$style" in
        light|heavy|simple)
            BOX_CURRENT_STYLE="$style"
            ;;
        *)
            echo "Error: Invalid box style '$style'. Use: light, heavy, or simple" >&2
            return 1
            ;;
    esac
}

# Get character from current style
box_char() {
    local char_name="$1"
    local style_var="BOX_${BOX_CURRENT_STYLE^^}"
    local -n style_ref="$style_var"
    echo "${style_ref[$char_name]}"
}

# Convenience functions for common patterns
box_side_border() {
    box_char "v"
}

box_horizontal_line() {
    local width="$1"
    local char
    char=$(box_char "h")
    printf "%*s" "$width" "" | tr ' ' "$char"
}

# Top border: ┌─────────┐
box_top_border() {
    local width="$1"
    local left_char right_char middle_char
    left_char=$(box_char "tl")
    right_char=$(box_char "tr")
    middle_char=$(box_char "h")
    
    echo -n "$left_char"
    printf "%*s" $((width - 2)) "" | tr ' ' "$middle_char"
    echo -n "$right_char"
}

# Bottom border: └─────────┘
box_bottom_border() {
    local width="$1"
    local left_char right_char middle_char
    left_char=$(box_char "bl")
    right_char=$(box_char "br")
    middle_char=$(box_char "h")
    
    echo -n "$left_char"
    printf "%*s" $((width - 2)) "" | tr ' ' "$middle_char"
    echo -n "$right_char"
}

# Middle border (separator): ├─────────┤
box_middle_border() {
    local width="$1"
    local left_char right_char middle_char
    left_char=$(box_char "t_right")
    right_char=$(box_char "t_left")
    middle_char=$(box_char "h")
    
    echo -n "$left_char"
    printf "%*s" $((width - 2)) "" | tr ' ' "$middle_char"
    echo -n "$right_char"
}

# Create a complete box frame
box_frame() {
    local width="$1"
    local height="$2"
    
    # Top border
    box_top_border "$width"
    echo
    
    # Side borders
    local side_char
    side_char=$(box_char "v")
    for (( i = 1; i < height - 1; i++ )); do
        echo -n "$side_char"
        printf "%*s" $((width - 2)) ""
        echo "$side_char"
    done
    
    # Bottom border
    box_bottom_border "$width"
    echo
}

# Box with content
box_with_content() {
    local width="$1"
    local content="$2"
    local padding="${3:-1}"
    
    local content_width=$((width - 2 - 2 * padding))
    local side_char
    side_char=$(box_char "v")
    
    # Top border
    box_top_border "$width"
    echo
    
    # Content with padding
    local padded_content
    if (( ${#content} > content_width )); then
        padded_content="${content:0:$((content_width-1))}…"
    else
        padded_content="$content"
    fi
    
    echo -n "$side_char"
    printf "%*s" "$padding" ""
    printf "%-*s" "$content_width" "$padded_content"
    printf "%*s" "$padding" ""
    echo "$side_char"
    
    # Bottom border
    box_bottom_border "$width"
    echo
}