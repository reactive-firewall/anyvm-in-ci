# AnyVM in CI

Run CI steps inside a full VM (FreeBSD, OpenBSD, NetBSD, Solaris, Haiku, Ubuntu, etc.) using anyvm and QEMU. This GitHub Action provisions a nested VM on the runner, prepares the guest for CI (replicates the GitHub workspace, forwards selected GitHub environment variables and inputs, rotates ephemeral SSH keys), runs the requested commands inside the VM, and optionally copies artifacts back to the host.

Key goals
- Let you run CI steps inside non-Linux OSes (FreeBSD, OpenBSD, NetBSD, Solaris, Haiku, ...) on GitHub-hosted or self-hosted runners.
- Prepare the guest VM for CI pipelines autonomously by:
  - replicating the repository workspace into the guest,
  - forwarding non-sensitive GitHub environment variables into SSH sessions (with optional extensibility to all variables)
  - generating ephemeral SSH keys and atomically rotating guest authorized_keys away from per-baked keys,
  - optionally creating a non-root user that mirrors the GH host `runner` user (with unprivileged ephemeral keys),
  - providing auto-boxing of step run instructions for the guest VM
- Minimize host exposure (VNC is disabled in CI as default; SSH is limited to localhost).

Status
- (BADGES placeholder)

## Inputs

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `osname` | choice | yes | `freebsd` | Target VM OS name. Options: freebsd, ghostbsd, openbsd, netbsd, dragonflybsd, midnightbsd, solaris, omnios, openindiana, tribblix, haiku, ubuntu, blissos |
| `prepare` | string | no | — | Shell commands to run inside the VM before `run` (pre-run hook) |
| `run` | string | no | — | CI command(s) to run inside the VM |
| `afterwards` | string | no | — | Shell commands to run inside the VM after `run` (post-run hook) |
| `release` | string | no | _latest supported by anyvm_ | OS release/version of the VM image (passed to anyvm) |
| `arch` | choice | no | null | VM CPU architecture. Options: `x86_64`, `aarch64`, `riscv64`, `s390x`, `powerpc64`, `ppc64le`, `sparc64` |
| `envs` | string | no | — | Extra environment variables to forward to the VM (newline-separated KEY=VALUE pairs or names to forward via SSH SendEnv as configured) |
| `mem` | number | no | `3072` | Memory (MB) for the VM. Note: entrypoint.sh has a different fallback default (6144) — see implementation notes. |
| `cpu` | number | no | `autodetect` | Number of CPU cores for the VM |
| `nat` | string | no | — | NAT port forwarding rules (passed to anyvm) |
| `usesh` | boolean | no | `true` | Use `sh` as the default shell in the VM |
| `sync` | choice | no | `scp` | Strategy for synchronizing the workspace to/from the VM. Options: `rsync`, `scp` |
| `copyback` | boolean | no | `true` | Copy build artifacts back from VM to host when done |
| `drop-root` | boolean | no | `true` | Create a runner-style unprivileged user on the VM instead of using `root` for CI steps |
| `data-dir` | string | no | `'data'` | Directory inside cache to store VM images and data |
| `cache-dir` | string | no | `~/Library/Caches/anyvm-in-ci` | Cache location used by the action |
| `sync-time` | boolean | no | `false` | Synchronize VM time with NTP |
| `disable-cache` | boolean | no | `false` | Disable local caching for packages and VM images |
| `custom-shell-name` | string | no | `'vmsh'` | Name for the generated wrapper script that runs commands inside the VM |
| `ipv6-enabled` | boolean | no | `false` | Enable IPv6 networking mode inside the guest |
| `token` | string | Optional (required for GHES) | `github.token` or null | Token for GitHub API operations, including when fetching anyvm builders when required (defaults to `github.token` on github.com) |

## Outputs

- This action currently defines no outputs.

## Minimal example

This minimal workflow runs a single command inside a FreeBSD guest:

```yaml
name: CI (FreeBSD)
on: [push]

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v7
      - name: Run inside FreeBSD VM
        uses: reactive-firewall/anyvm-in-ci@v1
        with:
          osname: freebsd
          run: |
            uname -a
            sudo pkg info
```
