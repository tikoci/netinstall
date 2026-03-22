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
| `MODESCRIPT` | *(auto-set)* | First-boot script via `-sm`. Auto-set to `/system/device-mode update mode=advanced container=yes zerotier=yes` when PKGS includes `container` or `zerotier` and VER_NETINSTALL >= 7.22. |

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

`netinstall-cli` is a Linux x86 ELF binary — it cannot run natively on macOS.  On macOS, `make run` and `make service` automatically boot a lightweight QEMU system VM:

- Alpine virt kernel + custom initramfs with virtio/9p modules
- Host directory mounted via 9p (`virtfs`) at `/host`
- vmnet-bridged networking connects the VM to the macOS interface
- Inside the VM, `netinstall-cli` runs natively on x86_64 Linux

**First run** builds the VM components (kernel + initramfs) from an Alpine APK — cached in `downloads/`.  Subsequent runs start in seconds.

**Requirements:**
- `qemu-system-x86_64` — `brew install qemu`
- `crane` — needed once to build the VM rootfs from the Alpine OCI image
- `sudo` — required for vmnet-bridged networking

> `make download` works on macOS without QEMU — it only downloads packages.  QEMU is only needed for `make run` and `make service`.

## Linux Prerequisites

- `make`, `wget`, `unzip`
- On aarch64/ARM: `qemu-i386` or `qemu-i386-static` (e.g., `sudo apt install qemu-user-static`)
- `sudo` for `make run`/`make service` (BOOTP/TFTP use privileged ports)

## Why a Makefile?

`make` is well-suited for this task:

- File-based dependency tracking — downloads only when needed
- Phony targets make it act script-like (`make run`, `make service`, `make download`)
- Native support for both CLI arguments and environment variables — ideal for container + CLI dual use
- Small runtime footprint — `make` + busybox is ~13MB before packages
- No additional language runtime (Python/Node/etc.) needed

The tradeoff is that Makefiles are dense if you're not familiar with GNU make.  But since `make` handles file state and variables well, it saves a lot of boilerplate compared to shell scripts.
