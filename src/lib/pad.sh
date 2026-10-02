#!/usr/bin/env bash

pad_lib_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if ! declare -F strip_ansi_into >/dev/null; then
   # shellcheck source=ansi.sh
   source "$pad_lib_dir/ansi.sh"
fi
unset pad_lib_dir

# The *_into forms store the padded string in the variable named by their first argument; see ansi.sh.

_pad_validate() {
   local length="$1"
   local char="$2"
   local -i char_length=0

   if [[ ! "$length" =~ ^[0-9]+$ ]]; then
      printf 'Padding length must be a non-negative integer: %s\n' "$length" >&2
      return 2
   fi
   [[ -n "$char" ]] && stripped_length_into char_length "$char"
   if ((char_length != 1)); then
      printf 'Padding character must have a visible width of one.\n' >&2
      return 2
   fi
}

# Store count copies of char in the named variable; nothing when count is not positive.
_pad_repeat_into() {
   local _prp_padding=""

   if (($3 > 0)); then
      printf -v _prp_padding '%*s' "$3" ''
      _prp_padding=${_prp_padding// /"$2"}
   fi
   printf -v "$1" '%s' "$_prp_padding"
}

# Pad a string on the right to a visible width.
pad_right_into() {
   local _pri_string="${2-}"
   local _pri_length="${3-}"
   local _pri_char="${4:- }"
   local _pri_padding
   local -i _pri_visible

   _pad_validate "$_pri_length" "$_pri_char" || return
   stripped_length_into _pri_visible "$_pri_string"
   _pad_repeat_into _pri_padding "$_pri_char" $((_pri_length - _pri_visible))
   printf -v "$1" '%s%s' "$_pri_string" "$_pri_padding"
}
pad_right() {
   local padded
   pad_right_into padded "$@" || return
   printf '%s' "$padded"
}
padr() { pad_right "$@"; }

# Pad a string on the left to a visible width.
pad_left_into() {
   local _pli_string="${2-}"
   local _pli_length="${3-}"
   local _pli_char="${4:- }"
   local _pli_padding
   local -i _pli_visible

   _pad_validate "$_pli_length" "$_pli_char" || return
   stripped_length_into _pli_visible "$_pli_string"
   _pad_repeat_into _pli_padding "$_pli_char" $((_pli_length - _pli_visible))
   printf -v "$1" '%s%s' "$_pli_padding" "$_pli_string"
}
pad_left() {
   local padded
   pad_left_into padded "$@" || return
   printf '%s' "$padded"
}
padl() { pad_left "$@"; }

# Pad between two strings to a combined visible width.
pad_center_into() {
   local _pci_left="${2-}"
   local _pci_right="${3-}"
   local _pci_length="${4-}"
   local _pci_char="${5:- }"
   local _pci_padding
   local -i _pci_left_visible _pci_right_visible

   _pad_validate "$_pci_length" "$_pci_char" || return
   stripped_length_into _pci_left_visible "$_pci_left"
   stripped_length_into _pci_right_visible "$_pci_right"
   _pad_repeat_into _pci_padding "$_pci_char" $((_pci_length - _pci_left_visible - _pci_right_visible))
   printf -v "$1" '%s%s%s' "$_pci_left" "$_pci_padding" "$_pci_right"
}
pad_center() {
   local padded
   pad_center_into padded "$@" || return
   printf '%s' "$padded"
}
padc() { pad_center "$@"; }

# Pad a string evenly on both sides to a visible width.
pad_sides_into() {
   local _psi_string="${2-}"
   local _psi_length="${3-}"
   local _psi_char="${4:- }"
   local _psi_left _psi_right
   local -i _psi_visible _psi_pad_length

   _pad_validate "$_psi_length" "$_psi_char" || return
   stripped_length_into _psi_visible "$_psi_string"
   _psi_pad_length=$((_psi_length - _psi_visible))
   _pad_repeat_into _psi_left "$_psi_char" $((_psi_pad_length / 2))
   _pad_repeat_into _psi_right "$_psi_char" $((_psi_pad_length - _psi_pad_length / 2))
   printf -v "$1" '%s%s%s' "$_psi_left" "$_psi_string" "$_psi_right"
}
pad_sides() {
   local padded
   pad_sides_into padded "$@" || return
   printf '%s' "$padded"
}
pads() { pad_sides "$@"; }
