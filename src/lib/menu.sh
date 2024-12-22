#!/bin/bash

script_dir=$(dirname "${BASH_SOURCE[0]}")
source "$script_dir/ansi.sh"
source "$script_dir/pad.sh"
source "$script_dir/settings.sh"

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
opt_top=4
opt_left=$((1 + ${#menu_tab}))

declare -i selected_index
declare -i previous_index=0
declare -i max_options           # The maximum number of options that can be displayed
declare -i top_option            # The index of last option that is displayed
declare -i previous_top_option=0 # The index of the last option that was displayed

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

   # Scroll
   local max_rows=$(tput lines)
   max_options=$((max_rows - 6))
   top_option=0
   previous_top_option=0

   # Set the selection indexes
   selected_index=0
   previous_index=0

   # Clear the screen
   clear

   # Hide the cursor
   tput civis

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
      content_width=${#menu_header}
   fi

   # Setup
   menu_width=$((content_width + 2 + (${#menu_tab} * 2)))
   empty_line="${BORDER_COLOR}$(padc "${BORDER_TYPE[1010]}" "${BORDER_TYPE[1010]}" "$menu_width")${FG_DEFAULT}"

   # Display the menu top border
   echo -e "${BORDER_COLOR}$(padc "${BORDER_TYPE[0110]}" "${BORDER_TYPE[0011]}" "$menu_width" "${BORDER_TYPE[0101]}")${FG_DEFAULT}"

   # Display the menu header
   echo -e "${BORDER_COLOR}${BORDER_TYPE[1010]}${FG_DEFAULT}${menu_tab}$(pads "$menu_header" "$content_width")${menu_tab}${BORDER_COLOR}${BORDER_TYPE[1010]}${FG_DEFAULT}"

   # Display the menu middle border
   echo -e "${BORDER_COLOR}$(padc "${BORDER_TYPE[1110]}" "${BORDER_TYPE[1011]}" "$menu_width" "${BORDER_TYPE[0101]}")${FG_DEFAULT}"

   # Display an empty line
   echo -e "$empty_line"

   # Display the menu items
   local start_index=$top_option
   local end_index=$((top_option + max_options - 1))
   for ((i = start_index; i <= end_index; i++)); do
      local task_display_name="${menu_items[(i * 2)]}"
      echo -e "${BORDER_COLOR}${BORDER_TYPE[1010]}${FG_DEFAULT}${menu_tab}$(padr "$task_display_name" "$content_width")${menu_tab}${BORDER_COLOR}${BORDER_TYPE[1010]}${FG_DEFAULT}"
   done

   # Display an empty line
   echo -e "$empty_line"

   # Display the menu bottom border
   echo -e -n "${BORDER_COLOR}$(padc "${BORDER_TYPE[1100]}" "${BORDER_TYPE[1001]}" "$menu_width" "${BORDER_TYPE[0101]}")${FG_DEFAULT}"
}

# Navigate the menu by redrawing specific parts
menu_navigate() {
   # ANSI settings
   local POINTER_COLOR_NAME=${settings["MENU_POINTER_COLOR"]:-"FG_DEFAULT"} # TODO: Move to top level
   local POINTER_COLOR=${ANSI[$POINTER_COLOR_NAME]}                         # TODO: Move to top level
   local POINTER_TYPE=${settings["MENU_POINTER_TYPE"]:-">"}                 # TODO: Move to top level

   # Restore the cursor visibility and reset the terminal in case of exit
   trap 'tput cnorm; clear; exit 0' EXIT

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

      # Redraw the applicatble menu items
      for ((i = start_index; i <= end_index; i++)); do
         local task_display_name="${menu_items[(i * 2)]}"
         local visual_i=$((i - top_option))

         if [ "$i" -ne $selected_index ]; then
            # Redraw the unselected option's line
            tput cup $((opt_top + visual_i)) $((opt_left - 2))
            echo -n " "
            tput cup $((opt_top + visual_i)) $opt_left
            echo -e "$(padr "$task_display_name" "$content_width")"
         else
            # Redraw the selected option's line
            tput cup $((opt_top + visual_i)) $((opt_left - 2))
            echo -e "${POINTER_COLOR}${POINTER_TYPE}${FG_DEFAULT} ${INVERSE}$(padr "$task_display_name" "$content_width")${INVERSE_OFF}"
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
               top_option=$((menu_length - max_options))
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
         # Restore the cursor visibility
         tput cnorm

         # Call the associated function
         local task_function="${menu_items[(selected_index * 2) + 1]}" # Function name
         $task_function

         # Redraw the menu
         menu_build
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
