# mytool

`mytool` is an interactive Bash utility for administering virtual private servers. It provides a menu-driven home for server setup, reverse-proxy configuration, and other VPS tasks.

## Requirements

- Bash 4.3 or newer
- A UTF-8 terminal with `tput`

Reverse-proxy tasks additionally require Nginx and systemd, plus permission to write to the
configured Nginx directory and reload Nginx.

Installing MongoDB adds the official MongoDB 9.0 APT repository and requires Ubuntu or Debian on
amd64 (with AVX CPU support) or arm64.

## Run

```bash
bash src/mytool
```

Use the up and down arrow keys to move and Enter to select an item. In multi-select menus,
press Space to toggle items and Enter to execute the selected items from top to bottom.
Press Esc or `q` to go back, or to exit from the main menu. Each menu's footer lists its keys.
Settings are stored in `~/.mytool.conf` by default. Set `MYTOOL_SETTINGS_FILE` before launching
to use another file.

## Install and update

Clone the repository with git, then choose **Update MyTool** in the main menu. It pulls the latest
commits (`git pull --ff-only`), restarts mytool with the new code, and runs each component's
initialization:

- installs a `mytool` command in `/usr/local/bin`, so mytool runs from any directory;
- updates every installed utility script from the scripts repository.

## Utility scripts

Utility scripts are small commands installed into `/usr/local/bin` from your own Git repository.
Set its URL in **Edit settings** under `UTIL_SCRIPTS_REPO` (an `https://` or `git@` URL), then open
**Utility Scripts**:

- **Show Scripts** lists the scripts in a sidebar. Use Up/Down to switch, PgUp/PgDn to scroll the
  documentation, and Enter, `q`, or Esc to go back.
- **Install Scripts** and **Uninstall Scripts** install or remove the selected scripts.
- **Update Scripts** pulls the repository and updates every installed script.

The maintained scripts repository is
[RubyDevil/mytool-utility-scripts](https://github.com/RubyDevil/mytool-utility-scripts); its README
describes the layout and the `install.sh`/`uninstall.sh` hooks. The `util-scripts` directory here is
a copy used by the test suite.

## Test

```bash
bash src/tests/run.sh
```

The test suite does not modify system configuration or reload services.
