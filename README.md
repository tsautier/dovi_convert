# dovi_convert

A Bash script to automate the conversion of Dolby Vision Profile 7 MKV files (UHD Blu-ray rips) into Profile 8.1.

This conversion ensures compatibility with media players that do not support the Profile 7 Enhancement Layer (EL), such as the Apple TV 4K (with Plex or Infuse), Nvidia Shield (to a certain extent), Zidoo, and other devices, preventing fallback to standard HDR10 and other issues. The result is a highly compatible file that can be played on a wide range of devices.

Make sure to read important notes in the [Caveats and Notes](#caveats-and-notes) section.

## Table of Contents

- [Features](#features)
- [Compatibility](#compatibility)
- [Dependencies](#dependencies)
- [Installation](#installation)
- [Usage](#usage)
    - [1. File Analysis](#1-file-analysis)
    - [2. Advanced Inspection](#2-advanced-inspection)
    - [3. Single File Conversion](#3-single-file-conversion)
    - [4. Batch Processing](#4-batch-processing)
    - [5. Cleanup](#5-cleanup)
- [Troubleshooting](#troubleshooting)
- [Caveats and Notes](#caveats-and-notes)

## Features

### Simple Command Line Interface
Easy to use if you are comfortable using the terminal.

### Non-Destructive
Creates backups of original files (`*.bak.dovi_convert`) before converting.

### Two Modes of Operation

**Standard Mode**
Uses "piping" to stream video data directly between tools. This is the fastest method and requires no temporary disk space. Limitation: It may fail on files with irregular structures.

**Safe Mode**
Extracts the video track to a temporary file on disk before converting. This is slower and uses more disk space, but it is robust against structural issues. It engages automatically if the Standard Mode fails (e.g. on "Seamless Branching" discs common from Disney/Marvel), or you can enforce it manually.

### Deep scan file analysis

Automatically analyzes the RPU (Dolby Vision dynamic metadata) of files to detect "Complex FEL".

*   **Complex FEL:** Titles where the Full Enhancement Layer (FEL) contains significant brightness information (e.g. a 4000-nit master vs a 1000-nit base layer). Converting these results in incorrect tone mapping. The script **skips** these files by default to prevent quality loss.

### RPU Inspection

A dedicated `-inspect` command to manually verify brightness expansion (Luminance check) when you want to confirm a "Complex FEL" verdict.

*   **Why use it?** The default deep scan samples the file to detect meaningful data, but it might flag files that are actually safe to convert. `-inspect` digs deeper by extracting and analyzing the entire FEL frame-by-frame. This takes significantly longer but provides a definitive answer on whether brightness expansion is present.

## Compatibility

This script works on:
*   **macOS** (tested on macOS 26)
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
Check the Dolby Vision profile of files and perform a **deep scan** to detect Complex FEL.
```bash
dovi_convert -check              # Analyze all files in current directory
dovi_convert -check -r           # Analyze recursively (default depth 5)
dovi_convert -check -r 2         # Analyze recursively (depth 2)
dovi_convert -check "Film.mkv"   # Analyze specific file
```
The tool will output details with the results of the scan and a verdict for each file:
*   **Green:** Safe to convert (Simple FEL/MEL).
*   **Red:** Complex FEL (Active Brightness). Conversion is skipped by default.

### 2. Advanced Inspection
If you want to verify a "Complex FEL" verdict manually, use the inspection tool. It analyzes the entire FEL to check for active luminance expansion.
```bash
dovi_convert -inspect "Film.mkv"
```
*   **Note:** This command strictly checks for active brightness data (L1 metadata). It does not analyze other reconstruction data, as brightness mismatch is the primary concern for playback compatibility. See [notes below](#1-a-note-on-fel-full-enhancement-layer).

### 3. Single File Conversion
**Standard Mode (Default):** Uses piping. Fastest method.
```bash
dovi_convert -convert "Movie.mkv"
```

**Safe Mode:** Extracts the video track to disk before converting. Required for Seamless Branching titles or files with structural issues.
*   **Automatic Fallback:** The script will automatically offer to use Safe Mode if the Standard Mode fails.
*   **Manual Force:** You can force it manually if you suspect issues:
    ```bash
    dovi_convert -convert "Movie.mkv" -safe
    ```

**Forcing Conversion (Complex FEL):**
To convert a file detected as "Complex FEL" (e.g., if you successfully verified the file with `-inspect` and deemed it safe, or if you accept the potential tone mapping inaccuracy):
```bash
dovi_convert -convert "Complex_Movie.mkv" -force
```

### 4. Batch Processing
Recursively scans for Profile 7 files and converts them. Automatically **skips** Complex FEL files unless `-force` is used, which will convert all files.
```bash
dovi_convert -batch           # Process current directory only
dovi_convert -batch 2         # Process 2 folders deep
dovi_convert -batch -y        # Run without confirmation prompts
dovi_convert -batch -force    # Convert ALL files (including Complex FEL)
dovi_convert -batch 2 -force  # Recursive force conversion
```

### 5. Cleanup
Deletes the `.bak.dovi_convert` backup files created during conversion.
```bash
dovi_convert -cleanup         # Clean current dir only
dovi_convert -cleanup -r      # Clean recursively
```
**Safety Note:** The script checks if the "Parent" MKV exists. If the main movie file is missing, the backup is treated as an "orphan" and will **not** be deleted.

## Troubleshooting

If a conversion fails:

1.  Run the command with the `-debug` flag to generate a full log (`dovi_convert_debug.log`):
    ```bash
    dovi_convert -convert "Fail.mkv" -debug
    ```
2.  Check the log file for errors from `dovi_tool` or `ffmpeg`.

## Caveats and Notes

### 1. A note on FEL (Full Enhancement Layer)
This script discards the Enhancement Layer while retaining the RPU (dynamic metadata). For **most** content, this works perfectly. However, a small number of films use FEL to **elevate brightness** beyond the base layer (e.g., a 4000-nit master where the HDR10 base layer is a 1000-nit trim pass). For these specific titles, the retained RPU metadata may produce suboptimal tone mapping because it was designed for the combined layers.

*   **Detection:** This tool's deep scan feature detects these files and will advise you to **SKIP** them.
*   **Recommendation:** For Complex FEL titles, it is often better to watch the HDR10 base layer (or use a dedicated FEL-capable player like the Ugoos AM6B+) than to convert them to Profile 8.1.
*   **Reference List:** As a last resort, check the [Official DoVi_Scripts FEL List](https://docs.google.com/spreadsheets/d/15i0a84uiBtWiHZ5CXZZ7wygLFXwYOd84/edit?gid=828864432#gid=828864432) (maintained by **RESET_9999**, author of [DoVi_Scripts](https://github.com/R3S3t9999/DoVi_Scripts)) for a maintained list of confimed "Complex FEL" titles.

### 2. Single Video Track Only
The converted file will contain exactly one video track (the main movie). Secondary video streams (such as Picture-in-Picture commentary or Multi-Angle views) will be dropped because the conversion process isolates the main video track. All audio and subtitle tracks are preserved.
*   **Note:** Your original file (containing all tracks) is preserved as a [filename].mkv.bak.dovi_convert backup, so no data is lost.

### 3. Apple TV and Plex Caveat

If you are using the **Plex app on Apple TV 4K**, you will likely encounter a "Fake Dolby Vision" issue, regardless of which version of tvOS you use, and regardless of which Dolby Vision profile the file uses.

-   **The Technical Reality:** While Apple officially added **native Profile 8.1 support in tvOS 17**, the Plex app's implementation (which relies on Apple's **AVPlayer** framework for Dolby Vision) is notoriously inconsistent.
-   **the "Fake DV" Issue:** In most cases, Plex will successfully trigger the "Dolby Vision" logo on your TV, but it fails to actually process and apply the dynamic RPU metadata. This means your TV is effectively playing the HDR10 base layer with a Dolby Vision flag - essentially "HDR10 in a Dolby Vision container."
-   **Plex vs. Infuse:** Unlike Plex, the **Infuse** app uses a custom player engine. Infuse is able to correctly leverage the tvOS 17+ native APIs (and its own internal processing) to ensure that the dynamic RPU metadata is actually applied to the video, resulting in a "True" Dolby Vision experience.
-   **Current Status:** Users have reported this behavior for years on the Plex forums. While Plex has occasionally updated their player, they have not yet achieved the same level of Profile 8.1 accuracy as Infuse.
-   **Recommendation:** If your primary playback device is an Apple TV 4K, **Infuse** is currently the only reliable way to ensure Dolby Vision files are played with active, true dynamic metadata. Infuse integrates with your Plex server. Be aware that it is a paid app. The free version does not support Dolby Vision.

### 4. A Note on Nvidia Shield

The Nvidia Shield is technically capable of handling Profile 7 FEL files on its own by stripping the Enhancement Layer (EL) and injecting the RPU (dynamic metadata) into the video in real-time (essentially what the dovi_convert script does).

However, the Shield can struggle with this process, especially with high-bitrate content. This often results in stuttering or skipped frames. For Shield users, this script is a useful tool to perform this conversion offline, pre-stripping the EL and injecting the RPU to ensure smooth and reliable playback for problematic high-bitrate files.
