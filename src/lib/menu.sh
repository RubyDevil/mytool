#!/bin/bash

source "./ansi.sh"

declare -x menu_header="=============== Menu ==============="
declare -x -a menu=(
   "Exit" "exit 0"
   "Option 1" "echo 'Option 1' && read -p 'Press Enter to continue'"
   "Option 2" "echo 'Option 2' && read -p 'Press Enter to continue'"
   "Option 3" "echo 'Option 3' && read -p 'Press Enter to continue'"
)

# Trap exit signal and restore the terminal settings
trap 'tput cnorm; exit 0' EXIT

menu_display() {
   local -n menu_items=menu # Use nameref for the menu array
   local selected_index=0
   local menu_length=$((${#menu_items[@]} / 2)) # Each tuple has 2 elements

   while true; do
      clear

      # Recalculate the menu length (in case it has changed)
      menu_length=$((${#menu_items[@]} / 2))

      # Display the header
      echo -e "$menu_header\n"

      # Display menu items
      for ((i = 0; i < menu_length; i++)); do
         local task_display_name="${menu_items[i * 2]}"
         if [ "$i" -eq "$selected_index" ]; then
            echo -e "  > ${INVERSE}${task_display_name}${RESET}"
         else
            echo -e "    ${task_display_name}"
         fi
      done

      # Hide the cursor
      tput civis

      # Read user input
      read -rsn1 key
      case "$key" in
      $'\x1b') # Escape sequence
         read -rsn2 key
         case "$key" in
         "[A") # Up arrow
            ((selected_index--))
            if [ "$selected_index" -lt 0 ]; then
               selected_index=$((menu_length - 1))
            fi
            ;;
         "[B") # Down arrow
            ((selected_index++))
            if [ "$selected_index" -ge "$menu_length" ]; then
               selected_index=0
            fi
            ;;
         esac
         ;;
      "") # Enter key
         # Call the associated function
         local task_function="${menu_items[(selected_index * 2) + 1]}" # Function name
         $task_function
         ;;
      esac
   done
}
