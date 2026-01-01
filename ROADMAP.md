# Project Roadmap

This document outlines planned future development for `dovi_convert`.

> **Note:** This roadmap is subject to change based on user feedback and technical feasibility.

---

## In Progress

### Python Rewrite
What started as a simple idea has grown into a 2000-line Bash script. Before adding major new features, the plan is to rewrite the core in Python for improved maintainability and robustness.

---

## Planned

### Convert to HDR10 (Strip DV)
Command to convert P7 files to pure, spec-compliant HDR10 by completely removing Dolby Vision metadata. Ideal for Complex FEL titles where P8.1 conversion is undesirable.

### Backup & Restore
Dedicated feature to backup original Dolby Vision layers (EL + RPU) into compact `.dovi` archives before conversion. This enables you to convert to P8.1 or HDR10 and delete the original, while retaining the ability to bit-perfectly restore the full Profile 7 source later (e.g., for future FEL-capable hardware). Saves ~90% disk space compared to keeping full backups (~10GB vs ~80GB).

### Configurable Scan Samples for -scan
Add `-samples N` flag to increase sampling during FEL analysis. Default remains 10; users can set 10-30 for taking more samples and improving the detection of brightness expansion - at the cost of longer processing time. `-inspect`remains the go to option for detailed analysis.

### FEL Threshold Adjustment  
Reduce false positives in Complex FEL detection by adjusting the brightness threshold. Add `-threshold N` flag for power users who want to fine-tune detection sensitivity.

### Custom Output Path
Support `-o /path` flag to write converted files to a different directory. Enables automation workflows (Automator, watch folders) without re-trigger issues.

### Temporary Directory Support
Option to use a separate drive (like an SSD) for intermediate files. This avoids read/write bottleneck when converting files stored on mechanical hard drives, significantly improving speed.

---

## Under Consideration

### Web Interface (Docker Phase 2)
Browser-based management UI for NAS users: visual file browser, batch selection, live progress monitoring, and backup management. Depends on Docker container release.

### TrueHD Atmos to EAC3 Atmos Conversion
Convert TrueHD Atmos audio tracks to EAC3 Atmos for Apple TV compatibility. Feasibility still under investigation (may require paid Dolby encoder license).
