# dovi_convert

A Bash script to automate the conversion of Dolby Vision Profile 7 MKV files (UHD Blu-ray rips) into Profile 8.1.

This conversion ensures compatibility with media players that do not support the Profile 7 Enhancement Layer (EL), such as the Apple TV 4K (with Plex or Infuse), Nvidia Shield, Zidoo, and other devices, preventing fallback to standard HDR10 and other issues. The result is a highly compatible file that can be played on a wide range of devices, without loss of quality.

## Features

*   **Simple Command Line Interface:** Easy to use if you are comfortable using the terminal.
*   **Single File Conversion:** Convert individual MKV files.
*   **Interactive Batch Conversion:** Recursively process entire directory trees.
*   **Seamless Branching Support:** Handles complex playlists (common on Disney/Marvel discs) to prevent audio sync issues.
*   **Non-Destructive:** Renames original files to `*.bak.dovi_convert` instead of overwriting.

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

### From Source
```bash
git clone https://github.com/cryptochrome/dovi_convert.git && cd dovi_convert
chmod +x dovi_convert.sh
sudo ln -s "$(pwd)/dovi_convert.sh" /usr/local/bin/dovi_convert
```

## Usage

### 1. Single File Conversion
```bash
dovi_convert -convert "Movie.mkv"
```
**Standard Mode:** Uses piping to process the video stream. This is the default and fastest method.

```bash
dovi_convert -convert "Movie.mkv" -safe
```
**Safe Mode:** Extracts the video track to disk before converting. Use this if the standard mode fails or results in audio desync (common with seamless branching discs).

### 2. Batch Processing
Scans for Profile 7 files and converts them.
```bash
dovi_convert -batch           # Scan current directory only
dovi_convert -batch 2         # Scan 2 folders deep
dovi_convert -batch -y        # Run without confirmation prompts
```

### 3. Cleanup
Deletes the `.bak.dovi_convert` backup files created during conversion.
```bash
dovi_convert -cleanup         # Clean current dir only
dovi_convert -cleanup -r      # Clean recursively
```
**Safety Note:** The script checks if the "Parent" MKV exists. If the main movie file is missing, the backup is treated as an "Orphan" and will **not** be deleted.

### 4. Analysis
Check the Dolby Vision profile of files.
```bash
dovi_convert -check              # Check all files in current directory
dovi_convert -check "Film.mkv"   # Check specific file
```

## Caveats

**Single Video Track Only**
The converted file will contain exactly one video track (the main movie). Secondary video streams (such as Picture-in-Picture commentary or Multi-Angle views) will be dropped because the conversion process isolates the main video track. All audio and subtitle tracks are preserved.
*   **Note:** Your original file (containing all tracks) is preserved as a backup, so no data is lost.

## Troubleshooting

If a conversion fails:

1.  Run the command with the `-debug` flag to generate a full log (`dovi_convert_debug.log`):
    ```bash
    dovi_convert -convert "Fail.mkv" -debug
    ```
2.  Check the log file for errors from `dovi_tool` or `ffmpeg`.
