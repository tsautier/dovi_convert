# dovi_convert

A Bash script to automate the conversion of Dolby Vision Profile 7 MKV files (UHD Blu-ray rips) into Profile 8.1.

This conversion ensures compatibility with media players that do not support the Profile 7 Enhancement Layer (EL), such as the Apple TV 4K (with Plex or Infuse), Nvidia Shield (to a certain extent), Zidoo, and other devices, preventing fallback to standard HDR10 and other issues. The result is a highly compatible file that can be played on a wide range of devices.



## Table of Contents

- [Features](#features)
- [Compatibility](#compatibility)
- [Dependencies](#dependencies)
- [Installation](#installation)
- [Usage](#usage)
    - [1. File Analysis](#1-file-analysis)
    - [2. Single File Conversion](#2-single-file-conversion)
    - [3. Batch Processing](#3-batch-processing)
    - [4. Cleanup](#4-cleanup)
- [Troubleshooting](#troubleshooting)
- [Caveats and Notes](#caveats-and-notes)

## Features

*   **Simple Command Line Interface:** Easy to use if you are comfortable using the terminal.
*   **Single File Conversion:** Convert individual MKV files.
*   **Interactive Batch Conversion:** Recursively process entire directory trees.
*   **Seamless Branching Support:** Handles complex playlists (common on Disney/Marvel discs) to prevent audio sync issues.
*   **Non-Destructive:** Renames original files to `*.bak.dovi_convert` instead of overwriting.

## Compatibility

This script works on:
*   **macOS** (tested on macOS 12 Monterey and later)
*   **Linux** (any modern distribution)
*   **Windows** (via WSL - Windows Subsystem for Linux)

## Dependencies

*   [ffmpeg](https://ffmpeg.org/download.html)
*   [dovi_tool](https://github.com/quietvoid/dovi_tool/releases)
*   [MKVToolNix](https://mkvtoolnix.download/downloads.html)
*   [MediaInfo](https://mediaarea.net/en/MediaInfo/Download)
*   [jq](https://jqlang.github.io/jq/download/)
*   [bc](https://www.gnu.org/software/bc/)

## Installation

### Stable Release
```bash
wget https://github.com/cryptochrome/dovi_convert/releases/latest/download/dovi_convert.sh
chmod +x dovi_convert.sh
sudo mv dovi_convert.sh /usr/local/bin/dovi_convert
```

### From Source (development version)
```bash
git clone https://github.com/cryptochrome/dovi_convert.git && cd dovi_convert
chmod +x dovi_convert.sh
sudo ln -s "$(pwd)/dovi_convert.sh" /usr/local/bin/dovi_convert
```

## Usage

### 1. File Analysis
Check the Dolby Vision profile of files.
```bash
dovi_convert -check              # Check all files in current directory
dovi_convert -check "Film.mkv"   # Check specific file
```

### 2. Single File Conversion
**Standard Mode (Default):** Uses piping to process the video stream. This is the default and fastest method.
```bash
dovi_convert -convert "Movie.mkv"
```

**Safe Mode:** Extracts the video track to disk before converting. Use this if the standard mode fails or results in audio desync (common with seamless branching discs). Note that the script will automatically offer fallback to safe mode if the standard mode fails. You can use the `-safe` switch to force safe mode.
```bash
dovi_convert -convert "Movie.mkv" -safe
```

### 3. Batch Processing
Scans for Profile 7 files and converts them.
```bash
dovi_convert -batch           # Scan current directory only
dovi_convert -batch 2         # Scan 2 folders deep
dovi_convert -batch -y        # Run without confirmation prompts
```

### 4. Cleanup
Deletes the `.bak.dovi_convert` backup files created during conversion.
```bash
dovi_convert -cleanup         # Clean current dir only
dovi_convert -cleanup -r      # Clean recursively
```
**Safety Note:** The script checks if the "Parent" MKV exists. If the main movie file is missing, the backup is treated as an "Orphan" and will **not** be deleted.
## Troubleshooting

If a conversion fails:

1.  Run the command with the `-debug` flag to generate a full log (`dovi_convert_debug.log`):
    ```bash
    dovi_convert -convert "Fail.mkv" -debug
    ```
2.  Check the log file for errors from `dovi_tool` or `ffmpeg`.

## Caveats and Notes

### 1. Single Video Track Only
The converted file will contain exactly one video track (the main movie). Secondary video streams (such as Picture-in-Picture commentary or Multi-Angle views) will be dropped because the conversion process isolates the main video track. All audio and subtitle tracks are preserved.
*   **Note:** Your original file (containing all tracks) is preserved as a backup, so no data is lost.

### 2. A Note on FEL (Full Enhancement Layer)

This script discards the Enhancement Layer while retaining the RPU (dynamic metadata). For **most** content, this works perfectly. However, a small number of films use FEL to **elevate brightness** beyond the base layer (e.g., a 4000-nit master where the HDR10 base layer is a 1000-nit trim pass). For these specific titles, the retained RPU metadata may produce suboptimal tone mapping because it was designed for the combined layers.

**The Reality:**
- Most consumer media players ignore the EL completely anyway (falling back to standard HDR10).
- For the vast majority of titles, the conversion improves compatibility with no visible quality loss.
- For the rare "problematic" titles, consider using a FEL-capable player (like the AM6B+) or simply watching in HDR10 mode.

### 3. Apple TV and Plex Caveat

If you are using the **Plex app on Apple TV 4K**, you will likely encounter a "Fake Dolby Vision" issue, regardless of which version of tvOS you use, and regardless of which Dolby Vision profile the file uses.

- **The Technical Reality:** While Apple officially added **native Profile 8.1 support in tvOS 17**, the Plex app's implementation (which relies on Apple's **AVPlayer** framework for Dolby Vision) is notoriously inconsistent.
- **The "Fake DV" Issue:** In most cases, Plex will successfully trigger the "Dolby Vision" logo on your TV, but it fails to actually process and apply the dynamic RPU metadata. This means your TV is effectively playing the HDR10 base layer with a Dolby Vision flag - essentially "HDR10 in a Dolby Vision container."
- **Plex vs. Infuse:** Unlike Plex, the **Infuse** app uses a custom player engine. Infuse is able to correctly leverage the tvOS 17+ native APIs (and its own internal processing) to ensure that the dynamic RPU metadata is actually applied to the video, resulting in a "True" Dolby Vision experience.
- **Current Status:** Users have reported this behavior for years on the Plex forums. While Plex has occasionally updated their player, they have not yet achieved the same level of Profile 8.1 accuracy as Infuse for local media files (especially MKVs).
- **Recommendation:** If your primary playback device is an Apple TV 4K, **Infuse** is currently the only reliable way to ensure Dolby Vision files are played with active, true dynamic metadata. Infuse integrates with your Plex server. Be aware that it is a paid app. The free version does not support Dolby Vision.

### 4. A Note on Nvidia Shield

The Nvidia Shield is technically capable of handling Profile 7 FEL files on its own by stripping the Enhancement Layer (EL) and injecting the RPU (dynamic metadata) into the video in real-time (essentially what the dovi_convert script does).

However, the Shield can struggle with this process, especially with high-bitrate content. This often results in stuttering or skipped frames. For Shield users, this script is a useful tool to perform this conversion offline, pre-stripping the EL and injecting the RPU to ensure smooth and reliable playback for problematic high-bitrate files.
