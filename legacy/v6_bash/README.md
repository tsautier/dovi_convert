# Legacy Bash Version (v6.x)

> [!CAUTION]
> **This version is deprecated.** Please use v7+ (Python).

This directory contains the original Bash implementation of dovi_convert, preserved for historical reference.

## Why It's Here

The Bash version was maintained through v6.6.5 and worked well, but became difficult to maintain as features grew. The Python rewrite (v7+) provides:

- Better maintainability and error handling
- 5x faster RPU analysis (`-inspect`)
- Fewer dependencies (no `jq`, `bc`, `curl`)
- Improved cross-platform compatibility

## Do Not Use This Script

If you're here looking for the latest version, please visit the [main repository](https://github.com/cryptochrome/dovi_convert) and download `dovi_convert.py`.
