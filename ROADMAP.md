# Project Roadmap

This document outlines the planned future development for `dovi_convert`.
*Note: This roadmap is subject to change based on user feedback and technical feasibility.*

## Rewrite in Pything
- What started as a simple idea to quickly convert Dolby Vision files to Profile 7 has now turned into a 2000-line Bash script.
- Not ideal. 
- Before implementing any new features (see below), the next big project is to completely re-write everything in Python.
- This will make the script much more robust and easier to maintain.
- It will also make it possible to implement features that are currently not possible with Bash.

## Core Features
- [x] **Automatic Dependency Management**
    - Detect missing tools (ffmpeg, mkvtoolnix, dovi_tool).
    - Auto-install via system package manager (Homebrew, apt, dnf, pacman).
- [ ] **Enhanced Audio Support (Apple TV)**
    - Add option to convert TrueHD Atmos tracks to EAC3 Atmos (using tools like `deezy`).
    - Ensures full spatial audio compatibility on Apple TV and similar devices.
    - Still investigating if this is possible (paid Dolby Vision encoder required).
- [x] **Smart FEL Detection and Analysis**
    - Automatically detect films where the Enhancement Layer significantly impacts brightness.
    - Provide clear warnings or "Purist Grade" ratings during file scanning.
    - Helps identify titles where conversion might lead to suboptimal tone mapping.

## Docker & NAS Support
### Phase 1: The Container
- [ ] **Official Docker Image**
    - Lightweight, plug-and-play container (Alpine Linux base).
    - Pre-packaged with all dependencies (ffmpeg, dovi_tool, mkvtoolnix).
    - Ready for Unraid, TrueNAS, and Synology.
    - Automated builds via GitHub Actions (Docker Hub & GHCR).

### Phase 2: Web Interface (WebUI)
- [ ] **Browser-Based Management**
    - **Visual File Browser:** Navigate storage directly in the browser to find media.
    - **Batch Selection:** Select multiple files or entire folders for processing.
    - **Live Monitoring:** View real-time progress bars and conversation logs.
    - **Backup Management:** Review and clean up backup files easily.
