ARCH ?= arm
PKGS ?= wifi-qcom-ac
CHANNEL ?= stable
OPTS ?= -b -r
IFACE ?= eth0
# PKGS_CUSTOM ?= ""
# example: CLIENTIP ?= 172.17.9.101
NET_OPTS ?= $(if $(CLIENTIP),-a $(CLIENTIP),-i $(IFACE))
URLVER ?= https://upgrade.mikrotik.com/routeros/NEWESTa7
channel_ver = $(firstword $(shell for _i in 1 2 3 4 5; do _v=$$(wget -q -O - $(URLVER).$(1)) && [ -n "$$_v" ] && echo "$$_v" && break; sleep 2; done))
ver_ge = $(shell echo '$(1) $(2)' | awk -F'[. ]' '{if($$1>$$3||$$1==$$3&&$$2>=$$4)print 1}')
ifndef VER
VER := $(call channel_ver,$(CHANNEL))
endif
ifndef VER_NETINSTALL
VER_NETINSTALL := $(call channel_ver,$(CHANNEL))
endif
DLDIR ?= downloads
ROUTEROS_FILES := $(foreach arch,$(ARCH),$(DLDIR)/routeros-$(VER)-$(arch).npk)
PKGS_FILES := $(foreach arch,$(ARCH),$(foreach pkg,$(PKGS),$(DLDIR)/$(pkg)-$(VER)-$(arch).npk))
ALL_PACKAGES_ZIPS := $(foreach arch,$(ARCH),$(DLDIR)/all_packages-$(arch)-$(VER).zip)

# Auto-set modescript for container/zerotier packages on netinstall >= 7.22
MODESCRIPT ?= $(if $(and $(or $(findstring container,$(PKGS)),$(findstring zerotier,$(PKGS))),$(call ver_ge,$(VER_NETINSTALL),7.22)),/system/device-mode update mode=advanced container=yes zerotier=yes)

PLATFORM ?= $(shell uname -m)
OS ?= $(shell uname -s)

# Auto-detect qemu-i386 for non-x86_64 platforms
# Priority: ./i386 (container), qemu-i386-static (Debian/Ubuntu), qemu-i386 (Alpine/Fedora)
find_qemu = $(firstword $(foreach q,./i386 qemu-i386-static qemu-i386,$(if $(shell if [ -x "$(q)" ] || command -v $(q) >/dev/null 2>&1; then echo y; fi),$(q))))
ifndef QEMU
QEMU := $(call find_qemu)
endif

CHANNELS := stable long-term testing development
ARCHS := arm arm64 mipsbe mmips smips ppc tile x86

.PHONY: run all service download clean nothing dump $(CHANNELS) $(ARCHS)
.PHONY: image image-all image-platform image-push image-clean vm-run
.SUFFIXES:

run: all
	$(eval PKGS_FILES := $(shell for file in $(PKGS_FILES); do if [ -e "$$file" ]; then echo "$$file"; fi; done))
ifeq ($(OS),Darwin)
	@if [ -z "$(QEMU_SYSTEM)" ]; then \
	  echo "Error: qemu-system-x86_64 required on macOS." >&2; \
	  echo "  Install: brew install qemu" >&2; \
	  exit 1; \
	fi
	$(MAKE) vm-run VM_TARGET=run VER=$(VER) VER_NETINSTALL=$(VER_NETINSTALL) \
	  "ARCH=$(ARCH)" "PKGS=$(PKGS)" "OPTS=$(OPTS)" 'MODESCRIPT=$(MODESCRIPT)'
else
	@if [ "$(PLATFORM)" != "x86_64" ] && [ -z "$(QEMU)" ]; then \
	  echo "Error: qemu-i386 not found. Required to run netinstall-cli on $(PLATFORM)." >&2; \
	  echo "  Debian/Ubuntu: sudo apt install qemu-user-static" >&2; \
	  echo "  Alpine:        apk add qemu-i386" >&2; \
	  echo "  Fedora:        sudo dnf install qemu-user-static" >&2; \
	  echo "  Or: make run QEMU=/path/to/qemu-i386" >&2; \
	  exit 1; \
	fi
	@echo starting netinstall... PLATFORM=$(PLATFORM) ARCH=$(ARCH) VER=$(VER) OPTS="$(OPTS)" NET_OPTS="$(NET_OPTS)" PKGS=$(PKGS) $(if $(MODESCRIPT),MODESCRIPT="$(MODESCRIPT)")
	@echo using $(PKGS_FILES)
	$(if $(MODESCRIPT),@printf '%s\n' '$(MODESCRIPT)' > .modescript.rsc)
	$(if $(findstring x86_64, $(PLATFORM)), , $(QEMU)) $(DLDIR)/netinstall-cli-$(VER_NETINSTALL) $(OPTS) $(NET_OPTS) $(if $(MODESCRIPT),-sm .modescript.rsc) $(ROUTEROS_FILES) $(PKGS_FILES) $(PKGS_CUSTOM)
endif

service: all
ifeq ($(OS),Darwin)
	@if [ -z "$(QEMU_SYSTEM)" ]; then \
	  echo "Error: qemu-system-x86_64 required on macOS." >&2; \
	  echo "  Install: brew install qemu" >&2; \
	  exit 1; \
	fi
	$(MAKE) vm-run VM_TARGET=service VER=$(VER) VER_NETINSTALL=$(VER_NETINSTALL) \
	  "ARCH=$(ARCH)" "PKGS=$(PKGS)" "OPTS=$(OPTS)" 'MODESCRIPT=$(MODESCRIPT)'
else
	while :; do $(MAKE) run "ARCH=$(ARCH)" VER=$(VER) 'MODESCRIPT=$(MODESCRIPT)'; done
endif

download: all
	@echo use 'make' to run netinstall after connecting $(IFACE) or $(CLIENTIP) to router

all: $(ROUTEROS_FILES) $(DLDIR)/netinstall-cli-$(VER_NETINSTALL) $(ALL_PACKAGES_ZIPS)
	@echo finished download ARCH=$(ARCH) VER=$(VER) PKGS=$(PKGS) PLATFORM=$(PLATFORM)

dump:
	@echo ARCH=$(ARCH) VER=$(VER) CHANNEL=$(CHANNEL) PLATFORM=$(PLATFORM) OS=$(OS) QEMU=$(QEMU) QEMU_SYSTEM=$(QEMU_SYSTEM) $(if $(MODESCRIPT),MODESCRIPT="$(MODESCRIPT)")

clean:
	rm -rf $(DLDIR) images .image-build .vm-build .modescript.rsc .vm-cmd.sh

$(DLDIR)/netinstall-$(VER_NETINSTALL).tar.gz:
	mkdir -p $(DLDIR)
	wget -O $@ https://download.mikrotik.com/routeros/$(VER_NETINSTALL)/netinstall-$(VER_NETINSTALL).tar.gz

$(DLDIR)/netinstall-cli-$(VER_NETINSTALL): $(DLDIR)/netinstall-$(VER_NETINSTALL).tar.gz
	tar zxvf $< -C $(DLDIR)
	mv $(DLDIR)/netinstall-cli $(DLDIR)/netinstall-cli-$(VER_NETINSTALL)
	touch $@

$(DLDIR)/routeros-$(VER)-%.npk:
	mkdir -p $(DLDIR)
	wget -O $@ https://download.mikrotik.com/routeros/$(VER)/$(@F)

$(DLDIR)/all_packages-%-$(VER).zip:
	mkdir -p $(DLDIR)
	wget -O $@ https://download.mikrotik.com/routeros/$(VER)/$(@F)
	unzip -o -d $(DLDIR) $@

$(CHANNELS):
	$(if $(filter $(ARCHS),$(MAKECMDGOALS)),@:,$(MAKE) $(filter-out $(CHANNELS),$(MAKECMDGOALS)) CHANNEL=$@ ARCH=$(ARCH))

$(ARCHS):
	$(MAKE) $(filter-out $(CHANNELS) $(ARCHS),$(MAKECMDGOALS)) CHANNEL=$(or $(filter $(CHANNELS),$(MAKECMDGOALS)),$(CHANNEL)) ARCH=$@

# --- OCI image building (requires: crane, wget) ---
IMAGE ?= tikoci/netinstall
IMAGE_TAG ?= latest
IMAGE_PLATFORMS ?= linux/arm64 linux/arm/v7 linux/amd64
ALPINE_MIRROR ?= https://dl-cdn.alpinelinux.org/alpine/latest-stable/main
BINFMT_IMAGE ?= tonistiigi/binfmt:latest

image image-all:
	@for plat in $(IMAGE_PLATFORMS); do \
	  $(MAKE) image-platform "IMAGE_PLATFORM=$$plat"; \
	done

image-platform:
	@set -e; \
	plat="$(IMAGE_PLATFORM)"; \
	case "$$plat" in \
	  linux/arm64)  apk_arch=aarch64; cfg_arch=arm64; need_qemu=1 ;; \
	  linux/arm/v7) apk_arch=armv7;   cfg_arch=arm;   need_qemu=1 ;; \
	  linux/amd64)  apk_arch=x86_64;  cfg_arch=amd64; need_qemu=0 ;; \
	  *) echo "Unsupported: $$plat" >&2; exit 1 ;; \
	esac; \
	ptag=$$(echo "$$plat" | tr '/' '-'); \
	output="images/netinstall-$$ptag.tar"; \
	echo "Building $$output"; \
	rm -rf .image-build; \
	mkdir -p .image-build/rootfs/app .image-build/image images; \
	echo "  alpine rootfs ($$plat)"; \
	crane export --platform "$$plat" alpine:latest - | tar xf - -C .image-build/rootfs; \
	while read -r _bpath; do \
	  mkdir -p ".image-build/rootfs/$$(dirname "$$_bpath")"; \
	  ln -sf /bin/busybox ".image-build/rootfs/$$_bpath"; \
	done < .image-build/rootfs/etc/busybox-paths.d/busybox; \
	wget -q "$(ALPINE_MIRROR)/$$apk_arch/APKINDEX.tar.gz" -O .image-build/apkindex.tar.gz; \
	tar xzf .image-build/apkindex.tar.gz -C .image-build APKINDEX; \
	make_ver=$$(awk '/^P:make$$/{f=1} f&&/^V:/{print substr($$0,3);exit}' .image-build/APKINDEX); \
	echo "  make $$make_ver ($$apk_arch)"; \
	wget -q "$(ALPINE_MIRROR)/$$apk_arch/make-$${make_ver}.apk" -O .image-build/make.apk; \
	tar xzf .image-build/make.apk -C .image-build/rootfs usr/bin/make; \
	chmod +x .image-build/rootfs/usr/bin/make; \
	if [ "$$need_qemu" = "1" ]; then \
	  echo "  qemu-i386 from $(BINFMT_IMAGE) ($$plat)"; \
	  crane export --platform "$$plat" $(BINFMT_IMAGE) - | \
	    tar xf - -C .image-build usr/bin/qemu-i386; \
	  mv .image-build/usr/bin/qemu-i386 .image-build/rootfs/app/i386; \
	  chmod +x .image-build/rootfs/app/i386; \
	fi; \
	cp Makefile .image-build/rootfs/app/Makefile; \
	echo "  creating layer"; \
	tar cf .image-build/image/layer.tar -C .image-build/rootfs .; \
	_digest=$$( ( shasum -a 256 .image-build/image/layer.tar 2>/dev/null || \
	  sha256sum .image-build/image/layer.tar ) | cut -d' ' -f1); \
	printf '{"architecture":"%s","os":"linux","config":{"WorkingDir":"/app","Cmd":["make","service"]},"rootfs":{"type":"layers","diff_ids":["sha256:%s"]}}' \
	  "$$cfg_arch" "$$_digest" > .image-build/image/config.json; \
	printf '[{"Config":"config.json","RepoTags":["$(IMAGE):$(IMAGE_TAG)"],"Layers":["layer.tar"]}]' \
	  > .image-build/image/manifest.json; \
	tar cf "$$output" -C .image-build/image config.json manifest.json layer.tar; \
	rm -rf .image-build; \
	echo "Built: $$output"

image-push:
	@for plat in $(IMAGE_PLATFORMS); do \
	  ptag=$$(echo "$$plat" | tr '/' '-'); \
	  crane push "images/netinstall-$$ptag.tar" "$(IMAGE):$$ptag"; \
	  crane mutate --workdir /app --cmd "make,service" "$(IMAGE):$$ptag"; \
	done
	crane index append \
	  -t "$(IMAGE):$(IMAGE_TAG)" \
	  $(foreach p,$(IMAGE_PLATFORMS),-m "$(IMAGE):$(subst /,-,$(p))")

image-clean:
	rm -rf images .image-build

# --- VM support for macOS (qemu-system-x86_64 with vmnet-bridged) ---
# On macOS, netinstall-cli (Linux ELF) cannot run natively. Instead, boot a
# lightweight QEMU VM with the Alpine rootfs from the amd64 OCI image,
# share the working directory via 9p, and bridge networking via vmnet.
QEMU_SYSTEM ?= $(shell command -v qemu-system-x86_64 2>/dev/null)
VMLINUZ ?= $(DLDIR)/vmlinuz-virt
VM_INITRAMFS ?= $(DLDIR)/initramfs-netinstall.gz
VM_TARGET ?= run

# Auto-build amd64 OCI image if needed (provides Alpine rootfs for VM)
images/netinstall-linux-amd64.tar:
	$(MAKE) image-platform IMAGE_PLATFORM=linux/amd64

# Build vmlinuz + initramfs from linux-virt APK and OCI image.
# Single APK provides matched kernel + all modules (including 9p for virtfs).
$(VMLINUZ) $(VM_INITRAMFS): images/netinstall-linux-amd64.tar
	@set -e; \
	echo "Building VM kernel + initramfs..."; \
	rm -rf .vm-build; mkdir -p .vm-build/rootfs $(DLDIR); \
	tar xf $< -C .vm-build layer.tar; \
	tar xf .vm-build/layer.tar -C .vm-build/rootfs; \
	echo "  resolving linux-virt version"; \
	wget -q "$(ALPINE_MIRROR)/x86_64/APKINDEX.tar.gz" -O .vm-build/apkindex.tar.gz; \
	tar xzf .vm-build/apkindex.tar.gz -C .vm-build APKINDEX; \
	kvirt=$$(awk '/^P:linux-virt$$/{f=1} f&&/^V:/{print substr($$0,3);exit}' .vm-build/APKINDEX); \
	echo "  linux-virt $$kvirt"; \
	wget -q "$(ALPINE_MIRROR)/x86_64/linux-virt-$${kvirt}.apk" -O .vm-build/linux-virt.apk; \
	tar xzf .vm-build/linux-virt.apk -C .vm-build boot/vmlinuz-virt; \
	cp .vm-build/boot/vmlinuz-virt $(VMLINUZ); \
	echo "  extracting kernel modules"; \
	kver=$$(tar tzf .vm-build/linux-virt.apk | sed -n 's|^lib/modules/\([^/]*\)/.*|\1|p' | head -1); \
	tar xzf .vm-build/linux-virt.apk -C .vm-build/rootfs \
	  "lib/modules/$$kver/kernel/drivers/virtio/" \
	  "lib/modules/$$kver/kernel/drivers/net/virtio_net.ko.gz" \
	  "lib/modules/$$kver/kernel/drivers/net/net_failover.ko.gz" \
	  "lib/modules/$$kver/kernel/net/core/failover.ko.gz" \
	  "lib/modules/$$kver/kernel/net/9p/" \
	  "lib/modules/$$kver/kernel/fs/9p/" \
	  "lib/modules/$$kver/kernel/fs/netfs/" 2>/dev/null || true; \
	find .vm-build/rootfs/lib/modules -name '*.ko.gz' -exec gunzip {} \; 2>/dev/null; \
	echo "  creating init"; \
	printf '%s\n' '#!/bin/sh' \
	  'mount -t proc none /proc' \
	  'mount -t sysfs none /sys' \
	  'mount -t devtmpfs none /dev' \
	  'kmod=/lib/modules/$$(uname -r)/kernel' \
	  'insmod $$kmod/drivers/virtio/virtio.ko 2>/dev/null' \
	  'insmod $$kmod/drivers/virtio/virtio_ring.ko 2>/dev/null' \
	  'insmod $$kmod/drivers/virtio/virtio_pci.ko 2>/dev/null' \
	  'insmod $$kmod/net/core/failover.ko 2>/dev/null' \
	  'insmod $$kmod/drivers/net/net_failover.ko 2>/dev/null' \
	  'insmod $$kmod/drivers/net/virtio_net.ko' \
	  'insmod $$kmod/fs/netfs/netfs.ko 2>/dev/null' \
	  'insmod $$kmod/net/9p/9pnet.ko' \
	  'insmod $$kmod/net/9p/9pnet_virtio.ko' \
	  'insmod $$kmod/fs/9p/9p.ko' \
	  'mkdir -p /host' \
	  'mount -t 9p -o trans=virtio,version=9p2000.L hostfs /host' \
	  'ip link set eth0 up' \
	  'ip addr add 169.254.1.1/16 dev eth0' \
	  'sh /host/.vm-cmd.sh' \
	  'poweroff -f' > .vm-build/rootfs/init; \
	chmod +x .vm-build/rootfs/init; \
	( cd .vm-build/rootfs && find . | cpio -o -H newc 2>/dev/null | gzip > ../../$(VM_INITRAMFS) ); \
	rm -rf .vm-build; \
	echo "Built: $(VMLINUZ) $(VM_INITRAMFS)"

# Boot QEMU VM with vmnet-bridged networking to run netinstall-cli
# IFACE = macOS interface to bridge to (e.g. en5); inside VM it becomes eth0
# Requires: brew install qemu, sudo for vmnet-bridged
vm-run: all $(VMLINUZ) $(VM_INITRAMFS)
	$(eval PKGS_FILES := $(shell for file in $(PKGS_FILES); do if [ -e "$$file" ]; then echo "$$file"; fi; done))
	@printf '%s\n' '#!/bin/sh' 'cd /host' \
	  'exec make $(VM_TARGET) IFACE=eth0 OS=Linux PLATFORM=x86_64 QEMU= VER=$(VER) VER_NETINSTALL=$(VER_NETINSTALL) "ARCH=$(ARCH)" "PKGS=$(PKGS)" "OPTS=$(OPTS)" $(if $(MODESCRIPT),"MODESCRIPT=$(MODESCRIPT)")' \
	  > .vm-cmd.sh
	@echo "Starting QEMU VM ($(VM_TARGET)) bridged to $(IFACE)..."
	sudo $(QEMU_SYSTEM) \
	  -m 256M \
	  -kernel $(VMLINUZ) \
	  -initrd $(VM_INITRAMFS) \
	  -append "console=ttyS0 quiet" \
	  -virtfs local,path=.,mount_tag=hostfs,security_model=none \
	  -netdev vmnet-bridged,id=n0,ifname=$(IFACE) \
	  -device virtio-net-pci,netdev=n0 \
	  -nographic \
	  -no-reboot
	@rm -f .vm-cmd.sh

nothing:
	while :; do sleep 3600; done
