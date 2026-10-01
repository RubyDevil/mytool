#!/usr/bin/env bash

menu_lib_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if ! declare -F strip_ansi >/dev/null; then
   # shellcheck source=ansi.sh
   source "$menu_lib_dir/ansi.sh"
fi
if ! declare -F pad_right >/dev/null; then
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

menu_footer() {
   local back=""

   [[ -n "$menu_back_callback" ]] && back="   Esc/q: $menu_back_label"
   if ((menu_multi_select)); then
      printf '%s' "Space: toggle   Enter: run${back}"
   else
      printf '%s' "Enter: select${back}"
   fi
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

menu_display_label() {
   local -i item_index="$1"
   local marker='[ ]'

   if ((menu_multi_select)); then
      if ((menu_selectable[item_index])); then
         [[ -n "${menu_selected[$item_index]+set}" ]] && marker='[x]'
         printf '%s %s' "$marker" "${menu_labels[item_index]-}"
      else
         printf '%s' "${menu_labels[item_index]-}"
      fi
   else
      printf '%s' "${menu_labels[item_index]-}"
   fi
}

menu_resolve_color() {
   local name="${1^^}"
   printf '%s' "${ANSI[$name]:-$FG_DEFAULT}"
}

menu_border_char() {
   local key="$1"
   case "${settings[MENU_BORDER_TYPE]^^}" in
   HEAVY) printf '%s' "${MENU_BORDER_HEAVY[$key]}" ;;
   *) printf '%s' "${MENU_BORDER_LIGHT[$key]}" ;;
   esac
}

menu_terminal_rows() {
   local rows="${MENU_HEIGHT-}"

   if [[ "$rows" =~ ^[0-9]+$ ]] && ((rows > 0)); then
      printf '%d' "$rows"
      return
   fi

   rows=$(tput lines 2>/dev/null) || rows=24
   [[ "$rows" =~ ^[0-9]+$ ]] || rows=24
   printf '%d' "$rows"
}

menu_prepare_layout() {
   local -i item_index
   local -i item_length
   local -i rows
   local -i header_length

   local -i footer_length

   rows=$(menu_terminal_rows)
   max_options=$((rows - 8))
   ((max_options < 1)) && max_options=1

   content_width=0
   for ((item_index = 0; item_index < ${#menu_labels[@]}; item_index++)); do
      item_length=$(slen "$(menu_display_label "$item_index")")
      ((item_length > content_width)) && content_width=$item_length
   done

   header_length=$(slen "$menu_header")
   ((header_length > content_width)) && content_width=$header_length
   footer_length=$(slen "$(menu_footer)")
   ((footer_length > content_width)) && content_width=$footer_length
   menu_width=$((content_width + 2 + (${#menu_tab} * 2)))
   opt_left=$((1 + ${#menu_tab}))
}

# Render the full menu without changing terminal state.
menu_render() {
   menu_prepare_layout

   local border_color
   local vertical horizontal top_left top_right middle_left middle_right bottom_left bottom_right
   local empty_line label
   local -i item_index
   local -i end_index=$((top_option + max_options - 1))

   border_color=$(menu_resolve_color "${settings[MENU_BORDER_COLOR]:-FG_DEFAULT}")
   vertical=$(menu_border_char 1010)
   horizontal=$(menu_border_char 0101)
   top_left=$(menu_border_char 0110)
   top_right=$(menu_border_char 0011)
   middle_left=$(menu_border_char 1110)
   middle_right=$(menu_border_char 1011)
   bottom_left=$(menu_border_char 1100)
   bottom_right=$(menu_border_char 1001)
   empty_line="${border_color}$(pad_center "$vertical" "$vertical" "$menu_width")${FG_DEFAULT}"

   printf '%s\n' "${border_color}$(pad_center "$top_left" "$top_right" "$menu_width" "$horizontal")${FG_DEFAULT}"
   printf '%s\n' "${border_color}${vertical}${FG_DEFAULT}${menu_tab}$(pad_sides "$menu_header" "$content_width")${menu_tab}${border_color}${vertical}${FG_DEFAULT}"
   printf '%s\n' "${border_color}$(pad_center "$middle_left" "$middle_right" "$menu_width" "$horizontal")${FG_DEFAULT}"
   printf '%s\n' "$empty_line"

   for ((item_index = top_option; item_index <= end_index; item_index++)); do
      label=$(menu_display_label "$item_index")
      printf '%s\n' "${border_color}${vertical}${FG_DEFAULT}${menu_tab}$(pad_right "$label" "$content_width")${menu_tab}${border_color}${vertical}${FG_DEFAULT}"
   done

   printf '%s\n' "$empty_line"
   printf '%s\n' "${border_color}$(pad_center "$middle_left" "$middle_right" "$menu_width" "$horizontal")${FG_DEFAULT}"
   printf '%s\n' "${border_color}${vertical}${FG_DEFAULT}${menu_tab}$(pad_right "${DIM}$(menu_footer)${RESET}" "$content_width")${menu_tab}${border_color}${vertical}${FG_DEFAULT}"
   printf '%s' "${border_color}$(pad_center "$bottom_left" "$bottom_right" "$menu_width" "$horizontal")${FG_DEFAULT}"
}

menu_build() {
   selected_index=0
   previous_index=0
   top_option=0
   previous_top_option=0
   menu_prepare_layout

   if [[ -t 1 ]]; then
      clear
      tput civis 2>/dev/null || true
   fi
   menu_active=1
   menu_render
}

menu_draw_option() {
   local -i item_index="$1"
   local -i visual_index=$((item_index - top_option))
   local label
   local pointer_color pointer

   label=$(menu_display_label "$item_index")
   pointer_color=$(menu_resolve_color "${settings[MENU_POINTER_COLOR]:-FG_DEFAULT}")
   pointer="${settings[MENU_POINTER_TYPE]:->}"

   if ((item_index == selected_index)); then
      tput cup $((opt_top + visual_index)) $((opt_left - 2))
      printf '%s' "${pointer_color}${pointer}${FG_DEFAULT} $(pad_right "${INVERSE}${label}${INVERSE_OFF}" "$content_width")"
   else
      tput cup $((opt_top + visual_index)) $((opt_left - 2))
      printf ' '
      tput cup $((opt_top + visual_index)) "$opt_left"
      printf '%s' "$(pad_right "$label" "$content_width")"
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
