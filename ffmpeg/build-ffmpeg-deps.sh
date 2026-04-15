#!/usr/bin/env bash

LAME_VERSION="3.100"
LAME_SOURCE_ARCHIVE="lame-$LAME_VERSION.tar.gz"
LAME_SOURCE_URL="https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/$LAME_SOURCE_ARCHIVE"
OPUS_VERSION="1.5.2"
OPUS_SOURCE_ARCHIVE="opus-$OPUS_VERSION.tar.gz"
OPUS_SOURCE_URL="https://downloads.xiph.org/releases/opus/$OPUS_SOURCE_ARCHIVE"

FFMPEG_COMMON_CONFIGURE_ARGS=(
  --pkg-config=pkg-config
  --pkg-config-flags=--static
  --disable-everything
  --enable-small
  --disable-doc
  --disable-network
  --disable-debug
  --disable-autodetect
  --disable-bsfs
  --disable-indevs
  --disable-outdevs
  --enable-static
  --disable-shared
  --enable-ffmpeg
  --disable-ffplay
  --disable-ffprobe
)

FFMPEG_COMMON_PROTOCOL_ARGS=(
  --enable-protocol=file
  --enable-protocol=pipe
)

FFMPEG_COMMON_DEMUXER_ARGS=(
  --enable-demuxer=mp3
  --enable-demuxer=ogg
  --enable-demuxer=flac
  --enable-demuxer=wav
  --enable-demuxer=aiff
)

FFMPEG_COMMON_MUXER_ARGS=(
  --enable-muxer=mp3
  --enable-muxer=ogg
  --enable-muxer=flac
  --enable-muxer=wav
  --enable-muxer=aiff
  --enable-muxer=null
)

FFMPEG_COMMON_DECODER_ARGS=(
  --enable-decoder=mp3
  --enable-decoder=opus
  --enable-decoder=vorbis
  --enable-decoder=flac
  --enable-decoder=pcm_s8
  --enable-decoder=pcm_s16be
  --enable-decoder=pcm_s16le
  --enable-decoder=pcm_s24be
  --enable-decoder=pcm_s24le
  --enable-decoder=pcm_s32be
  --enable-decoder=pcm_f32be
  --enable-decoder=pcm_f32le
  --enable-decoder=pcm_f64be
)

FFMPEG_COMMON_ENCODER_ARGS=(
  --enable-encoder=libmp3lame
  --enable-encoder=libopus
  --enable-encoder=vorbis
  --enable-encoder=flac
  --enable-encoder=pcm_s16be
  --enable-encoder=pcm_s16le
  --enable-encoder=pcm_s24be
  --enable-encoder=pcm_s24le
  --enable-encoder=pcm_f32be
  --enable-encoder=pcm_f32le
)

FFMPEG_COMMON_PARSER_ARGS=(
  --enable-parser=mpegaudio
  --enable-parser=vorbis
  --enable-parser=flac
)

FFMPEG_COMMON_FILTER_ARGS=(
  --disable-filters
  --enable-filter=aresample
  --enable-filter=anull
  --enable-filter=atrim
  --enable-filter=afade
  --enable-filter=silencedetect
  --enable-filter=volumedetect
  --enable-filter=concat
)

FFMPEG_COMMON_LIBRARY_ARGS=(
  --enable-libmp3lame
  --enable-libopus
)

FFMPEG_REQUIRED_CONFIG_SETTINGS=(
  "CONFIG_LIBMP3LAME=yes|FFmpeg configure did not enable libmp3lame"
  "CONFIG_LIBOPUS=yes|FFmpeg configure did not enable libopus"
  "CONFIG_AIFF_DEMUXER=yes|FFmpeg configure did not enable the AIFF demuxer"
  "CONFIG_AIFF_MUXER=yes|FFmpeg configure did not enable the AIFF muxer"
  "CONFIG_OPUS_DECODER=yes|FFmpeg configure did not enable the Opus decoder"
  "CONFIG_LIBOPUS_ENCODER=yes|FFmpeg configure did not enable the libopus encoder"
)

download_source_archive() {
  local url="$1"
  local archive_path="$2"

  if [ -f "$archive_path" ]; then
    return
  fi

  log "Downloading $(basename "$archive_path")"
  curl --fail --location --silent --show-error "$url" --output "$archive_path"
}

extract_source_archive() {
  local archive_path="$1"
  local output_dir="$2"

  rm -rf "$output_dir"
  mkdir -p "$output_dir"
  tar -xzf "$archive_path" -C "$output_dir"
}

write_pkg_config_file() {
  local prefix="$1"
  local pkg_config_name="$2"
  local description="$3"
  local version="$4"
  local libs="$5"
  local cflags="$6"
  local pkg_config_dir="$prefix/lib/pkgconfig"
  local pkg_config_path="$pkg_config_dir/$pkg_config_name.pc"

  mkdir -p "$pkg_config_dir"
  cat >"$pkg_config_path" <<EOF
prefix=$prefix
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: $pkg_config_name
Description: $description
Version: $version
Libs: -L\${libdir} $libs
Libs.private: -lm
Cflags: $cflags
EOF
}

resolve_default_target_host() {
  local target_triple="$1"
  local target_host="${2:-}"

  if [ -n "$target_host" ]; then
    printf '%s\n' "$target_host"
    return
  fi

  case "$target_triple" in
    x86_64-pc-windows-msvc)
      gcc -dumpmachine
      ;;
    *)
      printf '%s\n' ""
      ;;
  esac
}

run_autotools_install() {
  local package_label="$1"
  local source_dir="$2"
  local cpu_count="$3"
  local target_cc="${4:-}"
  local target_cflags="${5:-}"
  local target_ldflags="${6:-}"
  local target_ar="${7:-}"
  local target_ranlib="${8:-}"
  local target_strip="${9:-}"
  shift 9
  local configure_args=("$@")

  log "Building $package_label into ${configure_args[0]#--prefix=}"
  (
    cd "$source_dir"
    if [ -n "$target_cc" ]; then
      export CC="$target_cc"
    fi
    if [ -n "$target_cflags" ]; then
      export CFLAGS="$target_cflags"
    fi
    if [ -n "$target_ldflags" ]; then
      export LDFLAGS="$target_ldflags"
    fi
    if [ -n "$target_ar" ]; then
      export AR="$target_ar"
    fi
    if [ -n "$target_ranlib" ]; then
      export RANLIB="$target_ranlib"
    fi
    if [ -n "$target_strip" ]; then
      export STRIP="$target_strip"
    fi
    ./configure "${configure_args[@]}"
    make -j"$cpu_count"
    make install
  )
}

build_audio_dependency_into_prefix() {
  local package_id="$1"
  local target_triple="$2"
  local prefix="$3"
  local work_dir="$4"
  local cpu_count="$5"
  local target_cc="${6:-}"
  local target_cflags="${7:-}"
  local target_ldflags="${8:-}"
  local target_host="${9:-}"
  local target_ar="${10:-}"
  local target_ranlib="${11:-}"
  local target_strip="${12:-}"
  local archive_name=""
  local archive_url=""
  local source_root="$work_dir/src"
  local source_dir=""
  local package_label=""
  local pkg_config_name=""
  local pkg_description=""
  local package_version=""
  local package_libs=""
  local package_cflags=""
  local expected_header_path=""
  local expected_library_path=""
  local resolved_target_host=""
  local configure_args=()
  local archive_path=""

  mkdir -p "$work_dir"
  mkdir -p "$prefix"

  case "$package_id" in
    lame)
      archive_name="$LAME_SOURCE_ARCHIVE"
      archive_url="$LAME_SOURCE_URL"
      source_dir="$source_root/lame-$LAME_VERSION"
      package_label="libmp3lame $LAME_VERSION"
      pkg_config_name="lame"
      pkg_description="LAME MP3 encoder library"
      package_version="$LAME_VERSION"
      package_libs="-lmp3lame"
      package_cflags='-I${includedir}'
      expected_header_path="$prefix/include/lame/lame.h"
      expected_library_path="$prefix/lib/libmp3lame.a"
      configure_args=(
        --prefix="$prefix"
        --disable-shared
        --enable-static
        --disable-frontend
      )
      ;;
    opus)
      archive_name="$OPUS_SOURCE_ARCHIVE"
      archive_url="$OPUS_SOURCE_URL"
      source_dir="$source_root/opus-$OPUS_VERSION"
      package_label="libopus $OPUS_VERSION"
      pkg_config_name="opus"
      pkg_description="Opus audio codec library"
      package_version="$OPUS_VERSION"
      package_libs="-lopus"
      package_cflags='-I${includedir}/opus'
      expected_header_path="$prefix/include/opus/opus.h"
      expected_library_path="$prefix/lib/libopus.a"
      configure_args=(
        --prefix="$prefix"
        --disable-shared
        --enable-static
        --disable-extra-programs
        --disable-doc
      )
      ;;
    *)
      fail "Unsupported dependency package: $package_id"
      ;;
  esac

  archive_path="$work_dir/$archive_name"
  download_source_archive "$archive_url" "$archive_path"
  extract_source_archive "$archive_path" "$source_root"
  [ -d "$source_dir" ] || fail "Missing extracted source directory: $source_dir"

  resolved_target_host="$(resolve_default_target_host "$target_triple" "$target_host")"
  if [ -n "$resolved_target_host" ]; then
    configure_args+=(--host="$resolved_target_host")
  fi

  run_autotools_install \
    "$package_label" \
    "$source_dir" \
    "$cpu_count" \
    "$target_cc" \
    "$target_cflags" \
    "$target_ldflags" \
    "$target_ar" \
    "$target_ranlib" \
    "$target_strip" \
    "${configure_args[@]}"

  write_pkg_config_file \
    "$prefix" \
    "$pkg_config_name" \
    "$pkg_description" \
    "$package_version" \
    "$package_libs" \
    "$package_cflags"
  [ -f "$expected_header_path" ] || fail "Missing installed header: $expected_header_path"
  [ -f "$expected_library_path" ] || fail "Missing installed static library: $expected_library_path"
  [ -f "$prefix/lib/pkgconfig/$pkg_config_name.pc" ] || fail "Missing installed pkg-config file: $prefix/lib/pkgconfig/$pkg_config_name.pc"
}

print_pkg_config_details() {
  local pkg_config_name="$1"
  local package_label="$2"
  local prefix="$3"
  local pkg_config_dir="$prefix/lib/pkgconfig"

  [ -d "$pkg_config_dir" ] || fail "Missing pkg-config directory: $pkg_config_dir"

  log "pkg-config version for $package_label"
  PKG_CONFIG_PATH= PKG_CONFIG_LIBDIR="$pkg_config_dir" pkg-config --modversion "$pkg_config_name"
  log "pkg-config static link flags for $package_label"
  PKG_CONFIG_PATH= PKG_CONFIG_LIBDIR="$pkg_config_dir" pkg-config --libs --static "$pkg_config_name"
}

configure_ffmpeg_with_common_features() {
  local deps_prefix="$1"
  local ffmpeg_extra_cflags="$2"
  local ffmpeg_extra_ldflags="$3"
  shift 3
  local platform_configure_args=("$@")

  PKG_CONFIG_PATH= PKG_CONFIG_LIBDIR="$deps_prefix/lib/pkgconfig" ./configure \
    "${platform_configure_args[@]+"${platform_configure_args[@]}"}" \
    "${FFMPEG_COMMON_CONFIGURE_ARGS[@]}" \
    "${FFMPEG_COMMON_PROTOCOL_ARGS[@]}" \
    "${FFMPEG_COMMON_DEMUXER_ARGS[@]}" \
    "${FFMPEG_COMMON_MUXER_ARGS[@]}" \
    "${FFMPEG_COMMON_DECODER_ARGS[@]}" \
    "${FFMPEG_COMMON_ENCODER_ARGS[@]}" \
    "${FFMPEG_COMMON_PARSER_ARGS[@]}" \
    "${FFMPEG_COMMON_FILTER_ARGS[@]}" \
    "${FFMPEG_COMMON_LIBRARY_ARGS[@]}" \
    --extra-cflags="$ffmpeg_extra_cflags" \
    --extra-ldflags="$ffmpeg_extra_ldflags"
}

verify_ffmpeg_configure_result() {
  local config_mak_path="$1"
  local entry
  local setting
  local message

  log "Verifying ffmpeg configure result for key codecs and containers"
  for entry in "${FFMPEG_REQUIRED_CONFIG_SETTINGS[@]}"; do
    setting="${entry%%|*}"
    message="${entry#*|}"
    grep "^$setting\$" "$config_mak_path" || fail "$message"
  done
}

verify_ffmpeg_runtime_capabilities() {
  local ffmpeg_binary="$1"
  local ffmpeg_label="${2:-$(basename "$ffmpeg_binary")}"

  log "Verifying ffmpeg runtime capability lists"
  "$ffmpeg_binary" -hide_banner -demuxers | grep -E '^[[:space:]]*D[[:space:]]+aiff([[:space:]]|$)' || fail "Built $ffmpeg_label is missing the AIFF demuxer"
  "$ffmpeg_binary" -hide_banner -muxers | grep -E '^[[:space:]]*E[[:space:]]+aiff([[:space:]]|$)' || fail "Built $ffmpeg_label is missing the AIFF muxer"
  "$ffmpeg_binary" -hide_banner -decoders | grep -E '^[[:space:]]*A.*[[:space:]]opus([[:space:]]|$)' || fail "Built $ffmpeg_label is missing the Opus decoder"
  "$ffmpeg_binary" -hide_banner -encoders | grep 'libmp3lame' || fail "Built $ffmpeg_label is missing the libmp3lame encoder"
  "$ffmpeg_binary" -hide_banner -encoders | grep 'libopus' || fail "Built $ffmpeg_label is missing the libopus encoder"
}

build_lame_into_prefix() {
  build_audio_dependency_into_prefix lame "$@"
}

build_opus_into_prefix() {
  build_audio_dependency_into_prefix opus "$@"
}

print_lame_pkg_config_details() {
  local prefix="$1"

  log "Using dependency prefix: $prefix"
  print_pkg_config_details "lame" "lame" "$prefix"
}

print_opus_pkg_config_details() {
  local prefix="$1"

  print_pkg_config_details "opus" "opus" "$prefix"
}
