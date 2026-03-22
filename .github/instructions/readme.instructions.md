---
description: "Use when editing README.md — covers DockerHub/GHCR publishing constraints and content conventions for this project."
applyTo: "**/README.md"
---
# README.md Conventions

## Publishing Context

`README.md` is published to two registries by CI (`repo-as-web.yaml`):

- **DockerHub** (`ammo74/netinstall`) — via `peter-evans/dockerhub-description` action
- **GHCR** (`ghcr.io/tikoci/netinstall`) — as the repository's package page

## DockerHub Length Limit

DockerHub truncates the full description (README) at **25,000 characters**.  The current README exceeds this limit and will be truncated on DockerHub.

- Keep total README size below 25,000 characters if possible
- When adding new sections, consider removing or condensing lower-priority content to stay under the limit
- GitHub rendering is unaffected — only the DockerHub display is truncated
- Run `wc -c README.md` to check current size

## Short Description

The DockerHub short description is hardcoded in the workflow:

```yaml
short-description: "RouterOS /container for running netinstall to flash MikroTik devices on ARM/ARM64/X86"
```

DockerHub short description limit is **100 characters**.  Update that string in `.github/workflows/build-and-push.yaml` if the project description changes — it is not derived from README.md.
