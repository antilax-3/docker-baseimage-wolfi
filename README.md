<p align="center">
  <a href="https://github.com/AntilaX-3/"><img src="https://avatars.githubusercontent.com/u/35715409" width="150" title="AntilaX-3"></a>
</p>

<p align="center">
  <a href="https://buildkite.com/antilax-3/wolfi"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/dynamic/json.svg?url=https%3A%2F%2Fimg.shields.io%2Fbuildkite%2F90b075de0ea7d9466d2deabf13a8d50f161a42d6f7d383f672%2Fmaster.json&query=%24.message&label=build&logo=buildkite&logoColor=%2314cc80&mode=dark&size=sm&variant=outline"><img alt="Build" src="https://shieldcn.dev/badge/dynamic/json.svg?url=https%3A%2F%2Fimg.shields.io%2Fbuildkite%2F90b075de0ea7d9466d2deabf13a8d50f161a42d6f7d383f672%2Fmaster.json&query=%24.message&label=build&logo=buildkite&logoColor=%2314cc80&mode=light&size=sm&variant=outline"></picture></a>
  <a href="https://hub.docker.com/r/antilax3/wolfi/tags"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/dynamic/json.svg?url=https%3A%2F%2Fimg.shields.io%2Fdocker%2Fimage-size%2Fantilax3%2Fwolfi%2Flatest.json&query=%24.message&label=image%20size&logo=docker&logoColor=%232496ed&mode=dark&size=sm&variant=outline"><img alt="Docker Size" src="https://shieldcn.dev/badge/dynamic/json.svg?url=https%3A%2F%2Fimg.shields.io%2Fdocker%2Fimage-size%2Fantilax3%2Fwolfi%2Flatest.json&query=%24.message&label=image%20size&logo=docker&logoColor=%232496ed&mode=light&size=sm&variant=outline"></picture></a>
  <a href="https://hub.docker.com/r/antilax3/wolfi"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/dynamic/json.svg?url=https%3A%2F%2Fimg.shields.io%2Fdocker%2Fpulls%2Fantilax3%2Fwolfi.json&query=%24.message&label=pulls&logo=docker&logoColor=%232496ed&mode=dark&size=sm&variant=outline"><img alt="Docker Pulls" src="https://shieldcn.dev/badge/dynamic/json.svg?url=https%3A%2F%2Fimg.shields.io%2Fdocker%2Fpulls%2Fantilax3%2Fwolfi.json&query=%24.message&label=pulls&logo=docker&logoColor=%232496ed&mode=light&size=sm&variant=outline"></picture></a>
</p>

### This base container is not aimed at public consumption. It exists to serve as a single endpoint for AntilaX-3 containers and is based upon [Wolfi](https://github.com/chainguard-dev/wolfi-base) and [S6 overlay](https://github.com/just-containers/s6-overlay), following the layout of our [Alpine baseimage](https://github.com/AntilaX-3/docker-baseimage-alpine).

## Differences from the Alpine baseimage

The s6-overlay layout, the `abc` user, the `PUID`/`PGID` handling and the `/app`, `/config` and `/defaults`
directories are identical. What Wolfi changes:

| | Alpine | Wolfi |
| --- | --- | --- |
| Platforms | `amd64`, `arm64`, `armv7` | `amd64`, `arm64`; `wolfi-base` publishes no others |
| libc | musl | glibc |
| Tags | `latest`, `3`, `3.24`, `3.24.1`, `BK<build>` | `latest`, `2026`, `2026.09`, `2026.09.16`, `BK<build>` |
| Base pin | `alpine:<release>@sha256:...` | `cgr.dev/chainguard/wolfi-base:latest@sha256:...` |
| Build deps | `curl`, `tar`, `xz` | `curl`; busybox provides `tar` and decompresses xz itself |
| `users` group | renumbered to gid 1000 | created at gid 1000; Wolfi ships no `users` group |

## Versioning

Wolfi is a rolling distribution with no release number of its own: the `VERSION_ID` in its `os-release` is the
frozen constant `20230201`, and Chainguard publishes no tag but `latest`. The version ladder is therefore the
**pinned base image's own build date**, read from `org.opencontainers.image.created` on the manifest Renovate pins:

```
2026.09.16   the base image this build used
2026.09      the newest build from that month
2026         the newest build from that year
latest       the newest build
BK<build>    immutable, one per Buildkite build
```

It behaves like the Alpine baseimage's `3`/`3.24`/`3.24.1`: the ladder advances when Renovate bumps the digest, and
is republished in place when only our own layer changes. `resolve_release()` in `.buildkite/libs/common.sh` reads the
annotation from the registry without pulling the image, retries, and fails the build rather than publish a tag built
from a missing value. The digest itself is also recorded on every image as `org.opencontainers.image.base.digest`
and asserted by the test suite, so a tag can always be traced back to an exact base.

Wolfi also ships no `getent`, so anything reading the account databases must read `/etc/passwd` and `/etc/group`
directly.

## Development

Linting runs locally through [lefthook](https://github.com/evilmartians/lefthook). Install the hooks once per clone:

```bash
lefthook install
```

`pre-commit` runs [editorconfig-checker](https://github.com/editorconfig-checker/editorconfig-checker),
[hadolint](https://github.com/hadolint/hadolint), `jq`, [shellcheck](https://github.com/koalaman/shellcheck),
[typos](https://github.com/crate-ci/typos) and [yamllint](https://github.com/adrienverge/yamllint) over the staged
files, and `commit-msg` enforces [Conventional Commits](https://www.conventionalcommits.org). Run everything on demand
with:

```bash
lefthook run pre-commit --all-files
```
