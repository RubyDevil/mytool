#!/usr/bin/env bash

menu_lib_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if ! declare -F strip_ansi_into >/dev/null; then
   # shellcheck source=ansi.sh
   source "$menu_lib_dir/ansi.sh"
fi
if ! declare -F pad_right_into >/dev/null; then
   # shellcheck source=pad.sh
   source "$menu_lib_dir/pad.sh"
fi
if ! declare -p settings &>/dev/null; then
   # shellcheck source=settings.sh
   source "$menu_lib_dir/settings.sh"
fi
unset menu_lib_dir

# Unicode box drawing characters, keyed by connected directions.
declare -gA MENU_BORDER_LIGHT=(
   [0001]="╴" [0010]="╷" [0011]="┐" [0100]="╶" [0101]="─" [0110]="┌"
   [0111]="┬" [1000]="╵" [1001]="┘" [1010]="│" [1011]="┤" [1100]="└"
   [1101]="┴" [1110]="├" [1111]="┼"
)
declare -gA MENU_BORDER_HEAVY=(
   [0001]="╸" [0010]="╹" [0011]="┓" [0100]="╺" [0101]="━" [0110]="┏"
   [0111]="┳" [1000]="╹" [1001]="┛" [1010]="┃" [1011]="┫" [1100]="┗"
   [1101]="┻" [1110]="┣" [1111]="╋"
)

declare -g menu_header="Menu"
declare -g menu_tab="    "
declare -ga menu_labels=()
declare -ga menu_callbacks=()
declare -ga menu_argument_counts=()
declare -ga menu_selectable=()
declare -gA menu_arguments=()
declare -gA menu_selected=()

declare -gi menu_width=0
declare -gi content_width=0
declare -gi opt_top=4
declare -gi opt_left=$((1 + ${#menu_tab}))
declare -gi selected_index=0
declare -gi previous_index=0
declare -gi max_options=1
declare -gi top_option=0
declare -gi previous_top_option=0
declare -g menu_stty_state=""
declare -gi menu_active=0
declare -gi menu_multi_select=0
declare -g menu_selected_start_callback=""
declare -g menu_selected_complete_callback=""
declare -g menu_back_callback=""
declare -ga menu_back_arguments=()
declare -g menu_back_label="back"
# Styles resolved from the settings by menu_prepare_layout, once per build.
declare -g menu_border_color="$FG_DEFAULT"
declare -g menu_pointer_color="$FG_DEFAULT"
declare -g menu_pointer=">"
# Terminal size cached by menu_update_terminal_size so redraws never fork.
declare -gi menu_terminal_lines=24
declare -gi menu_terminal_columns=80
declare -gi menu_terminal_size_known=0

menu_clear() {
   menu_header="${1:-Menu}"
   menu_labels=()
   menu_callbacks=()
   menu_argument_counts=()
   menu_selectable=()
   menu_arguments=()
   menu_selected=()
   menu_multi_select=0
   menu_selected_start_callback=""
   menu_selected_complete_callback=""
   menu_back_callback=""
   menu_back_arguments=()
   menu_back_label="back"
}

# Set the callback, with lossless arguments, that Esc or q invokes.
menu_set_back() {
   local callback="${1-}"

   [[ "$callback" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 2
   shift
   menu_back_callback="$callback"
   menu_back_arguments=("$@")
   menu_back_label="back"
}

# Like menu_set_back, for a root menu where Esc or q leaves the application.
menu_set_exit() {
   menu_set_back "$@" || return
   menu_back_label="exit"
}

menu_go_back() {
   local callback="$menu_back_callback"
   local -a arguments=("${menu_back_arguments[@]}")

   [[ -n "$callback" ]] || return 1
   if ! declare -F "$callback" >/dev/null; then
      printf 'Menu back callback is not defined: %s\n' "$callback" >&2
      return 1
   fi
   "$callback" "${arguments[@]}"
}

menu_footer_into() {
   local _mfi_back=""

   [[ -n "$menu_back_callback" ]] && _mfi_back="   Esc/q: $menu_back_label"
   if ((menu_multi_select)); then
      printf -v "$1" '%s' "Space: toggle   Enter: run${_mfi_back}"
   else
      printf -v "$1" '%s' "Enter: select${_mfi_back}"
   fi
}

menu_footer() {
   local footer
   menu_footer_into footer
   printf '%s' "$footer"
}

menu_clear_multi() {
   menu_clear "$1"
   menu_multi_select=1
}

menu_set_selected_complete_callback() {
   local callback="${1-}"

   [[ "$callback" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 2
   menu_selected_complete_callback="$callback"
}

menu_set_selected_start_callback() {
   local callback="${1-}"

   [[ "$callback" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 2
   menu_selected_start_callback="$callback"
}

# Add an item as a label, callback, and zero or more lossless callback arguments.
menu_add() {
   local label="${1-}"
   local callback="${2-}"
   shift 2 || return 2

   if [[ ! "$callback" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      printf 'Invalid menu callback: %s\n' "$callback" >&2
      return 2
   fi

   local -i item_index=${#menu_labels[@]}
   local -i argument_index=0
   local argument

   menu_labels[item_index]="$label"
   menu_callbacks[item_index]="$callback"
   menu_argument_counts[item_index]=$#
   menu_selectable[item_index]=1
   for argument in "$@"; do
      menu_arguments["$item_index:$argument_index"]="$argument"
      argument_index=$((argument_index + 1))
   done
}

menu_add_action() {
   menu_add "$@" || return
   menu_selectable[$((${#menu_labels[@]} - 1))]=0
}

menu_add_selected() {
   menu_add "$@" || return
   menu_selected[$((${#menu_labels[@]} - 1))]=1
}

menu_invoke() {
   local -i item_index="$1"
   local callback="${menu_callbacks[item_index]-}"
   local -a arguments=()
   local -i argument_count=${menu_argument_counts[item_index]:-0}
   local -i argument_index

   if [[ -z "$callback" ]] || ! declare -F "$callback" >/dev/null; then
      printf 'Menu callback is not defined: %s\n' "$callback" >&2
      return 1
   fi

   for ((argument_index = 0; argument_index < argument_count; argument_index++)); do
      arguments+=("${menu_arguments["$item_index:$argument_index"]}")
   done

   "$callback" "${arguments[@]}"
}

menu_toggle_selected() {
   local -i item_index="${1:-$selected_index}"

   if ((item_index < 0 || item_index >= ${#menu_labels[@]})) || ((menu_selectable[item_index] == 0)); then
      return 1
   fi

   if [[ -n "${menu_selected[$item_index]+set}" ]]; then
      unset 'menu_selected[$item_index]'
   else
      menu_selected[$item_index]=1
   fi
}

menu_invoke_selected() {
   local -a callbacks=()
   local -a argument_counts=()
   local -a arguments=()
   local -i item_index argument_index argument_count
   local -i queue_index=0
   local -i arguments_index=0
   local -i status=0
   local callback
   local start_callback="$menu_selected_start_callback"
   local complete_callback="$menu_selected_complete_callback"

   for ((item_index = 0; item_index < ${#menu_labels[@]}; item_index++)); do
      [[ -n "${menu_selected[$item_index]+set}" ]] || continue
      callbacks[queue_index]="${menu_callbacks[item_index]}"
      argument_counts[queue_index]=${menu_argument_counts[item_index]:-0}
      for ((argument_index = 0; argument_index < argument_counts[queue_index]; argument_index++)); do
         arguments[arguments_index]="${menu_arguments["$item_index:$argument_index"]}"
         arguments_index=$((arguments_index + 1))
      done
      queue_index=$((queue_index + 1))
   done

   ((queue_index > 0)) || return 1
   menu_selected=()
   if [[ -n "$start_callback" ]]; then
      if ! declare -F "$start_callback" >/dev/null; then
         printf 'Menu start callback is not defined: %s\n' "$start_callback" >&2
         status=1
      elif ! "$start_callback"; then
         status=1
      fi
   fi
   arguments_index=0
   for ((queue_index = 0; queue_index < ${#callbacks[@]}; queue_index++)); do
      callback="${callbacks[queue_index]}"
      argument_count=${argument_counts[queue_index]}
      local -a callback_arguments=()
      for ((argument_index = 0; argument_index < argument_count; argument_index++)); do
         callback_arguments[argument_index]="${arguments[arguments_index]}"
         arguments_index=$((arguments_index + 1))
      done
      if [[ -z "$callback" ]] || ! declare -F "$callback" >/dev/null; then
         printf 'Menu callback is not defined: %s\n' "$callback" >&2
         status=1
      elif ! "$callback" "${callback_arguments[@]}"; then
         status=1
      fi
   done

   if [[ -n "$complete_callback" ]]; then
      if ! declare -F "$complete_callback" >/dev/null; then
         printf 'Menu completion callback is not defined: %s\n' "$complete_callback" >&2
         status=1
      elif ! "$complete_callback"; then
         status=1
      fi
   fi

   return "$status"
}

menu_display_label_into() {
   local -i _mdl_index="$2"
   local _mdl_marker='[ ]'

   if ((menu_multi_select && menu_selectable[_mdl_index])); then
      [[ -n "${menu_selected[$_mdl_index]+set}" ]] && _mdl_marker='[x]'
      printf -v "$1" '%s %s' "$_mdl_marker" "${menu_labels[_mdl_index]-}"
   else
      printf -v "$1" '%s' "${menu_labels[_mdl_index]-}"
   fi
}

menu_display_label() {
   local label
   menu_display_label_into label "$1"
   printf '%s' "$label"
}

menu_resolve_color_into() {
   local _mrc_name="${2^^}"
   printf -v "$1" '%s' "${ANSI[$_mrc_name]:-$FG_DEFAULT}"
}

menu_resolve_color() {
   local color
   menu_resolve_color_into color "$1"
   printf '%s' "$color"
}

menu_border_char_into() {
   case "${settings[MENU_BORDER_TYPE]^^}" in
   HEAVY) printf -v "$1" '%s' "${MENU_BORDER_HEAVY[$2]}" ;;
   *) printf -v "$1" '%s' "${MENU_BORDER_LIGHT[$2]}" ;;
   esac
}

menu_border_char() {
   local char
   menu_border_char_into char "$1"
   printf '%s' "$char"
}

# Refresh the cached terminal size with a single stty call, falling back to tput, then 24x80.
menu_update_terminal_size() {
   local size lines columns

   size=$(stty size 2>/dev/null) || size=""
   lines=${size% *}
   columns=${size#* }
   if [[ ! "$lines" =~ ^[1-9][0-9]*$ ]]; then
      lines=$(tput lines 2>/dev/null) || lines=""
      [[ "$lines" =~ ^[1-9][0-9]*$ ]] || lines=24
   fi
   if [[ ! "$columns" =~ ^[1-9][0-9]*$ ]]; then
      columns=$(tput cols 2>/dev/null) || columns=""
      [[ "$columns" =~ ^[1-9][0-9]*$ ]] || columns=80
   fi
   menu_terminal_lines=$lines
   menu_terminal_columns=$columns
   menu_terminal_size_known=1
}

# Store the menu height in the named variable; MENU_HEIGHT overrides the cached terminal size.
menu_terminal_rows_into() {
   local _mtr_rows="${MENU_HEIGHT-}"

   if [[ "$_mtr_rows" =~ ^[0-9]+$ ]] && ((_mtr_rows > 0)); then
      printf -v "$1" '%d' "$_mtr_rows"
      return
   fi

   ((menu_terminal_size_known)) || menu_update_terminal_size
   printf -v "$1" '%d' "$menu_terminal_lines"
}

# Print the menu height, querying the terminal afresh unless MENU_HEIGHT overrides it.
menu_terminal_rows() {
   local rows
   menu_terminal_size_known=0
   menu_terminal_rows_into rows
   printf '%d' "$rows"
}

menu_prepare_layout() {
   local -i item_index
   local -i item_length
   local -i rows
   local label footer

   menu_terminal_rows_into rows
   max_options=$((rows - 8))
   ((max_options < 1)) && max_options=1

   content_width=0
   for ((item_index = 0; item_index < ${#menu_labels[@]}; item_index++)); do
      menu_display_label_into label "$item_index"
      stripped_length_into item_length "$label"
      ((item_length > content_width)) && content_width=$item_length
   done

   stripped_length_into item_length "$menu_header"
   ((item_length > content_width)) && content_width=$item_length
   menu_footer_into footer
   stripped_length_into item_length "$footer"
   ((item_length > content_width)) && content_width=$item_length
   menu_width=$((content_width + 2 + (${#menu_tab} * 2)))
   opt_left=$((1 + ${#menu_tab}))

   menu_resolve_color_into menu_border_color "${settings[MENU_BORDER_COLOR]:-FG_DEFAULT}"
   menu_resolve_color_into menu_pointer_color "${settings[MENU_POINTER_COLOR]:-FG_DEFAULT}"
   menu_pointer="${settings[MENU_POINTER_TYPE]:->}"
}

# Render the full menu without changing terminal state.
menu_render() {
   menu_prepare_layout

   local vertical horizontal top_left top_right middle_left middle_right bottom_left bottom_right
   local border_left border_right empty_line divider label padded footer frame
   local -i item_index
   local -i end_index=$((top_option + max_options - 1))

   menu_border_char_into vertical 1010
   menu_border_char_into horizontal 0101
   menu_border_char_into top_left 0110
   menu_border_char_into top_right 0011
   menu_border_char_into middle_left 1110
   menu_border_char_into middle_right 1011
   menu_border_char_into bottom_left 1100
   menu_border_char_into bottom_right 1001
   border_left="${menu_border_color}${vertical}${FG_DEFAULT}${menu_tab}"
   border_right="${menu_tab}${menu_border_color}${vertical}${FG_DEFAULT}"
   pad_center_into empty_line "$vertical" "$vertical" "$menu_width"
   pad_center_into divider "$middle_left" "$middle_right" "$menu_width" "$horizontal"

   pad_center_into padded "$top_left" "$top_right" "$menu_width" "$horizontal"
   frame="${menu_border_color}${padded}${FG_DEFAULT}"$'\n'
   pad_sides_into padded "$menu_header" "$content_width"
   frame+="${border_left}${padded}${border_right}"$'\n'
   frame+="${menu_border_color}${divider}${FG_DEFAULT}"$'\n'
   frame+="${menu_border_color}${empty_line}${FG_DEFAULT}"$'\n'

   for ((item_index = top_option; item_index <= end_index; item_index++)); do
      menu_display_label_into label "$item_index"
      pad_right_into padded "$label" "$content_width"
      frame+="${border_left}${padded}${border_right}"$'\n'
   done

   frame+="${menu_border_color}${empty_line}${FG_DEFAULT}"$'\n'
   frame+="${menu_border_color}${divider}${FG_DEFAULT}"$'\n'
   menu_footer_into footer
   pad_right_into padded "${DIM}${footer}${RESET}" "$content_width"
   frame+="${border_left}${padded}${border_right}"$'\n'
   pad_center_into padded "$bottom_left" "$bottom_right" "$menu_width" "$horizontal"
   frame+="${menu_border_color}${padded}${FG_DEFAULT}"
   printf '%s' "$frame"
}

menu_build() {
   selected_index=0
   previous_index=0
   top_option=0
   previous_top_option=0

   if [[ -t 1 ]]; then
      menu_update_terminal_size
      clear
      tput civis 2>/dev/null || true
   fi
   menu_active=1
   menu_render
}

# Redraw one visible option in place with a single write.
menu_draw_option() {
   local -i item_index="$1"
   local -i row=$((opt_top + item_index - top_option + 1))
   local label padded

   menu_display_label_into label "$item_index"
   if ((item_index == selected_index)); then
      pad_right_into padded "${INVERSE}${label}${INVERSE_OFF}" "$content_width"
      printf '\033[%d;%dH%s %s' "$row" "$((opt_left - 1))" "${menu_pointer_color}${menu_pointer}${FG_DEFAULT}" "$padded"
   else
      pad_right_into padded "$label" "$content_width"
      printf '\033[%d;%dH  %s' "$row" "$((opt_left - 1))" "$padded"
   fi
}

menu_redraw_changed_options() {
   local -i start_index end_index item_index
   local -i item_count=${#menu_labels[@]}

   ((item_count == 0)) && return
   if ((top_option != previous_top_option)); then
      start_index=$top_option
      end_index=$((top_option + max_options - 1))
   else
      start_index=$((selected_index < previous_index ? selected_index : previous_index))
      end_index=$((selected_index > previous_index ? selected_index : previous_index))
   fi
   ((end_index >= item_count)) && end_index=$((item_count - 1))

   for ((item_index = start_index; item_index <= end_index; item_index++)); do
      menu_draw_option "$item_index"
   done
}

menu_move_up() {
   local -i item_count=${#menu_labels[@]}
   ((item_count == 0)) && return

   previous_index=$selected_index
   previous_top_option=$top_option
   ((selected_index--))
   if ((selected_index < 0)); then
      selected_index=$((item_count - 1))
      top_option=$((item_count > max_options ? item_count - max_options : 0))
   elif ((selected_index < top_option)); then
      ((top_option--))
   fi
}

menu_move_down() {
   local -i item_count=${#menu_labels[@]}
   ((item_count == 0)) && return

   previous_index=$selected_index
   previous_top_option=$top_option
   ((selected_index++))
   if ((selected_index >= item_count)); then
      selected_index=0
      top_option=0
   elif ((selected_index >= top_option + max_options)); then
      ((top_option++))
   fi
}

menu_restore_input() {
   if [[ -n "$menu_stty_state" && -t 0 ]]; then
      stty "$menu_stty_state" 2>/dev/null || true
   fi
   [[ -t 1 ]] && tput cnorm 2>/dev/null || true
}

menu_terminal_cleanup() {
   local status=$?
   menu_restore_input
   printf '%s' "$RESET"
   if ((menu_active)) && [[ -t 1 ]]; then
      clear
   fi
   menu_active=0
   trap - EXIT INT TERM HUP
   return "$status"
}

menu_navigate_back() {
   [[ -n "$menu_back_callback" ]] || return 0
   menu_restore_input
   menu_go_back
   menu_build
   stty -icanon -echo min 1 time 0
}

menu_navigate() {
   local key sequence

   if [[ ! -t 0 || ! -t 1 ]]; then
      printf 'Interactive menu navigation requires a terminal.\n' >&2
      return 1
   fi
   if ((${#menu_labels[@]} == 0)); then
      printf 'Cannot navigate an empty menu.\n' >&2
      return 1
   fi

   menu_stty_state=$(stty -g) || return 1
   trap menu_terminal_cleanup EXIT
   trap 'exit 130' INT
   trap 'exit 143' TERM HUP
   stty -icanon -echo min 1 time 0

   while true; do
      menu_redraw_changed_options
      IFS= read -rsn1 key || break

      case "$key" in
      $'\033')
         sequence=""
         IFS= read -rsn2 -t 0.1 sequence || true
         case "$sequence" in
         "[A") menu_move_up ;;
         "[B") menu_move_down ;;
         "") menu_navigate_back ;;
         esac
         ;;
      q | Q)
         menu_navigate_back
         ;;
      "")
         menu_restore_input
         if ((menu_multi_select && menu_selectable[selected_index])); then
            menu_invoke_selected || true
         else
            menu_invoke "$selected_index"
         fi
         menu_build
         stty -icanon -echo min 1 time 0
         ;;
      " ")
         if ((menu_multi_select && menu_selectable[selected_index])); then
            menu_toggle_selected "$selected_index"
            menu_draw_option "$selected_index"
         fi
         ;;
      esac
   done

   menu_terminal_cleanup
}

menu_start() {
   menu_build
   menu_navigate
}
