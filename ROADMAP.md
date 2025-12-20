# Project Roadmap

This document outlines the planned future development for `dovi_convert`.
*Note: This roadmap is subject to change based on user feedback and technical feasibility.*

## Core Features
- [ ] **Automatic Dependency Management**
    - Detect missing tools (ffmpeg, mkvtoolnix, dovi_tool).
    - Auto-install via system package manager (Homebrew, apt, dnf, pacman).
- [ ] **Enhanced Audio Support (Apple TV)**
    - Add option to convert TrueHD Atmos tracks to EAC3 Atmos (using tools like `deezy`).
    - Ensures full spatial audio compatibility on Apple TV and similar devices.
- [ ] **Smart FEL Detection and Analysis**
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
