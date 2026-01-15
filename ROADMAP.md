# Project Roadmap

This document outlines planned future development for `dovi_convert`.

> **Note:** This roadmap is subject to change based on user feedback and technical feasibility.


## Planned (in no particular order)

- **Backup & Restore** — Dedicated feature to backup original Dolby Vision layers (EL + RPU) into compact `.dovi` archives before conversion. This enables you to convert to P8.1 or HDR10 and delete the original, while retaining the ability to bit-perfectly restore the full Profile 7 source later (e.g., for future FEL-capable hardware). Saves ~90% disk space compared to keeping full backups (~10GB vs ~80GB).

- **Adjustable Scan Samples** — Add `-samples N` flag to increase sampling during FEL analysis. Default remains 10; users can set 10-50 for taking more samples and improving the detection of brightness expansion - at the cost of longer processing time. `-inspect` remains the go to option for detailed analysis.

- **FEL Threshold Adjustment** — Reduce false positives in Complex FEL detection by adjusting the brightness threshold. Add `-threshold N` flag for power users who want to fine-tune detection sensitivity.

- **Watch Folder Support** - for Docker users, set up a watch folder to automatically trigger conversions when new files are added to the folder.

- **Store `-inspect`verdicts** - Store the verdicts of `-inspect`, so we can re-use them in `-scan`. Use case: If you verifiy a Simple or Complex FEL scan verdict with `-inspect` and it turns out to be a false positive, future scans will pick this up and report the correct verdict.

## Under Consideration

- **Auto-Inspect Simple FEL During Scan** — New `-inspect-simple` flag for `-scan` that automatically runs full inspection on all Simple FEL files after the scan completes. Eliminates the need to manually run `-inspect` on each file. ([#16](https://github.com/cryptochrome/dovi_convert/issues/16))

- **Web Interface (Docker Phase 2)** — Browser-based management UI for NAS users: visual file browser, batch selection, live progress monitoring, and backup management.

- **TrueHD Atmos to EAC3 Atmos Conversion** — Convert TrueHD Atmos audio tracks to EAC3 Atmos for Apple TV compatibility. Feasibility still under investigation (may require paid Dolby encoder license).

- **`-keep-both`Option:** Preserves the original filename (no added *.bak.dovi_convert suffix) and adds `.p81.mkv` suffix to converted file. This allows you to keep both files as .mkv files. Useful for seeding or multi-version-capable media servers (like Plex). If you think this is useful, please open a discussion or issue, so I know you want this.