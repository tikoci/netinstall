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

MikroTik's `netinstall-cli` is a Linux-only binary.  This project makes it work on macOS by automatically booting a lightweight QEMU VM with bridged networking — the same `make` commands work on both platforms.

#### Install prerequisites

```sh
brew install qemu make wget
go install github.com/google/go-containerregistry/cmd/crane@latest
```

- `qemu` — provides `qemu-system-x86_64` for the VM
- `make` — Homebrew's GNU make (macOS ships an older version that also works, but Homebrew's is recommended)
- `wget` — for downloading packages
- `crane` — needed once to build the VM rootfs from an Alpine OCI image

#### Run netinstall

Set `IFACE` to the macOS interface your target device is connected to (e.g., `en5` for a USB ethernet adapter):

```sh
sudo make run ARCH=arm64 PKGS="container wifi-qcom-ac" IFACE=en5
```

The first run builds the VM components (Alpine kernel + initramfs), which are cached in `downloads/`.  Subsequent runs start in seconds.  Your macOS password is required for `sudo` (vmnet-bridged networking needs root).

> [!IMPORTANT]
>
> **To exit the QEMU VM, press <kbd>Ctrl-A</kbd> then <kbd>X</kbd>** (the QEMU monitor escape sequence).  <kbd>Ctrl-C</kbd> does **not** work — this is intentional, since interrupting `netinstall` mid-flash could leave a device in a bad state.  The VM shuts down automatically after a single `make run` completes.

`make download` works without QEMU — it only downloads packages.  QEMU is only needed for `make run` and `make service`.  For details on how the VM works under the hood, see the [Configuration Guide](GUIDE.md#macos-vm-details).

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
> Requires **RouterOS 7.22+** (REST API property names changed in 7.22).

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

Configure via `/container/envs` (RouterOS 7.22+ syntax):

```routeros
/container envs add key=ARCH    list=NETINSTALL value=arm64
/container envs add key=PKGS    list=NETINSTALL value="container wifi-qcom"
/container envs add key=CHANNEL list=NETINSTALL value=stable
/container envs add key=OPTS    list=NETINSTALL value="-b -r"
/container envs add key=IFACE   list=NETINSTALL value=veth-netinstall
```

> On RouterOS pre-7.22, use `name=NETINSTALL` instead of `list=NETINSTALL`.

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
| `MODESCRIPT` | *(auto-set)* | First-boot script via `-sm`; auto-set when PKGS includes `container`/`zerotier` and version >= 7.22 |

See the [Configuration Guide](GUIDE.md) for the complete variable reference, `netinstall-cli` flags, and advanced options.

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
| `make test` | Lint the Makefile with checkmake |

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
