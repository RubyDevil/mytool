#!/usr/bin/env bash

# Remove SGR color and style sequences from a string.
strip_ansi() {
   local text="${1-}"
   local escape_pattern=$'^(.*)\033\[[0-9;:]*m(.*)$'
   local literal_pattern='^(.*)\\(e|x1b|033)\[[0-9;:]*m(.*)$'

   while [[ "$text" =~ $escape_pattern ]]; do
      text=${BASH_REMATCH[1]}${BASH_REMATCH[2]}
   done
   while [[ "$text" =~ $literal_pattern ]]; do
      text=${BASH_REMATCH[1]}${BASH_REMATCH[3]}
   done

   printf '%s' "$text"
}

# Return the visible character length of a string.
stripped_length() {
   local stripped
   stripped=$(strip_ansi "${1-}")
   printf '%d' "${#stripped}"
}
slen() { stripped_length "$@"; }

# ANSI escape codes
declare -A _ANSI_CODES=(
   [RESET]=0 [BOLD]=1 [DIM]=2 [ITALIC]=3 [UNDERLINE]=4 [BLINK]=5 [RAPID_BLINK]=6
   [INVERSE]=7 [CONCEAL]=8 [STRIKE]=9 [PRIMARY_FONT]=10 [ALTERNATE_FONT_1]=11
   [ALTERNATE_FONT_2]=12 [ALTERNATE_FONT_3]=13 [ALTERNATE_FONT_4]=14
   [ALTERNATE_FONT_5]=15 [ALTERNATE_FONT_6]=16 [ALTERNATE_FONT_7]=17
   [ALTERNATE_FONT_8]=18 [ALTERNATE_FONT_9]=19 [FRAKTUR]=20 [BOLD_OFF]=21
   [NORMAL_COLOR]=22 [ITALIC_OFF]=23 [UNDERLINE_OFF]=24 [BLINK_OFF]=25
   [INVERSE_OFF]=27 [CONCEAL_OFF]=28 [STRIKE_OFF]=29 [FG_BLACK]=30 [FG_RED]=31
   [FG_GREEN]=32 [FG_YELLOW]=33 [FG_BLUE]=34 [FG_MAGENTA]=35 [FG_CYAN]=36
   [FG_WHITE]=37 [FG_DEFAULT]=39 [BG_BLACK]=40 [BG_RED]=41 [BG_GREEN]=42
   [BG_YELLOW]=43 [BG_BLUE]=44 [BG_MAGENTA]=45 [BG_CYAN]=46 [BG_WHITE]=47
   [BG_DEFAULT]=49 [FRAMED]=51 [ENCIRCLED]=52 [OVERLINED]=53 [FRAMED_OFF]=54
   [OVERLINED_OFF]=55
)

for key in "${!_ANSI_CODES[@]}"; do
   printf -v "$key" '\033[%sm' "${_ANSI_CODES[$key]}"
   export "$key"
done
unset _ANSI_CODES

# Foreground color shorthands
BLACK=$FG_BLACK
RED=$FG_RED
GREEN=$FG_GREEN
YELLOW=$FG_YELLOW
BLUE=$FG_BLUE
MAGENTA=$FG_MAGENTA
CYAN=$FG_CYAN
WHITE=$FG_WHITE
DEFAULT=$FG_DEFAULT
export BLACK RED GREEN YELLOW BLUE MAGENTA CYAN WHITE DEFAULT

# Associative table of ANSI
declare -gA ANSI=(
   ["RESET"]="$RESET"
   ["BOLD"]="$BOLD"
   ["DIM"]="$DIM"
   ["ITALIC"]="$ITALIC"
   ["UNDERLINE"]="$UNDERLINE"
   ["BLINK"]="$BLINK"
   ["RAPID_BLINK"]="$RAPID_BLINK"
   ["INVERSE"]="$INVERSE"
   ["CONCEAL"]="$CONCEAL"
   ["STRIKE"]="$STRIKE"
   ["PRIMARY_FONT"]="$PRIMARY_FONT"
   ["ALTERNATE_FONT_1"]="$ALTERNATE_FONT_1"
   ["ALTERNATE_FONT_2"]="$ALTERNATE_FONT_2"
   ["ALTERNATE_FONT_3"]="$ALTERNATE_FONT_3"
   ["ALTERNATE_FONT_4"]="$ALTERNATE_FONT_4"
   ["ALTERNATE_FONT_5"]="$ALTERNATE_FONT_5"
   ["ALTERNATE_FONT_6"]="$ALTERNATE_FONT_6"
   ["ALTERNATE_FONT_7"]="$ALTERNATE_FONT_7"
   ["ALTERNATE_FONT_8"]="$ALTERNATE_FONT_8"
   ["ALTERNATE_FONT_9"]="$ALTERNATE_FONT_9"
   ["FRAKTUR"]="$FRAKTUR"
   ["BOLD_OFF"]="$BOLD_OFF"
   ["NORMAL_COLOR"]="$NORMAL_COLOR"
   ["ITALIC_OFF"]="$ITALIC_OFF"
   ["UNDERLINE_OFF"]="$UNDERLINE_OFF"
   ["BLINK_OFF"]="$BLINK_OFF"
   ["INVERSE_OFF"]="$INVERSE_OFF"
   ["CONCEAL_OFF"]="$CONCEAL_OFF"
   ["STRIKE_OFF"]="$STRIKE_OFF"
   ["FG_BLACK"]="$FG_BLACK"
   ["FG_RED"]="$FG_RED"
   ["FG_GREEN"]="$FG_GREEN"
   ["FG_YELLOW"]="$FG_YELLOW"
   ["FG_BLUE"]="$FG_BLUE"
   ["FG_MAGENTA"]="$FG_MAGENTA"
   ["FG_CYAN"]="$FG_CYAN"
   ["FG_WHITE"]="$FG_WHITE"
   ["FG_DEFAULT"]="$FG_DEFAULT"
   ["BG_BLACK"]="$BG_BLACK"
   ["BG_RED"]="$BG_RED"
   ["BG_GREEN"]="$BG_GREEN"
   ["BG_YELLOW"]="$BG_YELLOW"
   ["BG_BLUE"]="$BG_BLUE"
   ["BG_MAGENTA"]="$BG_MAGENTA"
   ["BG_CYAN"]="$BG_CYAN"
   ["BG_WHITE"]="$BG_WHITE"
   ["BG_DEFAULT"]="$BG_DEFAULT"
   ["FRAMED"]="$FRAMED"
   ["ENCIRCLED"]="$ENCIRCLED"
   ["OVERLINED"]="$OVERLINED"
   ["FRAMED_OFF"]="$FRAMED_OFF"
   ["OVERLINED_OFF"]="$OVERLINED_OFF"
   # Shorthands
   ["BLACK"]="$BLACK"
   ["RED"]="$RED"
   ["GREEN"]="$GREEN"
   ["YELLOW"]="$YELLOW"
   ["BLUE"]="$BLUE"
   ["MAGENTA"]="$MAGENTA"
   ["CYAN"]="$CYAN"
   ["WHITE"]="$WHITE"
   ["DEFAULT"]="$DEFAULT"
)
# Add lowercase keys
for key in "${!ANSI[@]}"; do
   ANSI["${key,,}"]="${ANSI[$key]}"
done

BEEP=$'\a'
export BEEP
unset key
