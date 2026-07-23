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
- `src/core/reverse_proxy.sh` is the canonical reverse-proxy domain module. It owns validation, parsing, rendering, persistence, cache state, Nginx validation/reload, and rollback.
- `src/lib/tools/reverse_proxy.sh` and `src/lib/utils.sh` are legacy merge artifacts. Do not import, extend, or treat them as canonical unless the project explicitly migrates to them and removes the current equivalents with matching tests.
- Tests live in `src/tests`; shared test assertions belong in `src/lib/test.sh`.

## Behavioral Invariants

- Preserve the existing menu appearance and interaction: light/heavy Unicode borders, ANSI colors, centered header, pointer plus inverse selected item, arrow-key navigation, scrolling, wraparound, and reliable cursor/TTY restoration.
- Build menus with `menu_clear` and `menu_add`. Store callbacks as function names with separate arguments and invoke them through `menu_invoke`; never construct or evaluate command strings.
- Keep rendering testable without a TTY through `menu_render` and `MENU_HEIGHT`.
- Resolve paths relative to `${BASH_SOURCE[0]}` so scripts work from any current directory. Source libraries defensively when they may also be used standalone.
- Validate all external input before using it in paths, arithmetic, settings, or Nginx configuration. Quote expansions and use `--` for filesystem operands where supported.
- Never use `eval` or `source` a settings file. Preserve the deterministic escaped `KEY=value` format, private atomic writes, default merging, malformed-line reporting, and read-only compatibility with the legacy array-assignment format.
- Reverse-proxy writes and deletes must remain atomic and transactional. Run `nginx -t` before reload, restore the previous file/state when validation or reload fails, and keep `domains_and_ports` free of stale entries.
- Do not perform real Nginx reloads or write to system Nginx directories in tests; stub `reverse_proxy_reload_nginx` and use temporary directories.
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
bash -n src/mytool src/core/*.sh src/lib/*.sh src/lib/tools/*.sh src/tests/*.sh
```

Run the complete suite after code changes:

```bash
bash src/tests/run.sh
```

Also run `git diff --check`. ShellCheck is useful when available, but it is not currently guaranteed in the development environment.
