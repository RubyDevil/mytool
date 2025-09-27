#!/bin/bash
# Test script for the new menu system

script_dir=$(dirname "${BASH_SOURCE[0]}")
cd "$script_dir/../.." || exit 1

echo "Testing MyTool v2 Menu System"
echo "=============================="
echo

# Test 1: Syntax check
echo -n "1. Syntax check... "
if bash -n src/mytool_v2; then
    echo -e "\033[32mPASS\033[0m"
else
    echo -e "\033[31mFAIL\033[0m"
    exit 1
fi

# Test 2: Component loading
echo -n "2. Component loading... "
if bash -c "source src/v2/core/menu_engine.sh" 2>/dev/null; then
    echo -e "\033[32mPASS\033[0m"
else
    echo -e "\033[31mFAIL\033[0m"
    exit 1
fi

# Test 3: Menu definition
echo -n "3. Menu definition... "
if bash -c "
source src/v2/core/menu_engine.sh
source src/v2/menus/main_menu.sh
menu_main
if [[ \"\$MENU_CURRENT_TITLE\" == \"Main Menu\" ]] && (( \$(menu_option_count) > 0 )); then
    exit 0
else
    exit 1
fi
" 2>/dev/null; then
    echo -e "\033[32mPASS\033[0m"
else
    echo -e "\033[31mFAIL\033[0m"
    exit 1
fi

# Test 4: Box drawing styles
echo -n "4. Box drawing styles... "
if bash -c "
source src/v2/utils/box_drawing.sh
box_set_style light
[[ \"\$(box_char h)\" == \"─\" ]] || exit 1
box_set_style heavy
[[ \"\$(box_char h)\" == \"━\" ]] || exit 1
box_set_style simple
[[ \"\$(box_char h)\" == \"-\" ]] || exit 1
" 2>/dev/null; then
    echo -e "\033[32mPASS\033[0m"
else
    echo -e "\033[31mFAIL\033[0m"
    exit 1
fi

# Test 5: State management
echo -n "5. State management... "
if bash -c "
source src/v2/core/menu_def.sh
source src/v2/core/menu_state.sh
# Create a dummy menu for testing
MENU_CURRENT_OPTIONS=('opt1' 'action1' '' 'opt2' 'action2' '' 'opt3' 'action3' '')
menu_state_init
(( MENU_SELECTION == 0 )) || exit 1
menu_update_selection 2
(( MENU_SELECTION == 2 )) || exit 1
" 2>/dev/null; then
    echo -e "\033[32mPASS\033[0m"
else
    echo -e "\033[31mFAIL\033[0m"
    exit 1
fi

# Test 6: Integration with reverse proxy
echo -n "6. Reverse proxy integration... "
if bash -c "
source src/v2/menus/reverse_proxy_menu.sh
menu_reverse_proxy
[[ \"\$MENU_CURRENT_TITLE\" == \"Reverse Proxy Manager\" ]] || exit 1
" 2>/dev/null; then
    echo -e "\033[32mPASS\033[0m"
else
    echo -e "\033[31mFAIL\033[0m"
    exit 1
fi

echo
echo -e "\033[32mAll tests passed!\033[0m"
echo
echo "Key features implemented:"
echo "• Modular architecture with separated concerns"
echo "• Custom keybind system (j/k, arrows, Ctrl+C, Ctrl+B)"
echo "• Optimized rendering with incremental updates"
echo "• Recursive menu definitions"
echo "• Unicode box drawing with multiple styles"
echo "• Integration with existing reverse proxy tools"
echo "• Navigation stack for proper back functionality"
echo "• Configuration system for customization"
echo
echo "Run './src/mytool_v2' to try the new menu system!"