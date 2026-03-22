# GitHub Copilot Instructions

## Project: MikroTik netinstall automation

A `Makefile` + `Dockerfile` wrapper around MikroTik's `netinstall-cli` binary for automated RouterOS device flashing. Used either directly on Linux/macOS or as a MikroTik RouterOS `/container`.

**This is a Makefile-based project — not Node.js/Bun/npm.** Core tools: GNU `make`, `wget`, `unzip`, and standard POSIX utilities. Image building adds `crane`. The `routeros-setup.sh` script uses `curl` and `jq`. On macOS, all are available via `brew`.

GitHub repo: `tikoci/netinstall` — DockerHub: `ammo74/netinstall` — License: CC0 1.0 (public domain).

**Model preference**: Anthropic Claude Sonnet 4.6 (or Opus 4.6 for complex tasks).

## Core Architecture

- **`Makefile`** — all logic lives here: downloads `netinstall-cli` (x86 binary from MikroTik), downloads RouterOS `.npk` packages for the target architecture, invokes `netinstall-cli` with constructed args. OCI images are also built here via `make image` using `crane` (no Docker required).
- **`Dockerfile`** — Alpine Linux + `make` + `qemu-i386-static` (copied from Debian build stage). Kept for compatibility with users who prefer `docker build`; CI and primary builds use `make image` (crane).
- **`routeros-setup.sh`** — shell script that provisions the full netinstall container stack on a RouterOS device via REST API. Requires `curl`, `jq`, and RouterOS 7.22+.

QEMU is needed because `netinstall-cli` is an i386-only binary; it's skipped automatically on x86_64 hosts via `uname -m` check in Makefile.

## Key Variables

All use `?=` (overridable via CLI args or env vars):

| Variable | Default | Notes |
|---|---|---|
| `ARCH` | `arm` | `arm`, `arm64`, `mipsbe`, `mmips`, `smips`, `ppc`, `tile`, `x86`. Space-separated for multi-arch. |
| `PKGS` | `wifi-qcom-ac` | Extra packages, space-separated, no version/arch suffix. `routeros-*.npk` always prepended. |
| `CHANNEL` | `stable` | `stable`, `testing`, `long-term`, `development` |
| `VER` / `VER_NETINSTALL` | *(from CHANNEL)* | Pin versions independently (format: `7.14.3`, `7.15rc2`) |
| `OPTS` | `-b -r` | Raw flags for `netinstall-cli`; `-r`=reset config, `-e`=empty config, `-b`=strip branding |
| `IFACE` | `eth0` | Interface for `-i` mode. In containers, set to VETH name (RouterOS 7.21+). |
| `CLIENTIP` | *(unset)* | If set, uses `-a <CLIENTIP>` mode instead of `-i <IFACE>` |
| `NET_OPTS` | *(computed)* | Overrides both IFACE and CLIENTIP; set directly if needed (e.g. `NET_OPTS=-i en4`) |
| `MODESCRIPT` | *(auto-set)* | First-boot script via `-sm`. Auto-set when PKGS includes `container` or `zerotier` and VER_NETINSTALL >= 7.22. |
| `PKGS_CUSTOM` | *(empty)* | Full paths to custom/branding packages; appended verbatim to netinstall command |
| `QEMU` | *(auto-detected)* | Path to `qemu-i386` binary. Auto-detects `./i386` (container), `qemu-i386-static`, or `qemu-i386`. Skipped on x86_64. |
| `DLDIR` | `downloads` | Directory for downloaded packages and netinstall binary |
| `IMAGE` | `tikoci/netinstall` | OCI image name for `make image` / `make image-push`. CI overrides for DockerHub/GHCR. |
| `IMAGE_PLATFORMS` | `linux/arm64 linux/arm/v7 linux/amd64` | Platforms built by `make image` |

## `netinstall-cli` Command Syntax

```text
netinstall-cli [-r|-e] [-b] [-m [-o]] [-f] [-v] [-c] [--mac <mac>]
               [-k <keyfile>] [-s <userscript>] [-sm <modescript>]
               {-i <interface> | -a <client-ip>} routeros-VER-ARCH.npk [extra.npk...]
```

- System package (`routeros-*.npk`) **must be first** in the package list
- Multiple architecture `.npk` files can be provided; tool auto-detects device arch
- Requires `sudo` (uses privileged BOOTP port 68 and TFTP port 69)

## Make Targets

- `make` / `make run` — run netinstall once
- `make service` — run in a loop (container entrypoint)
- `make download` — download packages only, don't run
- `make clean` — delete all `.npk`, `.zip`, netinstall binary, images
- `make dump` — print computed ARCH/VER/CHANNEL/PLATFORM/OS/QEMU/MODESCRIPT
- `make nothing` — infinite sleep (keep container alive for shell access)
- `make image` — build OCI images for all platforms (requires `crane`)
- `make image-platform IMAGE_PLATFORM=linux/arm64` — build for single platform
- `make image-push` — push to registry
- Architecture shortcuts: `make arm64`, `make mipsbe`, etc.
- Channel shortcuts: `make stable`, `make testing`, `make long-term`, `make development`
- Combined: `sudo make testing arm64 PKGS="container wifi-qcom"`

## OCI Image Building

`make image` builds container images without Docker, using `crane` to export base layers. Single-layer Docker v1 tar format — required by RouterOS's container loader (**no gzip compression**, **single layer only**).

Architecture mapping (RouterOS → Docker platform): `arm`→`linux/arm/v7`, `arm64`→`linux/arm64`, `x86`→`linux/amd64`

## `routeros-setup.sh` — Container Provisioning

Automates the full netinstall container stack on a RouterOS device via REST API: creates VETH, bridge, environment variables, builds image, uploads via SCP, creates container.

Requires RouterOS 7.22+ (uses 7.22+ REST API property names). Key REST API notes:
- HTTP verbs: PUT = create, PATCH = update, POST = command, DELETE = remove
- Container status: use `.running` field (`"true"`/`"false"` as strings)
- Container delete must fully stop first; poll `.running` and retry

## Planned Future Work (design awareness, do not implement)

1. **Local use on aarch64 Linux** (partially done): Makefile auto-detects `qemu-i386` from system packages. macOS cannot run `netinstall-cli` natively (Linux ELF binary) — requires container approach.
2. **Post-install orchestration**: After `netinstall-cli` completes, PoE switch port cycling for `/system/device-mode`. MODESCRIPT handles first-boot config; missing piece is PoE cycling.
3. **Cross-platform Makefile**: GNU make required. POSIX shell portability in recipes — `dash` (GitHub Actions) and busybox `ash` (Alpine) are the strictest targets.

## RouterOS `/container` Integration

The container reads config from `/container/envs` (7.22+ CLI syntax):
```routeros
/container envs add key=ARCH     list=NETINSTALL value=arm64
/container envs add key=PKGS     list=NETINSTALL value="container wifi-qcom"
/container envs add key=CHANNEL  list=NETINSTALL value=stable
/container envs add key=OPTS     list=NETINSTALL value="-b -r"
/container envs add key=IFACE    list=NETINSTALL value=veth-netinstall
```

Note: env list field name changed in RouterOS 7.22 — pre-7.22 CLI used `name=`, 7.22+ and REST API use `list=`.

Images on DockerHub: `ammo74/netinstall:latest`
GHCR: `ghcr.io/tikoci/netinstall`

## GNU Make Compatibility

- **macOS ships GNU Make 3.81** (2006). Shell parameter expansion (`${var%%.*}`) inside `$(shell ...)` causes parse errors — use `awk` instead.
- `$(shell)` runs `/bin/sh` — on Alpine that's busybox `ash`, on GitHub Actions it's `dash`. Both stricter than bash.
- DNS may not be ready at container startup. `channel_ver` has retry logic (5 attempts, 2s delay).
