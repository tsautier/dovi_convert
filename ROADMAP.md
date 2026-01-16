# Project Roadmap

This document outlines planned future development for `dovi_convert`.

> **Note:** This roadmap is subject to change based on user feedback and technical feasibility.


## Planned Next (in development)

- **Complete Command Syntax Overhaul** - The goal is to align better with Unix conventions and make the syntax more consistent. This will break compatibility with existing scripts, but I think it's worth it. See this [discussion](https://github.com/cryptochrome/dovi_convert/discussions/32) - Thanks to @dzuelke for ideas and inspiration.

- **Merge `-convert` and `-batch`** into a single command. There is so much overlap between the two commands now that it makes sense to merge them into one unified function.

## Planned for the future (in no particular order)

- **Backup & Restore** - Dedicated feature to backup original Dolby Vision layers (EL + RPU) into compact `.dovi` archives before conversion. This enables you to convert to P8.1 or HDR10 and delete the original, while retaining the ability to restore (remux) the full Profile 7 source later (e.g., for future FEL-capable hardware). Saves ~90% disk space compared to keeping full backups (~10GB vs ~80GB).

- **Adjustable Scan Samples** - Add `-samples N` flag to increase sampling during FEL analysis. Default remains 10; users can set 10-50 for taking more samples and improving the detection of brightness expansion - at the cost of longer processing time. `-inspect` remains the go to option for detailed analysis.

- **FEL Threshold Adjustment** - Reduce false positives in Complex FEL detection by adjusting the brightness threshold. Add `-threshold N` flag for power users who want to fine-tune detection sensitivity.

- **Watch Folder Support** - for Docker users, set up a watch folder to automatically trigger conversions when new files are added to the folder.

- **Store `-inspect`verdicts** - Store the verdicts of `-inspect`, so we can re-use them in `-scan`. Use case: If you verifiy a Simple or Complex FEL scan verdict with `-inspect` and it turns out to be a false positive, future scans will pick this up and report the correct verdict.

- **Auto-Inspect Simple FEL During Scan** — New `-inspect-simple` flag for `-scan` that automatically runs full inspection on all Simple FEL files after the scan completes. Eliminates the need to manually run `-inspect` on each file. ([#16](https://github.com/cryptochrome/dovi_convert/issues/16))

## Under Consideration

- **Web Interface (Docker Phase 2)** — Browser-based management UI for NAS users: visual file browser, batch selection, live progress monitoring, and backup management.

- **`-keep-both` Option:** Preserves the original filename (no added *.bak.dovi_convert suffix) and adds `.p81.mkv` suffix to converted file. This allows you to keep both files as .mkv files. Useful for seeding or multi-version-capable media servers (like Plex). If you think this is useful, please open a discussion or issue, so I know you want this.