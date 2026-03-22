---
description: "Use when editing Dockerfile or OCI image build logic — covers the two-stage build, QEMU requirement, and single-layer constraint for RouterOS containers."
applyTo: "**/Dockerfile"
---
# Dockerfile & OCI Image Conventions

## Dockerfile (docker build)

- Two-stage build: **Debian** stage extracts `qemu-i386-static`, **Alpine** runtime stage
- `netinstall-cli` is always an x86 Linux ELF binary — QEMU is non-negotiable on ARM/ARM64 hosts
- Container default entrypoint: `make service` (continuous netinstall loop)
- The Dockerfile is kept for compatibility with Docker users; CI and primary builds use `make image` (crane). If `make image` changes, the Dockerfile should be updated to match.

## OCI Images (make image / crane)

- `make image` builds without Docker using `crane` to export Alpine base layers
- **Single-layer Docker v1 tar** — RouterOS's container loader requires this format
- **No gzip compression** — RouterOS cannot decompress gzipped layers
- Busybox symlinks must be created manually from `etc/busybox-paths.d/busybox` (crane export doesn't create them)
- `qemu-i386` binary comes from `tonistiigi/binfmt` image (note: binary name is `qemu-i386`, not `qemu-i386-static`)

## Architecture Mapping

RouterOS arch → Docker platform:
- `arm` → `linux/arm/v7`
- `arm64` → `linux/arm64`
- `x86` → `linux/amd64`
