#!/usr/bin/env bash

set -euo pipefail

TARGET_TRIPLE="${FFMPEG_TARGET_TRIPLE:-aarch64-apple-darwin}"
FFMPEG_TAG="n8.0.1"
FFMPEG_REPO_URL="https://github.com/ffmpeg/ffmpeg"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_BINARY="$REPO_ROOT/src-tauri/binaries/ffmpeg-$TARGET_TRIPLE"
source "$SCRIPT_DIR/build-ffmpeg-deps.sh"

tmp_dir=""

case "$TARGET_TRIPLE" in
  aarch64-apple-darwin)
    TARGET_LABEL="Apple Silicon"
    TARGET_ARCH="aarch64"
    EXPECTED_FILE_ARCH="arm64"
    ;;
  x86_64-apple-darwin)
    TARGET_LABEL="Intel Mac"
    TARGET_ARCH="x86_64"
    EXPECTED_FILE_ARCH="x86_64"
    ;;
  *)
    printf 'Error: Unsupported ffmpeg target triple: %s\n' "$TARGET_TRIPLE" >&2
    exit 1
    ;;
esac

log() {
  printf '==> %s\n' "$1"
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

path_exists() {
  [ -e "$1" ] || [ -L "$1" ]
}

cleanup() {
  set +e
  if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
    rm -rf "$tmp_dir"
  fi
}

main() {
  local host_arch
  local sdk_root
  local deps_prefix
  local deps_work_dir
  local checkout_dir
  local cpu_count
  local tag_commit
  local target_cc=""
  local target_cflags=""
  local target_ldflags=""
  local target_host_triple=""
  local should_run_built_binary="yes"
  local ffmpeg_extra_cflags
  local ffmpeg_extra_ldflags
  local ffmpeg_configure_args=()
  local linked_libraries
  local file_output

  [ "$(uname -s)" = "Darwin" ] || fail "This script only supports macOS"
  host_arch="$(uname -m)"

  require_command git
  require_command nasm
  require_command pkg-config
  require_command make
  require_command strip
  require_command otool
  require_command file
  require_command curl
  require_command tar
  require_command xcrun

  trap cleanup EXIT
  trap 'exit 1' INT TERM HUP

  sdk_root="$(xcrun --sdk macosx --show-sdk-path)"
  [ -d "$sdk_root" ] || fail "Unable to resolve the macOS SDK path"

  case "$TARGET_TRIPLE" in
    aarch64-apple-darwin)
      [ "$host_arch" = "arm64" ] || fail "Building $TARGET_TRIPLE requires Apple Silicon hardware. Run this target on an arm64 Mac."
      ;;
    x86_64-apple-darwin)
      case "$host_arch" in
        x86_64)
          ;;
        arm64)
          target_cc="clang -arch x86_64 -isysroot $sdk_root"
          target_cflags="-arch x86_64 -isysroot $sdk_root"
          target_ldflags="-arch x86_64 -isysroot $sdk_root"
          target_host_triple="x86_64-apple-darwin"
          should_run_built_binary="no"
          log "Cross-compiling $TARGET_TRIPLE from Apple Silicon using the macOS SDK at $sdk_root"
          ;;
        *)
          fail "Unsupported host architecture for $TARGET_TRIPLE: $host_arch"
          ;;
      esac
      ;;
  esac

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/ffmpeg-build.XXXXXX")"
  deps_prefix="$tmp_dir/deps/$TARGET_TRIPLE"
  deps_work_dir="$tmp_dir/deps-src/$TARGET_TRIPLE"
  checkout_dir="$tmp_dir/ffmpeg"
  cpu_count="$(sysctl -n hw.logicalcpu)"
  ffmpeg_extra_cflags="-I$deps_prefix/include"
  ffmpeg_extra_ldflags="-L$deps_prefix/lib -Wl,-search_paths_first"
  ffmpeg_configure_args=()

  if [ -n "$target_cflags" ]; then
    ffmpeg_extra_cflags="$target_cflags $ffmpeg_extra_cflags"
  fi

  if [ -n "$target_ldflags" ]; then
    ffmpeg_extra_ldflags="$target_ldflags $ffmpeg_extra_ldflags"
  fi

  if [ "$TARGET_TRIPLE" = "x86_64-apple-darwin" ] && [ "$host_arch" = "arm64" ]; then
    ffmpeg_configure_args+=(
      --arch="$TARGET_ARCH"
      --target-os=darwin
      --enable-cross-compile
      --cc=clang
      --host-cc=clang
    )
  fi

  log "Preparing libmp3lame $LAME_VERSION, libopus $OPUS_VERSION, and ffmpeg $FFMPEG_TAG for $TARGET_LABEL ($TARGET_TRIPLE)"
  build_lame_into_prefix "$TARGET_TRIPLE" "$deps_prefix" "$deps_work_dir" "$cpu_count" "$target_cc" "$target_cflags" "$target_ldflags" "$target_host_triple"
  build_opus_into_prefix "$TARGET_TRIPLE" "$deps_prefix" "$deps_work_dir" "$cpu_count" "$target_cc" "$target_cflags" "$target_ldflags" "$target_host_triple"
  print_lame_pkg_config_details "$deps_prefix"
  print_opus_pkg_config_details "$deps_prefix"

  log "Fetching ffmpeg tag $FFMPEG_TAG"
  git init "$checkout_dir" >/dev/null
  cd "$checkout_dir"
  git remote add origin "$FFMPEG_REPO_URL"
  git fetch --depth 1 origin "refs/tags/$FFMPEG_TAG:refs/tags/$FFMPEG_TAG"
  tag_commit="$(git rev-parse "refs/tags/$FFMPEG_TAG^{}")"
  [ -n "$tag_commit" ] || fail "Unable to resolve ffmpeg tag $FFMPEG_TAG"
  git checkout --detach "$tag_commit"

  log "Configuring ffmpeg"
  configure_ffmpeg_with_common_features \
    "$deps_prefix" \
    "$ffmpeg_extra_cflags" \
    "$ffmpeg_extra_ldflags" \
    "${ffmpeg_configure_args[@]+"${ffmpeg_configure_args[@]}"}"

  verify_ffmpeg_configure_result ffbuild/config.mak

  log "Building ffmpeg"
  make -j"$cpu_count"

  if [ "$should_run_built_binary" = "yes" ]; then
    verify_ffmpeg_runtime_capabilities ./ffmpeg ffmpeg
  else
    log "Skipping runtime encoder validation for the cross-built Intel binary; using configure, linkage, and file checks instead"
  fi

  mkdir -p "$(dirname "$OUTPUT_BINARY")"
  cp ffmpeg "$OUTPUT_BINARY"
  chmod 755 "$OUTPUT_BINARY"

  log "Stripping $OUTPUT_BINARY"
  strip "$OUTPUT_BINARY"

  log "Inspecting linked libraries"
  linked_libraries="$(otool -L "$OUTPUT_BINARY")"
  printf '%s\n' "$linked_libraries"
  if printf '%s\n' "$linked_libraries" | grep -Eq 'libmp3lame(\.0)?\.dylib'; then
    fail "The built ffmpeg still depends on a dynamic libmp3lame dylib"
  fi

  log "Inspecting binary format"
  file_output="$(file "$OUTPUT_BINARY")"
  printf '%s\n' "$file_output"
  if ! printf '%s\n' "$file_output" | grep -Eq "Mach-O 64-bit executable $EXPECTED_FILE_ARCH"; then
    fail "The built ffmpeg has the wrong architecture; expected $EXPECTED_FILE_ARCH"
  fi

  log "Wrote $OUTPUT_BINARY"
}

main "$@"
