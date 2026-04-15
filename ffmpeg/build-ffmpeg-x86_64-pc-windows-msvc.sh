#!/usr/bin/env bash

set -euo pipefail

TARGET_TRIPLE="x86_64-pc-windows-msvc"
FFMPEG_TAG="n8.0.1"
FFMPEG_REPO_URL="https://github.com/ffmpeg/ffmpeg"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_BINARY="$REPO_ROOT/src-tauri/binaries/ffmpeg-$TARGET_TRIPLE.exe"
source "$SCRIPT_DIR/build-ffmpeg-deps.sh"

tmp_dir=""

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

require_path() {
  path_exists "$1" || fail "Missing required path: $1"
}

path_exists() {
  [ -e "$1" ] || [ -L "$1" ]
}

resolve_brew_mingw_w64_bin_dir() {
  local root=""

  if [ -n "${MINGW_W64_ROOT:-}" ]; then
    root="$MINGW_W64_ROOT"
  elif command -v brew >/dev/null 2>&1; then
    root="$(brew --prefix mingw-w64 2>/dev/null || true)"
  fi

  if [ -n "$root" ]; then
    if [ -d "$root/bin" ]; then
      printf '%s\n' "$root/bin"
      return 0
    fi

    if [ -d "$root" ]; then
      printf '%s\n' "$root"
      return 0
    fi
  fi

  if command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
    dirname "$(command -v x86_64-w64-mingw32-gcc)"
    return 0
  fi

  fail "Missing MinGW-w64 cross toolchain. Install it with 'brew install mingw-w64 nasm pkg-config' and ensure Homebrew's bin directory is on PATH before building $TARGET_TRIPLE on macOS."
}

cleanup() {
  set +e
  if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
    rm -rf "$tmp_dir"
  fi
}

main() {
  local uname_s
  local host_arch
  local mingw_w64_bin_dir=""
  local deps_prefix
  local deps_work_dir
  local checkout_dir
  local cpu_count
  local tag_commit
  local target_cc=""
  local target_cflags=""
  local target_ldflags=""
  local target_host_triple=""
  local target_ar=""
  local target_ranlib=""
  local target_strip=""
  local target_objdump=""
  local target_windres=""
  local target_cross_prefix=""
  local should_run_built_binary="yes"
  local ffmpeg_extra_cflags
  local ffmpeg_extra_ldflags
  local ffmpeg_configure_args=()
  local dll_dependencies
  local pe_header_output
  local file_output

  uname_s="$(uname -s)"
  host_arch="$(uname -m)"

  case "$uname_s" in
    MINGW64_NT-*|MSYS_NT-*)
      [ "${MSYSTEM:-}" = "MINGW64" ] || fail "Run this script from the MSYS2 MINGW64 shell"
      [ "$host_arch" = "x86_64" ] || fail "This script only supports x86_64 Windows hosts"

      require_command git
      require_command gcc
      require_command make
      require_command nasm
      require_command objdump
      require_command pkg-config
      require_command strip
      require_command curl
      require_command tar

      target_cc="gcc"
      target_host_triple="$(gcc -dumpmachine)"
      target_ar="ar"
      target_ranlib="ranlib"
      target_strip="strip"
      target_objdump="objdump"
      cpu_count="$(nproc)"
      ;;
    Darwin)
      [ "$host_arch" = "arm64" ] || fail "Cross-building $TARGET_TRIPLE on macOS is supported only on Apple Silicon hosts"

      require_command git
      require_command cc
      require_command make
      require_command nasm
      require_command pkg-config
      require_command curl
      require_command tar
      require_command file

      mingw_w64_bin_dir="$(resolve_brew_mingw_w64_bin_dir)"
      require_path "$mingw_w64_bin_dir"
      export PATH="$mingw_w64_bin_dir:$PATH"

      target_cc="x86_64-w64-mingw32-gcc"
      target_ar="x86_64-w64-mingw32-ar"
      target_ranlib="x86_64-w64-mingw32-ranlib"
      target_strip="x86_64-w64-mingw32-strip"
      target_objdump="x86_64-w64-mingw32-objdump"
      target_windres="x86_64-w64-mingw32-windres"
      target_cross_prefix="x86_64-w64-mingw32-"

      require_command "$target_cc"
      require_command "$target_ar"
      require_command "$target_ranlib"
      require_command "$target_strip"
      require_command "$target_objdump"
      require_command "$target_windres"

      target_cflags="-O2"
      target_host_triple="x86_64-w64-mingw32"
      should_run_built_binary="no"
      cpu_count="$(sysctl -n hw.logicalcpu)"
      ffmpeg_configure_args+=(
        --enable-cross-compile
        --cross-prefix="$target_cross_prefix"
        --cc="$target_cc"
        --host-cc=cc
        --ar="$target_ar"
        --ranlib="$target_ranlib"
        --strip="$target_strip"
        --windres="$target_windres"
      )
      log "Cross-compiling $TARGET_TRIPLE from Apple Silicon using Homebrew MinGW-w64 from $mingw_w64_bin_dir"
      ;;
    *)
      fail "This script supports Windows under MSYS2 or macOS on Apple Silicon with Homebrew MinGW-w64"
      ;;
  esac

  trap cleanup EXIT
  trap 'exit 1' INT TERM HUP

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/ffmpeg-build.XXXXXX")"
  deps_prefix="$tmp_dir/deps/$TARGET_TRIPLE"
  deps_work_dir="$tmp_dir/deps-src/$TARGET_TRIPLE"
  checkout_dir="$tmp_dir/ffmpeg"
  ffmpeg_extra_cflags="-I$deps_prefix/include"
  ffmpeg_extra_ldflags="-L$deps_prefix/lib -static -static-libgcc"

  log "Preparing libmp3lame $LAME_VERSION, libopus $OPUS_VERSION, and ffmpeg $FFMPEG_TAG for Windows x64 ($TARGET_TRIPLE)"
  build_lame_into_prefix \
    "$TARGET_TRIPLE" \
    "$deps_prefix" \
    "$deps_work_dir" \
    "$cpu_count" \
    "$target_cc" \
    "$target_cflags" \
    "$target_ldflags" \
    "$target_host_triple" \
    "$target_ar" \
    "$target_ranlib" \
    "$target_strip"
  build_opus_into_prefix \
    "$TARGET_TRIPLE" \
    "$deps_prefix" \
    "$deps_work_dir" \
    "$cpu_count" \
    "$target_cc" \
    "$target_cflags" \
    "$target_ldflags" \
    "$target_host_triple" \
    "$target_ar" \
    "$target_ranlib" \
    "$target_strip"
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
    "${ffmpeg_configure_args[@]+"${ffmpeg_configure_args[@]}"}" \
    --target-os=mingw32 \
    --arch=x86_64

  verify_ffmpeg_configure_result ffbuild/config.mak

  log "Building ffmpeg"
  make -j"$cpu_count"

  if [ "$should_run_built_binary" = "yes" ]; then
    verify_ffmpeg_runtime_capabilities ./ffmpeg.exe ffmpeg.exe
  else
    log "Skipping runtime encoder validation for the macOS cross-build; using configure, PE, and DLL checks instead"
  fi

  mkdir -p "$(dirname "$OUTPUT_BINARY")"
  cp ffmpeg.exe "$OUTPUT_BINARY"
  chmod 755 "$OUTPUT_BINARY"

  log "Stripping $OUTPUT_BINARY"
  "$target_strip" "$OUTPUT_BINARY"

  if [ "$uname_s" = "Darwin" ]; then
    log "Inspecting binary format"
    file_output="$(file "$OUTPUT_BINARY")"
    printf '%s\n' "$file_output"
    if ! printf '%s\n' "$file_output" | grep -Eq 'PE32\+ executable .*x86-64'; then
      fail "The built ffmpeg.exe has the wrong architecture; expected a PE32+ x86-64 executable"
    fi
  fi

  log "Inspecting PE header"
  pe_header_output="$("$target_objdump" -f "$OUTPUT_BINARY")"
  printf '%s\n' "$pe_header_output"
  if ! printf '%s\n' "$pe_header_output" | grep -Eq 'file format pei-x86-64|architecture: i386:x86-64'; then
    fail "The built ffmpeg.exe does not look like an x86_64 Windows PE binary"
  fi

  log "Inspecting DLL dependencies"
  dll_dependencies="$("$target_objdump" -p "$OUTPUT_BINARY" | grep 'DLL Name' || true)"
  if [ -n "$dll_dependencies" ]; then
    printf '%s\n' "$dll_dependencies"
  fi

  if printf '%s\n' "$dll_dependencies" | grep -Eiq 'DLL Name: (libmp3lame|libgcc|libstdc\+\+|libwinpthread)'; then
    fail "The built ffmpeg.exe still depends on MinGW/MSYS runtime DLLs; verify the static-link setup before bundling it"
  fi

  log "Wrote $OUTPUT_BINARY"
}

main "$@"
