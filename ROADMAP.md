# Project Roadmap

This document outlines planned future development for `dovi_convert`.

> **Note:** This roadmap is subject to change based on user feedback and technical feasibility.

---

## In Progress

### Python Rewrite
What started as a simple idea has grown into a 2000-line Bash script. Before adding major new features, the plan is to rewrite the core in Python for improved maintainability and robustness.

---

## Planned

### Convert to HDR10
New command to convert Complex FEL files to pure HDR10 instead of Profile 8.1, by stripping the Dolby Vision layers entirely and only retaining the HDR10 base layer. Useful for Complex FEL files where standard conversion would cause incorrect tone mapping. Includes optional backup of removed DV layers for future restoration.

### Configurable Scan Samples for -scan
Add `-samples N` flag to increase sampling during FEL analysis. Default remains 10; users can set 10-30 for taking more samples and improving the detection of brightness expansion - at the cost of longer processing time. `-inspect`remains the go to option for detailed analysis.

### FEL Threshold Adjustment  
Reduce false positives in Complex FEL detection by adjusting the brightness threshold. Add `-threshold N` flag for power users who want to fine-tune detection sensitivity.

### Docker Container
Lightweight, plug-and-play container with all dependencies pre-packaged. Target platforms: Unraid, TrueNAS, Synology, QNAP, and any Docker-compatible NAS. Automated builds via GitHub Actions. Possibly with a web based shell (ttyd + XTerm.js)

### Custom Output Path
Support `-o /path` flag to write converted files to a different directory. Enables automation workflows (Automator, watch folders) without re-trigger issues.

---

## Under Consideration

### HDR10 Restoration from Backup
Automated command to restore full Profile 7 FEL from HDR10 output + saved DV layer backups. Depends on "Convert to HDR10" feature.

### Web Interface (Docker Phase 2)
Browser-based management UI for NAS users: visual file browser, batch selection, live progress monitoring, and backup management. Depends on Docker container release.

### TrueHD Atmos to EAC3 Atmos Conversion
Convert TrueHD Atmos audio tracks to EAC3 Atmos for Apple TV compatibility. Feasibility still under investigation (may require paid Dolby encoder license).
