# Changelog 13: Full GNU Shell Environment (GNU Bash, Sudo, Coreutils)

## Summary of Changes
- **Full GNU Shell Environment**:
  - Integrated `bash`, `bash-completion`, `sudo`, `coreutils` (full versions of `echo`, `mkdir`, `touch`, `cat`, `rm`, `cp`, `mv`, `ls`, etc.), `findutils`, `grep`, `sed`, `gawk`, `nano`, and `less`.
  - Configured `/etc/sudoers.d/wheel` and `/etc/sudoers.d/root` with passwordless privileges (`NOPASSWD: ALL`), `secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"`, and `Defaults env_keep += "PATH"`. Bare sudo calls (`sudo echo`, `sudo mkdir`, `sudo cat`, `sudo nano`) work immediately.
  - Set root's default shell to `/bin/bash` with interactive features: custom colored prompt (`bootos:\w# `), command history, colorized aliases (`ls`, `ll`, `la`, `l`, `grep`, `menu`), and full tab-completion.
- **BootOS Main Menu Option `[9]` Enhancements**:
  - Main menu Option `[9]` upgraded to `Open Root Terminal Shell (GNU Bash, sudo, Coreutils)`.
  - Invokes `/bin/bash -i` with environment isolation (`BOOTOS_SHELL=1 HOME=/root USER=root SHELL=/bin/bash`) to prevent `/etc/profile.d/bootos.sh` from recursively triggering the main menu.
  - Exiting the subshell (`exit`) or typing `menu` seamlessly returns the user back to the interactive BootOS main menu.
- **Persistence Across Reboots**:
  - All files, directories, shell history, and configurations created in the shell are saved to the designated storage partition via Option `[10]` or auto-saved upon choosing Option `[11]` (Reboot).
- **ISO Size Efficiency**:
  - Resulting bootable ISO size is **~417 MB**, well below the 1 GB constraint and easily deployable to a 2GB USB flash drive.
