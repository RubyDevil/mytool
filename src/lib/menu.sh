#!/bin/bash

script_dir=$(dirname "${BASH_SOURCE[0]}")
source "$script_dir/ansi.sh"
source "$script_dir/pad.sh"
source "$script_dir/settings.sh"
source "$script_dir/tools/reverse_proxy.sh"

# New configurable settings (override by editing the associative array `settings` before calling menu_start):
#   MENU_TOP / MENU_LEFT        Integer >=0. Screen row/col where the top-left corner of the menu box is placed. Default 0/0.
#   MENU_MIN_WIDTH / MENU_MAX_WIDTH  Total outer width of menu (borders included) after content measurement is clamped to this range.
#                                   If content would exceed MENU_MAX_WIDTH it is truncated with a trailing ellipsis (…). Padding is preserved.
#   MENU_MIN_HEIGHT / MENU_MAX_HEIGHT Total outer height (borders + header + spacers + visible option rows). Visible option rows = height - 6.
#                                   Scrolling still lists all options; only the visible window changes. If MAX not set uses available terminal space.
#                                   If MIN forces more space than available terminal rows, it is reduced to fit.
# Behavior notes:
#   * Width calculation order: Measure widest header/option -> + padding -> clamp with MIN/MAX -> recompute content width.
#   * Truncation adds a single Unicode ellipsis provided there is at least 1 column for content.
#   * Height structural constant lines = 6. (top border, header, mid border, spacer, spacer, bottom border). Remaining lines show options.
#   * Changing any of these settings between actions (e.g. inside a menu command) will re-apply on next menu_build.

# Unicode box drawing characters
declare -A LIGHT=(["0001"]="╴" ["0010"]="╷" ["0011"]="┐" ["0100"]="╶" ["0101"]="─" ["0110"]="┌" ["0111"]="┬" ["1000"]="╵" ["1001"]="┘" ["1010"]="│" ["1011"]="┤" ["1100"]="└" ["1101"]="┴" ["1110"]="├" ["1111"]="┼")
declare -A HEAVY=(["0001"]="╸" ["0010"]="╹" ["0011"]="┓" ["0100"]="╺" ["0101"]="━" ["0110"]="┏" ["0111"]="┳" ["1000"]="╹" ["1001"]="┛" ["1010"]="┃" ["1011"]="┫" ["1100"]="┗" ["1101"]="┻" ["1110"]="┣" ["1111"]="╋")

declare -x menu_header="Menu"
declare -x -a menu=(
   "Exit" "exit 0"
   "Option 1" "echo 'Option 1' && read -p 'Press Enter to continue'"
   "Option 2" "echo 'Option 2' && read -p 'Press Enter to continue'"
   "Option 3" "echo 'Option 3' && read -p 'Press Enter to continue'"
)

menu_tab="    "
menu_width=
content_width=
opt_top=4      # Will be recalculated after positioning
opt_left=$((1 + ${#menu_tab})) # Will be recalculated after positioning

declare -i selected_index
declare -i previous_index=0
declare -i max_options           # The maximum number of options that can be displayed
declare -i top_option            # The index of last option that is displayed
declare -i previous_top_option=0 # The index of the last option that was displayed

# Navigation stack for generic Back behavior
declare -a menu_history=()
current_menu_command=""

# Open a new menu (push current onto stack)
menu_open() {
   local next_fn=$1; shift || true
   if [ -n "$current_menu_command" ]; then
      menu_history+=("$current_menu_command")
   fi
   current_menu_command="$next_fn${1:+ }$*"
   "$next_fn" "$@"
}

# Go back to previous menu; exit if none
menu_back() {
   local last_index=$(( ${#menu_history[@]} - 1 ))
   if (( last_index < 0 )); then
      exit 0
   fi
   local cmd="${menu_history[$last_index]}"
   unset 'menu_history[$last_index]'
   current_menu_command="$cmd"
   eval "$cmd"
}

# Allow external scripts to set the current menu command after manual build
menu_set_current() { current_menu_command="$*"; }


# Draw the entire menu with a border
menu_build() {
   # ANSI settings
   local BORDER_TYPE_NAME=${settings["MENU_BORDER_TYPE"]:-"LIGHT"}
   if ! declare -p "$BORDER_TYPE_NAME" &>/dev/null; then BORDER_TYPE_NAME="LIGHT"; fi
   local -n BORDER_TYPE_REF=$BORDER_TYPE_NAME
   local -n BORDER_TYPE=${!BORDER_TYPE_REF}
   local BORDER_COLOR_NAME=${settings["MENU_BORDER_COLOR"]:-"FG_DEFAULT"}
   local BORDER_COLOR=${ANSI[$BORDER_COLOR_NAME]}

   local -n menu_items=menu                     # Use nameref for the menu array
   local menu_length=$((${#menu_items[@]} / 2)) # Each tuple has 2 elements

   # Terminal size
   local term_rows=$(tput lines)
   local term_cols=$(tput cols)

   # Positioning from settings (clamped within terminal)
   local menu_top_setting=${settings["MENU_TOP"]:-0}
   local menu_left_setting=${settings["MENU_LEFT"]:-0}
   # Sanitize numeric (fallback to 0 if not integer)
   [[ $menu_top_setting =~ ^[0-9]+$ ]] || menu_top_setting=0
   [[ $menu_left_setting =~ ^[0-9]+$ ]] || menu_left_setting=0
   (( menu_top_setting < 0 )) && menu_top_setting=0
   (( menu_left_setting < 0 )) && menu_left_setting=0

   local base_top=$menu_top_setting
   local base_left=$menu_left_setting

   # Find the maximum content width (menu options or header)
   content_width=0
   for ((i = 0; i < menu_length; i++)); do
      local task_display_name="${menu_items[i * 2]}"
      local task_display_name_length=$(slen "$task_display_name")
      if [ "$task_display_name_length" -gt "$content_width" ]; then
         content_width=$task_display_name_length
      fi
   done
   local header_length=$(slen "$menu_header")
   if [ "$header_length" -gt "$content_width" ]; then
      content_width=$header_length
   fi

   # Compute initial menu width (content + padding + borders)
   menu_width=$((content_width + 2 + (${#menu_tab} * 2)))

   # Width constraints
   local min_w_setting=${settings["MENU_MIN_WIDTH"]:-0}
   local max_w_setting=${settings["MENU_MAX_WIDTH"]:-0}
   [[ $min_w_setting =~ ^[0-9]+$ ]] || min_w_setting=0
   [[ $max_w_setting =~ ^[0-9]+$ ]] || max_w_setting=0
   # Apply min width first
   if (( min_w_setting > 0 && menu_width < min_w_setting )); then
      menu_width=$min_w_setting
   fi
   # Apply max width (truncate content width if needed)
   if (( max_w_setting > 0 && menu_width > max_w_setting )); then
      menu_width=$max_w_setting
   fi

   # Recalculate content_width from adjusted menu_width (minus padding and borders)
   local inner_padding=$((2 + (${#menu_tab} * 2)))
   local adjusted_content_width=$((menu_width - inner_padding))
   if (( adjusted_content_width < content_width )); then
      content_width=$adjusted_content_width
   fi
   if (( content_width < 1 )); then
      content_width=1
   fi

   # Height constraints
   # Base structural lines: 1 top border, 1 header, 1 middle border, 1 empty spacer above list, N options, 1 empty spacer below list, 1 bottom border = 6 + N
   # So total_height = 6 + visible_options
   local min_h_setting=${settings["MENU_MIN_HEIGHT"]:-0}
   local max_h_setting=${settings["MENU_MAX_HEIGHT"]:-0}
   [[ $min_h_setting =~ ^[0-9]+$ ]] || min_h_setting=0
   [[ $max_h_setting =~ ^[0-9]+$ ]] || max_h_setting=0

   # Maximum possible options based on terminal rows (keep within screen)
   local max_options_by_term=$((term_rows - base_top - 7)) # leave at least one row below; using 7 safety (borders & spacers) -> ensures >=1 option
   (( max_options_by_term < 1 )) && max_options_by_term=1

   # Derive requested visible options from height constraints
   # If max height specified, compute max visible options allowed
   local requested_visible_options
   if (( max_h_setting > 0 )); then
      # visible_options = max_h_setting - 6 (structure)
      requested_visible_options=$((max_h_setting - 6))
      (( requested_visible_options < 1 )) && requested_visible_options=1
      if (( requested_visible_options > max_options_by_term )); then
         requested_visible_options=$max_options_by_term
      fi
   else
      # Default to max fitting terminal
      requested_visible_options=$max_options_by_term
   fi

   # Apply min height (ensure at least min_h_setting total height)
   if (( min_h_setting > 0 )); then
      local min_visible_options=$((min_h_setting - 6))
      (( min_visible_options < 1 )) && min_visible_options=1
      if (( requested_visible_options < min_visible_options )); then
         requested_visible_options=$min_visible_options
      fi
   fi

   max_options=$requested_visible_options
   # Guard against menu smaller than number of items
   if (( max_options > menu_length )); then
      max_options=$menu_length
   fi

   # Adjust if width exceeds terminal width; clamp and update content width
   if (( menu_left_setting + menu_width > term_cols )); then
      menu_width=$(( term_cols - menu_left_setting ))
      (( menu_width < 10 )) && menu_width=10
      adjusted_content_width=$((menu_width - inner_padding))
      if (( adjusted_content_width < content_width )); then
         content_width=$adjusted_content_width
      fi
   fi

   # Compute option region top/left based on final positioning
   opt_top=$((base_top + 4))
   opt_left=$((base_left + 1 + ${#menu_tab}))

   # Scroll init
   top_option=0
   previous_top_option=0
   top_option=0
   previous_top_option=0

   # Set the selection indexes
   selected_index=0
   previous_index=0

   # Always clear the entire screen for a deterministic fresh draw
   clear
   tput civis

   # Helper function (cannot be declared with 'local' in bash)
   print_at() { local rel_row=$1; shift; tput cup $((base_top + rel_row)) $base_left; echo -e "$*"; }

   empty_line="${BORDER_COLOR}$(padc "${BORDER_TYPE[1010]}" "${BORDER_TYPE[1010]}" "$menu_width")${FG_DEFAULT}"

   # Draw components positioned
   print_at 0 "${BORDER_COLOR}$(padc "${BORDER_TYPE[0110]}" "${BORDER_TYPE[0011]}" "$menu_width" "${BORDER_TYPE[0101]}")${FG_DEFAULT}"
   # Header (truncate if needed)
   local header_display="$menu_header"
   if (( $(slen "$header_display") > content_width )); then
      header_display="$(echo -n "$header_display" | cut -c1-$((content_width-1)))…"
   fi
   # Build header line ensuring exact width even for edge parity cases
   local header_inner="${menu_tab}$(pads "$header_display" "$content_width")${menu_tab}"
   local expected_inner_len=$(( (${#menu_tab} * 2) + content_width ))
   # Measure visible length (strip ANSI)
   local header_inner_len=$(slen "$header_inner")
   if (( header_inner_len > expected_inner_len )); then
      # Trim extra (rare off-by-one scenarios)
      local trim=$((header_inner_len - expected_inner_len))
      header_inner="$(echo -n "$header_inner" | head -c $expected_inner_len)"
   elif (( header_inner_len < expected_inner_len )); then
      # Pad right to fill
      local pad_needed=$((expected_inner_len - header_inner_len))
      header_inner="${header_inner}$(printf '%*s' $pad_needed '')"
   fi
   print_at 1 "${BORDER_COLOR}${BORDER_TYPE[1010]}${FG_DEFAULT}${header_inner}${BORDER_COLOR}${BORDER_TYPE[1010]}${FG_DEFAULT}"
   print_at 2 "${BORDER_COLOR}$(padc "${BORDER_TYPE[1110]}" "${BORDER_TYPE[1011]}" "$menu_width" "${BORDER_TYPE[0101]}")${FG_DEFAULT}"
   print_at 3 "$empty_line"

   local start_index=$top_option
   local end_index=$((top_option + max_options - 1))
   (( end_index >= menu_length )) && end_index=$((menu_length-1))
   local rel_row=4
   for ((i = start_index; i <= end_index; i++)); do
      local task_display_name="${menu_items[(i * 2)]}"
      local display_name="$task_display_name"
      if (( $(slen "$display_name") > content_width )); then
         display_name="$(echo -n "$display_name" | cut -c1-$((content_width-1)))…"
      fi
      print_at $rel_row "${BORDER_COLOR}${BORDER_TYPE[1010]}${FG_DEFAULT}${menu_tab}$(padr "$display_name" "$content_width")${menu_tab}${BORDER_COLOR}${BORDER_TYPE[1010]}${FG_DEFAULT}"
      ((rel_row++))
   done

   print_at $rel_row "$empty_line"
   ((rel_row++))
   print_at $rel_row "${BORDER_COLOR}$(padc "${BORDER_TYPE[1100]}" "${BORDER_TYPE[1001]}" "$menu_width" "${BORDER_TYPE[0101]}")${FG_DEFAULT}"

   # Previous region tracking removed (always clearing screen now)
}

# Navigate the menu by redrawing specific parts
menu_navigate() {
   # ANSI settings
   local POINTER_COLOR_NAME=${settings["MENU_POINTER_COLOR"]:-"FG_DEFAULT"} # TODO: Move to top level
   local POINTER_COLOR=${ANSI[$POINTER_COLOR_NAME]}                         # TODO: Move to top level
   local POINTER_TYPE=${settings["MENU_POINTER_TYPE"]:-">"}                 # TODO: Move to top level

   # Restore the cursor visibility and reset the terminal in case of exit
   trap 'stty icanon echo; tput cnorm; clear; exit 0' EXIT

   # Set terminal to non-canonical mode (raw input)
   stty -icanon -echo

   while true; do
      local -n menu_items=menu
      local -i menu_length=$((${#menu_items[@]} / 2)) # Each tuple has 2 elements

      local -i start_index
      local -i end_index
      # If the range of visible options has changed, redraw all the options
      if [ "$top_option" -ne "$previous_top_option" ]; then
         # Redraw all the options
         start_index=$top_option
         end_index=$((top_option + max_options - 1))
      else
         # Redraw only the unselected and selected options
         start_index=$((selected_index < previous_index ? selected_index : previous_index))
         end_index=$((selected_index > previous_index ? selected_index : previous_index))
      fi

      # Adjust the range of visible options in case no scrolling is needed
      if [ "$end_index" -ge "$menu_length" ]; then
         end_index=$((menu_length - 1))
      fi

      # Redraw the applicatble menu items
      for ((i = start_index; i <= end_index; i++)); do
         local task_display_name="${menu_items[(i * 2)]}"
         # Truncate if needed
         local display_name="$task_display_name"
         if (( $(slen "$display_name") > content_width )); then
            display_name="$(echo -n "$display_name" | cut -c1-$((content_width-1)))…"
         fi
         local visual_i=$((i - top_option))

         if [ "$i" -ne $selected_index ]; then
            # Redraw the unselected option's line
            tput cup $((opt_top + visual_i)) $((opt_left - 2))
            echo -n " "
            tput cup $((opt_top + visual_i)) $opt_left
            echo -e "$(padr "$display_name" "$content_width")"
         else
            # Redraw the selected option's line
            tput cup $((opt_top + visual_i)) $((opt_left - 2))
            # Apply inverse before truncation display
            local inv_name="${INVERSE}$display_name${INVERSE_OFF}"
            echo -e "${POINTER_COLOR}${POINTER_TYPE}${FG_DEFAULT} $(padr "$inv_name" "$content_width")"
         fi
      done

      # Read user input
      read -rsn1 key
      case "$key" in
      # Escape sequence
      $'\x1b')
         read -rsn2 key
         case "$key" in
         # Up arrow key
         "[A")
            # Store the previous index
            previous_index="$selected_index"
            # Store the previous top option
            previous_top_option="$top_option"
            # Update the selected index
            ((selected_index--))
            # Update the top option
            if [ "$selected_index" -lt "$top_option" ]; then
               ((top_option--))
            fi
            # Wrap around
            if [ "$selected_index" -lt 0 ]; then
               selected_index=$((menu_length - 1))
               top_option=$((menu_length - max_options < 0 ? 0 : menu_length - max_options))
            fi
            ;;
         # Down arrow key
         "[B")
            # Store the previous index and update the selected index
            previous_index="$selected_index"
            # Store the previous top option
            previous_top_option="$top_option"
            # Update the selected index
            ((selected_index++))
            # Update the top option
            local bottom_option=$((top_option + max_options - 1))
            if [ "$selected_index" -gt "$bottom_option" ]; then
               ((top_option++))
            fi
            # Wrap around
            if [ "$selected_index" -ge "$menu_length" ]; then
               selected_index=0
               top_option=0
            fi
            ;;
         esac
         ;;
      # Enter key
      "")
         # Restore terminal to normal mode before executing the task
         stty icanon echo
         tput cnorm

         # Call the associated function
         local task_function="${menu_items[(selected_index * 2) + 1]}" # Function name
         $task_function

         # Redraw the menu
         menu_build

         # Set terminal to non-canonical mode (raw input)
         stty -icanon -echo
         tput civis
         continue
         ;;
      esac
   done

   # Restore the cursor visibility
   tput cnorm

   # Restore terminal to normal mode
   stty icanon echo
}

# Build and navigate the menu
menu_start() {
   menu_build
   menu_navigate
}
