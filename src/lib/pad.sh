#!/usr/bin/env bash

pad_lib_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if ! declare -F strip_ansi >/dev/null; then
   # shellcheck source=ansi.sh
   source "$pad_lib_dir/ansi.sh"
fi
unset pad_lib_dir

_pad_validate() {
   local length="$1"
   local char="$2"

   if [[ ! "$length" =~ ^[0-9]+$ ]]; then
      printf 'Padding length must be a non-negative integer: %s\n' "$length" >&2
      return 2
   fi
   if [[ -z "$char" ]] || (( $(slen "$char") != 1 )); then
      printf 'Padding character must have a visible width of one.\n' >&2
      return 2
   fi
}

_pad_repeat() {
   local char="$1"
   local count="$2"
   local padding=""
   local -i index

   for ((index = 0; index < count; index++)); do
      padding+="$char"
   done

   printf '%s' "$padding"
}

# Pad a string on the right to a visible width.
pad_right() {
   local string="${1-}"
   local length="${2-}"
   local char="${3:- }"
   local -i pad_length

   _pad_validate "$length" "$char" || return
   pad_length=$((length - $(slen "$string")))

   printf '%s' "$string"
   if ((pad_length > 0)); then
      _pad_repeat "$char" "$pad_length"
   fi
}
padr() { pad_right "$@"; }

# Pad a string on the left to a visible width.
pad_left() {
   local string="${1-}"
   local length="${2-}"
   local char="${3:- }"
   local -i pad_length

   _pad_validate "$length" "$char" || return
   pad_length=$((length - $(slen "$string")))

   if ((pad_length > 0)); then
      _pad_repeat "$char" "$pad_length"
   fi
   printf '%s' "$string"
}
padl() { pad_left "$@"; }

# Pad between two strings to a combined visible width.
pad_center() {
   local string_left="${1-}"
   local string_right="${2-}"
   local length="${3-}"
   local char="${4:- }"
   local -i pad_length

   _pad_validate "$length" "$char" || return
   pad_length=$((length - $(slen "$string_left") - $(slen "$string_right")))

   printf '%s' "$string_left"
   if ((pad_length > 0)); then
      _pad_repeat "$char" "$pad_length"
   fi
   printf '%s' "$string_right"
}
padc() { pad_center "$@"; }

# Pad a string evenly on both sides to a visible width.
pad_sides() {
   local string="${1-}"
   local length="${2-}"
   local char="${3:- }"
   local -i pad_length left_pad_length right_pad_length

   _pad_validate "$length" "$char" || return
   pad_length=$((length - $(slen "$string")))

   if ((pad_length <= 0)); then
      printf '%s' "$string"
      return
   fi

   left_pad_length=$((pad_length / 2))
   right_pad_length=$((pad_length - left_pad_length))
   _pad_repeat "$char" "$left_pad_length"
   printf '%s' "$string"
   _pad_repeat "$char" "$right_pad_length"
}
pads() { pad_sides "$@"; }
