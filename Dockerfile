# syntax=docker/dockerfile:1
FROM cgr.dev/chainguard/wolfi-base:latest@sha256:9c2092b053779e14c82fb50f77b37bcc38b7d2c83972352d5813280f9d035b03

# set version labels
ARG build_date
ARG version
LABEL build_date="${build_date}"
LABEL version="${version}"
LABEL maintainer="Nightah"

# set version for s6 overlay
# renovate: datasource=github-releases depName=just-containers/s6-overlay
ARG OVERLAY_VERSION="3.2.3.2"

# environment variables
ENV PS1="$(whoami)@$(hostname):$(pwd)$ " \
HOME="/root" \
S6_CMD_WAIT_FOR_SERVICES_MAXTIME="0" \
TERM="xterm"

SHELL ["/bin/ash", "-euo", "pipefail", "-c"]

RUN <<'EOF'
set -euo pipefail

echo "**** install build packages ****"
# Wolfi has no tar package; busybox provides tar and decompresses xz itself, so neither is installed.
apk add --no-cache --virtual=build-dependencies \
  curl

echo "**** install runtime packages ****"
# wget and netcat-openbsd restore two applets Wolfi's busybox build drops but Alpine's ships; downstream healthchecks
# expect them, and curl is purged below with the build dependencies.
apk add --no-cache \
  bash \
  ca-certificates \
  coreutils \
  netcat-openbsd \
  shadow \
  tzdata \
  wget

echo "**** add s6 overlay ****"
OVERLAY_ARCH=$(apk --print-arch)
curl -sSfL -o /tmp/s6-overlay-noarch.tar.xz "https://github.com/just-containers/s6-overlay/releases/download/v${OVERLAY_VERSION}/s6-overlay-noarch.tar.xz"
curl -sSfL -o /tmp/s6-overlay.tar.xz "https://github.com/just-containers/s6-overlay/releases/download/v${OVERLAY_VERSION}/s6-overlay-${OVERLAY_ARCH}.tar.xz"
tar -C / -Jpxf /tmp/s6-overlay-noarch.tar.xz
tar -C / -Jpxf /tmp/s6-overlay.tar.xz

echo "**** create abc user and make our folders ****"
# Wolfi ships no users group, so it is created rather than renumbered. useradd warns that uid 911 sits below Wolfi's
# UID_MIN of 1000; the account is still created with that uid, which the test suite asserts.
groupadd -g 1000 users
useradd -u 911 -U -d /config -s /bin/false abc
usermod -G users abc
mkdir -p \
  /app \
  /config \
  /defaults

echo "**** cleanup ****"
apk del --purge \
  build-dependencies
rm -rf \
  /tmp/*
EOF

# add local files
COPY --link root/ /

ENTRYPOINT ["/init"]
