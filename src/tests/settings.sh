#!/bin/bash

source "../lib/ansi.sh"
source "../lib/test.sh"
source "../lib/settings.sh"

# Test settings_save_to_file
test_print_name "Saving settings to file"        # Print the test name
settings["foo"]="bar"                            # Set a setting
settings_save_to_file "settings.txt" &>/dev/null # Save the settings to a file
test -f "settings.txt"                           # Check if the file exists
result=$?                                        # Store the result of the test
test_print_result "$result"                      # Print the test result
if [ "$result" -ne 0 ]; then
   # Clean up and exit
   rm "settings.txt"
   exit 1
fi

# Test settings_load_from_file
test_print_name "Loading settings from file"       # Print the test name
declare -A settings                                # Reset the settings array
settings_load_from_file "settings.txt" &>/dev/null # Load the settings from the file
test "${settings["foo"]}" == "bar"                 # Check if the setting was loaded correctly
result=$?                                          # Store the result of the test
test_print_result "$result"                        # Print the test result
if [ "$result" -ne 0 ]; then
   # Clean up and exit
   rm "settings.txt"
   exit 1
fi

# Clean up and exit
rm "settings.txt"
exit 0
