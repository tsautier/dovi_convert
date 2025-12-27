# dovi_convert

A Bash script to automate the conversion of Dolby Vision Profile 7 MKV files (UHD Blu-ray rips) into Profile 8.1.

This conversion ensures compatibility with media players that do not support the Profile 7 Enhancement Layer (EL), such as the Apple TV 4K (with Plex or Infuse), Nvidia Shield (to a certain extent), Zidoo, and other devices, preventing fallback to standard HDR10 and other issues. The result is a highly compatible file that can be played on a wide range of devices.

### Important Note

Converting Dolby Vision Profile 7 with FEL to Profile 8 is always a compromise. Make sure you read and understand the [Caveats and Notes](#caveats-and-notes) before you use this script.

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
    - [6. Update Check](#6-update-check)
    - [7. Using dovi_convert with a NAS](#7-using-dovi_convert-with-a-nas)
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

Automatically scans MKV files, detects HDR standards (e.g. HDR10, HDR10+, Dolby Vision), and inspects the RPU (Dolby Vision dynamic metadata) of DV Profile 7 files to detect "Complex FEL".

*   **Complex FEL:** Titles where the Full Enhancement Layer (FEL) contains significant brightness information (e.g. a 4000-nit master vs a 1000-nit base layer). Converting these results in incorrect tone mapping. The script **skips** these files by default to prevent quality loss.

### Dolby Vision Dynamic Metadata (RPU) Inspection

A dedicated `-inspect` command to manually verify brightness expansion (Luminance check) if you want to verify the deep scan verdict.

*   **Why use it?** The default deep scan samples a small part of the file to detect meaningful FEL data, but it might miss isolated brightness spikes between the sample points. `-inspect` digs deeper by extracting and analyzing the entire FEL frame-by-frame. This takes significantly longer but provides a definitive answer on whether brightness expansion is present.
* You should always use it if you don't trust the deep scan verdict, especially on Simple FEL files.
*   Because it is "data-heavy" and slow, batch processing is not available for `-inspect`. This feature is designed to be used for "one-off" inspections of individual files, for cases where you are in doubt about the verdict of the default deep scan.

## Compatibility

This script works on:
*   **macOS** (tested on macOS 26)
*   **Linux** (any modern distribution)
*   **Windows** (via WSL - Windows Subsystem for Linux)

## Dependencies

**macOS Prerequisite:** [Homebrew](https://brew.sh) is required for automatic dependency installation.

*   [ffmpeg](https://ffmpeg.org/download.html)
*   [dovi_tool](https://github.com/quietvoid/dovi_tool/releases)
*   [MKVToolNix](https://mkvtoolnix.download/downloads.html)
*   [MediaInfo](https://mediaarea.net/en/MediaInfo/Download)
*   [jq](https://jqlang.github.io/jq/download/)
*   [bc](https://www.gnu.org/software/bc/)
*   [curl](https://curl.se/)

**Automatic Installation (Beta):** If any dependencies are missing, the tool will offer to install them for you using your system's package manager (Homebrew, apt, dnf, or pacman).

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
*   **Green:** Safe to convert (MEL).
*   **Cyan:** Likely safe to convert (Simple FEL).
*   **Red:** Complex FEL (Active Brightness). Conversion is skipped by default.

### 2. Advanced Inspection
If you want to verify a scan verdicts manually (recommended for "Simple FEL" files), use the inspection tool. It analyzes the entire FEL to check for active luminance expansion.
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
Recursively scans for Profile 7 files and converts them. Automatically **skips** Complex FEL files unless `-force` is used.

**Note on Simple FEL:** If the batch detects files marked as "Simple FEL", it will pause and ask for confirmation to ensure they are safe, even if you use `-y`. To automate these, use the `-include-simple` flag.

```bash
dovi_convert -batch           # Process current directory only
dovi_convert -batch 2         # Process 2 folders deep
dovi_convert -batch -y        # Run without confirmation prompts (Stops on Simple FEL)
dovi_convert -batch -y -include-simple  # Run fully automated (Includes Simple FEL)
dovi_convert -batch -force    # Convert ALL files (including Complex FEL)
```

### 5. Cleanup
Deletes the `.bak.dovi_convert` backup files created during conversion.
```bash
dovi_convert -cleanup         # Clean current dir only
dovi_convert -cleanup -r      # Clean recursively
```
**Safety Note:** The script checks if the "Parent" MKV exists. If the main movie file is missing, the backup is treated as an "orphan" and will **not** be deleted.

### 6. Update Check
The tool automatically checks for updates in the background. If a new version is available, a notification is displayed on the next run. To check immediately:
```bash
dovi_convert -update-check
```

### 7. Using dovi_convert with a NAS

If your media library is on a NAS and your system supports running bash scripts with the required dependencies, consider running the script directly on the NAS rather than from another machine.

**Why?** The script processes large files (often 50-80 GB) and needs to read significant portions for conversion, inspection, and even deep scanning. On slower networks such as 1 GbE or WiFi, a single conversion can take 15-20 minutes due to network overhead. Running locally on the NAS eliminates this bottleneck.

**Note:** A Docker container for easier deployment on supported NAS devices is on the [roadmap](ROADMAP.md).

## Troubleshooting

If a conversion fails:

1.  Run the command with the `-debug` flag to generate a full log (`dovi_convert_debug.log`):
    ```bash
    dovi_convert -convert "Fail.mkv" -debug
    ```
2.  Check the log file for errors from `dovi_tool` or `ffmpeg`.

## Caveats and Notes

### 1. A note on FEL (Full Enhancement Layer)
This script discards the Enhancement Layer while retaining the RPU (dynamic metadata). For a lot of content, this works perfectly. However, a number of films use FEL to elevate brightness beyond the base layer (e.g., a 4000-nit master where the HDR10 base layer is a 1000-nit trim pass). For these specific titles, the retained RPU metadata may produce suboptimal tone mapping because it was designed for the combined layers.

*   **MEL (Minimal Enhancement Layer):** These files are safe to convert, as the EL contains no data. This is very common.
*   **FEL (Full Enhancement Layer):** These files contain an active video layer.
    *   **Complex FEL:** A significant number of FEL titles use this layer to expand brightness (as described above). Converting these results in incorrect tone mapping.
    *   **Simple FEL:** Occasionally, FEL is used but does not expand brightness beyond the Base Layer. These are safe.

**Detection:** This tool's "Deep Scan" feature automatically distinguishes between these types. It will advise you to **SKIP** Complex FEL files to prevent quality loss.

**Recommendation:** For verified Complex FEL titles, it is better to watch the HDR10 base layer (or use a dedicated FEL-capable player like the **Ugoos AM6B+**) than to convert them to Profile 8.1.

**Reference List:** If you want to cross-check the scan results of this script, refer to the [Official DoVi_Scripts FEL List](https://docs.google.com/spreadsheets/d/15i0a84uiBtWiHZ5CXZZ7wygLFXwYOd84/edit?gid=828864432#gid=828864432) (maintained by **R3S3t999**, author of [DoVi_Scripts](https://github.com/R3S3t9999/DoVi_Scripts)).

**Additional important caveat:** Some FEL titles contain reconstructive data beyond just luminance, such as film grain, noise, or color fixes. However, this tool assumes your playback device cannot handle FEL. While discarding the FEL means losing these specific visual enhancements, your device would be unable to display them regardless. This conversion ensures that you at least retain the critical Dolby Vision dynamic metadata.

### 2. Single Video Track Only
The converted file will contain exactly one video track (the main movie). Secondary video streams (such as Picture-in-Picture commentary or Multi-Angle views) will be dropped because the conversion process isolates the main video track. All audio and subtitle tracks are preserved.
*   **Note:** Your original file (containing all tracks) is preserved as a [filename].mkv.bak.dovi_convert backup, so no data is lost.

### 3. Apple TV and Plex Caveat

If you are using the **Plex app on Apple TV 4K**, you will likely encounter a "Fake Dolby Vision" issue, regardless of which version of tvOS you use, and regardless of which Dolby Vision profile the file uses.

-   **The Technical Reality:** While Apple officially added **native Profile 8.1 support in tvOS 17**, the Plex app's implementation (which relies on Apple's **AVPlayer** framework for Dolby Vision) is notoriously inconsistent.
-   **the "Fake DV" Issue:** In most cases, Plex will successfully trigger the "Dolby Vision" logo on your TV, but it fails to actually process and apply the dynamic RPU metadata. This means your TV is effectively playing the HDR10 base layer with a Dolby Vision flag - essentially "HDR10 in a Dolby Vision container."
-   **Plex vs. Infuse:** Unlike Plex, the **Infuse** app uses a custom player engine. Infuse is able to correctly leverage the tvOS 17+ native APIs (and its own internal processing) to ensure that the dynamic RPU metadata is actually applied to the video, resulting in a "true" Dolby Vision experience.
-   **Current Status:** Users have reported this behavior for years on the Plex forums. While Plex has occasionally updated their player, they have not yet achieved the same level of Profile 8.1 accuracy as Infuse.
-   **Recommendation:** If your primary playback device is an Apple TV 4K, **Infuse** is currently the only reliable way to ensure Dolby Vision files are played with active, true dynamic metadata. Infuse integrates with your Plex server. Be aware that it is a paid app. The free version does not support Dolby Vision.

### 4. A Note on Nvidia Shield

The Nvidia Shield is technically capable of handling Profile 7 FEL files on its own by stripping the Enhancement Layer (EL) and injecting the RPU (dynamic metadata) into the video in real-time (essentially what the dovi_convert script does).

However, the Shield can struggle with this process, especially with high-bitrate content. This often results in stuttering or skipped frames. For Shield users, this script is a useful tool to perform this conversion offline, pre-stripping the EL and injecting the RPU to ensure smooth and reliable playback for problematic high-bitrate files.

