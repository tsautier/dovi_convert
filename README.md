# dovi_convert

[![Documentation](https://img.shields.io/badge/docs-doviconvert.com-blue)](https://docs.doviconvert.com)

<br>

**Convert Dolby Vision Profile 7 MKV files to Profile 8.1 for universal playback compatibility.**

## Why?

Most streaming devices (Apple TV, Shield, Amazon Fire*, etc.) don't support Profile 7's Enhancement Layer. They either fall back to HDR10 or blindly strip the layer, potentially ruining the picture.

**dovi_convert** analyzes files first, converts only what's safe, and preserves dynamic metadata for correct Dolby Vision playback.

## What's New (v7.1.0)

**Key improvements:** 

Multi-file convert, target directories, temp directory for HDD/NAS performance, directory grouping in scans, and more.

See [CHANGELOG.md](CHANGELOG.md) for full details.

## Documentation

> [!IMPORTANT]
> Reading the documentation before you begin is highly recommended.

**Full documentation, guides, and command reference:**

### **[docs.doviconvert.com](https://docs.doviconvert.com)**

## Compatibility

- **macOS** (tested on macOS 26)
- **Linux** (any modern distribution)
- **Windows** (via WSL2 or Docker)

## Requirements

- Python 3.8+
- ffmpeg, mkvtoolnix, mediainfo, [dovi_tool](https://github.com/quietvoid/dovi_tool)

Missing dependencies are detected and can be installed automatically.

## Quick Start

> [!IMPORTANT]
> **Upgrading from v6.x?** v7.0.0 is a complete Python rewrite. Dependencies have changed. Please ensure you have **Python 3.8+** installed and read the updated [installation instructions](https://docs.doviconvert.com/installation/terminal).
>
> **Docker users:** If you were testing the `:beta` tag, switch to `:latest`. The `:beta` tag will be deprecated.


### Terminal

```bash
curl -sSLO https://github.com/cryptochrome/dovi_convert/releases/latest/download/dovi_convert.py
chmod +x dovi_convert.py && sudo mv dovi_convert.py /usr/local/bin/dovi_convert
```

### Docker

#### docker run

```bash
docker run -d \
  --name=dovi_convert \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Europe/Berlin \
  -p 7681:7681 \
  -v /path/to/media:/data \
  --restart unless-stopped \
  cryptochrome/dovi_convert:latest
```

#### docker-compose.yml

```yaml
services:
  dovi_convert:
    image: cryptochrome/dovi_convert:latest
    container_name: dovi_convert
    environment:
      - PUID=1000 # Change to required User ID, if needed
      - PGID=1000 # Change to required Group ID, if needed
      - TZ=Europe/Berlin # Change to your timezone
    volumes:
      - /path/to/media:/data # Change to your media directory
    ports:
      - 7681:7681 # Change left port to your desired port (e. g. 8080:7681)
    restart: unless-stopped
```

Access the web terminal at `http://<your-docker-host>:7681`.

## Basic Usage

```bash
dovi_convert -scan              # Analyze files in current directory
dovi_convert -convert Movie.mkv # Convert a single file
dovi_convert -batch             # Batch convert directory
```

## Before You Convert

- Not all Profile 7 files should be converted. Some use the Enhancement Layer for brightness expansion, which causes incorrect tone mapping if removed.
- The tool detects these "Complex FEL" files and skips them by default. Don't use `-force` unless you understand the consequences.
- FEL can also contain film grain, noise, and color data. Retaining this data during conversion requires re-encoding, which is out of scope. Your player can't decode FEL anyway, so this data is already inaccessible. You do retain the Dolby Vision dynamic metadata (RPU).
- Original files are backed up automatically. The `-delete` flag removes them permanently.
- Read [Before You Start](https://docs.doviconvert.com/before-you-start) for the full explanation.

## Changelog & Roadmap

- [CHANGELOG.md](CHANGELOG.md) - Version history
- [ROADMAP.md](ROADMAP.md) - Planned features

## Credits

- [dovi_tool](https://github.com/quietvoid/dovi_tool) by quietvoid
- [dovi_scripts](https://github.com/R3S3t9999/dovi_scripts) by R3S3t9999 - for inspiration and knowledge (the OG)
- [FFmpeg](https://ffmpeg.org/)
- [MKVToolNix](https://mkvtoolnix.download/)
- [MediaInfo](https://mediaarea.net/en/MediaInfo)

## License

MIT
