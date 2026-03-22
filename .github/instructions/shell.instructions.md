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
