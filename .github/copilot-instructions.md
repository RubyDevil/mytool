# Project Guidelines

## Scope

- This is a Bash 4.3+ terminal application. Keep changes compatible with Bash 4.3 and a UTF-8 terminal.
- Preserve the current compact, reusable shell style: small focused functions, three-space indentation, quoted expansions, `local` variables, and `printf` instead of `echo -e`.
- Keep shell files and `src/mytool` LF-only as required by `.gitattributes`.

## Architecture

- `src/mytool` is the thin application layer. It owns prompts, user-facing tasks, setting-value validation, menu composition, and `main`.
- `src/lib/ansi.sh` owns ANSI constants, escape stripping, and visible string length.
- `src/lib/pad.sh` owns ANSI-aware padding and the `padr`, `padl`, `padc`, and `pads` aliases.
- `src/lib/settings.sh` owns defaults and safe settings serialization. Settings files are data, never executable shell code.
- `src/lib/menu.sh` owns terminal rendering, navigation, scrolling, cleanup, and typed callback dispatch.
- `src/lib/sidebar.sh` owns the two-pane sidebar viewer (item list plus scrollable content) built on the menu's borders and colors.
- `src/lib/system.sh` owns privileged command execution and atomic privileged file installs.
- `src/core/reverse_proxy.sh` is the canonical reverse-proxy domain module. It owns validation, parsing, rendering, persistence, cache state, Nginx validation/reload, and rollback.
- `src/core/util_scripts.sh` owns the utility-scripts repository sync, install records, `install.sh`/`uninstall.sh` hooks, and rollback. The scripts themselves live in the separate `RubyDevil/mytool-utility-scripts` repository; `util-scripts/` mirrors its layout as the test fixture. When the repository layout contract changes, update `util-scripts/` and that repository's README together.
- `src/core/self_update.sh` owns pulling mytool's own checkout and installing the `mytool` launcher. Post-update initialization hooks are listed in `mytool_post_update_hooks` in `src/mytool` and run by the freshly restarted process.
- `install.sh` at the repository root is the standalone `curl ... | bash` bootstrap. It clones (or pulls) the checkout into `MYTOOL_INSTALL_DIR`, then sources the checkout's `self_update.sh` to install the launcher. It cannot source anything before the clone exists, keeps the `install_main` call at the end so a truncated download runs nothing, and must never read stdin (stdin is the script when piped).
- `src/lib/tools/reverse_proxy.sh` and `src/lib/utils.sh` are legacy merge artifacts. Do not import, extend, or treat them as canonical unless the project explicitly migrates to them and removes the current equivalents with matching tests.
- Tests live in `src/tests`; shared test assertions belong in `src/lib/test.sh`.

## Behavioral Invariants

- Preserve the existing menu appearance and interaction: light/heavy Unicode borders, ANSI colors, centered header, pointer plus inverse selected item, arrow-key navigation, Esc/q back navigation, the key-hint footer, scrolling, wraparound, and reliable cursor/TTY restoration.
- Build menus with `menu_clear` and `menu_add`. Declare the parent menu with `menu_set_back` (`menu_set_exit` for the root menu) instead of adding a Back or Exit item. Store callbacks as function names with separate arguments and invoke them through `menu_invoke`; never construct or evaluate command strings.
- Keep rendering testable without a TTY through `menu_render` and `MENU_HEIGHT`.
- Keep menu and sidebar rendering and keypress navigation free of processes: no `$(...)`, pipelines, `tput`, or external commands, since each fork costs about 1 ms on Linux and much more under Git Bash. Helpers used there return through an `*_into VAR ...` form that assigns with `printf -v` and gives its locals a prefix unique to that function (for example `_pri_` in `pad_right_into`); the printing forms are thin wrappers for other callers. `test_assert_no_processes` enforces this on Linux.
- Resolve paths relative to `${BASH_SOURCE[0]}` so scripts work from any current directory. Source libraries defensively when they may also be used standalone.
- Validate all external input before using it in paths, arithmetic, settings, or Nginx configuration. Quote expansions and use `--` for filesystem operands where supported.
- Never use `eval` or `source` a settings file. Preserve the deterministic escaped `KEY=value` format, private atomic writes, default merging, malformed-line reporting, and read-only compatibility with the legacy array-assignment format.
- Reverse-proxy writes and deletes must remain atomic and transactional. Run `nginx -t` before reload, restore the previous file/state when validation or reload fails, and keep `domains_and_ports` free of stale entries.
- Do not perform real Nginx reloads or write to system Nginx directories in tests; stub `reverse_proxy_reload_nginx` and use temporary directories.
- Do not run privileged commands or write to system paths in tests; stub `system_run_privileged` and point the `UTIL_SCRIPTS_*_DIR`, `SELF_UPDATE_BIN_DIR`, and `MYTOOL_INSTALL_DIR` overrides at temporary directories.
- Keep `src/mytool` safe to source by guarding `main` with `[[ "${BASH_SOURCE[0]}" == "$0" ]]`.

## Change Discipline

- Prefer the existing module and public helper APIs over duplicating logic in the entrypoint.
- Keep compatibility aliases that tests or callers may use unless intentionally removing them with updated coverage.
- Add or update focused tests for every behavior change, especially input validation, ANSI-visible widths, menu navigation/rendering, settings round trips/security, and reverse-proxy rollback.
- Do not weaken security or transaction behavior to simplify implementation.
- Do not introduce external runtime dependencies when Bash or the existing standard Unix tools are sufficient.

## Validation

Run syntax checks for every shell entrypoint and module touched. A repository-wide check is:

```bash
bash -n install.sh src/mytool src/core/*.sh src/lib/*.sh src/lib/tools/*.sh src/tests/*.sh util-scripts/*/*.sh
```

Run the complete suite after code changes:

```bash
bash src/tests/run.sh
```

Also run `git diff --check`. ShellCheck is useful when available, but it is not currently guaranteed in the development environment.
