# mytool

`mytool` is an interactive Bash utility for managing local Nginx reverse-proxy configurations.

## Requirements

- Bash 4.3 or newer
- A UTF-8 terminal with `tput`
- Nginx and systemd for applying reverse-proxy changes
- Permission to write to the configured Nginx directory and reload Nginx

## Run

```bash
bash src/mytool
```

Use the up and down arrow keys to move and Enter to select an item. Settings are stored in
`~/.mytool.conf` by default. Set `MYTOOL_SETTINGS_FILE` before launching to use another file.

## Test

```bash
bash src/tests/run.sh
```

The test suite does not modify the system Nginx configuration or reload the service.
