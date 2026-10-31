# Changelog 25: Native Windows 11 File Explorer for BootOS

## Summary of Changes
- **Windows 11 File Explorer Built from Scratch (`src/explorer/`)**:
  - Pure custom application built with zero borrowed desktop environment code or shortcuts.
  - **Mica Dark Theme & Fluent UI**: Windows 11 dark mode design (`#191919`), rounded cards, custom fluent scrollbars, and authentic Segoe UI / Noto Sans typography.
  - **Tabs System**: Multi-tab browsing (`Ctrl+T`, `Ctrl+W`) with custom tab headers, close buttons, and independent directory history.
  - **Command Bar**: Windows 11 action bar with `+ New` dropdown (Folder, Text Document, Shell Script), Cut (`Ctrl+X`), Copy (`Ctrl+C`), Paste (`Ctrl+V`), Rename (`F2`), and Delete (`Del`).
  - **Interactive Breadcrumb Address Bar**: Interactive breadcrumb segments (`This PC > Local Disk (C:) > root`), editable text address input on click, and path copy button.
  - **Navigation Pane (Sidebar)**: Quick Access shortcuts (Desktop, Downloads, Documents, Pictures), This PC with live disk usage progress meters (`X GB free of Y GB`), and Linux root shortcuts.
  - **Dual View Modes**: Windows 11 Details view (Name, Date modified, Type, Size) with column sorting, and Large Icons grid view.
  - **Built-in Properties Dialog**: Displays file metadata, location, permissions, size, and modification timestamp.
  - **Built-in Notepad Editor**: Built-in text viewer and editor modal for editing scripts, configs, and text documents directly.
- **Python 3 Backend REST Server (`src/explorer/server.py`)**:
  - Lightweight multithreaded server handling directory listings, disk usage, real filesystem operations (create, delete, rename, copy, move), and process execution with zero external pip dependencies.
- **GUI Launcher & Shell Aliases (`src/explorer-launcher.sh`)**:
  - Automatic Xorg/Openbox integration and Chromium app-mode kiosk window.
  - Created `explorer` and `files` commands in bash prompt.
  - Integrated into BootOS homescreen menu as Option `[2] Launch Windows 11 File Explorer (GUI)`.
- **ISO Rebuild**:
  - Packaged into `bootos.iso` (429 MB, 100% RAM-resident, fits on 2GB USB).
  - All Windows binaries signed with `CN=BootOS Developer`.
