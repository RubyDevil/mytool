#!/bin/bash
# Shared utility functions

wait_for_key() {
  echo
  echo -e "${DIM:-}Press any key to continue...${RESET:-}"
  # -s silent, -n1 single char
  read -sn1
}

require_root() {
   if [ "$EUID" -ne 0 ]; then
      echo -e "${RED:-}This script must be run as root.${RESET:-}" >&2
      exit 1
   fi
}