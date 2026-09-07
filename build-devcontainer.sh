#!/usr/bin/env bash
# Build script for devcontainer-nvim images
# Supports variants: clang, clang-tsan, clang++ (alias for clang with CXX default)

set -e

SCRIPT_DIR="$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/../../..")"

# Load settings from settings.env if available
SETTINGS_FILE="${DEVCONTAINER_SETTINGS_FILE:-$SCRIPT_DIR/settings.env}"
if [ -f "$SETTINGS_FILE" ]; then
    # shellcheck source=/dev/null
    source "$SETTINGS_FILE"
fi

# Determine toolchain architecture if not already defined in settings.env
if [ -z "$TOOLCHAIN_ARCH" ]; then
    ARCH="$(uname -m)"
    case "${ARCH}" in
        aarch64|arm64)
            TOOLCHAIN_ARCH="aarch64"
            ;;
        x86_64|amd64)
            TOOLCHAIN_ARCH="x86_64"
            ;;
        *)
            echo "Unknown architecture: ${ARCH}" >&2
            exit 1
            ;;
    esac
fi

REGISTRY="${REGISTRY:-registry.example.com/toolchain/trixie/${TOOLCHAIN_ARCH}}"

show_help() {
    cat <<EOF
Usage: $(basename "$0") [VARIANT] [OPTIONS]

Builds the devcontainer Docker image for Neovim development.

Variants:
  clang        Base clang toolchain image (default)
  clang-tsan   TSan-instrumented clang toolchain image
  clang++      Clang C++ variant (builds with base clang toolchain, tagged clangpp)
  all          Build all variants

Options:
  --no-cache   Build Docker image without cache
  --verbose    Enable bash tracing (set -x)
  -h, --help   Show this help message
EOF
}

build_variant() {
    local variant="$1"
    local no_cache_flag="$2"
    local base_image=""
    local tag_name=""

    case "$variant" in
        clang)
            base_image="${BASE_IMAGE:-${BASE_IMAGE_CLANG:-${REGISTRY}/clang-22.1.8/main}}"
            tag_name="${IMAGE_TAG_CLANG:-devcontainer-nvim:clang}"
            ;;
        clang-tsan)
            base_image="${BASE_IMAGE:-${BASE_IMAGE_CLANG_TSAN:-${REGISTRY}/clang-22.1.8-tsan/main}}"
            tag_name="${IMAGE_TAG_CLANG_TSAN:-devcontainer-nvim:clang-tsan}"
            ;;
        clang++|clangpp)
            base_image="${BASE_IMAGE:-${BASE_IMAGE_CLANGPP:-${REGISTRY}/clang-22.1.8/main}}"
            tag_name="${IMAGE_TAG_CLANGPP:-devcontainer-nvim:clangpp}"
            ;;
        *)
            echo "Unknown variant: $variant" >&2
            exit 1
            ;;
    esac

    echo "============================================================"
    echo "Building devcontainer image: ${tag_name}"
    echo "Base toolchain image:        ${base_image}"
    echo "Architecture:                ${TOOLCHAIN_ARCH}"
    echo "============================================================"

    # shellcheck disable=SC2086
    docker build \
        ${no_cache_flag} \
        --build-arg BASE_IMAGE="${base_image}" \
        -t "${tag_name}" \
        -f "${SCRIPT_DIR}/Dockerfile" \
        "${SCRIPT_DIR}"

    echo "Successfully built ${tag_name}"
}

VARIANT="${DEFAULT_CONTAINER_VARIANT:-clang}"
NO_CACHE=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        --verbose)
            set -x
            shift
            ;;
        clang|clang-tsan|clang++|clangpp|all)
            VARIANT="$1"
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

if [ "$VARIANT" = "all" ]; then
    build_variant "clang" "$NO_CACHE"
    build_variant "clang-tsan" "$NO_CACHE"
    build_variant "clang++" "$NO_CACHE"
else
    build_variant "$VARIANT" "$NO_CACHE"
fi
