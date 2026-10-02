# MyTool v2 - Redesigned Menu System

A complete ground-up rewrite of the menu system with modern architecture, optimized rendering, and enhanced user experience.

## Key Features

### 🎯 **No More Exit/Back Buttons**
- Footer-based hotkeys: `Ctrl+C` to exit, `Ctrl+B` to go back
- Custom keybinds for quick navigation (`j/k`, arrows, letters)
- Clean interface without cluttered navigation options

### ⚡ **Optimized Rendering**
- Incremental updates - only redraws changed elements
- Smart scrolling with configurable margins
- Efficient terminal handling with proper cleanup

### 🏗️ **Modular Architecture**
- **Separation of Concerns**: Definition, State, Rendering, Input
- **Component-based**: Easy to extend and maintain
- **Recursive Menus**: Clean nested menu definitions

### 🎨 **Modern Interface**
- Unicode box drawing with multiple styles (light, heavy, simple)
- Configurable appearance and behavior
- Responsive sizing based on terminal dimensions

## Architecture

```
src/v2/
├── core/                   # Core menu engine
│   ├── menu_def.sh        # Menu definition system
│   ├── menu_state.sh      # State management & navigation
│   ├── menu_render.sh     # Rendering engine
│   ├── menu_input.sh      # Input handling & keybinds
│   └── menu_engine.sh     # Main coordinator
├── menus/                  # Menu definitions
│   ├── main_menu.sh       # Application main menu
│   └── reverse_proxy_menu.sh # RPM integration
├── utils/                  # Utilities
│   └── box_drawing.sh     # Unicode box drawing
└── test_menu.sh           # Test suite
```

## Usage

### Running the New System
```bash
./src/mytool_v2
```

### Creating a Menu
```bash
# Define a menu
my_menu() {
    local -a options=(
        "$(menu_option "Option 1" "my_action_1" "1")"
        "$(menu_option "Submenu" "menu_call my_submenu" "s")"
        "$(menu_option "Exit" "exit 0" "q")"
    )
    
    menu_define "My Menu" options
}

# Start the menu system
menu_start my_menu
```

### Navigation
- **Arrow Keys** / **j/k**: Navigate up/down
- **Enter** / **Space**: Select option
- **Letter Keys**: Quick select (if defined)
- **Ctrl+C** / **q**: Exit application
- **Ctrl+B** / **b**: Go back in menu stack
- **Home/End** / **g/G**: First/last option
- **Page Up/Down** / **u/d**: Page navigation

## Configuration

```bash
# Configure appearance
menu_configure "border_style" "heavy"    # light, heavy, simple
menu_configure "max_width" "70"
menu_configure "max_height" "20"
menu_configure "scroll_margin" "3"

# Start with custom settings
menu_start my_root_menu
```

## Integration

The v2 system integrates seamlessly with existing tools:

- **Reverse Proxy Manager**: Full integration with enhanced UX
- **Settings System**: Compatible with existing configuration
- **ANSI Colors**: Uses the same color scheme
- **Legacy Functions**: Can call existing utility functions

## Testing

Run the comprehensive test suite:
```bash
./src/v2/test_menu.sh
```

Tests cover:
- Syntax validation
- Component loading
- Menu definition
- Box drawing styles
- State management
- Integration functionality

## Comparison: v1 vs v2

| Feature | v1 (Old) | v2 (New) |
|---------|----------|----------|
| Architecture | Monolithic (405 lines) | Modular (8 components) |
| Navigation | Exit/Back buttons | Footer hotkeys |
| Rendering | Full redraws | Incremental updates |
| Menu Definition | Imperative arrays | Declarative functions |
| Scrolling | Basic | Optimized with margins |
| Keybinds | Limited | Fully customizable |
| Styling | Fixed | Configurable |
| Testing | None | Comprehensive suite |

## Benefits

1. **Maintainability**: Clear separation of concerns makes code easier to understand and modify
2. **Performance**: Optimized rendering reduces flicker and improves responsiveness
3. **User Experience**: Custom keybinds and footer hints provide a cleaner, more intuitive interface
4. **Extensibility**: Modular design makes it easy to add new features and menu types
5. **Reliability**: Comprehensive testing ensures stability and correctness

## Migration

The v2 system is designed to coexist with the v1 system:
- Run `./src/mytool` for the old system
- Run `./src/mytool_v2` for the new system
- Gradually migrate menu definitions to the new API
- Legacy functions can be called from v2 menus

## Future Enhancements

- Animation support for menu transitions
- Theme system with color customization
- Multi-column menu layouts
- Search/filter functionality
- Menu state persistence
- Accessibility improvements