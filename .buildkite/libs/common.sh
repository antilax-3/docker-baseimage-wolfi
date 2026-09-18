#!/usr/bin/env bash

# .buildkite/libs/common.sh
#
# Shared values and helpers for the pipeline generator, hooks and step scripts.
# Source with a BASH_SOURCE-relative path so it works regardless of CWD:
#   source "$(dirname "${BASH_SOURCE[0]}")/libs/common.sh"        # from .buildkite/
#   source "$(dirname "${BASH_SOURCE[0]}")/../libs/common.sh"     # from .buildkite/hooks/ and .buildkite/steps/
#
# The variables set here and by resolve_image() are read by the sourcing files, which shellcheck can't see when
# linting this file in isolation.
# shellcheck disable=SC2034

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GITHUB_REPOSITORY="antilax-3/docker-baseimage-wolfi"
DOCKER_REPOSITORY="antilax3/wolfi"
REGISTRY="docker.io"
# Platforms every image is built for, by the short name used in test step keys and labels.
# wolfi-base publishes linux/amd64 and linux/arm64 only, so this list cannot grow before the base image does.
PLATFORMS="amd64 arm64"

DOCKERFILE="${REPOSITORY_ROOT}/Dockerfile"
# Wolfi is a rolling distribution: it has no release number, the VERSION_ID in its os-release is the frozen constant
# 20230201, and Chainguard publishes no tag but latest. The base image digest pinned on the Dockerfile's FROM line is
# therefore what identifies which Wolfi an image was built from, and resolve_release() turns that digest's own build
# date into the version ladder.
WOLFI_DIGEST=$(sed -nE 's|^FROM cgr\.dev/chainguard/wolfi-base:latest@(sha256:[0-9a-f]{64})$|\1|p' "${DOCKERFILE}")
WOLFI_DIGEST_SHORT="${WOLFI_DIGEST:7:12}"

# Test jobs keyed "test-<platform>" get their platform from the step key, so steps don't each need it in env.
if [[ "${BUILDKITE_STEP_KEY:-}" == test-* ]]; then
  PLATFORM="${BUILDKITE_STEP_KEY#test-}"
fi

# Prints the Docker platform for a short platform name, e.g. arm64 -> linux/arm64.
docker_platform() {
  case "${1}" in
    amd64) echo "linux/amd64" ;;
    arm64) echo "linux/arm64" ;;
  esac
}

# Returns success for pushes to master, the only builds that publish the latest tag.
master() {
  [[ "${BUILDKITE_BRANCH}" == "master" ]] && [[ "${BUILDKITE_PULL_REQUEST}" == "false" ]]
}

# Makes a branch name safe to use in a Docker tag.
sanitize_tag() {
  echo "${1}" | sed -E 's/[^A-Za-z0-9_.-]+/-/g'
}

# Resolves the Wolfi release identity from the pinned base image. Wolfi ships no release number of its own, so the
# base image's build date - org.opencontainers.image.created, on the very manifest Renovate pins - is what versions
# this image: it is monotonic, and it moves only when the base does. Sets as globals:
#   WOLFI_CREATED - the base image's RFC 3339 build timestamp, e.g. 2026-09-16T12:50:30Z
#   WOLFI_RELEASE - that date as a tag, e.g. 2026.09.16
#   WOLFI_VERSION - its month, e.g. 2026.09
#   WOLFI_MAJOR   - its year, e.g. 2026
#
# The annotation is read from the registry rather than the image, so nothing is pulled. Lookups are retried as the
# platform digest lookups are. Returns non-zero if no valid date resolves; callers must treat that as fatal rather
# than publish a tag built from a missing value.
resolve_release() {
  local attempt created

  if [[ -n "${WOLFI_RELEASE:-}" ]]; then
    return 0
  fi

  for attempt in 1 2 3 4 5; do
    created=$(docker buildx imagetools inspect "cgr.dev/chainguard/wolfi-base@${WOLFI_DIGEST}" --raw 2> /dev/null | \
      jq -r '.annotations["org.opencontainers.image.created"] // empty')

    if [[ "${created}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
      WOLFI_CREATED="${created}"
      WOLFI_RELEASE=$(date -u -d "${created}" +"%Y.%m.%d")
      WOLFI_VERSION="${WOLFI_RELEASE%.*}"
      WOLFI_MAJOR="${WOLFI_RELEASE%%.*}"
      return 0
    fi

    [[ ${attempt} -lt 5 ]] && echo "Unable to resolve the build date of wolfi-base@${WOLFI_DIGEST}, retrying (${attempt}/5)" >&2 && sleep $((attempt * 5))
  done

  echo "Unable to resolve the build date of wolfi-base@${WOLFI_DIGEST}" >&2
  return 1
}

# Resolves the image details for the build. Sets as globals:
#   BUILD_TAG - the build-scoped tag, e.g. BK12, also used as the version label/build arg
#   IMAGE     - the fully qualified build-scoped image the test step pulls
#   TAGS      - the tags pushed for the build context:
#                 local branch -> <branch> with unsafe characters replaced, e.g. renovate/wolfi-base-digest ->
#                                 renovate-wolfi-base-digest
#                 fork PRs     -> PR<number> (Buildkite prefixes fork branch names with owner:)
#                 master       -> latest and the version ladder, e.g. latest 2026 2026.09 2026.09.16
#               and always BK<build>.
#
# The ladder is the base image's build date (see resolve_release), which stands in for the release number Wolfi does
# not have, so it moves when Renovate bumps the digest and is republished when only our own layer changes - the same
# behaviour the Alpine baseimage's 3/3.24/3.24.1 ladder has.
resolve_image() {
  BUILD_TAG="BK${BUILDKITE_BUILD_NUMBER}"
  IMAGE="${REGISTRY}/${DOCKER_REPOSITORY}:${BUILD_TAG}"
  TAGS=""

  if [[ "${BUILDKITE_BRANCH}" != "master" ]] && [[ ! "${BUILDKITE_BRANCH}" =~ .*:.* ]]; then
    TAGS="$(sanitize_tag "${BUILDKITE_BRANCH}")"
  elif [[ "${BUILDKITE_BRANCH}" =~ .*:.* ]]; then
    TAGS="PR${BUILDKITE_PULL_REQUEST}"
  elif master; then
    resolve_release || return 1
    TAGS="latest ${WOLFI_MAJOR} ${WOLFI_VERSION} ${WOLFI_RELEASE}"
  fi

  TAGS+=" ${BUILD_TAG}"
}

# Resolves IMAGE (see resolve_image) to the manifest for one platform. Sets as globals:
#   DOCKER_PLATFORM - the Docker platform, e.g. linux/arm64
#   PLATFORM_IMAGE  - IMAGE pinned to that platform's manifest digest; tests of different platforms can share a
#                     Docker daemon, and pulling the multi-platform tag for each would race over the local tag.
#
# The pre-command hook exports both, so the command and later hooks reuse them instead of querying the registry again.
# Registry lookups are retried, as Docker Hub intermittently fails token requests. Returns non-zero if no digest resolves.
#
# $1 - the short platform name, e.g. arm64
resolve_platform_image() {
  local attempt digest

  DOCKER_PLATFORM=$(docker_platform "${1}")

  if [[ "${PLATFORM_IMAGE:-}" == "${IMAGE%:*}@sha256:"* ]]; then
    return 0
  fi

  for attempt in 1 2 3 4 5; do
    digest=$(docker buildx imagetools inspect "${IMAGE}" --format '{{json .Manifest}}' | jq -r --arg platform "${DOCKER_PLATFORM}" \
      '.manifests[] | select((.platform.os + "/" + .platform.architecture + (if .platform.variant then "/" + .platform.variant else "" end)) == $platform) | .digest')

    if [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
      PLATFORM_IMAGE="${IMAGE%:*}@${digest}"
      return 0
    fi

    [[ ${attempt} -lt 5 ]] && echo "Unable to resolve the ${DOCKER_PLATFORM} digest of ${IMAGE}, retrying (${attempt}/5)" >&2 && sleep $((attempt * 5))
  done

  echo "Unable to resolve the ${DOCKER_PLATFORM} digest of ${IMAGE}" >&2
  PLATFORM_IMAGE=""
  return 1
}
