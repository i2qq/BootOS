# Changelog 41: Full Native 1080p Display Resolution, Auto-Unmuted Audio, and GUI Clean Exit

### 1. Native High-Resolution Display (Fixing Blurry Scaling)
- Integrated `linux-firmware-radeon` (1.69 MB) for the AMD/ATI Radeon discrete graphics card on the Dell OptiPlex 990.
- Re-enabled `radeon`, `amdgpu`, and `i915` KMS display drivers. With firmware in place, these initialize instantaneously without firmware fallback timeouts.
- Added `xrandr` package and `xrandr --auto` in `.xinitrc` to query the monitor's EDID and switch directly to native 1920x1080 60Hz.
- Configured `--force-device-scale-factor=1` in Chromium to prevent oversized UI scaling.
- Configured `tk scaling 1.0` in `bootos_explorer.py` and added a dedicated `❌ Exit` toolbar button and Escape key binding.

### 2. Audio Subsystem (ALSA & Codecs)
- Integrated `alsa-utils` (`amixer`, `aplay`, `speaker-test`).
- Probed `snd_hda_intel`, `snd_hda_codec_realtek`, `snd_hda_codec_hdmi`, and `snd_hda_codec_generic`.
- Automatically unmuted Master, PCM, Speaker, Headphone, and Front audio channels to 90% volume on startup.
- Configured Chromium with `--audio-backend=alsa` for direct sound playback.

### 3. Clean GUI Exit & VT Switching
- Removed `-novtswitch` from `xinit` in both `explorer-launcher.sh` and `browser-launcher.sh`, allowing Xorg to cleanly restore text VT console mode when exiting.
