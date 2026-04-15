# Audiobook Cutter Studio Resources

This repository contains supporting resources for Audiobook Cutter Studio, including FFmpeg build scripts, ffmpeg binaries, upstream source archives, and related materials.
The Audiobook Cutter Studio application itself is proprietary and is not included in this repository.

## Official links

- https://buymeacoffee.com/audiobookcutter
- https://www.audiobookcutter.de/
- https://www.audiobookcutter.com/

## Evolution of Audiobook Cutter

Audiobook Cutter has evolved through three main stages.

### 1. Audiobook Cutter (2006–2013)

The original **Audiobook Cutter** was a Windows desktop application published on SourceForge under the GPL. Its core purpose was simple and practical: splitting large spoken-word MP3 files into smaller parts **without re-encoding**, while automatically generating **ID3 tags, titles, and chapter numbers**.

### 2. Audiobook Cutter Free & Pro Edition (2008–2026)

The later **Free** and **Pro** editions carried this idea forward as more polished consumer products. The focus remained on **Windows** and **MP3 audiobook cutting**, while adding features such as **time-based cutting, pause detection, extended ID3 tagging, and more precise control over cut behavior**. Accessibility also became a stronger focus, with particular attention to visually impaired users.

A defining feature of the **Pro** edition was **silence-based split point detection**, which made long audiobooks and podcasts easier to manage. This generation marked the **first major rewrite** of the original tool.

### 3. Audiobook Cutter Studio (2026–present)

**Audiobook Cutter Studio** continues as a **complete rewrite** built on a new architecture. It extends the original chapter-splitting concept to **multiple platforms**, broadens **input and output format support**, and bundles an optimized **FFmpeg** command-line tool as the foundation for all media operations.

A distinctive feature of Studio is its **interactive chapter-splitting simulation**. When the target chapter length is adjusted, the application immediately previews the resulting number of chapters and their estimated lengths, and even allows the user to listen to the beginning of a chapter before exporting.

## FFmpeg

Audiobook Cutter Studio uses a bundled FFmpeg command-line binary for its analysis and cutting backend. Studio does not link FFmpeg and, if needed, the bundled FFmpeg binary can be replaced with a custom build when the application is started with an explicit binary path.

Special thanks to the FFmpeg project and its community. FFmpeg is an amazing project, and without it, Audiobook Cutter Studio would not be possible.

### FFmpeg Build scripts for macOS and Windows

- [`build-ffmpeg-deps.sh`](ffmpeg/build-ffmpeg-deps.sh)
- [`build-ffmpeg-apple-darwin.sh`](ffmpeg/build-ffmpeg-apple-darwin.sh)
- [`build-ffmpeg-x86_64-pc-windows-msvc.sh`](ffmpeg/build-ffmpeg-x86_64-pc-windows-msvc.sh)
- pinned versions: ffmpeg `n8.0.1`, lame `3.100`, and opus `1.5.2`

### FFmpeg binaries

This repository redistributes the following FFmpeg command-line binaries:

- macOS Apple Silicon [`ffmpeg-aarch64-apple-darwin`](ffmpeg/ffmpeg-aarch64-apple-darwin)
- macOS Intel [`ffmpeg-x86_64-apple-darwin`](ffmpeg/ffmpeg-x86_64-apple-darwin)
- Windows [`ffmpeg-x86_64-pc-windows-msvc.exe`](ffmpeg/ffmpeg-x86_64-pc-windows-msvc.exe)
- Checksums in [`ffmpeg/SHA256SUMS`](ffmpeg/SHA256SUMS) and a machine-readable inventory in [`ffmpeg/manifest.json`](ffmpeg/manifest.json)

### License and source code materials

The bundled FFmpeg binaries in this repository are intended to be redistributed as LGPL v2.1-or-later builds. The shipped build configuration does not enable `--enable-gpl`, `--enable-version3`, or `--enable-nonfree`.

The exact build configuration and platform-specific build steps used for the redistributed binaries are defined in:

- [`ffmpeg/build-ffmpeg-deps.sh`](ffmpeg/build-ffmpeg-deps.sh)
- [`ffmpeg/build-ffmpeg-apple-darwin.sh`](ffmpeg/build-ffmpeg-apple-darwin.sh)
- [`ffmpeg/build-ffmpeg-x86_64-pc-windows-msvc.sh`](ffmpeg/build-ffmpeg-x86_64-pc-windows-msvc.sh)

No local patches are applied to FFmpeg, LAME, or Opus by these build scripts. The corresponding upstream source archives redistributed with this repository are:

- FFmpeg `n8.0.1`: [`ffmpeg/FFmpeg-n8.0.1.tar.gz`](ffmpeg/FFmpeg-n8.0.1.tar.gz)
- LAME `3.100`: [`lame/lame-3.100.tar.gz`](lame/lame-3.100.tar.gz)
- Opus `1.5.2`: [`opus/opus-1.5.2.tar.gz`](opus/opus-1.5.2.tar.gz)

The license texts and upstream licensing notices redistributed with this repository are:

- FFmpeg LGPL v2.1: [`ffmpeg/COPYING.LGPLv2.1`](ffmpeg/COPYING.LGPLv2.1)
- LAME licensing materials: [`lame/COPYING`](lame/COPYING) and [`lame/license.txt`](lame/license.txt)
- Opus BSD 3-Clause license: [`opus/COPYING`](opus/COPYING)

LAME is used as the external `libmp3lame` library in the bundled FFmpeg builds. The corresponding LAME source archive and upstream licensing files are included here as part of the redistribution materials.

Opus is used as the external `libopus` library in the bundled FFmpeg builds. Its corresponding source archive and BSD 3-Clause license text are included here as part of the redistribution materials.

### Codec patent notice

This repository provides software and source-code redistribution materials. Patent rights relating to media codecs may vary by codec and jurisdiction and are separate from copyright licenses. Users are responsible for assessing any patent requirements relevant to their use and distribution.
