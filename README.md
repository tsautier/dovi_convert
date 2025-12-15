# dovi_convert

A Bash utility to automate the conversion of **Dolby Vision Profile 7** MKV files (UHD Blu-ray) into **Profile 8.1**.

## Why use this?

UHD Blu-ray discs use a complex "Dual Layer" Dolby Vision structure (Profile 7) that many media players cannot process correctly. While some devices can play the files, they often lack the specific hardware decoder required to handle the secondary video track (Enhancement Layer).

This mismatch often results in:
* **Silent Fallback to HDR10:** The player ignores the Dolby Vision metadata entirely, losing the scene-by-scene brightness optimization (common on **Apple TV 4K** via Infuse/Plex).
* **Instability:** Stuttering, freezing, or audio desync caused by the player struggling to parse the complex dual-layer structure (common on devices like the **Nvidia Shield Pro** with specific high-bitrate titles).

**The Solution:**
This tool converts the file to **Profile 8.1**. It retains the high-quality video and the dynamic Dolby metadata (RPU) but discards the problematic Enhancement Layer. This creates a highly compatible "Single Layer" file that plays perfectly on virtually all Dolby Vision-capable devices, including the Apple TV 4K, Shield, Fire TV, and internal TV apps.

## Features

* **Safe Mode:** Never modifies the original file in place. It creates a specific backup (`*.mkv.bak.dovi_convert`) and only deletes it if you explicitly use the `-delete` flag.
* **Smart Cleanup:** The cleanup command is context-aware. It will refuse to delete a backup if the main movie file is missing, preventing accidental data loss.
* **FPS Safety:** Enforces the original frame rate to prevent `mkvmerge` from defaulting raw streams to 25fps.
* **Batch Processing:** Can recursively scan and convert entire libraries.

## Requirements

* **Linux / macOS**
* `mkvtoolnix` (mkvmerge, mkvextract)
* `dovi_tool`
* `mediainfo`
* `jq`
* `bc`

## Installation

1.  Clone the repository:
    ```bash
    git clone [https://github.com/YOUR_USERNAME/dovi_convert.git](https://github.com/YOUR_USERNAME/dovi_convert.git)
    cd dovi_convert
    ```

2.  Make it executable and link it to your path:
    ```bash
    chmod +x dovi_convert.sh
    sudo ln -s "$(pwd)/dovi_convert.sh" /usr/local/bin/dovi_convert
    ```

## Usage Guide

### 1. Analysis
Before converting, you can check which files in your library are actually Profile 7. The tool identifies Profile 7 (Target), Profile 8.1 (Already compatible), and Profile 5 (used by streaming services).

* **Check a single file:**
    ```bash
    dovi_convert -check "Movie Name.mkv"
    ```
* **Check the current folder:**
    ```bash
    dovi_convert -check
    ```
* **Check recursively (scan subfolders):**
    Use the `-r` flag followed by the depth level (e.g., scan 3 folders deep). If no depth is specified, it will scan 3 folders deep (default).
    ```bash
    dovi_convert -check -r 2
    ```

---

### 2. Single File Conversion
This is the safest method for testing. The script will **not** delete your original file.

```bash
dovi_convert -convert "Movie Name.mkv"
```

**What happens:**
1.  The original file is renamed to `Movie Name.mkv.bak.dovi_convert`.
2.  The new Profile 8.1 version is created as `Movie Name.mkv`.
3.  Metadata, audio tracks, and chapters are cloned exactly.

---

### 3. Batch Processing
Automatically find and convert all Profile 7 files in a directory tree.

* **Standard Batch (Keep Backups):**
    This scans the current folder and subfolders (Depth 2 in this example). Originals are kept as backups. If no depth is specified, it will convert all files in the current folder.
    ```bash
    dovi_convert -batch 2
    ```

* **Batch with Auto-Delete (Destructive):**
    Use the `-delete` flag to automatically remove the original source file **only after** the conversion is verified successfully. Use this if you lack disk space for backups. Or, if you have used the script often and trust it.
    ```bash
    dovi_convert -batch 2 -delete
    ```

---

### 4. Maintenance & Cleanup
If you converted files without the `-delete` flag, you will have `.bak.dovi_convert` files taking up space.

* **Smart Cleanup:**
    This command recursively finds backup files and offers to delete them.
    ```bash
    dovi_convert -cleanup
    ```
    **Safety Note:** This feature is "Context Aware." It checks if the parent MKV file still exists. If you deleted the converted movie, the script will consider the backup an "Orphan" and **refuse to delete it**, saving you from accidental data loss.

---

### 5. Troubleshooting
If a conversion fails or you need more details, use the verbose flag.

* **Debug Mode:**
    Prints the full output of `mkvmerge`, `mkvextract`, and `dovi_tool` to the console.
    ```bash
    dovi_convert -convert file.mkv -v
    ```
