#!/bin/bash

script_dir=$(dirname "${BASH_SOURCE[0]}")
source "$script_dir/ansi.sh"
source "$script_dir/pad.sh"

declare -x menu_header="Menu"
declare -x -a menu=(
   "Exit" "exit 0"
   "Option 1" "echo 'Option 1' && read -p 'Press Enter to continue'"
   "Option 2" "echo 'Option 2' && read -p 'Press Enter to continue'"
   "Option 3" "echo 'Option 3' && read -p 'Press Enter to continue'"
)

menu_width=
menu_tab="    "
opt_top=4
opt_left=$((1 + ${#menu_tab}))

# Heavy:    ━ ┃ ┏ ┓ ┗ ┛ ┣ ┫ ┳ ┻ ╋
# Light:    ─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼
# Double:   ═ ║ ╔ ╗ ╚ ╝ ╠ ╣ ╦ ╩ ╬
# Rounded:      ╒ ╕ ╘ ╛ ╞ ╡ ╤ ╧ ╪
# All:    ┌ ┍ ┎ ┏ ┐ ┑ ┒ ┓ └ ┕ ┖ ┗ ┘ ┙ ┚ ┛ ├ ┝ ┞ ┟ ┠ ┡ ┢ ┣ ┤ ┥ ┦ ┧ ┨ ┩ ┪ ┫ ┬ ┭ ┮ ┯ ┰ ┱ ┲ ┳ ┴ ┵ ┶ ┷ ┸ ┹ ┺ ┻ ┼ ┽ ┾ ┿ ╀ ╁ ╂ ╃ ╄ ╅ ╆ ╇ ╈ ╉ ╊ ╋

# Draw the entire menu with a border
menu_build() {
   local -n menu_items=menu                     # Use nameref for the menu array
   local menu_length=$((${#menu_items[@]} / 2)) # Each tuple has 2 elements

   # Clear the screen
   clear

   # Hide the cursor
   tput civis

   # Find the maximum content width (menu options or header)
   local content_width=0
   for ((i = 0; i < menu_length; i++)); do
      local task_display_name="${menu_items[i * 2]}"
      local task_display_name_length=${#task_display_name}
      if [ "$task_display_name_length" -gt "$content_width" ]; then
         content_width=$task_display_name_length
      fi
   done
   if [ "${#menu_header}" -gt "$content_width" ]; then
      content_width=${#menu_header}
   fi

   # Setup
   menu_width=$((content_width + 2 + (${#menu_tab} * 2)))
   empty_line=$(padc "│" "│" "$menu_width")

   # Display the menu top border
   echo -e "$(padc "┌" "┐" "$menu_width" "─")"

   # Display the menu header
   echo -e "│${menu_tab}$(pads "$menu_header" "$content_width")${menu_tab}│"

   # Display the menu middle border
   echo -e "$(padc "╞" "╡" "$menu_width" "═")"

   # Display an empty line
   echo -e "$empty_line"

   # Display the menu items
   for ((i = 0; i < menu_length; i++)); do
      local task_display_name="${menu_items[i * 2]}"
      echo -e "│${menu_tab}$(padr "$task_display_name" "$content_width")${menu_tab}│"
   done

   # Display an empty line
   echo -e "$empty_line"

   # Display the menu bottom border
   echo -e "$(padc "└" "┘" "$menu_width" "─")"
}

# Navigate the menu by redrawing specific parts
menu_navigate() {
   local selected_index=0
   local previous_index=0

   # Restore the cursor visibility and reset the terminal in case of exit
   trap 'tput cnorm; clear; exit 0' EXIT

   while true; do
      local -n menu_items=menu
      local menu_length=$((${#menu_items[@]} / 2)) # Each tuple has 2 elements

      # Redraw the unselected option's line
      tput cup $((opt_top + previous_index)) $((opt_left - 2))
      echo -n " "
      tput cup $((opt_top + previous_index)) $opt_left
      local task_display_name="${menu_items[(previous_index * 2)]}"
      echo -e "${task_display_name}"

      # Redraw the selected option's line
      tput cup $((opt_top + selected_index)) $((opt_left - 2))
      echo -n ">"
      tput cup $((opt_top + selected_index)) $opt_left
      local task_display_name="${menu_items[(selected_index * 2)]}"
      echo -e "${INVERSE}${task_display_name}${RESET}"

      # Read user input
      read -rsn1 key
      case "$key" in
      $'\x1b') # Escape sequence
         read -rsn2 key
         case "$key" in
         "[A") # Up arrow
            # Store the previous index and update the selected index
            previous_index="$selected_index"
            ((selected_index--))
            if [ "$selected_index" -lt 0 ]; then
               selected_index=$((menu_length - 1))
            fi
            ;;
         "[B") # Down arrow
            # Store the previous index and update the selected index
            previous_index="$selected_index"
            ((selected_index++))
            if [ "$selected_index" -ge "$menu_length" ]; then
               selected_index=0
            fi
            ;;
         esac
         ;;
      "") # Enter key
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
}

# Build and navigate the menu
menu_start() {
   menu_build
   menu_navigate
}
