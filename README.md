# dovi_convert

A tool to automate the conversion of Dolby Vision Profile 7 MKV files (UHD Blu-ray rips) into Profile 8.1.

This conversion ensures compatibility with media players that do not support the Profile 7 Enhancement Layer (EL), such as the Apple TV 4K (with Plex or Infuse), Nvidia Shield (to a certain extent), Zidoo, and other devices, preventing fallback to standard HDR10 and other issues. The result is a highly compatible file that can be played on a wide range of devices.

Unlike other tools and "real-time converters" such as those built into Kodi (Dovi Compatibility Mode) or the Nvidia Shield, this tool analyzes the Dolby Vision enhancement layer to determine if it is actually safe to convert. This readme will explain the difference between the two approaches. 

> [!IMPORTANT]
> **Upgrading from v6.x?** v7.0.0 is a complete Python rewrite. Dependencies have changed — please ensure you have **Python 3.8+** installed and read the updated [Installation](#installation) instructions.
>
> **Docker users:** If you were testing the `:beta` tag, switch to `:latest`. The `:beta` tag will be deprecated.

### Important Note

Converting Dolby Vision Profile 7 with FEL to Profile 8.1 is always a compromise. Make sure you read and understand the [Caveats and Notes](#caveats-and-notes) before you use this script.

## Table of Contents

- [What This Tool Does](#what-this-tool-does)
- [Features](#features)
- [Compatibility](#compatibility)
- [Dependencies](#dependencies)
- [Installation](#installation)
- [Usage](#usage)
    - [1. File Analysis (-scan)](#1-file-analysis--scan)
    - [2. Inspection (-inspect)](#2-inspection--inspect)
    - [3. Single File Conversion (-convert)](#3-single-file-conversion--convert)
    - [4. Batch Processing (-batch)](#4-batch-processing--batch)
    - [5. Cleanup (-cleanup)](#5-cleanup--cleanup)
    - [6. Update Check (-update-check)](#6-update-check--update-check)
- [Troubleshooting](#troubleshooting)
- [Caveats and Notes](#caveats-and-notes)


## What This Tool Does

The conversion process:
1. Strips the Enhancement Layer (EL) from the video
2. Injects the RPU (dynamic metadata) into the base layer
3. Creates a Profile 8.1 compatible file

All audio and subtitle tracks are preserved. The original file is backed up automatically.


## Features

### Non-Destructive
Original files are backed up as `*.bak.dovi_convert` before any modification.

### Two Modes of Operation

| Mode | Description |
|------|-------------|
| **Standard** (default) | Pipes video data directly between tools. Fast, no temp disk space. May fail on irregular files. |
| **Safe** (`-safe`) | Extracts video to disk first. Slower, but handles Seamless Branching and structural issues. Auto-triggered on failure. |

### File Scanning & Analysis

The tool scans MKV files to identify video format (HDR10, HDR10+, Dolby Vision Profile, etc.). For Profile 7 files with FEL, it samples RPU metadata to classify:

| Type | Color | Meaning |
|------|-------|---------|
| **MEL** | Green | No enhancement data. Safe to convert. |
| **Simple FEL** | Cyan | No brightness expansion detected. Likely safe. |
| **Complex FEL** | Red | Active brightness expansion. Conversion skipped by default. |

> **How it works:** The scan samples 10 timestamps across the file to analyze brightness metadata. Complex FEL verdicts are mostly reliable. Simple FEL verdicts might miss isolated spikes - verify with `-inspect` if in doubt.

### Deep Inspection

For definitive verification, the `-inspect` command reads the entire file frame-by-frame to confirm whether brightness expansion exists. Use this to verify Simple FEL verdicts, or when you need absolute certainty.

### Automatic Backups

All conversions create a backup: `[filename].mkv.bak.dovi_convert`

The `-cleanup` command only deletes files with this extension, and includes a safety check to avoid deleting orphan backups.


## Compatibility

- **macOS** (tested on macOS 26)
- **Linux** (any modern distribution)
- **Windows** (via WSL)


## Dependencies

**macOS Prerequisite:** [Homebrew](https://brew.sh) is required for automatic dependency installation.

> **Important:** On macOS, use CLI versions installed via [Homebrew](https://brew.sh) or [MacPorts](https://www.macports.org/). GUI app bundles (MKVToolNix.app, MediaInfo.app) may not work.

- Python 3.8+
- ffmpeg
- [dovi_tool](https://github.com/quietvoid/dovi_tool) (may require manual install)
- mkvtoolnix (CLI: `mkvmerge`, `mkvextract`)
- mediainfo (CLI version)

**Automatic Installation:** Missing dependencies are detected and can be installed via your system's package manager (Homebrew, apt, dnf, pacman).

> **Note:** `dovi_tool` may not be available in all package managers. If auto-install fails, download from the [GitHub releases](https://github.com/quietvoid/dovi_tool/releases).


## Installation



### Download

Requires **Python 3.8+** and the dependencies listed above.

```bash
curl -sSLO https://github.com/cryptochrome/dovi_convert/releases/latest/download/dovi_convert.py
chmod +x dovi_convert.py
sudo mv dovi_convert.py /usr/local/bin/dovi_convert
```

### Docker Container
The container provides a **Web Terminal** interface, allowing you to run the tool from any browser.

> **Note:** If you need to run the container with a specific user ID, set the `PUID` and `PGID` environment variables. Defaults to UID/GID 1000.

```bash
docker run -d \
  --name=dovi_convert \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Europe/Berlin \
  -p 7681:7681 \
  -v /path/to/media:/data \
  --restart unless-stopped \
  cryptochrome/dovi_convert:latest
```

Access the tool at `http://<your_docker_host>:7681`.

### Docker Compose

A `docker-compose.yml` example is included in the repository.

## Usage

### 1. File Analysis (`-scan`)

Scans files to identify video format and FEL complexity. (Alias: `-check`)

```bash
dovi_convert -scan              # All files in current directory
dovi_convert -scan "Film.mkv"   # Specific file
dovi_convert -scan -r           # Recursive (default depth: 5)
dovi_convert -scan -r 2         # Recursive (depth: 2)
```

**Output colors:**
- **Green:** MEL - Safe to convert
- **Cyan:** Simple FEL - Likely safe (verify with `-inspect` if uncertain)
- **Red:** Complex FEL - Conversion skipped by default


### 2. Inspection (`-inspect`)

Full frame-by-frame analysis to verify whether brightness expansion exists in the FEL.

```bash
dovi_convert -inspect "Film.mkv"
```

Use this to verify Simple FEL verdicts, or if you want absolute certainty.

**Note:** Reads the entire file. Significantly slower than `-check`. Not available for batch operations.

> This command checks for active brightness data (L1 metadata). It does not analyze other reconstruction data, as brightness expansion is the primary concern for playback compatibility. See [Caveats](#1-a-note-on-fel-full-enhancement-layer) for details.


### 3. Single File Conversion (`-convert`)

```bash
dovi_convert -convert "Movie.mkv"           # Standard mode
dovi_convert -convert "Movie.mkv" -safe     # Force Safe mode
dovi_convert -convert "Movie.mkv" -force    # Force convert Complex FEL
```

**Behavior:**
- Skips Complex FEL files by default (use `-force` to override)
- Original file renamed to `*.bak.dovi_convert`
- Safe mode auto-triggers if Standard mode fails


### 4. Batch Processing (`-batch`)

Recursively scans and converts Profile 7 files.

```bash
dovi_convert -batch               # Current directory
dovi_convert -batch 2             # Depth: 2 folders
dovi_convert -batch -y            # Auto-confirm (pauses on Simple FEL)
dovi_convert -batch -y -include-simple  # Fully automated
dovi_convert -batch -force        # Include Complex FEL
dovi_convert -batch -delete       # Auto-delete backups after success
```

**Safety behavior:**
- Complex FEL files are skipped unless `-force` is used
- Simple FEL files pause for confirmation unless `-include-simple` is used
- `-y` alone skips confirmation prompts but still pauses on Simple FEL


### 5. Cleanup (`-cleanup`)

Deletes `.bak.dovi_convert` backup files.

```bash
dovi_convert -cleanup         # Current directory
dovi_convert -cleanup -r      # Recursive
```

**Safety:** Checks if the parent MKV exists. Orphan backups (where the converted file is missing) are not deleted.

### 6. Update Check (`-update-check`)

The tool checks for updates in the background. A notification appears on the next run if an update is available.

```bash
dovi_convert -update-check    # Check immediately
```

## Troubleshooting

If a conversion fails:

1. Run with `-debug` to generate a log:
   ```bash
   dovi_convert -convert "Fail.mkv" -debug
   ```
2. Check `dovi_convert_debug.log` for errors from dovi_tool or ffmpeg.


## Caveats and Notes

### 1. A Note on FEL (Full Enhancement Layer)

This script discards the Enhancement Layer while retaining the RPU (dynamic metadata). For most content, this works well. However, some films use FEL to elevate brightness beyond the base layer (e.g., a 4000-nit master where the HDR10 base is a 1000-nit trim). For these titles, the retained RPU will lead to incorrect tone mapping (darker picture, flickering, and other issues)because it was designed for the combined layers.

| Type | Description |
|------|-------------|
| **MEL** | No EL data. Safe to convert. Very common. |
| **Simple FEL** | FEL exists but does not expand brightness. Safe to convert. |
| **Complex FEL** | FEL expands brightness. Conversion causes incorrect tone mapping. |

**Detection:** The scan feature automatically distinguishes these types. Complex FEL files are skipped by default.

**Recommendation:** For verified Complex FEL titles, watch the HDR10 base layer or use a FEL-capable player (e.g., Ugoos AM6B+) instead of converting.

**Reference:** Cross-check results with the [Official DoVi_Scripts FEL List](https://docs.google.com/spreadsheets/d/15i0a84uiBtWiHZ5CXZZ7wygLFXwYOd84/edit?gid=828864432#gid=828864432) (maintained by R3S3t999, author of [DoVi_Scripts](https://github.com/R3S3t9999/DoVi_Scripts)).

**Additional caveat:** Some FEL titles contain reconstructive data beyond luminance (film grain, noise, color fixes). Since your device cannot handle FEL anyway, discarding it means losing these enhancements - but you retain the critical Dolby Vision dynamic metadata.

### 2. Single Video Track Only

The converted file contains one video track (the main movie). Secondary streams (Picture-in-Picture, Multi-Angle) are dropped because the conversion isolates the main track.

All audio and subtitle tracks are preserved. Your original file is backed up, so no data is lost.

### 3. Apple TV and Plex

If you use **Plex on Apple TV 4K**, you may encounter "Fake Dolby Vision" regardless of tvOS version or DV profile.

- **Technical Reality:** Apple added native Profile 8.1 support in tvOS 17, but Plex's implementation (via AVPlayer) is inconsistent.
- **The Issue:** Plex triggers the "Dolby Vision" logo on your TV but often fails to apply the RPU metadata. Result: HDR10 in a DV container.
- **Plex vs Infuse:** Infuse uses a custom player that correctly applies RPU metadata for true Dolby Vision.
- **Recommendation:** For Apple TV, **Infuse** is currently the only reliable option for correct DV playback. It integrates with Plex servers. The free version does not support Dolby Vision.

### 4. Nvidia Shield

The Shield can handle Profile 7 FEL by stripping the EL and injecting the RPU in real-time (what this script does offline).

However, the Shield struggles with high-bitrate content while trying to convert in real-time, causing stuttering or dropped frames. Additionally, the Shield blindly converts any Profile 7 file without checking for Complex FEL - potentially causing incorrect tone mapping. This script analyzes files first and only converts what is safe, avoiding quality loss on problematic titles.
