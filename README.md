# MikroTik `netinstall` using `make`

`netinstall` allows the "flashing" of MikroTik devices, using a list of packages and various options.  While MikroTik provides a Linux version named `netinstall-cli`, running it involves **many** steps.  One of which is downloading packages, for the right CPU, possibly some "extra-packages" too.

MikroTik has a good overview of `netinstall` and the overall process: <https://help.mikrotik.com/docs/display/ROS/Netinstall#Netinstall-InstructionsforLinux>

The source code and CI image building are stored in a public GitHub repo, and an OCI image is also pushed to DockerHub and `ghcr.io` by GitHub Actions.  [Comments, complaints, and bugs](https://github.com/tikoci/netinstall/issues) are all welcome via GitHub Issues in the `tikoci/netinstall` [repo](https://github.com/tikoci/netinstall).

### Dual Use – `/container` or Linux Shell

#### Just Automating `netinstall` from Linux

The "script" is invoked by just calling `make` from the same directory, and by default that will start a netinstall using ARM packages, from "stable" channel, on an interface named "eth0". _This is often not the case, so variables on the network interface/IP will likely need to be changed from defaults._

#### _or..._ Running as a MikroTik `/container`

An OCI container image is built using `crane` (no Docker required) and includes QEMU to run MikroTik's x86 `netinstall` binary on other platforms, specifically ARM and ARM64.  By default, this container runs as a "service", so after one netinstall completes, it goes on to waiting for the next.

## RouterOS `/container` Install

`/container` running `netinstall` is handy to enable reset/recovery of a connected RouterOS device **without needing a PC**.  The basic approach is a container's VETH is bridged to a physical ethernet interface, using a new `/interface/bridge` for "netinstall".  Then the container runs the Linux `netinstall` using emulation (on ARM/ARM64).   The trick here is no `/container/mounts` are needed – **install packages are downloaded _automatically_** based on the environment variables provided to the image.

> Using "vlan-filtering=yes" bridge should work if VETH and target physical port have some vlan-id=.  But for `netinstall` likely best if just separate, since VLANs add another level of complexity here.  Possible, just untested and undocumented here.

#### Prerequisites

* RouterOS device that supports containers, generally ARM, ARM64, or x86 devices
* Some non-flash storage (internal drives, ramdisk, NFS/SMB client via RouterOS, USB, etc.)
* `container.npk` extra-package has been installed and other RouterOS specifics, and `/system/device-mode` has been used to enable container support as well.

See MikroTik's docs on `/container` for more details and background, including how to install the prerequisites:
<https://help.mikrotik.com/docs/display/ROS/Container>

### Automated Setup with `routeros-setup.sh`

The `routeros-setup.sh` script automates the entire container provisioning process via the RouterOS REST API.  It creates the VETH, bridge, environment variables, builds the image locally, uploads it via SCP, and creates the container — all in one command.

> [!WARNING]
>
> `routeros-setup.sh` requires **RouterOS 7.22+**.  MikroTik changed several REST API property names in 7.22 (e.g., env list field `name` → `list`), and the script uses the 7.22+ names.  On older versions, API calls will fail or silently use wrong field names.

#### First-Time Setup

Store credentials in your system keychain (macOS Keychain or Linux secret-tool):

```sh
./routeros-setup.sh credentials -r 192.168.88.1 -P 7080 -S http
```

Then provision everything:

```sh
./routeros-setup.sh setup -r 192.168.88.1 -P 7080 -S http -d disk1 -p ether5 -a arm64
```

This will:

1. Create VETH (`veth-netinstall`), bridge (`bridge-netinstall`), and IP addressing
2. Add both the VETH and your physical port (`ether5`) to the bridge
3. Add the bridge to the LAN interface list for internet access
4. Set container environment variables (`ARCH`, `CHANNEL`, `PKGS`, `OPTS`, `IFACE`)
5. Detect the router's architecture and build the correct image with `crane`
6. Upload the image via SCP and create the container

#### Managing the Container

```sh
# Start/stop
./routeros-setup.sh start -r 192.168.88.1 -P 7080 -S http
./routeros-setup.sh stop  -r 192.168.88.1 -P 7080 -S http

# Check status and environment variables
./routeros-setup.sh status -r 192.168.88.1 -P 7080 -S http

# View container logs
./routeros-setup.sh logs -r 192.168.88.1 -P 7080 -S http

# Remove everything (container, envs, bridge, VETH)
./routeros-setup.sh remove -r 192.168.88.1 -P 7080 -S http
```

After storing credentials, only the router address and port are needed — username and password are retrieved from the keychain automatically.

#### Script Options

| Option | Default | Purpose |
|---|---|---|
| `-r ROUTER` | `192.168.88.1` | Router address |
| `-P PORT` | auto-detected | REST API port |
| `-S SCHEME` | auto-detected | `http` or `https` |
| `-s SSHPORT` | `22` | SSH port for SCP upload |
| `-d DISK` | _(required)_ | Disk path on router (e.g. `disk1`) |
| `-p PORT` | _(required)_ | Ethernet port for netinstall (e.g. `ether5`) |
| `-a ARCH` | `arm64` | Target architecture for packages |
| `-c CHANNEL` | `stable` | Version channel |
| `-k PKGS` | `wifi-qcom` | Extra packages |
| `-o OPTS` | `-b -r` | netinstall flags |
| `-u USER` | `admin` | Router username |
| `-w PASS` | _(prompted)_ | Router password (or use keychain) |

> **TIP**
>
> Install `sshpass` (`brew install hudochenkov/sshpass/sshpass` on macOS) for non-interactive SCP uploads.  Otherwise you will be prompted for the SSH password during setup.

### Manual Setup (RouterOS CLI)

If you prefer to set things up manually, or need to understand what `routeros-setup.sh` does:

1. Create `/interface/veth` interface/IP:

    ```routeros
    /interface veth add address=172.17.9.200/24 gateway=172.17.9.1 name=veth-netinstall
    /ip address add address=172.17.9.1/24 interface=veth-netinstall
    ```

2. Create a separate bridge for `netinstall` use and add VETH and physical port:

    ```routeros
    /interface bridge add name=bridge-netinstall
    /interface bridge port add bridge=bridge-netinstall interface=veth-netinstall
    /interface bridge port add bridge=bridge-netinstall interface=ether5
    ```

3. Adjust the firewall so the container can download packages:

    ```routeros
    /interface/list/member add list=LAN interface=bridge-netinstall
    ```

4. Create environment variables to control `netinstall` operation:

    ```routeros
    /container envs add key=ARCH list=NETINSTALL value=arm64
    /container envs add key=CHANNEL list=NETINSTALL value=stable
    /container envs add key=PKGS list=NETINSTALL value="container wifi-qcom"
    /container envs add key=OPTS list=NETINSTALL value="-b -r"
    /container envs add key=IFACE list=NETINSTALL value=veth-netinstall
    ```

    > **NOTE**
    >
    > The `IFACE` variable must match the VETH name.  Since RouterOS 7.21+, the container network interface is named after the VETH (e.g. `veth-netinstall`), not `eth0`.

    > **NOTE**
    >
    > The env list field name changed in RouterOS 7.22: `name=` (pre-7.22 CLI) became `list=` (7.22+ CLI and REST API).  The examples above use `list=` which works on 7.22+.  On older versions, use `name=NETINSTALL` instead of `list=NETINSTALL`.

5. Create the container using a pre-built image or a local `.tar` file:

    **From DockerHub or GHCR (pull):**

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

### Additional `/container/env` options

All options are described in greater detail later.  But `CHANNEL`, `ARCH`, `PKGS`, and `OPTS` are the typical ones.  Some additional `/container/env` include:

#### `VER`

Instead of using `CHANNEL` like "stable", to select the version use:

```routeros
/container envs add key=VER list=NETINSTALL value=7.12.1
```

If both `CHANNEL` and `VER` are used, VER wins.

> **TIP**
>
> It is recommended you only set `VER` when needed, since it overrides what is set in `CHANNEL`.  This may be what you want – just as a default "stable" makes more sense.

#### `VER_NETINSTALL`

To set the version of `netinstall` use:

```routeros
/container envs add key=VER_NETINSTALL list=NETINSTALL value=7.15rc3
```

Left unset, the version of `netinstall` itself will follow what is set in `CHANNEL`, which defaults to "stable".

#### `IFACE` and `CLIENTIP`

Since RouterOS 7.21+, the container network interface is named after the VETH, not `eth0`.  Set `IFACE` to match your VETH name:

```routeros
/container envs add key=IFACE list=NETINSTALL value=veth-netinstall
```

`CLIENTIP` can be used instead of `IFACE` to specify a client IP address directly.  If neither is set, the default is `eth0`.

## Building Container Images

The OCI container images are built using [`crane`](https://github.com/google/go-containerregistry/blob/main/cmd/crane/README.md) — no Docker required.  The image is an Alpine Linux rootfs with `make`, the project `Makefile`, and (on ARM/ARM64) a `qemu-i386` binary for running the x86 `netinstall-cli`.

### Build All Platforms

```sh
make image
```

This builds images for all three platforms (`linux/arm64`, `linux/arm/v7`, `linux/amd64`) and saves them to `images/`.

### Build a Single Platform

```sh
make image-platform IMAGE_PLATFORM=linux/arm64
```

### Push to a Registry

```sh
# Push to DockerHub
make image-push IMAGE=ammo74/netinstall

# Push to GHCR
make image-push IMAGE=ghcr.io/tikoci/netinstall
```

`image-push` pushes all platform images and creates a multi-platform manifest index.

### Requirements

* [`crane`](https://github.com/google/go-containerregistry/blob/main/cmd/crane/README.md) — `go install github.com/google/go-containerregistry/cmd/crane@latest`
* `wget` — for downloading Alpine packages and QEMU binaries
* Internet access — to pull `alpine:latest` and `tonistiigi/binfmt:latest`

## Configuration Options and Variables

Let's start with some commons ones, directly from the `Makefile` script — these are the **defaults** _if left any **unset**_ elsewhere:

```makefile
ARCH ?= arm
PKGS ?= wifi-qcom-ac
CHANNEL ?= stable
OPTS ?= -b -r
IFACE ?= eth0
```

These can used in three ways:

1. **Using environment variables**
 This is generally most useful with containers since environment variables are the typical configuration method.
**_For MikroTik RouterOS_** these are stored in `/container/envs` and documented here.
**_For Linux_** use `export VER_NETINSTALL=7.14.2` in a `.profile` or similar. This allows environment variables to persist on a Linux shell, similar to a container.  _i.e._ to avoid always having to provide them every time without having to edit the `Makefile` directly.

2. **Provided via `make` at CLI**, in same directory as Makefile.  For example, to start netinstall for mipsbe using the `VER` number directly, with some extra packages and `-a 192.168.88.7` option, and specific version `netinstall` to be used of 7.15rc3:

    ```sh
    cd ~/netinstall
    sudo make -d ARCH=mipsbe VER=7.14.3 PKGS="iot gps ups" CLIENTIP=192.168.88.7 VER_NETINSTALL=7.15rc3
    ```

    which results in the following `netinstall` command line being used:

    ```text
    downloads/netinstall-cli-7.15rc3 -b -r -a 192.168.88.7 downloads/routeros-7.14.3-mipsbe.npk downloads/iot-7.14.3-mipsbe.npk downloads/gps-7.14.3-mipsbe.npk downloads/ups-7.14.3-mipsbe.npk
    ```

    > **TIP**
    >
    > Any `make` at CLI, can be used as the `/container cmd=` as an alternative to environment variables.

3. **Editing the `Makefile`**
 All of the variables are at the top of the file.  The ones with `?=` are used only if the same variable was **not** already provided via CLI or env.  In general, the only benefit of this method is proximity.  The method is not recommended - it makes using some future updated `Makefile` harder.
   > **TIP**
   >
   > In the `Makefile` take careful note to **use <kbd>tab</kbd> indentations** – `make` will fail if <kbd>space</kbd> indentations are used.
   >
   > Also, be careful not to change or override computed variables, _i.e._ variables that use `=` or `:=` assignment.  The `?=` mean default _if not provided_, so those are the one designed to be "overriden".

### Basic Settings

The specific file names needed for `netinstall` are generated automatically based on the `ARCH`, `CHANNEL`, and `PKGS` variables to make things easier to configure.   The routeros*.npk does NOT need to be included in `PKGS` - it is always added based on `ARCH`.  Only items "extra-packages" that needed to be installed are added to `PKGS`.

| _option_ | _default_ |           |
| -     | -             | -             |
| ARCH | `arm` | **architecture name** must match `/system/resource`|
| PKGS | `wifi-qcom-ac` | **additional package name(s)**, without version/CPU, separated by spaces, invalid/missing packages are skipped |
| CHANNEL | `stable` | same choices as `/system/package/update` i.e. **testing**, **long-term**, **development**|

 Each time `make` is run, the `CHANNEL`'s current version is checked via the web and sets `VER` automatically.

### Version Selection

 By design, `CHANNEL` should be used to control the version used.

If `VER` (RouterOS) and/or `VER_NETINSTALL` (executable) are provided, the string must be in the same form as published, like `7.15rc2` or `7.12.1`.  It **cannot** be a channel name like "stable".  But these variables can be any valid version, including older ones no longer on a channel.

`VER_NETINSTALL` is useful since sometimes `netinstall` has bugs or gains new features.  Generally, a newer netinstall can, and often should, be used to install older versions _i.e. some potential `OPTS` has changed over time..._ By default, only `CHANNEL` controls what version of `netinstall` will be used.  Meaning, even if `VER` is lower/older than `VER_NETINSTALL`, the latest "stable" `netinstall` for Linux will be used by default.  That is unless `VER_NETINSTALL` is specified explicitly

| _option_ | _default_ |           |
| -     | -             | -             |
| VER | _calculated from `CHANNEL`_ | specific version to install on a device, in `x.y.z` form |
| VER_NETINSTALL | _calculated from `CHANNEL`_ | version of `netinstall` to use, can be different than `VER` |

### `OPTS` - Device Configuration

 In the variable `OPTS`, the string is provided directly to `netinstall` unparsed.  So any valid `netinstall` command line options can be provided – they just get inserted with run.

To get an **empty config**, change `-r` in the `OPTS` variable to a **`-e`** (both `-r` and `-e` are NOT allowed at the same time).

The real `netinstall` also supports additional options, like replacing the default configuration via an option `-s <defconf_file>`, among others.  These too can be provided in `OPTS` - along with existing options.

> **TIP**
>
> If netinstall option needs a file, `/container/mount` can used, and the "container-relative" full path referenced in same `OPTS` after flag. For example, `-r -s /data/mydefconf.rsc`.

| _option_ | _default_ |           |
| -     | -             | -             |
| OPTS | `-b -r` | default is to "remove any branding" `-b` and "reset to default" `-r`, see [`netinstall` docs](https://help.mikrotik.com/docs/display/ROS/Netinstall#Netinstall-InstructionsforLinux)  |

### `MODESCRIPT` - First-Boot Script (RouterOS 7.22+)

The `-sm <modescript>` flag deploys a first-boot script that runs once after initial boot.  The `MODESCRIPT` variable controls this:

| _option_ | _default_ |           |
| -     | -             | -             |
| MODESCRIPT | _auto-set if applicable_ | RouterOS script to run on first boot; written to `.modescript.rsc` and passed via `-sm` |

When `PKGS` includes `container` or `zerotier` **and** `VER_NETINSTALL` is >= 7.22, `MODESCRIPT` automatically defaults to:

```routeros
/system/device-mode update mode=advanced container=yes zerotier=yes
```

This enables advanced device mode on the flashed device, which is required for container and ZeroTier support.  To disable the auto-set behavior, use `MODESCRIPT=""`.

### Network and System Configuration

Critical to `netinstall` working to flash a device is the networking is configured.  This is the trickiest part.  The `-i` or `-a` options must align with everything else, which corresponds to the `IFACE` **OR** `CLIENTIP`.

MikroTik has a YouTube video that explains a bit about these interface vs IP options: [Latest netinstall-cli changes](https://youtu.be/EdwcHcWQju0?si=CrmixEZyH7FOjlZk).  These are more applicable if you're using the Makefile standalone on a Linux machine.

When running in a MikroTik `/container`, set `IFACE` to match the VETH name (e.g. `veth-netinstall`).  Since RouterOS 7.21+, the container network interface is named after the VETH, not `eth0`.

| _option_ | _default_ |           |
| -     | -             | -             |
| IFACE | `eth0` | network interface for `netinstall`; set to VETH name when running in `/container` |
| CLIENTIP | _not set_ | by default `-i <iface>` is used, if `CLIENTIP` then `-a <clientip>` is used |
| NET_OPTS | _calculated_ | raw `netinstall` network options, like "-i en4" – `IFACE` and `CLIENTIP` are ignored if `NET_OPTS` is set, only needed if `-i <iface>` or `-a <clientip>` do not work (or change)|

### Branding and Non Standard Packages

To use a branding package, `PKGS_CUSTOM` variable can be used with `/container/mount`.  The full container-relative path need to be used.  The value of `PKGS_CUSTOM` is simply appended to the end of the `netinstall` command, so any package with a valid full path can used.

| _option_ | _default_ |           |
| -     | -             | -             |
| PKGS_CUSTOM | _empty_ | full path _within container_ to additional packages, space separated; any paths must match `/container/mount` |

### Uncommon Options

This should not be changed, documented here for consistency.

| _option_ | _default_ |           |
| -     | -             | -             |
| QEMU | _auto-detected_ | `qemu-i386` for non-x86 Linux platforms.  Auto-detects `./i386` (container), `qemu-i386-static`, or `qemu-i386` from PATH.  Not used on x86_64 or macOS (which uses QEMU system VM instead) |
| URLVER | <https://upgrade.mikrotik.com/routeros/NEWESTa7> | URL used to determine what version is "stable"/etc |
| DLDIR | `downloads` | directory for downloaded packages and netinstall binary |
| PKGS_FILES | _computed_ | _read-only_, in logs shows the resolved "extra-package" to be installed |

## Multi-Architecture Support

The `ARCH` variable accepts multiple architectures separated by spaces.  The Makefile downloads packages for all listed architectures and passes them all to a single `netinstall-cli` invocation.  `netinstall-cli` auto-detects the connected device's architecture and selects the matching packages.

```sh
# Serve both ARM and ARM64 devices
sudo make ARCH="arm arm64" PKGS="container wifi-qcom" -m

# Download only (no netinstall run)
make download ARCH="arm arm64 mipsbe" PKGS="wifi-qcom"
```

This is useful for flashing a mixed fleet of devices without restarting `netinstall` each time.  The `-m` flag (add to `OPTS` or pass directly) keeps netinstall running to serve multiple devices.

## macOS Usage (QEMU VM)

On macOS, `make run` and `make service` automatically boot a lightweight QEMU system VM with vmnet-bridged networking.  The same commands work on Linux and macOS — the VM is transparent.

#### Prerequisites

* `make`, `wget`, `unzip` (included with Xcode CLT or Homebrew)
* `qemu-system-x86_64` — install with `brew install qemu`
* `crane` — install with `go install github.com/google/go-containerregistry/cmd/crane@latest` (needed once to build the VM rootfs image)
* `sudo` — required for vmnet-bridged networking

#### macOS Usage Example

Set `IFACE` to the macOS interface your target device is connected to (e.g. `en5` for a USB ethernet dongle):

```sh
# Run once
sudo make run ARCH=mipsbe PKGS="wireless iot gps" IFACE=en5

# Run as a service (loops until stopped)
sudo make service ARCH=arm64 PKGS="container wifi-qcom" IFACE=en5
```

The first run builds the VM components (Alpine rootfs + virt kernel), which are cached in `downloads/`.  Subsequent runs start in seconds.

> **NOTE**
>
> `make download` works on macOS without QEMU — it only downloads packages.  QEMU is only needed for `make run` and `make service`, which execute the Linux `netinstall-cli` binary.

## Linux Install and Usage

#### Prerequisites

* Linux device (or virtual machine) with ethernet
* Some familiarity with the UNIX shell and commands
* `make`, `wget`, and `unzip` installed on your system
* On aarch64/ARM Linux: `qemu-i386` or `qemu-i386-static` (e.g. `sudo apt install qemu-user-static`).  The Makefile auto-detects the binary from PATH.

> **NOTE**
>
> Each distro is different.  Only limited testing was done on Linux, specifically virtualized Ubuntu.  While very generic POSIX commands/tools are used, still possible to get errors that stop `make` from running.  Please report any issues found, including errors.

#### Downloading Code to Run on Linux

You can download the Makefile itself to a new directory, but it may be easier to just use `git`, to make any future updates easier:

```sh
cd ~
git clone https://github.com/tikoci/netinstall.git
cd netinstall
```

To test it, just run `make download` which will download ARM packages, but NOT run netinstall.

#### Linux Usage Examples

To begin, `make` needs to be run from the **same directory** as the `Makefile`.  To use examples, the current directory in shell **must** contain the `Makefile`.

> **INFO**
>
> `sudo` must be used on most desktop Linux distros for any operation that starts running `netinstall`, since privileged ports are used.
> But just downloading files, should not require `root` or `sudo` – but running `netinstall` might on most Linux distros since it listens on a privileged port (69/udp).
>
* Download files for "stable" on the "tile" CPU - but NOT run netinstall:

    ```sh
    make stable tile download
    ```

* The runs netinstall using "testing" (`CHANNEL`) build with "mipsbe" (`ARCH`):

    ```sh
    sudo make testing mipsbe
    ```

* To remove all downloaded files, images, and build artifacts:

    ```sh
    make clean
    ```

* This command will continuously run the netinstall process in a loop.

    ```sh
    sudo make service
    ```

* All of `netinstall` options can be also provided using the `VAR=VAL` scheme after the `make`:

    ```sh
    make run ARCH=mipsbe VER=7.14.3 VER_NETINSTALL=7.15rc3 PKGS="wifi-qcom container zerotier" CLIENTIP=192.168.88.7 OPTS="-e"
    ```

    > `OPTS` is ace-in-the-hole since the value it just appended to `netinstall`, this can be used to control important stuff like `-e` (empty config after netinstall) vs `-r` (reset to defaults) options, or any valid option to netinstall.  `PKGS` is **only** for extra-packages – the base `routeros*.npk` is always included (based on `ARCH` and `VER`).

## `make` arguments for CLI (or Docker `CMD`)

The script is based on a `Makefile` and the `make` command in Linux.  One important detail is that `make` looks for the `Makefile` within the current working directory.

### Basic usage

* `make` -  same as `make run`, see below
* `make run` - **CLI default** is run netinstall until found and finished, then stop
* `make service` - **container default** runs netinstall as a service until stopped manually
* `make download` - used on desktop to download packages before potentially disconnecting the network, then `make` can be used without internet access

### Image building

* `make image` - build OCI container images for all platforms (ARM, ARM64, x86)
* `make image-platform IMAGE_PLATFORM=linux/arm64` - build for a single platform
* `make image-push IMAGE=tikoci/netinstall` - push all platform images to a registry
* `make image-clean` - remove built images only (keeps downloaded packages)

### Using CLI "shortcuts"

Any targets provided via arguments to `make` will OVERRIDE any environment variable with the same name. _i.e._ CLI arguments win

* `make <stable|testing|long-term|development>` - specify the `CHANNEL` to use
* `make <arm|arm64|mipsbe|mmips|smips|ppc|tile|x86>` - specify the `ARCH` to use

For example `make testing tile` which will start `netinstall` using the current "testing" channel version, for the "tile" architecture.

### Combine `make` "shortcuts"

For offline use, while only one channel and one architecture can be used at a time...Downloaded files are cached until deleted manually or `make clean`. So to download without running, add a `download` to the end of `make stable mipsbe download`, and repeat for any versions you want to "cache".

> **TIP**
>
> The "shortcut" with `make` variables provided like `make download VER=7.12 ARCH=mmips CLIENTIP=192.168.88.4 VER_NETINSTALL=7.15rc3`.  Just don't mix TOO many, but output (or logs) should indicate the potential problem

### Troubleshooting and File Management

* `make clean` - remove all downloaded packages, images, and build artifacts
* `make nothing` - does nothing, except keep running; used to access `/container/shell` without starting anything
* `make dump` - for internal debugging use, shows computed ARCH, VER, CHANNEL, and MODESCRIPT values

### Wait, a C/C++ `Makefile`, why not python or node?

The aim here is to simplify the process of automatically downloading all the various packages and `netinstall` tool itself.  But also an experiment in approaches too.  Essentially the "code" is just an old-school UNIX `Makefile`, but beyond its history, it has some modern advantages:

* `make` is very good at maintaining a directory with all the needed files, so it downloads only when needed efficiently.
* By using [`.PHONY` targets](https://www.gnu.org/software/make/manual/html_node/Phony-Targets.html), and non-traditional target names, _`make`_ this approach act more "script-like" than a C/C++ build tool.
* `make` natively supports taking variables from **either** via `make` arguments or environment variables.  This is pretty handy to allow some code to support containerization and plain CLI usage
* As a "script interpreter", `make` (plus busybox tools) is significantly smaller "runtime" than Python/Node/etc.  Before loading the packages, the container image is ~13MB.

The disadvantage is that is complex to understand unless one is already familiar with `Makefile`. It's a dense ~200-page manual (see "GNU make manual" in [HTML](https://www.gnu.org/software/make/manual/make.html) or [PDF](https://www.gnu.org/software/make/manual/make.pdf)).
 But since `make` deals well with state and files, it saves a lot of `if [ -f routeros* ] ... fi` stuff it takes to do the same as here in `bash`...

After trying this, it does seem like a nifty trick in the bag to get a little more organization out of what is mainly some busybox and `/bin/sh` commands.  In particular, how it deals with variables from EITHER env or program args.  Anyway, worked well enough for me to write it up and share – both the tool and approach.

## `netinstall-cli` Flags Reference

```text
netinstall-cli [-r] [-e] [-b] [-m [-o]] [-f] [-v] [-c]
               [-k <keyfile>] [-s <userscript>] [-sm <modescript>]
               [--mac <mac>] {-i <interface> | -a <client-ip>} [PACKAGES...]
```

| Flag | Meaning |
| --- | --- |
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

## Unlicensing

This work is marked with CC0 1.0. To view a copy of this license, visit <https://creativecommons.org/publicdomain/zero/1.0/>
