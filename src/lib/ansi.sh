#!/bin/bash

# Remove ANSI escape codes from a string
strip_ansi() {
   # Use awk to remove escape sequences
   echo -n "$1" | awk '{ gsub(/(\\e|\\x1b|\033)\[[0-9;]*m/, ""); print }'
}

# Return the length of a string without ANSI escape codes
slen() { stripped_length "$@"; }
stripped_length() {
   echo -n "$(strip_ansi "$1" | wc -c)"
}

# ANSI escape codes
export RESET="\e[0m"             # Reset all attributes
export BOLD="\e[1m"              # Bold
export DIM="\e[2m"               # Dim
export ITALIC="\e[3m"            # Italic (not widely supported, sometimes treated as inverse or blink)
export UNDERLINE="\e[4m"         # Underline
export BLINK="\e[5m"             # Blink
export RAPID_BLINK="\e[6m"       # Rapid blink
export INVERSE="\e[7m"           # Inverse (swap foreground and background ANSI)
export CONCEAL="\e[8m"           # Conceal (hidden)
export STRIKE="\e[9m"            # Strikethrough
export PRIMARY_FONT="\e[10m"     # Primary (default) font
export ALTERNATE_FONT_1="\e[11m" # First alternate font
export ALTERNATE_FONT_2="\e[12m" # Second alternate font
export ALTERNATE_FONT_3="\e[13m" # Third alternate font
export ALTERNATE_FONT_4="\e[14m" # Fourth alternate font
export ALTERNATE_FONT_5="\e[15m" # Fifth alternate font
export ALTERNATE_FONT_6="\e[16m" # Sixth alternate font
export ALTERNATE_FONT_7="\e[17m" # Seventh alternate font
export ALTERNATE_FONT_8="\e[18m" # Eighth alternate font
export ALTERNATE_FONT_9="\e[19m" # Ninth alternate font
export FRAKTUR="\e[20m"          # Fraktur (hardly ever supported)
export BOLD_OFF="\e[21m"         # Bold off
export NORMAL_COLOR="\e[22m"     # Normal color or intensity (neither bold nor faint)
export ITALIC_OFF="\e[23m"       # Italic off
export UNDERLINE_OFF="\e[24m"    # Underline off
export BLINK_OFF="\e[25m"        # Blink off
export INVERSE_OFF="\e[27m"      # Inverse off
export CONCEAL_OFF="\e[28m"      # Reveal (conceal off)
export STRIKE_OFF="\e[29m"       # Strikethrough off
export FG_BLACK="\e[30m"         # Foreground color black
export FG_RED="\e[31m"           # Foreground color red
export FG_GREEN="\e[32m"         # Foreground color green
export FG_YELLOW="\e[33m"        # Foreground color yellow
export FG_BLUE="\e[34m"          # Foreground color blue
export FG_MAGENTA="\e[35m"       # Foreground color magenta
export FG_CYAN="\e[36m"          # Foreground color cyan
export FG_WHITE="\e[37m"         # Foreground color white
export FG_DEFAULT="\e[39m"       # Foreground color default (usually colored)
export BG_BLACK="\e[40m"         # Background color black
export BG_RED="\e[41m"           # Background color red
export BG_GREEN="\e[42m"         # Background color green
export BG_YELLOW="\e[43m"        # Background color yellow
export BG_BLUE="\e[44m"          # Background color blue
export BG_MAGENTA="\e[45m"       # Background color magenta
export BG_CYAN="\e[46m"          # Background color cyan
export BG_WHITE="\e[47m"         # Background color white
export BG_DEFAULT="\e[49m"       # Background color default (usually colored)
export FRAMED="\e[51m"           # Framed
export ENCIRCLED="\e[52m"        # Encircled
export OVERLINED="\e[53m"        # Overlined
export FRAMED_OFF="\e[54m"       # Framed off
export OVERLINED_OFF="\e[55m"    # Overlined off

# Shorthands
export BLACK="\e[30m"   # Foreground color black
export RED="\e[31m"     # Foreground color red
export GREEN="\e[32m"   # Foreground color green
export YELLOW="\e[33m"  # Foreground color yellow
export BLUE="\e[34m"    # Foreground color blue
export MAGENTA="\e[35m" # Foreground color magenta
export CYAN="\e[36m"    # Foreground color cyan
export WHITE="\e[37m"   # Foreground color white
export DEFAULT="\e[39m" # Foreground color default (usually colored)

# Associative table of ANSI
declare -x -A ANSI=(
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
