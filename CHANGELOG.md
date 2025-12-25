# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [6.6] - 2025-12-25
### Added
- **Automatic Update Check:** The tool now silently checks for updates in the background without slowing down execution (Zero-Latency). If a new version is found, a notification is displayed on the *next* run.
- **Manual Update Check:** Added `-update-check` command to manually check for the latest version and report status immediately.
- **Automatic Dependency Installation (Beta):** If dependencies are missing, the tool now offers to install them automatically. Supports Homebrew (macOS), apt (Ubuntu/Debian), dnf (Fedora), and pacman (Arch).
- **Simple FEL Warning:** The `-convert` command now prompts for confirmation when processing Simple FEL files to match the safety behavior of batch mode.

### Changed
- **Dependencies:** Added `curl` to the list of required dependencies (standard on most systems).

## [6.5.1] - 2025-12-24
### Added
- Batch output now displays separate counts for MEL and Simple FEL files.
- Added warnings when "Simple FEL" files are detected in batch mode.
- `-include-simple` flag to allow automated processing of "Simple FEL" files in batch mode.
- Added context to the check command explaining "Simple FEL" results.

### Changed
- Improved detection logic to be more robust and accurate.
- Improved handling of titles mastered at 4000 nits.
- Batch mode now defaults to pausing if "Simple FEL" files are found, even with `-y`.
- Updated help text descriptions for clarity.

## [6.5] - 2025-12-22
### Added
- **Deep Scan FEL Detection**: New  analysis logic that inspects the RPU structure (Active NLQ/MMR) to deterministically identify "Complex" FEL titles (e.g. FEL that elevates luminance and shouldn't be converted to profile 8.1).
- **`-force` Flag**: Override safety warnings for Complex FEL titles (e.g., `dovi_convert -convert movie.mkv -force`). Works for single file and batch mode.
- **Improved Batch Summary**: Batch mode now tracks "Ignored" (Not Profile 7), "Skipped" (Unsafe), and "Converted" files separately. It also distinguishes between "Simple" and "Forced" conversions in the final report.
- **`-inspect` Command**: New standalone tool to inspect full RPU structure and verify Complex FEL verdicts by checking the entire file's brightness metadata.

### Changed
- **Default Behavior**: `-check` now performs a Deep Scan on Profile 7 files by default.
- **Strict Enforcement**: The tool now hard-fails if the input file is not Dolby Vision Profile 7 (removed interactive prompts for non-P7 files).
- **Safe Mode UI**: Progress numbering aligned to standard workflow (`[1/3] Extracting`, `[1/3] Converting`) for consistency.
- **Arguments**: Arguments can now be passed in any order. Fixed `-r` argument parsing logic.
- **Safety**: Conversion now defaults to skipping/warning on Complex FELs to prevent data loss.

## [6.4.2] - 2025-12-19
### Added
- **Piping Implementation:** Standard conversion now pipes `ffmpeg` output directly to `dovi_tool`. This eliminates temporary disk usage for the video stream and improves processing speed.
- **Batch Summary:** The `-batch` command scans the directory and displays total file count and size before requesting confirmation.
- **Smart Fallback:** Added logic to detect specific stream errors (often caused by Seamless Branching) and offer Safe Mode as a retry option.
- **Debug Logging:** Added `-debug` flag to write full tool output to `dovi_convert_debug.log` for troubleshooting.
- **Global `-y` Flag:** Added support for auto-confirming interactive prompts (batch start and cleanup).
- **Metrics:** Script now reports space saved (EL discarded) and average FPS upon completion.

### Changed
- **Cleanup Scope:** `-cleanup` now defaults to non-recursive scanning. Added `-r` flag to enable recursive mode.
- **Cleanup UI:** The command now lists all files to be deleted before asking for confirmation.
- **UI:** Replaced static text with a spinner for progress indication.
- **Validation:** Added strict argument parsing to prevent syntax errors.

## [6.3]
### Added
- Initial public release.
