---
description: "Use when editing shell scripts (.sh) or Makefile shell recipes — covers POSIX portability, RouterOS REST API patterns, and routeros-setup.sh conventions."
applyTo: "**/*.sh"
---
# Shell Script Conventions

## POSIX Portability

- Target `/bin/sh` — must work under busybox `ash` (Alpine) and `dash` (GitHub Actions)
- No bashisms: no `[[`, no `${var%%pat}`, no arrays, no `local` (use subshells or positional params), no `source` (use `.`)
- Quote variables: `"$var"` not `$var`
- Use `command -v` not `which` for checking executables
- Makefile recipes: prefer `wget` over `curl` (busybox includes wget)
- Standalone scripts (e.g. `routeros-setup.sh`): `curl` is fine — it's a stated dependency

## dash-Specific Gotchas (GitHub Actions `/bin/sh`)

GitHub Actions uses `dash` as `/bin/sh`. dash is stricter than bash in ways that cause subtle failures:

- **`$(( ))` arithmetic trap in recipes**: In Makefile recipes `$$(( ))` escapes to `$(( ))` in the shell — dash rejects this as malformed arithmetic with "Missing '))'". Use `$$( ( cmd ) )` instead (see makefile.instructions.md for detail).
- **No `local`**: dash does not support `local` in functions — use subshells or positional params
- **String comparisons**: use `=` not `==` in `[ ]` tests — dash rejects `==`
- **`echo -e`**: dash's `echo -e` does NOT interpret escapes — use `printf` for escape sequences
- **Here-strings `<<<`**: not supported — use `printf | cmd` or a heredoc
- **Process substitution `<()`**: bash-only, not available in dash
- Test locally with: `shellcheck --shell=dash script.sh`

## `routeros-setup.sh` Specifics

- Requires `curl`, `jq`, and RouterOS 7.22+
- Uses RouterOS REST API (`/rest/` prefix):
  - **PUT** = create new resource
  - **PATCH** = update existing
  - **POST** = run command
  - **DELETE** = remove
- Property names differ from pre-7.22 CLI: `envlists` (not `envlist`), `list` (not `name`) for env list field
- Container `.running` field returns `"true"`/`"false"` as strings — no `.stopped` field exists
- Container delete requires full stop first; poll `.running` and retry (up to 5 times, 3s waits)
- Credential storage: macOS Keychain (`security`) or Linux `secret-tool`; service name pattern: `routeros://HOST`
- SCP upload: `sshpass` for non-interactive, falls back to interactive prompt
