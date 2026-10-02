#!/usr/bin/env bash

sidebar_lib_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if ! declare -F menu_border_char_into >/dev/null; then
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
# Wrapped content lines of the selected item, filled by sidebar_load_content.
declare -ga sidebar_lines=()
# Content cache: callback output per item index and wrapped lines per "index:width",
# each stored as a (start, count) slice of a flat array.
declare -ga sidebar_raw_lines=()
declare -gA sidebar_raw_start=()
declare -gA sidebar_raw_count=()
declare -ga sidebar_wrapped_lines=()
declare -gA sidebar_wrapped_start=()
declare -gA sidebar_wrapped_count=()

sidebar_clear() {
   local callback="${2-}"

   [[ "$callback" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 2
   sidebar_title="${1:-Items}"
   sidebar_content_callback="$callback"
   sidebar_items=()
   sidebar_index=0
   sidebar_scroll=0
   sidebar_lines=()
   sidebar_raw_lines=()
   sidebar_raw_start=()
   sidebar_raw_count=()
   sidebar_wrapped_lines=()
   sidebar_wrapped_start=()
   sidebar_wrapped_count=()
}

sidebar_add() {
   sidebar_items+=("$1")
}

# Store the sidebar width in the named variable; SIDEBAR_WIDTH overrides the cached terminal size.
sidebar_terminal_columns_into() {
   local _stc_columns="${SIDEBAR_WIDTH-}"

   if [[ "$_stc_columns" =~ ^[0-9]+$ ]] && ((_stc_columns > 0)); then
      printf -v "$1" '%d' "$_stc_columns"
      return
   fi

   ((menu_terminal_size_known)) || menu_update_terminal_size
   # Stay off the last column so the terminal never wraps the frame.
   _stc_columns=$((menu_terminal_columns - 1))
   ((_stc_columns > sidebar_max_width)) && _stc_columns=$sidebar_max_width
   printf -v "$1" '%d' "$_stc_columns"
}

# Print the sidebar width, querying the terminal afresh unless SIDEBAR_WIDTH overrides it.
sidebar_terminal_columns() {
   local columns
   menu_terminal_size_known=0
   sidebar_terminal_columns_into columns
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

# Append a content line to sidebar_wrapped_lines, broken after the last space that fits the width
# like fold -s, keeping the line's indentation on its continuation lines.
sidebar_wrap_line() {
   local line="$1"
   local -i width="$2"
   local -i visible limit cut
   local indent rest chunk

   stripped_length_into visible "$line"
   if [[ -z "$line" || "$line" == *$'\033'* ]] || ((visible <= width)); then
      sidebar_wrapped_lines+=("$line")
      return
   fi

   indent=${line%%[! ]*}
   ((${#indent} > width / 2)) && indent=''
   rest=${line:${#indent}}
   limit=$((width - ${#indent}))
   ((limit < 1)) && limit=1
   while ((${#rest} > limit)); do
      chunk=${rest:0:limit}
      if [[ "$chunk" == *' '* ]]; then
         chunk=${chunk% *}
         cut=$((${#chunk} + 1))
      else
         cut=$limit
      fi
      sidebar_wrapped_lines+=("$indent${rest:0:cut}")
      rest=${rest:cut}
   done
   sidebar_wrapped_lines+=("$indent$rest")
}

# Fill sidebar_lines with the selected item's content wrapped to the given width. The callback runs
# once per item, and the wrapping once per item and width, until the next sidebar_clear.
sidebar_load_content() {
   local -i width="$1"
   local key="$sidebar_index:$width"
   local line
   local -i start count index

   sidebar_lines=()
   ((${#sidebar_items[@]} > 0)) || return 0
   declare -F "$sidebar_content_callback" >/dev/null || return 0

   if [[ -z "${sidebar_raw_count[$sidebar_index]+set}" ]]; then
      start=${#sidebar_raw_lines[@]}
      while IFS= read -r line || [[ -n "$line" ]]; do
         line=${line%$'\r'}
         sidebar_raw_lines+=("${line//$'\t'/    }")
      done < <("$sidebar_content_callback" "${sidebar_items[sidebar_index]}")
      sidebar_raw_start[$sidebar_index]=$start
      sidebar_raw_count[$sidebar_index]=$((${#sidebar_raw_lines[@]} - start))
   fi

   if [[ -z "${sidebar_wrapped_count[$key]+set}" ]]; then
      start=${sidebar_raw_start[$sidebar_index]}
      count=${sidebar_raw_count[$sidebar_index]}
      sidebar_wrapped_start[$key]=${#sidebar_wrapped_lines[@]}
      for ((index = start; index < start + count; index++)); do
         sidebar_wrap_line "${sidebar_raw_lines[index]}" "$width"
      done
      sidebar_wrapped_count[$key]=$((${#sidebar_wrapped_lines[@]} - ${sidebar_wrapped_start[$key]}))
   fi

   start=${sidebar_wrapped_start[$key]}
   count=${sidebar_wrapped_count[$key]}
   sidebar_lines=("${sidebar_wrapped_lines[@]:start:count}")
}

# Print the content lines of the selected item, wrapped to the given width.
sidebar_content_lines() {
   sidebar_load_content "$1"
   ((${#sidebar_lines[@]} == 0)) || printf '%s\n' "${sidebar_lines[@]}"
}

# Render the full sidebar view without changing terminal state.
sidebar_render() {
   local -i rows columns body_rows left_width right_width item_width
   local -i row item_index top_item max_scroll
   local border_color pointer_color pointer
   local vertical horizontal join_top join_bottom cross corner_left corner_right
   local left right label footer padded line frame
   local -a lines=()

   menu_terminal_rows_into rows
   sidebar_terminal_columns_into columns
   body_rows=$((rows - 6))
   ((body_rows < 1)) && body_rows=1

   stripped_length_into left_width "$sidebar_title"
   for label in "${sidebar_items[@]}"; do
      stripped_length_into item_width "$label"
      item_width=$((item_width + 2))
      ((item_width > left_width)) && left_width=$item_width
   done
   right_width=$((columns - left_width - 7))
   ((right_width < 10)) && right_width=10

   menu_resolve_color_into border_color "${settings[MENU_BORDER_COLOR]:-FG_DEFAULT}"
   menu_resolve_color_into pointer_color "${settings[MENU_POINTER_COLOR]:-FG_DEFAULT}"
   pointer="${settings[MENU_POINTER_TYPE]:->}"
   menu_border_char_into vertical 1010
   vertical="${border_color}${vertical}${FG_DEFAULT}"
   menu_border_char_into horizontal 0101
   menu_border_char_into join_top 0111
   menu_border_char_into join_bottom 1101
   menu_border_char_into cross 1111

   sidebar_load_content "$right_width"
   lines=("${sidebar_lines[@]}")
   max_scroll=$((${#lines[@]} - body_rows))
   ((max_scroll < 0)) && max_scroll=0
   ((sidebar_scroll > max_scroll)) && sidebar_scroll=$max_scroll
   lines=("${lines[@]:sidebar_scroll:body_rows}")
   if ((sidebar_scroll < max_scroll)); then
      lines[body_rows - 1]="${DIM}... (PgDn for more)${RESET}"
   fi
   top_item=$((sidebar_index >= body_rows ? sidebar_index - body_rows + 1 : 0))

   sidebar_border_line_into line 0110 "$join_top" 0011 "$left_width" "$right_width" "$horizontal" "$border_color"
   frame="$line"$'\n'
   pad_sides_into padded "$sidebar_title" "$left_width"
   pad_right_into right "${BOLD}${sidebar_items[sidebar_index]-}${RESET}" "$right_width"
   frame+="$vertical $padded $vertical $right $vertical"$'\n'
   sidebar_border_line_into line 1110 "$cross" 1011 "$left_width" "$right_width" "$horizontal" "$border_color"
   frame+="$line"$'\n'

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
      pad_right_into left "$left" "$left_width"
      pad_right_into right "${lines[row]-}" "$right_width"
      frame+="$vertical $left $vertical $right $vertical"$'\n'
   done

   sidebar_border_line_into line 1110 "$join_bottom" 1011 "$left_width" "$right_width" "$horizontal" "$border_color"
   frame+="$line"$'\n'
   footer='PgUp/PgDn: scroll   Esc/q: back'
   ((${#footer} > left_width + right_width + 3)) && footer='Esc/q: back'
   pad_right_into padded "${DIM}${footer}${RESET}" $((left_width + right_width + 3))
   frame+="$vertical $padded $vertical"$'\n'
   menu_border_char_into corner_left 1100
   menu_border_char_into corner_right 1001
   pad_center_into padded "$corner_left" "$corner_right" $((left_width + right_width + 7)) "$horizontal"
   frame+="${border_color}${padded}${FG_DEFAULT}"
   printf '%s' "$frame"
}

sidebar_border_line_into() {
   local _sbl_corner _sbl_left _sbl_right
   local -i _sbl_left_width="$5"
   local -i _sbl_right_width="$6"

   menu_border_char_into _sbl_corner "$2"
   pad_center_into _sbl_left "$_sbl_corner" "" $((_sbl_left_width + 3)) "$7"
   menu_border_char_into _sbl_corner "$4"
   pad_center_into _sbl_right "" "$_sbl_corner" $((_sbl_right_width + 3)) "$7"
   printf -v "$1" '%s%s%s%s%s' "$8" "$_sbl_left" "$3" "$_sbl_right" "$FG_DEFAULT"
}

sidebar_start() {
   local key sequence suffix stty_state
   local -i page rows

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
      menu_update_terminal_size
      menu_terminal_rows_into rows
      page=$((rows - 7))
      ((page < 1)) && page=1
      printf '\033[H'
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
