#!/usr/bin/env bash

sidebar_lib_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if ! declare -F menu_border_char >/dev/null; then
   # shellcheck source=menu.sh
   source "$sidebar_lib_dir/menu.sh"
fi
unset sidebar_lib_dir

declare -g sidebar_title="Items"
declare -g sidebar_content_callback=""
declare -ga sidebar_items=()
declare -gi sidebar_index=0
declare -gi sidebar_scroll=0
declare -gi sidebar_max_width=100

sidebar_clear() {
   local callback="${2-}"

   [[ "$callback" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 2
   sidebar_title="${1:-Items}"
   sidebar_content_callback="$callback"
   sidebar_items=()
   sidebar_index=0
   sidebar_scroll=0
}

sidebar_add() {
   sidebar_items+=("$1")
}

sidebar_terminal_columns() {
   local columns="${SIDEBAR_WIDTH-}"

   if [[ "$columns" =~ ^[0-9]+$ ]] && ((columns > 0)); then
      printf '%d' "$columns"
      return
   fi

   columns=$(tput cols 2>/dev/null) || columns=80
   [[ "$columns" =~ ^[0-9]+$ ]] || columns=80
   # Stay off the last column so the terminal never wraps the frame.
   columns=$((columns - 1))
   ((columns > sidebar_max_width)) && columns=$sidebar_max_width
   printf '%d' "$columns"
}

sidebar_move_up() {
   local -i item_count=${#sidebar_items[@]}

   ((item_count == 0)) && return
   sidebar_index=$(((sidebar_index - 1 + item_count) % item_count))
   sidebar_scroll=0
}

sidebar_move_down() {
   local -i item_count=${#sidebar_items[@]}

   ((item_count == 0)) && return
   sidebar_index=$(((sidebar_index + 1) % item_count))
   sidebar_scroll=0
}

# Scroll the content by a signed number of lines; sidebar_render clamps the offset.
sidebar_scroll_by() {
   sidebar_scroll=$((sidebar_scroll + $1))
   ((sidebar_scroll < 0)) && sidebar_scroll=0
   return 0
}

# Print the content lines of the selected item, wrapped to the given width.
sidebar_content_lines() {
   local width="$1"
   local line indent

   ((${#sidebar_items[@]} > 0)) || return 0
   declare -F "$sidebar_content_callback" >/dev/null || return 0
   while IFS= read -r line || [[ -n "$line" ]]; do
      line=${line//$'\t'/    }
      if [[ -z "$line" || "$line" == *$'\033'* ]] || (($(slen "$line") <= width)); then
         printf '%s\n' "$line"
      else
         # Keep the line's indentation on its wrapped continuation lines.
         indent=${line%%[! ]*}
         ((${#indent} > width / 2)) && indent=''
         printf '%s\n' "${line:${#indent}}" | fold -s -w $((width - ${#indent})) |
            while IFS= read -r line; do printf '%s%s\n' "$indent" "$line"; done
      fi
   done < <("$sidebar_content_callback" "${sidebar_items[sidebar_index]}")
}

# Render the full sidebar view without changing terminal state.
sidebar_render() {
   local -i rows columns body_rows left_width right_width item_width
   local -i row item_index top_item max_scroll
   local border_color pointer_color pointer
   local vertical horizontal join_top join_bottom
   local left right label footer
   local -a lines=()

   rows=$(menu_terminal_rows)
   columns=$(sidebar_terminal_columns)
   body_rows=$((rows - 6))
   ((body_rows < 1)) && body_rows=1

   left_width=$(slen "$sidebar_title")
   for label in "${sidebar_items[@]}"; do
      item_width=$(($(slen "$label") + 2))
      ((item_width > left_width)) && left_width=$item_width
   done
   right_width=$((columns - left_width - 7))
   ((right_width < 10)) && right_width=10

   border_color=$(menu_resolve_color "${settings[MENU_BORDER_COLOR]:-FG_DEFAULT}")
   pointer_color=$(menu_resolve_color "${settings[MENU_POINTER_COLOR]:-FG_DEFAULT}")
   pointer="${settings[MENU_POINTER_TYPE]:->}"
   vertical="${border_color}$(menu_border_char 1010)${FG_DEFAULT}"
   horizontal=$(menu_border_char 0101)
   join_top=$(menu_border_char 0111)
   join_bottom=$(menu_border_char 1101)

   mapfile -t lines < <(sidebar_content_lines "$right_width")
   max_scroll=$((${#lines[@]} - body_rows))
   ((max_scroll < 0)) && max_scroll=0
   ((sidebar_scroll > max_scroll)) && sidebar_scroll=$max_scroll
   lines=("${lines[@]:sidebar_scroll:body_rows}")
   if ((sidebar_scroll < max_scroll)); then
      lines[body_rows - 1]="${DIM}... (PgDn for more)${RESET}"
   fi
   top_item=$((sidebar_index >= body_rows ? sidebar_index - body_rows + 1 : 0))

   sidebar_border_line 0110 "$join_top" 0011 "$left_width" "$right_width" "$horizontal" "$border_color"
   printf '%s %s %s %s %s\n' "$vertical" "$(pad_sides "$sidebar_title" "$left_width")" "$vertical" \
      "$(pad_right "${BOLD}${sidebar_items[sidebar_index]-}${RESET}" "$right_width")" "$vertical"
   sidebar_border_line 1110 "$(menu_border_char 1111)" 1011 "$left_width" "$right_width" "$horizontal" "$border_color"

   for ((row = 0; row < body_rows; row++)); do
      item_index=$((top_item + row))
      left=""
      if ((item_index < ${#sidebar_items[@]})); then
         if ((item_index == sidebar_index)); then
            left="${pointer_color}${pointer}${FG_DEFAULT} ${INVERSE}${sidebar_items[item_index]}${INVERSE_OFF}"
         else
            left="  ${sidebar_items[item_index]}"
         fi
      fi
      right="${lines[row]-}"
      printf '%s %s %s %s %s\n' "$vertical" "$(pad_right "$left" "$left_width")" "$vertical" \
         "$(pad_right "$right" "$right_width")" "$vertical"
   done

   sidebar_border_line 1110 "$join_bottom" 1011 "$left_width" "$right_width" "$horizontal" "$border_color"
   footer='PgUp/PgDn: scroll   Esc/q: back'
   ((${#footer} > left_width + right_width + 3)) && footer='Esc/q: back'
   printf '%s %s %s\n' "$vertical" \
      "$(pad_right "${DIM}${footer}${RESET}" $((left_width + right_width + 3)))" "$vertical"
   printf '%s' "${border_color}$(pad_center "$(menu_border_char 1100)" "$(menu_border_char 1001)" \
      $((left_width + right_width + 7)) "$horizontal")${FG_DEFAULT}"
}

sidebar_border_line() {
   local left_key="$1"
   local join="$2"
   local right_key="$3"
   local -i left_width="$4"
   local -i right_width="$5"
   local horizontal="$6"
   local border_color="$7"

   printf '%s%s%s%s%s\n' "$border_color" \
      "$(pad_center "$(menu_border_char "$left_key")" "" $((left_width + 3)) "$horizontal")" \
      "$join" \
      "$(pad_center "" "$(menu_border_char "$right_key")" $((right_width + 3)) "$horizontal")" \
      "$FG_DEFAULT"
}

sidebar_start() {
   local key sequence suffix stty_state
   local -i page

   if [[ ! -t 0 || ! -t 1 ]]; then
      printf 'The sidebar view requires a terminal.\n' >&2
      return 1
   fi
   ((${#sidebar_items[@]} > 0)) || return 1

   stty_state=$(stty -g) || return 1
   stty -icanon -echo min 1 time 0
   tput civis 2>/dev/null || true
   clear

   while true; do
      page=$(($(menu_terminal_rows) - 7))
      ((page < 1)) && page=1
      tput cup 0 0
      sidebar_render
      IFS= read -rsn1 key || break
      case "$key" in
      $'\033')
         sequence=""
         IFS= read -rsn2 -t 0.1 sequence || true
         if [[ "$sequence" == "[5" || "$sequence" == "[6" ]]; then
            suffix=""
            IFS= read -rsn1 -t 0.1 suffix || true
            sequence+="$suffix"
         fi
         case "$sequence" in
         "[A") sidebar_move_up ;;
         "[B") sidebar_move_down ;;
         "[5~") sidebar_scroll_by $((-page)) ;;
         "[6~") sidebar_scroll_by "$page" ;;
         "") break ;;
         esac
         ;;
      k) sidebar_move_up ;;
      j) sidebar_move_down ;;
      "" | q | Q) break ;;
      esac
   done

   stty "$stty_state" 2>/dev/null || true
   tput cnorm 2>/dev/null || true
}
