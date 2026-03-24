# Configuration Guide

Extended reference for MikroTik netinstall automation.  See the [README](README.md) for quick start and overview.

## Configuration Variables (Complete Reference)

All variables use `?=` (default if not set), overridable via CLI (`make VAR=val`), environment variables, or `/container/envs`.

### Basic Settings

| Variable | Default | Purpose |
|---|---|---|
| `ARCH` | `arm` | Target architecture(s), space-separated: `arm`, `arm64`, `mipsbe`, `mmips`, `smips`, `ppc`, `tile`, `x86` |
| `PKGS` | `wifi-qcom-ac` | Extra packages (space-separated, no version/arch suffix). `routeros-*.npk` is always included automatically. |
| `CHANNEL` | `stable` | Version channel: `stable`, `testing`, `long-term`, `development` |

Each time `make` runs, the channel's current version is checked via `upgrade.mikrotik.com`.

### Version Selection

| Variable | Default | Purpose |
|---|---|---|
| `VER` | *(from CHANNEL)* | Pin a specific RouterOS version (e.g., `7.14.3`, `7.15rc2`). Overrides CHANNEL. |
| `VER_NETINSTALL` | *(from CHANNEL)* | Pin `netinstall-cli` version independently. Newer netinstall can install older RouterOS. |

`VER_NETINSTALL` is useful because `netinstall-cli` occasionally gains features or fixes bugs.  A newer netinstall can, and often should, be used to install older versions.

### Device Configuration

| Variable | Default | Purpose |
|---|---|---|
| `OPTS` | `-b -r` | Raw flags passed to `netinstall-cli`. `-r` = reset to default config, `-e` = empty config (mutually exclusive), `-b` = strip branding. |
| `MODESCRIPT` | *(auto-set)* | RouterOS script content passed via `-sm` for first-boot execution. Auto-set when both `VER` and `VER_NETINSTALL` >= 7.22. See [First-Boot Script](#first-boot-script) below. |

> If a netinstall flag needs a file (e.g., `-s <defconf>`), use `/container/mount` and the container-relative path in `OPTS`.

### Network Configuration

| Variable | Default | Purpose |
|---|---|---|
| `IFACE` | `eth0` | Network interface for `-i` mode.  In containers, set to VETH name (RouterOS 7.21+ names interfaces after the VETH).  On macOS, this is the host interface to bridge to the QEMU VM. |
| `CLIENTIP` | *(unset)* | If set, uses `-a <CLIENTIP>` instead of `-i <IFACE>`. |
| `NET_OPTS` | *(computed)* | Overrides both `IFACE` and `CLIENTIP`. Set directly if needed (e.g., `NET_OPTS=-i en4`). |

MikroTik has a video explaining the interface vs IP options: [Latest netinstall-cli changes](https://youtu.be/EdwcHcWQju0?si=CrmixEZyH7FOjlZk).

### Advanced Options

| Variable | Default | Purpose |
|---|---|---|
| `PKGS_CUSTOM` | *(empty)* | Full container-relative paths to custom/branding packages, space-separated. Appended verbatim to the netinstall command. |
| `QEMU` | *(auto-detected)* | Path to `qemu-i386`. Auto-detects `./i386` (container), `qemu-i386-static` (Debian), or `qemu-i386` (Alpine). Skipped on x86_64. |
| `DLDIR` | `downloads` | Directory for downloaded packages and netinstall binary. |
| `IMAGE` | `tikoci/netinstall` | OCI image name for `make image` / `make image-push`. |
| `IMAGE_PLATFORMS` | `linux/arm64 linux/arm/v7 linux/amd64` | Platforms built by `make image`. |

### macOS VM Variables

| Variable | Default | Purpose |
|---|---|---|
| `QEMU_SYSTEM` | *(auto-detected)* | Path to `qemu-system-x86_64`. Auto-detected via `command -v`. |
| `VMLINUZ` | `$(DLDIR)/vmlinuz-virt` | Alpine virt kernel for macOS VM. |
| `VM_INITRAMFS` | `$(DLDIR)/initramfs-netinstall.gz` | Custom initramfs for macOS VM. |

## First-Boot Script

`netinstall-cli` 7.22 added the `-sm` flag, which runs a RouterOS script **once on first boot** after flashing — before the device is accessible via the network.  Unlike `-s` (default configuration script), the first-boot script is **not saved** to the device; it executes during the initial boot and is then discarded.

The `-sm` flag is only available in `netinstall-cli` 7.22 and newer; on older versions, no first-boot script is sent regardless of the `MODESCRIPT` setting.

The primary use case is automating `/system/device-mode` setup.  Setting device-mode normally requires logging into each device, running `/system/device-mode update`, confirming a physical power cycle, and waiting for reboot — a significant bottleneck when flashing in bulk.  With `-sm`, device-mode is configured automatically on first boot.

### Auto-detection (default behavior)

When **both** `VER` and `VER_NETINSTALL` are 7.22 or newer, the Makefile automatically sets `MODESCRIPT` to a `/system/device-mode update` command.  The base is always `mode=advanced`, with `container=yes` and `zerotier=yes` added conditionally based on `PKGS`:

| Condition | MODESCRIPT value |
|---|---|
| 7.22+, `PKGS` includes `container` and `zerotier` | `/system/device-mode update mode=advanced container=yes zerotier=yes` |
| 7.22+, `PKGS` includes `container` only | `/system/device-mode update mode=advanced container=yes` |
| 7.22+, `PKGS` includes `zerotier` only | `/system/device-mode update mode=advanced zerotier=yes` |
| 7.22+, `PKGS` has neither (e.g. default `wifi-qcom-ac`) | `/system/device-mode update mode=advanced` |
| Either `VER` or `VER_NETINSTALL` < 7.22 | *(empty — no `-sm` flag passed)* |

This means that on 7.22+, `mode=advanced` is always set on first boot, and the container/zerotier flags match whatever packages you're installing.

### Overriding with a custom script

Set `MODESCRIPT` to any RouterOS script content to replace the auto-detected default:

```sh
# Add DNS configuration to the first-boot script
sudo make run ARCH=arm64 PKGS="container wifi-qcom-ac" \
  MODESCRIPT='/system/device-mode update mode=advanced container=yes
/ip dns set servers=1.1.1.1,8.8.8.8'

# Completely custom script — skip device-mode, just set an identity
sudo make run ARCH=arm64 VER=7.22 \
  MODESCRIPT='/system identity set name=factory-reset'
```

In a RouterOS `/container/envs` configuration:

```routeros
/container envs add key=MODESCRIPT list=NETINSTALL \
  value="/system/device-mode update mode=advanced container=yes"
```

### Disabling the mode script

To prevent any first-boot script from being sent — even on 7.22+ — set `MODESCRIPT` to an empty value:

```sh
sudo make run ARCH=arm64 PKGS="container wifi-qcom-ac" MODESCRIPT=
```

In a RouterOS container, you must explicitly set `MODESCRIPT` to an empty value — omitting the key entirely allows auto-detection to run:

```routeros
/container envs add key=MODESCRIPT list=NETINSTALL value=""
```

### How it works internally

The Makefile writes the `MODESCRIPT` content to a temporary file (`.modescript.rsc`) and passes it via `-sm .modescript.rsc` to `netinstall-cli`.  The file is created fresh on each run and cleaned up by `make clean`.  Since `MODESCRIPT` uses `?=`, environment variables, CLI args, and `/container/envs` all take precedence over the auto-detected default — but the variable must be _defined_ (even as empty) to suppress auto-detection.

See MikroTik's [`/system/device-mode` documentation](https://help.mikrotik.com/docs/spaces/ROS/pages/197033996/Device+Mode) for the full list of `device-mode` flags and options.

## `netinstall-cli` Flags Reference

```text
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
| `-sm <modescript>` | First-boot script (RouterOS 7.22+) |

The system package (`routeros-*.npk`) **must be listed first** in the package arguments. When multiple architecture `.npk` files are provided, `netinstall-cli` auto-detects the device architecture.

## Multi-Architecture Support

`ARCH` accepts multiple architectures separated by spaces.  All packages are downloaded and passed to a single `netinstall-cli` invocation:

```sh
sudo make ARCH="arm arm64" PKGS="container wifi-qcom" OPTS="-b -r -m"
```

This is useful for flashing a mixed fleet without restarting netinstall.

## Manual Container Setup

If you prefer to set things up manually on RouterOS, or need to understand what `tools/container-manager.sh` does under the hood:

1. Create VETH interface and IP:

    ```routeros
    /interface veth add address=172.17.9.200/24 gateway=172.17.9.1 name=veth-netinstall
    /ip address add address=172.17.9.1/24 interface=veth-netinstall
    ```

2. Create a separate bridge and add VETH and physical port:

    ```routeros
    /interface bridge add name=bridge-netinstall
    /interface bridge port add bridge=bridge-netinstall interface=veth-netinstall
    /interface bridge port add bridge=bridge-netinstall interface=ether5
    ```

3. Allow the container to access the internet (for downloading packages):

    ```routeros
    /interface/list/member add list=LAN interface=bridge-netinstall
    ```

4. Create environment variables:

    ```routeros
    /container envs add key=ARCH    list=NETINSTALL value=arm64
    /container envs add key=CHANNEL list=NETINSTALL value=stable
    /container envs add key=PKGS    list=NETINSTALL value="container wifi-qcom"
    /container envs add key=OPTS    list=NETINSTALL value="-b -r"
    /container envs add key=IFACE   list=NETINSTALL value=veth-netinstall
    ```

    > The `IFACE` value must match the VETH name.  Since RouterOS 7.21+, the container network interface is named after the VETH.
    >
    > The env list field name changed in RouterOS 7.22: `name=` (pre-7.22) became `list=` (7.22+).

5. Create the container:

    **From DockerHub (pull):**

    ```routeros
    /container config set registry-url=https://registry-1.docker.io tmpdir=disk1/pulls
    /container add remote-image=ammo74/netinstall:latest envlist=NETINSTALL interface=veth-netinstall logging=yes workdir=/app root-dir=disk1/root-netinstall
    ```

    **From a local `.tar` file (built with `make image`):**

    ```routeros
    /container add file=disk1/netinstall.tar envlist=NETINSTALL interface=veth-netinstall logging=yes workdir=/app root-dir=disk1/root-netinstall
    ```

6. Start the container:

    ```routeros
    /container/start [find tag~"netinstall"]
    ```

The complete RouterOS CLI script is also available as `tools/container-setup.rsc`.

## `tools/container-manager.sh` Options

| Option | Default | Purpose |
|---|---|---|
| `-r ROUTER` | `192.168.88.1` | Router address |
| `-P PORT` | auto-detected | REST API port |
| `-S SCHEME` | auto-detected | `http` or `https` |
| `-s SSHPORT` | `22` | SSH port for SCP upload |
| `-d DISK` | *(required for setup)* | Disk path on router (e.g., `disk1`) |
| `-p PORT` | *(required for setup)* | Ethernet port for netinstall (e.g., `ether5`) |
| `-a ARCH` | `arm64` | Target architecture for packages |
| `-c CHANNEL` | `stable` | Version channel |
| `-k PKGS` | `wifi-qcom` | Extra packages |
| `-o OPTS` | `-b -r` | netinstall flags |
| `-u USER` | `admin` | Router username |
| `-w PASS` | *(prompted)* | Router password (or use keychain) |

> Install `sshpass` (`brew install hudochenkov/sshpass/sshpass` on macOS) for non-interactive SCP uploads.

## macOS VM Details

MikroTik's `netinstall-cli` is a Linux x86 ELF binary — it cannot run natively on macOS.  Rather than requiring Docker Desktop (which lacks the bridged networking `netinstall` needs), this project uses [QEMU](https://www.qemu.org/) to boot a minimal Linux VM that bridges directly to a macOS ethernet port.  This gives `netinstall-cli` the raw Layer 2 access it needs for BOOTP/TFTP, which Docker's NAT networking cannot provide.

On macOS, `make run` and `make service` transparently delegate to a QEMU VM.  Here's what happens under the hood:

- Boots a lightweight [Alpine Linux](https://alpinelinux.org/) VM (~15MB kernel + initramfs) via [`qemu-system-x86_64`](https://www.qemu.org/docs/master/system/target-i386.html)
- Uses [vmnet-bridged networking](https://developer.apple.com/documentation/vmnet) to connect the VM directly to your macOS ethernet port — the VM appears as a device on that network segment, just like a physical Linux machine
- Shares the project directory into the VM via [9p/virtfs](https://wiki.qemu.org/Documentation/9psetup), so downloaded packages are accessible without copying
- Inside the VM, `netinstall-cli` runs natively on x86_64 Linux — no user-mode emulation overhead

**Why not Docker?** Docker Desktop on macOS runs containers inside a Linux VM with NAT networking.  `netinstall-cli` needs to send and receive BOOTP (broadcast) and TFTP packets on the same Layer 2 network as the target device.  Docker's NAT breaks this.  QEMU's vmnet-bridged mode gives the VM a real presence on the physical network — exactly what `netinstall` requires.

**First run** builds the VM components (kernel + initramfs) from an Alpine Linux APK — cached in `downloads/`.  Subsequent runs start in seconds.

**Requirements:**

```sh
brew install qemu crane wget
```

- [`qemu`](https://formulae.brew.sh/formula/qemu) — provides `qemu-system-x86_64` for the VM
- [`crane`](https://formulae.brew.sh/formula/crane) — needed once to extract the Alpine rootfs from its OCI image when building the VM initramfs
- `wget` — for downloading RouterOS packages
- `sudo` — required for vmnet-bridged networking (macOS prompts for your password)

> `make download` works on macOS without QEMU — it only downloads packages.  QEMU is only needed for `make run` and `make service`.

## Linux Prerequisites

### x86_64 (Intel/AMD)

`netinstall-cli` is an x86 binary — it runs natively on x86_64.  No QEMU is needed.

```sh
# Debian/Ubuntu
sudo apt install make wget unzip

# Alpine
apk add make wget unzip

# Fedora
sudo dnf install make wget unzip
```

`sudo` is required for `make run`/`make service` (BOOTP/TFTP use privileged ports).

### aarch64 (ARM)

`netinstall-cli` is an x86 binary and cannot run natively on aarch64.  The Makefile uses **user-mode QEMU** to emulate i386 syscalls directly in user space — no full VM is needed.

```sh
# Debian/Ubuntu
sudo apt install make wget unzip qemu-user-static

# Alpine
apk add make wget unzip qemu-i386

# Fedora
sudo dnf install make wget unzip qemu-user-static
```

`sudo` is required for `make run`/`make service` (BOOTP/TFTP use privileged ports).

The Makefile auto-detects in priority order: `./i386` (container bundled binary), then `qemu-i386-static`, then `qemu-i386`.  If none are found, it prints an install hint and exits.

This is the same mechanism the OCI container image uses — during image build, a `qemu-i386` binary is bundled as `./i386` inside the image.  You only need to install it manually when running `make` directly (not via the container).

> This is distinct from macOS, which boots a full `qemu-system-x86_64` VM — see [macOS VM Details](#macos-vm-details).

## Interactive Wizard (`mknetinstall`)

`mknetinstall` is a POSIX shell script wizard that guides you through all choices and then invokes `make` with the right variables.  It works on macOS and Linux — run it directly from the project directory, or install it to your PATH:

```sh
./mknetinstall

# Or install to PATH first:
make mknetinstall && mknetinstall
```

The wizard walks through these steps in order:

1. **Platform detection** — detects OS and CPU architecture, checks that required tools are installed, prints install hints if anything is missing
2. **Version channel** — choose `stable`, `testing`, `long-term`, `development`, or pin a specific version string (e.g., `7.22`)
3. **Target architecture** — one or more (e.g., `arm64`, or `arm arm64` for a mixed fleet)
4. **Packages** — downloads the selected packages first, then lists what's available so you can pick by number (WiFi driver note is shown here)
5. **Device mode** *(7.22+ only)* — `Automatic`, `Advanced`, `RoSE`, `Home`, or `Do not change`; see [First-Boot Script](#first-boot-script)
6. **Install config** — reset to default config (`-r`) or empty config (`-e`)
7. **Network interface** — auto-detects available interfaces and lets you select or type one
8. **Run mode** — run once (`make run`) or loop as a service (`make service`)
9. **Summary & confirmation** — shows the exact `make` command before running it

Non-interactive use — pass options to skip prompts:

```sh
./mknetinstall --arch arm64 --channel stable --dry-run
./mknetinstall --arch arm64 --pkgs "container wifi-qcom-ac" --iface en5 --run
```

Use `./mknetinstall --help` for the full option list.

**On macOS**, the wizard's `make run`/`make service` delegate to a QEMU system VM — see [macOS VM Details](#macos-vm-details).  The wizard checks for `qemu-system-x86_64` at startup and will tell you to `brew install qemu` if it's missing.  On Apple Silicon (aarch64), the VM emulates x86_64 in software (QEMU TCG) — slightly slower than on Intel Mac, but fine for netinstall's modest workload.

**On Linux aarch64**, the wizard's `make run` uses `qemu-i386` user-mode emulation — see [Linux Prerequisites](#linux-prerequisites).  The wizard prints a missing-tool message with the right `apt`/`apk`/`dnf` command if it isn't installed.

**On x86_64 Linux**, `netinstall-cli` runs natively — no QEMU is needed at all.

## Why a Makefile?

`make` is well-suited for this task:

- File-based dependency tracking — downloads only when needed
- Phony targets make it act script-like (`make run`, `make service`, `make download`)
- Native support for both CLI arguments and environment variables — ideal for container + CLI dual use
- Small runtime footprint — `make` + busybox is ~13MB before packages
- No additional language runtime (Python/Node/etc.) needed

The tradeoff is that Makefiles are dense if you're not familiar with GNU make.  But since `make` handles file state and variables well, it saves a lot of boilerplate compared to shell scripts.
