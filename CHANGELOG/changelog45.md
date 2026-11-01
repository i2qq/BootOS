# Changelog 45: UK/International Keyboard Mapping & Automatic Backtick-to-Pipe Translation

### 1. Embedded Terminal Auto-Translation
- In `bootos_explorer.py`, the embedded terminal automatically converts all backtick `` ` `` characters into pipe `|` characters when `<Return>` (Enter) is pressed.
- Bound `<grave>` key directly to insert `|` in real-time, allowing users on UK/international keyboards where the pipe key scancode produces `<` to effortlessly type pipe commands like `wget -qO- https://... | sudo bash`.

### 2. Linux Console (TTY) & X11 Keyboard Remapping
- In `/init`, configured `loadkeys` to remap keycode 41 (grave) to `bar` and keycode 86 (UK 102nd key next to Z) to `backslash bar`.
- In `browser-launcher.sh`, `explorer-launcher.sh`, and `partition-manager-launcher.sh`, added `xmodmap` rules:
  - `keysym grave = bar asciitilde bar asciitilde`
  - `keycode 94 = backslash bar`
- In `/etc/inputrc`, `/root/.inputrc`, `/etc/bash/bashrc`, and `/root/.bashrc`, added readline keybinding `bind '"`": "|"'`.
