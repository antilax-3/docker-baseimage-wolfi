#!/usr/bin/env bash
# BUILD_TAG, PLATFORMS and the other shared values are set in libs/common.sh, which shellcheck can't follow.
# shellcheck disable=SC2153
set -euo pipefail

: "${BUILDKITE_BRANCH:?must be set, e.g. BUILDKITE_BRANCH=master}"
: "${BUILDKITE_BUILD_NUMBER:?must be set, e.g. BUILDKITE_BUILD_NUMBER=1}"
: "${BUILDKITE_COMMIT:?must be set, e.g. BUILDKITE_COMMIT=\$(git rev-parse HEAD)}"
: "${BUILDKITE_PULL_REQUEST:?must be set, e.g. BUILDKITE_PULL_REQUEST=false}"

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/libs/common.sh"

BUILD_DATE=$(date +"%B-%d-%Y-%H:%M:%S-%Z")
CREATED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BUILDTAGS=""
BUILDPLATFORMS=""

resolve_release
resolve_image

for TAG in ${TAGS}; do BUILDTAGS+="-t ${REGISTRY}/${DOCKER_REPOSITORY}:${TAG} "; done
for PLATFORM in ${PLATFORMS}; do BUILDPLATFORMS+="$(docker_platform "${PLATFORM}"),"; done

cat << EOF
steps:
  - group: ":wolf: Wolfi ${WOLFI_RELEASE}"
    steps:
      - label: ":docker: Build and Deploy [${WOLFI_RELEASE}]"
        command: "docker build ${BUILDTAGS::-1} --build-arg build_date=\"${BUILD_DATE}\" --build-arg version=\"${BUILD_TAG}\" --label org.opencontainers.image.base.digest=\"${WOLFI_DIGEST}\" --label org.opencontainers.image.base.name=\"cgr.dev/chainguard/wolfi-base:latest\" --label org.opencontainers.image.created=\"${CREATED}\" --label org.opencontainers.image.revision=\"${BUILDKITE_COMMIT}\" --label org.opencontainers.image.source=\"https://github.com/${GITHUB_REPOSITORY}\" --label org.opencontainers.image.version=\"${BUILD_TAG}\" --platform ${BUILDPLATFORMS::-1} --provenance mode=max,reproducible=true --sbom true --builder buildx --progress plain --pull --no-cache --push ."
EOF
if master; then
cat << EOF
        concurrency: 1
        concurrency_group: "antilax3-wolfi-deployments"
EOF
fi
cat << EOF
        agents:
          upload: "fast"
        key: "build"
EOF

for PLATFORM in ${PLATFORMS}; do
cat << EOF

      - label: ":test_tube: Test Image [${WOLFI_RELEASE}] [${PLATFORM}]"
        command: ".buildkite/steps/test.sh"
        depends_on:
          - "build"
        key: "test-${PLATFORM}"
EOF
done

cat << EOF

  - label: ":docker: Update README.md"
    command: "curl -fsS \"https://ci.nerv.com.au/readmesync/update?github_repo=${GITHUB_REPOSITORY}&dockerhub_repo=${DOCKER_REPOSITORY}\""
    agents:
      upload: "fast"
    if: build.branch == "master"
EOF
