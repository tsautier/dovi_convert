# dovi_convert

A robust Bash script to automate the conversion of **Dolby Vision Profile 7** MKV files (UHD Blu-ray) into **Profile 8.1**.

This conversion ensures compatibility with media players that do not support the Profile 7 Enhancement Layer (EL), such as the **Apple TV 4K** (via Infuse), **Nvidia Shield**, and **Zidoo** players, preventing them from falling back to standard HDR10.

## Key Features
* **Smart Conversion:** Automatically detects Profile 7 files and ignores others (HDR10/SDR/Profile 5).
* **Two Modes:**
    * **Standard:** Uses efficient piping (ffmpeg -> dovi_tool) for speed and zero temp storage.
    * **Safe Mode:** Extracts tracks to disk first. Robust handling for **Seamless Branching** discs (Disney/Marvel) or files with irregular timestamps.
* **Interactive Batch:** Scans folders, calculates total batch size, and asks for confirmation before processing.
* **Safety First:**
    * Original files are **never** overwritten; they are renamed to a specific backup extension.
    * Cleanup tools are non-recursive by default to prevent accidents.
    * "Orphan Check" prevents deleting a backup if the main video file is missing.

## Installation

### Option 1: Quick Download
```bash
wget https://github.com/cryptochrome/dovi_convert/releases/latest/download/dovi_convert.sh
chmod +x dovi_convert.sh
sudo mv dovi_convert.sh /usr/local/bin/dovi_convert
```

### Option 2: Clone Repository (Recommended for updates - Warning: this will give you the latest version, but it may not be stable)
This method allows you to easily update the script using `git pull`.

```bash
git clone [https://github.com/cryptochrome/dovi_convert.git](https://github.com/cryptochrome/dovi_convert.git)
cd dovi_convert
chmod +x dovi_convert.sh
sudo ln -s "$(pwd)/dovi_convert.sh" /usr/local/bin/dovi_convert
```

## Dependencies

Ensure these tools are installed and available in your system `$PATH`:

* `ffmpeg`
* `dovi_tool`
* `mkvtoolnix` (`mkvmerge`, `mkvextract`)
* `mediainfo`
* `jq`
* `bc`

## Usage

### 1. Single File Conversion
```bash
# Default (Standard Mode)
dovi_convert -convert "Movie.mkv"

# Safe Mode (Force disk extraction)
dovi_convert -convert "Movie.mkv" -safe
```
* **Standard Mode:** Fastest. Pipes data directly between tools.
* **Safe Mode:** Slower but more reliable. Use this if Standard Mode fails or if audio/video sync issues occur (common with seamless branching rips).

### 2. Batch Processing
Scans the current directory for Profile 7 files.

```bash
# Scan current directory and 1 level deep (Default)
dovi_convert -batch

# Scan 3 levels deep
dovi_convert -batch 3

# Automated mode (Skip interactive confirmation)
dovi_convert -batch -y
```
**Interactive Flow:**
The tool will:
1.  Scan the directory.
2.  Display the number of files found and the **Total Batch Size** (GB).
3.  Ask if you want to see the file list.
4.  Ask for confirmation to proceed.

Use the `-y` flag to skip these questions and start immediately.

### 3. Cleanup (Disk Space Recovery)
Delete the backup files (`*.mkv.bak.dovi_convert`) generated during conversion.

```bash
# Clean current directory ONLY
dovi_convert -cleanup

# Clean RECURSIVELY (All subfolders)
dovi_convert -cleanup -r

# Auto-confirm deletion (No yes/no prompt)
dovi_convert -cleanup -y
```
**Safety Note:** The cleanup command checks for the "Parent" MKV. If the main movie file is missing, the backup is treated as an "Orphan" and will **not** be deleted to prevent data loss.

### 4. Analysis
Check the Dolby Vision profile of a file without converting.
```bash
dovi_convert -check "Movie.mkv"

# Recursively check all files in folder
dovi_convert -check -r
```

## Global Options

| Flag | Description |
| :--- | :--- |
| `-safe` | Forces Safe Mode (Disk Extraction). Useful for problematic files. |
| `-delete`| **Auto-Delete Backup.** Deletes the original source file immediately after a successful conversion/verification. Use with caution. |
| `-debug` | Generates a `dovi_convert_debug.log` file containing full ffmpeg/dovi_tool output. |
| `-y` | **Auto-Yes.** Automatically answers "Yes" to start-up prompts (Batch Start / Cleanup Deletion). **Note:** This does *not* override safety decisions like Safe Mode fallback. |

## Important Caveats

**1. Single Video Track Output**
The conversion process isolates the main video track to inject the RPU (Dolby Vision metadata). As a result, **secondary video tracks** (such as Picture-in-Picture commentary, Storyboards, or Multi-Angle views) will be dropped in the converted file.
* **Note:** Your original file (containing all tracks) is preserved as a backup, so no data is lost.

**2. Seamless Branching**
Movies authored with "Seamless Branching" (often Disney/Pixar/Marvel discs) effectively stitch multiple video files together. This can cause timestamp errors in `ffmpeg`.
* If Standard Mode fails, the script will suggest **Safe Mode**.
* Safe Mode extracts the raw HEVC stream to disk first, which usually resolves these synchronization issues.

## Troubleshooting

If a conversion fails:
1.  Run the command with the `-debug` flag:
    ```bash
    dovi_convert -convert "Fail.mkv" -debug
    ```
2.  Check the generated `dovi_convert_debug.log` file. It will contain the specific error messages from `dovi_tool` or `ffmpeg`.
