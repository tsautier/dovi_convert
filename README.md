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

## Usage

**Analyze a file:**
```bash
dovi_convert -check movie.mkv
```

**Convert a single file:**
```bash
dovi_convert -convert movie.mkv
```

**Batch convert a folder (recursively):**
```bash
dovi_convert -batch 2
```

**Cleanup backups (after verifying success):**
```bash
dovi_convert -cleanup
```
