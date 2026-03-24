# MikroTik `netinstall` using `make`

Automates MikroTik device flashing with `netinstall-cli`.  Downloads the right packages for your device's CPU and version channel, then runs `netinstall` — all via `make`.

Works three ways:

- **On macOS** — runs `netinstall` via a lightweight QEMU VM with bridged networking (MikroTik only provides a Linux binary — this project makes it work on Mac)
- **On Linux** — runs `netinstall-cli` directly (or via QEMU user-mode on ARM/ARM64)
- **As a MikroTik `/container`** — an OCI image runs `netinstall` as a service, no PC needed

Source: [tikoci/netinstall](https://github.com/tikoci/netinstall) — DockerHub: [ammo74/netinstall](https://hub.docker.com/r/ammo74/netinstall) — License: CC0 1.0

## Quick Start

### Interactive Wizard

The easiest way to get started — walks you through every option:

```sh
git clone https://github.com/tikoci/netinstall.git
cd netinstall
./mknetinstall
```

The wizard detects your platform, guides you through architecture/package/interface selection, and runs netinstall.  Use `./mknetinstall --help` for CLI flags or `./mknetinstall --dry-run` to preview the command without executing.

Install it to your PATH with `make mknetinstall`.

### Direct `make` Usage

```sh
# Download packages only (no device needed)
make download ARCH=arm64 PKGS="container wifi-qcom"

# Run netinstall once
sudo make run ARCH=arm64 PKGS="container wifi-qcom" IFACE=eth0

# Channel and arch shortcuts
sudo make testing arm64

# Run as a service (loop)
sudo make service ARCH=arm64 IFACE=eth0

# Pin exact versions
sudo make run ARCH=mipsbe VER=7.14.3 PKGS="iot gps" CLIENTIP=192.168.88.7
```

> **WiFi driver packages** vary by device model — use `wifi-qcom` or `wifi-qcom-ac` for Qualcomm-based devices, `wifi-mediatek` for MediaTek, or `wireless` for older legacy chipsets.  Check your device's specifications to pick the right one.  The `mknetinstall` wizard lists all available packages after downloading.

### macOS

MikroTik's `netinstall-cli` is a Linux-only binary.  This project uses a lightweight [QEMU](https://www.qemu.org/) VM with bridged networking so `netinstall` can access your ethernet port directly — no Docker required.  The same `make` commands work on both platforms.

#### Get the project

```sh
# Option A: git clone
git clone https://github.com/tikoci/netinstall.git && cd netinstall

# Option B: download ZIP
curl -L https://github.com/tikoci/netinstall/archive/refs/heads/master.zip -o netinstall.zip
unzip netinstall.zip && cd netinstall-master
```

#### Install prerequisites

```sh
brew install qemu crane make wget
```

See [macOS VM Details](GUIDE.md#macos-vm-details) in the Configuration Guide for what each tool does.

#### Run the interactive wizard

```sh
./mknetinstall
```

The wizard guides you through architecture, package, and interface selection.  See [Interactive Wizard](https://github.com/tikoci/netinstall?tab=readme-ov-file#interactive-wizard) for details.

#### Run netinstall directly

Set `IFACE` to the macOS interface your target device is connected to (e.g., `en5` for a USB ethernet adapter):

```sh
sudo make run ARCH=arm64 PKGS="container wifi-qcom-ac" IFACE=en5
```

> [!IMPORTANT]
>
> **To exit the QEMU VM, press <kbd>Ctrl-A</kbd> then <kbd>X</kbd>** (the QEMU monitor escape sequence).  <kbd>Ctrl-C</kbd> does **not** work — this is intentional, since interrupting `netinstall` mid-flash could leave a device in a bad state.  The VM shuts down automatically after a single `make run` completes.

## RouterOS `/container` Setup

Running `netinstall` as a container lets you flash MikroTik devices **without a PC** — the container bridges its VETH to a physical port and runs `netinstall` via QEMU emulation.

### Prerequisites

- RouterOS device with container support (ARM, ARM64, or x86)
- Non-flash storage (internal drive, USB, ramdisk, NFS/SMB)
- `container.npk` installed and `/system/device-mode` set to enable containers

See [MikroTik's `/container` docs](https://help.mikrotik.com/docs/display/ROS/Container) for prerequisites.

### Automated Setup

`tools/container-manager.sh` handles everything via the RouterOS REST API — creates the VETH, bridge, environment variables, builds and uploads the image, and creates the container.

> [!WARNING]
>
> Requires **RouterOS 7.20+** (REST API `/container/envs` property `name` changed to `list`.

```sh
# Store credentials in system keychain
./tools/container-manager.sh credentials -r 192.168.88.1 -P 7080 -S http

# Provision everything
./tools/container-manager.sh setup -r 192.168.88.1 -P 7080 -S http -d disk1 -p ether5

# Lifecycle
./tools/container-manager.sh start  -r 192.168.88.1 -P 7080 -S http
./tools/container-manager.sh status -r 192.168.88.1 -P 7080 -S http
./tools/container-manager.sh logs   -r 192.168.88.1 -P 7080 -S http
./tools/container-manager.sh stop   -r 192.168.88.1 -P 7080 -S http
./tools/container-manager.sh remove -r 192.168.88.1 -P 7080 -S http
```

Run `./tools/container-manager.sh` without arguments for option summary, or see the [Configuration Guide](GUIDE.md#toolscontainer-managersh-options) for the full reference.

### Manual Setup (RouterOS CLI)

For manual setup or to understand what the automated tool does, see `tools/container-setup.rsc` or the [Configuration Guide](GUIDE.md#manual-container-setup).

### Container Environment Variables

Configure via `/container/envs` (RouterOS 7.20+ syntax):

```routeros
/container envs add key=ARCH    list=NETINSTALL value=arm64
/container envs add key=PKGS    list=NETINSTALL value="container wifi-qcom"
/container envs add key=CHANNEL list=NETINSTALL value=stable
/container envs add key=OPTS    list=NETINSTALL value="-b -r"
/container envs add key=IFACE   list=NETINSTALL value=veth-netinstall
```

> On RouterOS pre-7.20, use `name=NETINSTALL` instead of `list=NETINSTALL`.

## Configuration Variables

All variables use `?=` — override via CLI (`make VAR=val`), environment, or `/container/envs`.

| Variable | Default | Purpose |
|---|---|---|
| `ARCH` | `arm` | Target architecture(s), space-separated: `arm`, `arm64`, `mipsbe`, `mmips`, `smips`, `ppc`, `tile`, `x86` |
| `PKGS` | `wifi-qcom-ac` | Extra packages (space-separated, no version/arch suffix) |
| `CHANNEL` | `stable` | Version channel: `stable`, `testing`, `long-term`, `development` |
| `VER` | *(from CHANNEL)* | Pin a specific RouterOS version (e.g., `7.14.3`) |
| `VER_NETINSTALL` | *(from CHANNEL)* | Pin `netinstall-cli` version independently |
| `OPTS` | `-b -r` | Flags for `netinstall-cli` (`-r` default config, `-e` empty config, `-b` strip branding) |
| `IFACE` | `eth0` | Network interface; set to VETH name in containers, macOS host interface for VM |
| `CLIENTIP` | *(unset)* | Use `-a <IP>` instead of `-i <IFACE>` |
| `MODESCRIPT` | *(auto-set)* | First-boot mode script via `-sm` — see [Controlling `device-mode`](#controlling-device-mode) below |

See the [Configuration Guide](GUIDE.md) for the complete variable reference, `netinstall-cli` flags, and advanced options.

### Controlling `device-mode`

RouterOS uses `/system/device-mode` to control access to advanced features like containers and ZeroTier.  `netinstall-cli` 7.22 added the `-sm` flag, which accepts a RouterOS script that runs once on first boot — before the device is network-accessible.

When **both** `VER` and `VER_NETINSTALL` are 7.22 or newer, the Makefile automatically generates a `MODESCRIPT` that sets `mode=advanced` and conditionally enables `container=yes` and/or `zerotier=yes` based on what's in `PKGS`.  For example, with the default `PKGS=wifi-qcom-ac`:

```routeros
/system/device-mode update mode=advanced
```

With `PKGS="container wifi-qcom-ac"`:

```routeros
/system/device-mode update mode=advanced container=yes
```

When either version is below 7.22, no `-sm` flag is passed.  `MODESCRIPT` accepts any RouterOS script content — set it directly to override the default, or set `MODESCRIPT=` (empty) to disable it entirely.  See the [Configuration Guide](GUIDE.md#first-boot-script) for the full behavior table and examples.

## Building Container Images

OCI images are built with `crane` (no Docker required):

```sh
make image                                    # All platforms
make image-platform IMAGE_PLATFORM=linux/arm64  # Single platform
make image-push IMAGE=ammo74/netinstall       # Push to registry
```

For Docker-based builds, see `tools/docker/`.  For details on the image format and architecture mapping, see the [Configuration Guide](GUIDE.md).

## Make Targets

| Target | Purpose |
|---|---|
| `make` / `make run` | Run netinstall once |
| `make service` | Run in a loop (container default) |
| `make download` | Download packages only — safe without a device |
| `make wizard` | Launch the interactive wizard (`mknetinstall`) |
| `make mknetinstall` | Install wizard to `~/.local/bin` (or `/usr/local/bin` as root) |
| `make image` | Build OCI images for all platforms |
| `make clean` | Remove all downloads, images, and build artifacts |
| `make dump` | Print computed variables for debugging |
| `make nothing` | Keep container alive without running netinstall |
| `make test` | Lint Makefile (checkmake) and shell scripts (shellcheck with `--shell=dash`) |

Channel shortcuts: `make stable`, `make testing`, `make long-term`, `make development`

Architecture shortcuts: `make arm64`, `make mipsbe`, `make x86`, etc.

Combine them: `sudo make testing arm64 PKGS="container wifi-qcom"`

See the [Configuration Guide](GUIDE.md) for the complete variable reference, `netinstall-cli` flags, multi-arch support, macOS VM internals, and advanced options.

## Project Structure

```text
mknetinstall              Interactive wizard (POSIX sh)
Makefile                  All automation logic
Dockerfile                Alternative Docker-based image build
tools/
  container-manager.sh    Provision & manage container on RouterOS (REST API)
  container-setup.rsc     Manual RouterOS CLI setup reference
  docker/                 Docker buildx image customization
```

## License

CC0 1.0 — <https://creativecommons.org/publicdomain/zero/1.0/>
