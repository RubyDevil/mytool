#!/bin/bash

# Pad a string right with a character to a specific length
alias padr="pad_right"
pad_right() {
   local string="$1"
   local length="$2"
   local char="${3:- }" # Default to whitespace
   local pad_length=$((length - ${#string}))
   local padding=$(printf "%0.s${char}" $(seq 1 $pad_length))
   echo -n "${string}${padding}"
}

# Pad a string left with a character to a specific length
alias padl="pad_left"
pad_left() {
   local string="$1"
   local length="$2"
   local char="${3:- }" # Default to whitespace
   local pad_length=$((length - ${#string}))
   local padding=$(printf "%0.s${char}" $(seq 1 $pad_length))
   echo -n "${padding}${string}"
}

# Pad in the center of two strings with a character to a specific length
alias padc="pad_center"
pad_center() {
   local string_left="$1"
   local string_right="$2"
   local length="$3"
   local char="${4:- }" # Default to whitespace
   local pad_length=$((length - ${#string_left} - ${#string_right}))
   local padding=$(printf "%0.s${char}" $(seq 1 $pad_length))
   echo -n "${string_left}${padding}${string_right}"
}
