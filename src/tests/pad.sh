#!/bin/bash

source "../lib/test.sh"
source "../lib/pad.sh"

# Test the pad_right function
test_print_name "Pad string to the right" # Print the test name
output=$(pad_right "foo" 25 ".")          # Generate the padding
expected="foo......................"      # Define the expected output
test "$output" == "$expected"             # Compare the output with the expected value
result=$?                                 # Store the result of the test
test_print_result "$result"               # Print the test result
if [ "$result" -ne 0 ]; then              # Clean up and exit if the test failed
   exit 1
fi

# Test the pad_left function
test_print_name "Pad string to the left" # Print the test name
output=$(pad_left "foo" 25 ".")          # Generate the padding
expected="......................foo"     # Define the expected output
test "$output" == "$expected"            # Compare the output with the expected value
result=$?                                # Store the result of the test
test_print_result "$result"              # Print the test result
if [ "$result" -ne 0 ]; then             # Clean up and exit if the test failed
   exit 1
fi

# Test the pad_center function
test_print_name "Pad in between two strings" # Print the test name
output=$(pad_center "foo" "bar" 25 ".")      # Generate the padding
expected="foo...................bar"         # Define the expected output
test "$output" == "$expected"                # Compare the output with the expected value
result=$?                                    # Store the result of the test
test_print_result "$result"                  # Print the test result
if [ "$result" -ne 0 ]; then                 # Clean up and exit if the test failed
   exit 1
fi

# Clean up and exit
exit 0
