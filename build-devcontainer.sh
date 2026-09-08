#!/usr/bin/env bash
# Build script for devcontainer-nvim images
# Supports variants configured in settings.env (VARIANTS array)

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

# Fallback defaults for VARIANTS if not configured in settings.env
if [ -z "${VARIANTS+x}" ] || [ ${#VARIANTS[@]} -eq 0 ]; then
    VARIANTS=(
        "clang|${BASE_IMAGE_CLANG:-${REGISTRY}/clang-22.1.8/main}|${IMAGE_TAG_CLANG:-devcontainer-nvim:clang}|clang|clang++"
        "clang-tsan|${BASE_IMAGE_CLANG_TSAN:-${REGISTRY}/clang-22.1.8-tsan/main}|${IMAGE_TAG_CLANG_TSAN:-devcontainer-nvim:clang-tsan}|clang|clang++"
        "gcc|${BASE_IMAGE_GCC:-${REGISTRY}/gcc-15.3.0/main}|${IMAGE_TAG_GCC:-devcontainer-nvim:gcc}|gcc|g++"
    )
fi

# Helper to parse a variant entry
# Sets: PARSED_VARIANT_NAME, PARSED_VARIANT_BASE, PARSED_VARIANT_TAG, PARSED_VARIANT_CC, PARSED_VARIANT_CXX
parse_variant_entry() {
    local entry="$1"
    local name="" base="" tag="" cc="" cxx=""

    if [[ "$entry" == *"|"* ]]; then
        IFS="|" read -r name base tag cc cxx <<< "$entry"
    elif [[ "$entry" == *:* ]]; then
        name="${entry%%:*}"
        base="${entry#*:}"
    else
        name="$entry"
    fi

    # Trim leading/trailing whitespace
    name="$(echo -n "$name" | xargs)"
    base="$(echo -n "$base" | xargs)"
    tag="$(echo -n "$tag" | xargs)"
    cc="$(echo -n "$cc" | xargs)"
    cxx="$(echo -n "$cxx" | xargs)"

    # Base image fallback (with global override support)
    if [ -n "$BASE_IMAGE" ]; then
        base="$BASE_IMAGE"
    elif [ -z "$base" ]; then
        base="${REGISTRY}/${name}/main"
    fi

    # Image tag fallback
    if [ -z "$tag" ]; then
        local safe_suffix
        safe_suffix="$(echo -n "$name" | tr -c 'a-zA-Z0-9_.-' '_')"
        tag="devcontainer-nvim:${safe_suffix}"
    fi

    # Compiler fallbacks
    if [ -z "$cc" ]; then
        case "$name" in
            *gcc*|*g++*) cc="gcc" ;;
            *)          cc="${DEFAULT_CC:-clang}" ;;
        esac
    fi
    if [ -z "$cxx" ]; then
        case "$name" in
            *gcc*|*g++*) cxx="g++" ;;
            *)          cxx="${DEFAULT_CXX:-clang++}" ;;
        esac
    fi

    PARSED_VARIANT_NAME="$name"
    PARSED_VARIANT_BASE="$base"
    PARSED_VARIANT_TAG="$tag"
    PARSED_VARIANT_CC="$cc"
    PARSED_VARIANT_CXX="$cxx"
}

find_variant() {
    local target="$1"
    for entry in "${VARIANTS[@]}"; do
        [ -z "$entry" ] && continue
        parse_variant_entry "$entry"
        if [ "$PARSED_VARIANT_NAME" = "$target" ]; then
            return 0
        fi
    done
    return 1
}

get_variant_names() {
    local names=()
    for entry in "${VARIANTS[@]}"; do
        [ -z "$entry" ] && continue
        parse_variant_entry "$entry"
        names+=("$PARSED_VARIANT_NAME")
    done
    echo "${names[*]}"
}

show_help() {
    cat <<EOF
Usage: $(basename "$0") [VARIANT] [OPTIONS]

Builds the devcontainer Docker image for Neovim development.

Configured Variants (from settings.env):
EOF
    for entry in "${VARIANTS[@]}"; do
        [ -z "$entry" ] && continue
        parse_variant_entry "$entry"
        printf "  %-12s Tag: %-25s (Base: %s)\n" "$PARSED_VARIANT_NAME" "$PARSED_VARIANT_TAG" "$PARSED_VARIANT_BASE"
    done
    cat <<EOF
  all          Build all configured variants

Options:
  --pull       Pull base image from registry before building (default)
  --no-pull    Do not pull base image from registry before building
  --no-cache   Build Docker image without cache
  --verbose    Enable bash tracing (set -x)
  -h, --help   Show this help message
EOF
}

build_variant() {
    local target="$1"
    local no_cache_flag="$2"
    local pull="$3"

    if ! find_variant "$target"; then
        echo "Error: Unknown variant '$target'." >&2
        echo "Available variants: $(get_variant_names)" >&2
        exit 1
    fi

    local tag_name="$PARSED_VARIANT_TAG"
    local base_image="$PARSED_VARIANT_BASE"

    echo "============================================================"
    echo "Building devcontainer image: ${tag_name}"
    echo "Base toolchain image:        ${base_image}"
    echo "Architecture:                ${TOOLCHAIN_ARCH}"
    echo "============================================================"

    local pull_build_flag=""
    if [ "$pull" = true ]; then
        echo "Pulling latest base image from registry: ${base_image}..."
        docker pull "${base_image}"
        pull_build_flag="--pull"
    fi

    # shellcheck disable=SC2086
    docker build \
        ${pull_build_flag} \
        ${no_cache_flag} \
        --build-arg BASE_IMAGE="${base_image}" \
        -t "${tag_name}" \
        -f "${SCRIPT_DIR}/Dockerfile" \
        "${SCRIPT_DIR}"

    echo "Successfully built ${tag_name}"
}

VARIANT="${DEFAULT_CONTAINER_VARIANT:-clang}"
NO_CACHE=""
PULL="${PULL_BASE_IMAGE:-true}"

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
        --pull)
            PULL=true
            shift
            ;;
        --no-pull)
            PULL=false
            shift
            ;;
        --verbose)
            set -x
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            show_help
            exit 1
            ;;
        *)
            VARIANT="$1"
            shift
            ;;
    esac
done

if [ "$VARIANT" = "all" ]; then
    for entry in "${VARIANTS[@]}"; do
        [ -z "$entry" ] && continue
        parse_variant_entry "$entry"
        build_variant "$PARSED_VARIANT_NAME" "$NO_CACHE" "$PULL"
    done
else
    build_variant "$VARIANT" "$NO_CACHE" "$PULL"
fi
