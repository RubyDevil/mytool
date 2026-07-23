# mytool

`mytool` is an interactive Bash utility for administering virtual private servers. It provides a menu-driven home for server setup, reverse-proxy configuration, and other VPS tasks.

## Requirements

- Bash 4.3 or newer
- A UTF-8 terminal with `tput`

Reverse-proxy tasks additionally require Nginx and systemd, plus permission to write to the
configured Nginx directory and reload Nginx.

## Run

```bash
bash src/mytool
```

Use the up and down arrow keys to move and Enter to select an item. In multi-select menus,
press Space to toggle items and Enter to execute the selected items from top to bottom.
Settings are stored in `~/.mytool.conf` by default. Set `MYTOOL_SETTINGS_FILE` before launching
to use another file.

## Test

```bash
bash src/tests/run.sh
```

The test suite does not modify system configuration or reload services.
