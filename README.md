# mytool

`mytool` is an interactive Bash utility for administering virtual private servers. It provides a menu-driven home for server setup, reverse-proxy configuration, and other VPS tasks.

## Requirements

- Bash 4.3 or newer
- A UTF-8 terminal with `tput`

Reverse-proxy tasks additionally require Nginx and systemd, plus permission to write to the
configured Nginx directory and reload Nginx.

Installing MongoDB adds the official MongoDB 9.0 APT repository and requires Ubuntu or Debian on
amd64 (with AVX CPU support) or arm64.

Installing Tailscale adds the official Tailscale stable APT repository and requires Ubuntu or
Debian. **Setup Tailscale** in Security Setup then runs `tailscale up` (optionally with a machine
name and Tailscale SSH) and prints a login URL to join the server to your tailnet.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/RubyDevil/mytool/main/install.sh | bash
```

The installer clones mytool into `/opt/mytool` and installs a `mytool` command in `/usr/local/bin`.
It uses `sudo` when it is not run as root, and installs git with `apt-get` when git is missing.
To clone somewhere else, set `MYTOOL_INSTALL_DIR` to an absolute path:

```bash
curl -fsSL https://raw.githubusercontent.com/RubyDevil/mytool/main/install.sh | MYTOOL_INSTALL_DIR=/srv/mytool bash
```

Running the installer again pulls the existing checkout and reinstalls the `mytool` command. To
also update installed utility scripts, use **Update MyTool**.

## Run

```bash
mytool
```

From a checkout you have not installed, run `bash src/mytool` instead.

Use the up and down arrow keys to move and Enter to select an item. In multi-select menus,
press Space to toggle items and Enter to execute the selected items from top to bottom.
Press Esc or `q` to go back, or to exit from the main menu. Each menu's footer lists its keys.
Settings are stored in `~/.mytool.conf` by default. Set `MYTOOL_SETTINGS_FILE` before launching
to use another file.

## Update

Choose **Update MyTool** in the main menu. It pulls the latest commits (`git pull --ff-only`) into
the checkout, restarts mytool with the new code, and runs each component's initialization:

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
