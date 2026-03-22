# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project wraps MikroTik's `netinstall-cli` binary in a `Makefile` to automate RouterOS device flashing. It has two deployment modes:
1. **Standalone Linux/macOS**: run `make` directly with a connected ethernet interface
2. **MikroTik `/container`**: an OCI image (Alpine + `make` + QEMU) runs as a RouterOS container

The entire "application logic" lives in `Makefile`. OCI images are built with `make image` using `crane` (no Docker required), producing a single-layer Docker v1 tar. A traditional `Dockerfile` is also provided as an alternative for users who prefer `docker build`.

**This is a Makefile-based project — not Node.js/Bun/npm.** Ignore any parent-level instructions about defaulting to Bun. Core tools: GNU `make`, `wget`, `unzip`, and standard POSIX utilities. Image building adds `crane`. The `routeros-setup.sh` script uses `curl` and `jq`. On macOS, all are available via `brew`. Future post-install orchestration may use `bun`, but the Makefile core will remain.

GitHub repo: `tikoci/netinstall` — DockerHub image: `ammo74/netinstall` — License: CC0 1.0 (public domain).

## Common Commands

```sh
# Download packages only (no netinstall run); safe without a connected device
make download ARCH=arm64 PKGS="container wifi-qcom"

# Run netinstall once (requires sudo on Linux for privileged BOOTP/TFTP ports)
sudo make ARCH=arm64 PKGS="container wifi-qcom" IFACE=eth0

# Shortcut syntax: channel and arch as positional targets
sudo make testing arm64

# Run as a service loop (container default)
sudo make service

# Pin exact versions
sudo make run ARCH=mipsbe VER=7.14.3 VER_NETINSTALL=7.15rc3 PKGS="iot gps" CLIENTIP=192.168.88.7

# Build OCI images for all platforms (requires crane)
make image

# Build for a single platform
make image-platform IMAGE_PLATFORM=linux/arm64

# Remove all downloads, images, and build artifacts
make clean

# Debug: print computed ARCH/VER/CHANNEL/PLATFORM/OS/QEMU/QEMU_SYSTEM/MODESCRIPT
make dump

# Keep container alive without running netinstall (use for /container/shell access)
make nothing
```

### `routeros-setup.sh` — Automated RouterOS container provisioning

```sh
# Store credentials in system keychain (macOS Keychain / Linux secret-tool)
./routeros-setup.sh credentials -r 192.168.74.1 -P 7080 -S http

# Full setup: creates VETH, bridge, envs, builds+uploads image, creates container
./routeros-setup.sh setup -r 192.168.74.1 -P 7080 -S http -d disk1 -p ether5

# Lifecycle commands
./routeros-setup.sh start  -r 192.168.74.1 -P 7080 -S http
./routeros-setup.sh status -r 192.168.74.1 -P 7080 -S http
./routeros-setup.sh logs   -r 192.168.74.1 -P 7080 -S http
./routeros-setup.sh stop   -r 192.168.74.1 -P 7080 -S http
./routeros-setup.sh remove -r 192.168.74.1 -P 7080 -S http
```

## Makefile Variable Reference

Variables use `?=` (default if not set), so they can be overridden via CLI (`make VAR=val`) or environment variables (useful for `/container/envs`).

| Variable | Default | Purpose |
|---|---|---|
| `ARCH` | `arm` | Target RouterOS architecture(s): `arm`, `arm64`, `mipsbe`, `mmips`, `smips`, `ppc`, `tile`, `x86`. Space-separated for multi-arch. |
| `PKGS` | `wifi-qcom-ac` | Extra packages to install (space-separated, no version/arch suffix). `routeros-*.npk` is always prepended. |
| `CHANNEL` | `stable` | Version channel: `stable`, `testing`, `long-term`, `development`. Auto-fetches version from `upgrade.mikrotik.com`. |
| `VER` | *(from CHANNEL)* | Pin a specific RouterOS version (e.g. `7.14.3`, `7.15rc2`). Overrides CHANNEL for the OS image. |
| `VER_NETINSTALL` | *(from CHANNEL)* | Pin the `netinstall-cli` version independently from `VER`. Newer netinstall can install older ROS. |
| `OPTS` | `-b -r` | Raw flags passed to `netinstall-cli`. Use `-e` instead of `-r` for empty config. See flags below. |
| `IFACE` | `eth0` | Network interface for netinstall (`-i` mode). In containers, set to the VETH name (RouterOS 7.21+ uses VETH name as interface name). On macOS, this is the host interface to bridge to (e.g. `en5`). |
| `CLIENTIP` | *(unset)* | If set, uses `-a <CLIENTIP>` instead of `-i <IFACE>`. |
| `NET_OPTS` | *(computed)* | Overrides both IFACE and CLIENTIP; set directly if needed (e.g. `NET_OPTS=-i en4`). |
| `MODESCRIPT` | *(auto-set if applicable)* | RouterOS script for first boot via `-sm`. Auto-set when PKGS includes `container` or `zerotier` and VER_NETINSTALL >= 7.22. |
| `PKGS_CUSTOM` | *(empty)* | Full container-relative paths to custom/branding packages; appended verbatim to netinstall command. |
| `QEMU` | *(auto-detected)* | Path to `qemu-i386` binary. Auto-detects `./i386` (container), `qemu-i386-static`, or `qemu-i386` from PATH. Skipped on x86_64. |
| `DLDIR` | `downloads` | Directory for downloaded packages and netinstall binary. |
| `IMAGE` | `tikoci/netinstall` | OCI image name/tag for `make image` and `make image-push`. CI overrides to `ammo74/netinstall` for DockerHub. |
| `IMAGE_PLATFORMS` | `linux/arm64 linux/arm/v7 linux/amd64` | Platforms built by `make image`. |
| `QEMU_SYSTEM` | *(auto-detected)* | Path to `qemu-system-x86_64`. Used on macOS for VM-based netinstall. Auto-detected via `command -v`. |
| `VMLINUZ` | `$(DLDIR)/vmlinuz-virt` | Alpine virt kernel for macOS VM. Built from `linux-virt` APK. |
| `VM_INITRAMFS` | `$(DLDIR)/initramfs-netinstall.gz` | Custom initramfs for macOS VM (Alpine rootfs + modules + init). |

## `netinstall-cli` Flags (for `OPTS`)

```
netinstall-cli [-r] [-e] [-b] [-m [-o]] [-f] [-v] [-c]
               [-k <keyfile>] [-s <userscript>] [-sm <modescript>]
               [--mac <mac>] {-i <interface> | -a <client-ip>} [PACKAGES...]
```

| Flag | Meaning |
|---|---|
| `-r` | Reinstall with default config (mutually exclusive with `-e`) |
| `-e` | Reinstall with empty config |
| `-b` | Discard branding package |
| `-m` | Repeat installation (loop same device); `-m -o` = one install per MAC per run |
| `-f` | Ignore storage size constraints |
| `-v` | Verbose output |
| `-c` | Allow concurrent instances on same host |
| `--mac <mac>` | Only serve the device with this MAC address |
| `-k <keyfile>` | Install a license key (.KEY file) |
| `-s <userscript>` | Deploy a default config script |
| `-sm <modescript>` | First-boot script (RouterOS 7.22+); written to `.modescript.rsc` by Makefile |

`PACKAGES` are positional args after flags; **system package (`routeros-*.npk`) must be listed first**. `netinstall-cli` auto-detects device architecture and selects matching packages when multiple architecture `.npk` files are provided.

## Architecture: How the Makefile Works

**Requires GNU make** — uses `$(eval)`, `$(foreach)`, `$(call)`, `$(if $(findstring ...))`. Shell recipe commands must be strictly POSIX `sh` (no bashisms) — Alpine uses busybox `ash`, GitHub Actions uses `dash`, both are stricter than bash.

1. **Version resolution**: `channel_ver` calls `wget` against `https://upgrade.mikrotik.com/routeros/NEWESTa7.<channel>` with retry logic (5 attempts, 2s delay) to handle DNS races at container startup.
2. **Version comparison**: `ver_ge` uses awk for major.minor comparison: `$(shell echo '$(1) $(2)' | awk ...)`. This avoids `${var%%.*}` shell parameter expansion which GNU Make 3.81 (macOS default) can't parse in `$(shell)`.
3. **MODESCRIPT auto-detection**: When PKGS includes `container` or `zerotier` and VER_NETINSTALL >= 7.22, MODESCRIPT defaults to `/system/device-mode update mode=advanced container=yes zerotier=yes`. The Makefile writes this to `.modescript.rsc` and passes `-sm .modescript.rsc`.
4. **File targets**: `$(DLDIR)/routeros-$(VER)-$(ARCH).npk`, `$(DLDIR)/netinstall-cli-$(VER_NETINSTALL)`, and `$(DLDIR)/all_packages-$(ARCH)-$(VER).zip` are Make file targets — only downloaded if the files don't exist.
5. **QEMU detection**: `PLATFORM=$(shell uname -m)` and `OS=$(shell uname -s)`. On x86_64 Linux, QEMU is skipped. On non-x86_64 Linux, `find_qemu` probes `./i386` (container), `qemu-i386-static` (Debian/Ubuntu), then `qemu-i386` (Alpine/Fedora) via `command -v`. On macOS (Darwin), the `run` and `service` targets use `ifeq ($(OS),Darwin)` to delegate to `vm-run`, which boots a QEMU system VM with vmnet-bridged networking (see VM section below).
6. **Run target**: filters `PKGS_FILES` to only existing files (skips missing packages rather than erroring), then builds the full `netinstall-cli` command.
7. **Service target**: wraps `run` in a `while :; do ... done` shell loop. **Note**: VER is resolved once at start and passed explicitly in the loop — the version will NOT auto-update while looping.
8. **Shortcut targets** (`arm64`, `testing`, etc.): work via recursive `$(MAKE)` re-invocation with overridden ARCH or CHANNEL. Adding a new architecture or channel requires updating both the `.PHONY` declaration and the corresponding pattern rule.

## OCI Image Building (crane-based)

`make image` builds OCI container images without Docker, using `crane` to export base layers. The `image-platform` target builds a single-platform image:

1. **Alpine rootfs**: `crane export --platform <plat> alpine:latest` extracts the filesystem. Busybox applet symlinks must be created manually from `etc/busybox-paths.d/busybox` — `crane export` does not create them.
2. **make APK**: Downloads the `make` package from Alpine's APKINDEX, extracts `usr/bin/make`.
3. **qemu-i386**: On ARM/ARM64 platforms, extracts `usr/bin/qemu-i386` from the `tonistiigi/binfmt` image (note: the binary name is `qemu-i386`, not `qemu-i386-static`).
4. **Single-layer tar**: Everything is packed into one `layer.tar` with a plain `config.json` and `manifest.json` (Docker v1 format). RouterOS's container loader requires this format — **no gzip compression**, **single layer only**.

The Dockerfile is still available as an alternative (`docker buildx build`), using a Debian stage to get `qemu-i386-static`.

Architecture mapping (RouterOS → Docker platform):
- `arm` → `linux/arm/v7`
- `arm64` → `linux/arm64`
- `x86` → `linux/amd64`

## `routeros-setup.sh` — Container Provisioning

Shell script that provisions the full netinstall container stack on a RouterOS device via REST API. Requires `curl`, `jq`, and **RouterOS 7.22+** (uses 7.22+ REST API property names). The Makefile and container images themselves work on any RouterOS version that supports `/container`. Creates VETH, bridge, bridge ports, firewall list member, env vars, and container.

Key behaviors:
- **Image handling**: Checks for pre-built image in `images/`, builds with `make image-platform` if crane is available, otherwise errors with suggestion to run `make image`.
- **Architecture detection**: Queries `/system/resource` via REST to get `architecture-name`, maps to Docker platform string.
- **Upload**: Uses SCP (`sshpass` for non-interactive, falls back to interactive prompt).
- **Container creation**: Uses `file=` property (local tar) instead of `remote-image=` (Docker pull).
- **Credential storage**: macOS Keychain (`security`) or Linux `secret-tool`. Service name: `routeros://HOST`.
- **Container lifecycle**: Stop polls `.running` field (not `.stopped`); delete retries up to 5 times with 3s waits.

## RouterOS REST API Gotchas

The REST API (`/rest/` prefix) has several differences from CLI syntax that trip up scripts:

- **HTTP verbs**: PUT = create new resource, PATCH = update existing, POST = run command, DELETE = remove
- **Property names differ from CLI (pre-7.22)**:
  - Container `envlists` (REST/7.22+ CLI) vs `envlist` (pre-7.22 CLI) — note the trailing `s`
  - Env list `list` (REST/7.22+ CLI) vs `name` (pre-7.22 CLI) — the field that names the env list
  - RouterOS 7.22 unified most REST and CLI property names; `routeros-setup.sh` requires 7.22+
- **Container status**: Use `.running` field (`"true"`/`"false"` as strings). There is no `.stopped` field.
- **RouterOS 7.21+**: Container interface names match the VETH name. Set `IFACE` env var to the VETH name (e.g., `veth-netinstall`).
- **Container delete**: Must fully stop first. A delete while still stopping returns HTTP 400. Poll `.running` and retry.
- **Auto-detection**: Scheme (http/https) and port can be probed by trying common endpoints.

## `examples/builder/`

Contains Dockerfiles and scripts for building custom OCI images with pre-downloaded packages. Key detail: `build.sh` maps RouterOS architectures to Docker platform strings (same mapping as above).

## macOS VM Support (QEMU system emulation)

`netinstall-cli` is a Linux x86 ELF binary — it cannot run natively on macOS. On macOS, `make run` and `make service` automatically boot a lightweight QEMU system VM with vmnet-bridged networking. This is transparent: the same `make` commands work on Linux and macOS.

**How it works:**
1. `ifeq ($(OS),Darwin)` in the `run`/`service` targets delegates to `vm-run`
2. First run builds `$(VMLINUZ)` and `$(VM_INITRAMFS)` from the Alpine `linux-virt` APK and amd64 OCI image — cached in `$(DLDIR)`
3. QEMU boots with `-netdev vmnet-bridged,ifname=$(IFACE)` bridging to the macOS interface
4. Inside the VM, the host working directory is mounted via 9p (`virtfs`) at `/host`
5. A `.vm-cmd.sh` script runs `make run` (or `make service`) inside the VM with `IFACE=eth0` and all other variables forwarded
6. Inside the VM, `netinstall-cli` runs natively on x86_64 Linux — no user-mode QEMU needed

**Requirements:** `brew install qemu` (provides `qemu-system-x86_64`), `crane` (for initial OCI image build), `sudo` (for vmnet-bridged)

**Key variables:**
- `IFACE` — on macOS, this is the macOS interface to bridge to (e.g. `en5`), not the VM's internal interface
- `QEMU_SYSTEM` — auto-detected via `command -v qemu-system-x86_64`; override with path if needed
- `VM_TARGET` — internal, set by `run`/`service` delegation (`run` or `service`)

**VM build (one-time, cached):**
- Downloads `linux-virt` APK from Alpine mirror — single source for matched kernel + modules
- Extracts `vmlinuz-virt` → `$(DLDIR)/vmlinuz-virt`
- Builds initramfs from: OCI image rootfs (Alpine + make + busybox) + kernel modules from APK
- Modules extracted: `virtio`, `virtio_ring`, `virtio_pci`, `failover`, `net_failover`, `virtio_net`, `netfs`, `9pnet`, `9pnet_virtio`, `9p`
- Modules are decompressed (`.ko.gz` → `.ko`) at build time for busybox `insmod` compatibility

**Initramfs init script:** mounts proc/sys/dev, loads kernel modules via `insmod` (explicit load order, not modprobe — modules aren't in modules.dep), mounts host dir via 9p, assigns link-local IP (169.254.1.1/16) to eth0, then `exec sh /host/.vm-cmd.sh`. Minimal — no OpenRC, no login, just the netinstall command.

**Key lessons learned during development:**
- Alpine virt kernel has almost nothing built-in — virtio, 9p, IDE all modules
- Alpine's `initramfs-virt` (netboot) only includes essential boot modules, NOT 9p
- Netboot `vmlinuz-virt` version lags behind the `linux-virt` APK — version mismatch breaks module loading. Solution: get both kernel and modules from the same APK.
- `virtio_net` depends on `net_failover` → `failover` (not obvious)
- `netinstall-cli` requires an IPv4 address on the interface even though it does its own BOOTP/TFTP
- Alpine container images use merged-usr (`/lib` → `/usr/lib` symlink) which breaks cpio overlay of `/lib/modules/` from a traditional initramfs — embed modules directly instead

## Planned Future Work (do not implement yet, but consider in design)

- **Post-install automation**: After `netinstall-cli` completes, additional steps like setting `/system/device-mode` (requires a physical power cycle — meaning PoE switch port control: disable port, wait, re-enable) are planned. This layer may use `bun` to orchestrate RouterOS API calls and switch control. MODESCRIPT handles the first-boot config portion; the missing piece is PoE cycling.
- **Makefile cross-platform**: GNU make is required and assumed. Shell recipe commands must stay strictly POSIX `sh` — no bashisms. GitHub Actions runners use `dash` as `/bin/sh`, which is stricter than bash and will catch violations. Alpine's `/bin/sh` (busybox ash) is similarly strict.

## CI/CD

- `build-on-commit.yaml`: Manual dispatch only. Uses `crane` (installed via `go install`) to build multi-platform images with `make image`. Pushes to DockerHub (`ammo74/netinstall`) and GHCR (`ghcr.io/tikoci/netinstall`) — note the CI explicitly overrides `IMAGE=` for each registry, so the Makefile default (`tikoci/netinstall`) doesn't affect CI pushes.
- `repo-as-web.yaml`: Triggers on push to `master`. Deploys repo to GitHub Pages and updates DockerHub description from `README.md`.

## MikroTik `/container` Quick Reference

Key environment variables for RouterOS `/container/envs` (7.22+ CLI syntax):

```routeros
/container envs add key=ARCH     list=NETINSTALL value=arm64
/container envs add key=PKGS     list=NETINSTALL value="container wifi-qcom"
/container envs add key=CHANNEL  list=NETINSTALL value=stable
/container envs add key=OPTS     list=NETINSTALL value="-b -r"
/container envs add key=IFACE    list=NETINSTALL value=veth-netinstall
```
Note: The env list field name changed in RouterOS 7.22 — pre-7.22 CLI used `name=`, 7.22+ CLI and REST API both use `list=`.

Start: `/container/start [find tag~"netinstall"]`

## GNU Make Compatibility Notes

- **macOS ships GNU Make 3.81** (2006). Complex shell parameter expansion (`${var%%.*}`, `${var#prefix}`) inside `$(shell ...)` causes parse errors. Use `awk` instead.
- **`$(shell)` runs `/bin/sh`** — on Alpine that's busybox `ash`, on GitHub Actions it's `dash`. Both are stricter than bash.
- **DNS may not be ready** at container startup. Any `$(shell wget ...)` called during Makefile parsing (like `channel_ver`) needs retry logic.
