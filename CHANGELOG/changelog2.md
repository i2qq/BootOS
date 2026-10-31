# Changelog 2: GitHub Release ISO Downloader & Remote Sync

- **GitHub Release ISO Installer**:
  - Added interactive feature to provide any GitHub repository (e.g. `owner/repo` or full URL / release tag).
  - Automatically queries GitHub API (`/releases/latest` and `/releases/tags/...`) with fallbacks.
  - Detects `.iso`, `.img`, and `.raw` assets with human-readable file sizes.
  - Allows selecting which release asset to download.
  - Provides instant choices:
    1. Direct installation / flashing to internal storage drive (`/dev/sda` or SSD).
    2. Direct Live DRAM boot via loopback extraction and `kexec`.
    3. Save ISO to local partition.
  - Added support for `GITHUB_TOKEN` for private repositories and rate-limit exemption.
- **Dependencies**: Added `jq` package to base Alpine image for robust JSON API parsing.
- **Remote Sync**: Added origin remote `https://github.com/VicRoger27/BootOS.git`.
