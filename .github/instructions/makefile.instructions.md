---
description: "Use when editing the Makefile — covers GNU make syntax, recipe conventions, variable patterns, and compatibility constraints for this project."
applyTo: "**/Makefile"
---
# Makefile Conventions

## Indentation & Syntax

- **Tabs only** for recipe indentation — spaces silently break make
- Use `?=` for user-configurable variables (overridable via CLI or env)
- Use `=` (recursive) or `:=` (simple) for computed/internal variables

## GNU Make Features

Requires GNU make — uses `$(eval)`, `$(foreach)`, `$(call)`, `$(if $(findstring ...))`.

- **macOS ships GNU Make 3.81** (2006) — avoid `${var%%.*}` shell parameter expansion inside `$(shell ...)`; it causes parse errors. Use `awk` instead.
- `$(shell)` runs `/bin/sh` — on Alpine that's busybox `ash`, on GitHub Actions it's `dash`. Both stricter than bash.

## Recipe Shell Commands

- **Strictly POSIX `sh`** — no bashisms (`[[`, `${var%%pat}`, arrays, `local`, `source`)
- Prefer `wget` over `curl` (available in Alpine busybox)
- Multi-line recipes: use `; \` continuation with `@set -e;` at the start for error handling

## Critical Escaping Hazard: `$$(( ))` in Recipes

In Makefile recipes, `$$` escapes to a literal `$` for the shell. This means `$$(( expr ))` becomes `$(( expr ))` — arithmetic expansion — which **dash rejects** with "Missing '))'".  This caused a real CI failure.

- **Never write `$$(( ... ))` in a recipe** — dash parses it as arithmetic expansion
- Wrap subshell pipelines as `$$( ( cmd ) )` — the space after `(` makes it unambiguously command substitution containing a subshell
- Example: `_digest=$$( ( shasum -a 256 file 2>/dev/null || sha256sum file ) | cut -d' ' -f1)`

## Version Resolution

- `channel_ver` fetches from `upgrade.mikrotik.com` with retry logic (5 attempts, 2s delay)
- `ver_ge` does major.minor comparison via awk — avoids shell expansion issues on Make 3.81

## Shortcut Targets

`arm64`, `testing`, etc. use recursive `$(MAKE)` re-invocation. Adding a new architecture or channel requires updating both the `.PHONY` declaration and the corresponding target rule.

## File Targets

`$(DLDIR)/routeros-$(VER)-$(ARCH).npk` and similar are Make file targets — only downloaded when the file doesn't exist. `touch $@` after extraction ensures the timestamp is current.
