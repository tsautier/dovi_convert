# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
