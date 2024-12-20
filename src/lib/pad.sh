#!/bin/bash

# Remove ANSI escape codes from a string
strip_ansi() {
   # Use awk to remove escape sequences
   echo "$1" | awk '{ gsub(/(\\e|\\x1b|\033)\[[0-9;]*m/, ""); print }'
}

# Pad a string right with a character to a specific length
pad_right() {
   local string=$(strip_ansi "$1")
   local length="$2"
   local char="${3:- }" # Default to whitespace
   local pad_length=$((length - ${#string}))
   if ((pad_length <= 0)); then
      echo -n "$string"
      return
   fi
   local padding=$(printf "%0.s${char}" $(seq 1 $pad_length))
   echo -n "${string}${padding}"
}
padr() { pad_right "$@"; }

# Pad a string left with a character to a specific length
padl() { pad_left "$@"; }
pad_left() {
   local string=$(strip_ansi "$1")
   local length="$2"
   local char="${3:- }" # Default to whitespace
   local pad_length=$((length - ${#string}))
   if ((pad_length <= 0)); then
      echo -n "$string"
      return
   fi
   local padding=$(printf "%0.s${char}" $(seq 1 $pad_length))
   echo -n "${padding}${string}"
}

# Pad in the center of two strings with a character to a specific length
padc() { pad_center "$@"; }
pad_center() {
   local string_left=$(strip_ansi "$1")
   local string_right=$(strip_ansi "$2")
   local length="$3"
   local char="${4:- }" # Default to whitespace
   local pad_length=$((length - ${#string_left} - ${#string_right}))
   if ((pad_length <= 0)); then
      echo -n "$string"
      return
   fi
   local padding=$(printf "%0.s${char}" $(seq 1 $pad_length))
   echo -n "${string_left}${padding}${string_right}"
}

# Pad a string on both sides with a character to a specific length
pads() { pad_sides "$@"; }
pad_sides() {
   local string=$(strip_ansi "$1")
   local length="$2"
   local char="${3:- }" # Default to whitespace
   local pad_length=$((length - ${#string}))
   if ((pad_length <= 0)); then
      echo -n "$string"
      return
   fi
   local left_pad_length=$((pad_length / 2))
   local right_pad_length=$((pad_length - left_pad_length))
   local left_padding=$(printf "%0.s${char}" $(seq 1 $left_pad_length))
   local right_padding=$(printf "%0.s${char}" $(seq 1 $right_pad_length))
   echo -n "${left_padding}${string}${right_padding}"
}
