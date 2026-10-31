#!/usr/bin/env python3
"""
BootOS File Explorer
A pure native desktop application built with Python 3 and Tkinter/ttk.
No web browser, no local server, no HTML/CSS - 100% native desktop process.
Styled with Windows 11 Dark Mode aesthetics (Mica dark #191919, #202020).
"""

import os
import sys
import time
import shutil
import subprocess
import tkinter as tk
from tkinter import ttk, messagebox, simpledialog

# Windows 11 Dark Theme Color Palette
CLR_BG = "#191919"           # Deep Mica canvas
CLR_SIDEBAR = "#202020"      # Navigation sidebar
CLR_SURFACE = "#2b2b2b"      # Controls and entry fields
CLR_HOVER = "#333333"        # Hover state
CLR_SELECTED = "#005fb8"     # Windows 11 blue selection
CLR_TEXT = "#ffffff"         # Primary text
CLR_TEXT_MUTED = "#9d9d9d"   # Secondary text / metadata
CLR_BORDER = "#383838"       # Subtle border lines
CLR_ACCENT = "#60cdff"       # Windows 11 cyan accent

def format_size(bytes_num):
    if bytes_num is None:
        return ""
    if bytes_num < 1024:
        return f"{bytes_num} B"
    elif bytes_num < 1024 * 1024:
        return f"{bytes_num / 1024:.1f} KB"
    elif bytes_num < 1024 * 1024 * 1024:
        return f"{bytes_num / (1024 * 1024):.1f} MB"
    else:
        return f"{bytes_num / (1024 * 1024 * 1024):.2f} GB"

def get_file_type_and_icon(name, is_dir):
    if is_dir:
        return "File folder", "📁"
    ext = os.path.splitext(name)[1].lower()
    mapping = {
        ".txt": ("Text Document", "📄"),
        ".md": ("Markdown Document", "📄"),
        ".log": ("Log File", "📄"),
        ".json": ("JSON File", "📜"),
        ".xml": ("XML Document", "📜"),
        ".yaml": ("YAML Config", "📜"),
        ".yml": ("YAML Config", "📜"),
        ".sh": ("Shell Script", "📜"),
        ".bash": ("Bash Script", "📜"),
        ".py": ("Python File", "🐍"),
        ".c": ("C Source File", "⚙"),
        ".h": ("C Header File", "⚙"),
        ".png": ("PNG Image", "🖼"),
        ".jpg": ("JPEG Image", "🖼"),
        ".jpeg": ("JPEG Image", "🖼"),
        ".gif": ("GIF Image", "🖼"),
        ".svg": ("SVG Image", "🖼"),
        ".iso": ("Disc Image File", "💿"),
        ".img": ("Disk Image File", "💿"),
        ".tar": ("TAR Archive", "📦"),
        ".gz": ("GZ Archive", "📦"),
        ".zip": ("ZIP Archive", "📦"),
        ".7z": ("7-Zip Archive", "📦"),
        ".mp3": ("MP3 Audio", "🎵"),
        ".wav": ("WAV Audio", "🎵"),
        ".mp4": ("MP4 Video", "🎬"),
        ".mkv": ("MKV Video", "🎬"),
        ".pdf": ("PDF Document", "📕"),
        ".exe": ("Executable App", "⚙"),
        ".conf": ("Config File", "🔧"),
    }
    return mapping.get(ext, (f"{ext[1:].upper()} File" if ext else "File", "📄"))

def get_system_drives():
    drives = []
    if os.name == 'nt':
        for letter in 'CDEFGHIJKLMNOPQRSTUVWXYZ':
            root = f"{letter}:\\"
            if os.path.exists(root):
                try:
                    usage = shutil.disk_usage(root)
                    name = "Local Disk" if letter in "CD" else "USB Drive" if letter == "E" else "Removable Disk"
                    drives.append({
                        "name": f"{name} ({letter}:)",
                        "path": root,
                        "free_fmt": format_size(usage.free),
                        "total_fmt": format_size(usage.total),
                        "percent": round((usage.used / usage.total) * 100, 1) if usage.total else 0
                    })
                except Exception:
                    pass
    else:
        # Linux / BootOS
        try:
            root_u = shutil.disk_usage("/")
            drives.append({
                "name": "BootOS System (C:)",
                "path": "/",
                "free_fmt": format_size(root_u.free),
                "total_fmt": format_size(root_u.total),
                "percent": round((root_u.used / root_u.total) * 100, 1) if root_u.total else 0
            })
        except Exception:
            pass

        if os.path.exists("/tmp"):
            try:
                tmp_u = shutil.disk_usage("/tmp")
                drives.append({
                    "name": "RAM Disk (Z:)",
                    "path": "/tmp",
                    "free_fmt": format_size(tmp_u.free),
                    "total_fmt": format_size(tmp_u.total),
                    "percent": round((tmp_u.used / tmp_u.total) * 100, 1) if tmp_u.total else 0
                })
            except Exception:
                pass

        for base in ["/media", "/mnt"]:
            if os.path.exists(base):
                for item in os.listdir(base):
                    p = os.path.join(base, item)
                    if os.path.isdir(p):
                        try:
                            u = shutil.disk_usage(p)
                            drives.append({
                                "name": f"USB Storage ({item})",
                                "path": p,
                                "free_fmt": format_size(u.free),
                                "total_fmt": format_size(u.total),
                                "percent": round((u.used / u.total) * 100, 1) if u.total else 0
                            })
                        except Exception:
                            pass
    return drives

class TabData:
    def __init__(self, initial_path):
        self.path = os.path.abspath(initial_path)
        self.history = [self.path]
        self.history_idx = 0
        self.sort_col = "name"
        self.sort_desc = False

class BootOSExplorerApp(tk.Tk):
    def __init__(self):
        super().__init__()

        self.title("BootOS File Explorer")
        self.geometry("1100x680")
        self.minsize(800, 500)
        self.configure(bg=CLR_BG)

        # Application state
        self.tabs_data = {}  # tab_id -> TabData
        self.clipboard = {"action": None, "paths": []}
        self.show_hidden = False

        self.setup_styles()
        self.build_ui()

        # Start initial tab
        initial_dir = os.path.abspath("C:\\") if os.name == 'nt' else os.path.expanduser("~")
        if not os.path.exists(initial_dir):
            initial_dir = "/"
        self.create_tab(initial_dir)

    def setup_styles(self):
        self.style = ttk.Style(self)
        self.style.theme_use("clam")

        # Configure generic colors
        self.style.configure(".", background=CLR_BG, foreground=CLR_TEXT, borderwidth=0)
        
        # Notebook (Tabs)
        self.style.configure("TNotebook", background="#141414", borderwidth=0)
        self.style.configure("TNotebook.Tab", background="#1a1a1a", foreground=CLR_TEXT_MUTED,
                             padding=[14, 6], font=("Segoe UI", 9, "bold"), borderwidth=0)
        self.style.map("TNotebook.Tab",
                       background=[("selected", CLR_BG), ("active", CLR_HOVER)],
                       foreground=[("selected", CLR_TEXT), ("active", CLR_TEXT)])

        # Treeview (File list & Sidebar)
        self.style.configure("File.Treeview",
                             background=CLR_BG,
                             foreground=CLR_TEXT,
                             fieldbackground=CLR_BG,
                             rowheight=28,
                             font=("Segoe UI", 10),
                             borderwidth=0)
        self.style.map("File.Treeview",
                       background=[("selected", CLR_SELECTED)],
                       foreground=[("selected", "#ffffff")])

        self.style.configure("Sidebar.Treeview",
                             background=CLR_SIDEBAR,
                             foreground=CLR_TEXT,
                             fieldbackground=CLR_SIDEBAR,
                             rowheight=26,
                             font=("Segoe UI", 9),
                             borderwidth=0)
        self.style.map("Sidebar.Treeview",
                       background=[("selected", CLR_HOVER)],
                       foreground=[("selected", CLR_ACCENT)])

        # Treeview Column Headers
        self.style.configure("Treeview.Heading",
                             background=CLR_BG,
                             foreground=CLR_TEXT_MUTED,
                             font=("Segoe UI", 9, "bold"),
                             padding=[6, 4],
                             borderwidth=1,
                             relief="flat")
        self.style.map("Treeview.Heading",
                       background=[("active", CLR_HOVER)],
                       foreground=[("active", CLR_TEXT)])

        # Buttons
        self.style.configure("Tool.TButton",
                             background=CLR_SURFACE,
                             foreground=CLR_TEXT,
                             font=("Segoe UI", 9),
                             padding=[8, 4],
                             borderwidth=1,
                             relief="flat")
        self.style.map("Tool.TButton",
                       background=[("active", CLR_HOVER)],
                       foreground=[("active", CLR_ACCENT)])

    def build_ui(self):
        # 1. Top Tabs Row
        tab_bar_frame = tk.Frame(self, bg="#141414", height=38)
        tab_bar_frame.pack(fill=tk.X, side=tk.TOP)

        self.notebook = ttk.Notebook(tab_bar_frame)
        self.notebook.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=4, pady=(4, 0))
        self.notebook.bind("<<NotebookTabChanged>>", self.on_tab_changed)

        btn_new_tab = tk.Button(tab_bar_frame, text=" + ", font=("Segoe UI", 10, "bold"),
                                bg="#141414", fg=CLR_TEXT_MUTED, activebackground=CLR_HOVER,
                                activeforeground=CLR_TEXT, bd=0, relief="flat", cursor="hand2",
                                command=lambda: self.create_tab(self.get_current_path()))
        btn_new_tab.pack(side=tk.LEFT, padx=4, pady=(4, 0))

        # 2. Command / Navigation Bar
        nav_frame = tk.Frame(self, bg=CLR_BG, height=44, bd=0)
        nav_frame.pack(fill=tk.X, side=tk.TOP, padx=8, pady=4)

        # Back, Forward, Up, Refresh
        self.btn_back = self.create_nav_button(nav_frame, "🡰", self.nav_back, "Back (Alt+Left)")
        self.btn_fwd = self.create_nav_button(nav_frame, "🡲", self.nav_forward, "Forward (Alt+Right)")
        self.btn_up = self.create_nav_button(nav_frame, "🡱", self.nav_up, "Up one level (Alt+Up)")
        self.btn_refresh = self.create_nav_button(nav_frame, "↻", self.refresh, "Refresh (F5)")

        # Address Breadcrumb / Entry
        self.address_var = tk.StringVar()
        self.address_entry = tk.Entry(nav_frame, textvariable=self.address_var, font=("Segoe UI", 10),
                                      bg=CLR_SURFACE, fg=CLR_TEXT, insertbackground=CLR_TEXT,
                                      bd=1, relief="solid", highlightthickness=1, highlightcolor=CLR_ACCENT)
        self.address_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=6, ipady=3)
        self.address_entry.bind("<Return>", lambda e: self.navigate_to(self.address_var.get()))

        # Search Bar
        search_frame = tk.Frame(nav_frame, bg=CLR_SURFACE, bd=1, relief="solid")
        search_frame.pack(side=tk.RIGHT, padx=4)

        lbl_search = tk.Label(search_frame, text=" 🔍", bg=CLR_SURFACE, fg=CLR_TEXT_MUTED, font=("Segoe UI", 9))
        lbl_search.pack(side=tk.LEFT)

        self.search_var = tk.StringVar()
        self.search_var.trace_add("write", lambda *args: self.filter_items(self.search_var.get()))
        search_entry = tk.Entry(search_frame, textvariable=self.search_var, font=("Segoe UI", 9),
                                bg=CLR_SURFACE, fg=CLR_TEXT, insertbackground=CLR_TEXT,
                                bd=0, width=18)
        search_entry.pack(side=tk.LEFT, padx=4, ipady=3)

        # 3. Action Command Bar (Windows 11 icons)
        cmd_bar = tk.Frame(self, bg=CLR_BG, height=36, bd=0)
        cmd_bar.pack(fill=tk.X, side=tk.TOP, padx=8, pady=(0, 4))

        self.create_cmd_button(cmd_bar, "➕ New Folder", self.action_new_folder)
        self.create_cmd_button(cmd_bar, "📄 New File", self.action_new_file)
        self.create_sep(cmd_bar)
        self.create_cmd_button(cmd_bar, "✂ Cut", self.action_cut)
        self.create_cmd_button(cmd_bar, "📋 Copy", self.action_copy)
        self.create_cmd_button(cmd_bar, "📥 Paste", self.action_paste)
        self.create_cmd_button(cmd_bar, "✏ Rename", self.action_rename)
        self.create_cmd_button(cmd_bar, "🗑 Delete", self.action_delete)
        self.create_sep(cmd_bar)
        self.create_cmd_button(cmd_bar, "💻 Terminal", self.action_terminal)

        # 4. Main Body: Left Sidebar + Right Content
        main_split = tk.PanedWindow(self, orient=tk.HORIZONTAL, bg=CLR_BORDER, bd=0, sashwidth=4)
        main_split.pack(fill=tk.BOTH, expand=True)

        # Sidebar Frame
        sidebar_frame = tk.Frame(main_split, bg=CLR_SIDEBAR, width=220)
        sidebar_frame.pack_propagate(False)
        main_split.add(sidebar_frame, minsize=160)

        # Sidebar Tree
        self.sidebar_tree = ttk.Treeview(sidebar_frame, style="Sidebar.Treeview", show="tree", selectmode="browse")
        self.sidebar_tree.pack(fill=tk.BOTH, expand=True, padx=4, pady=4)
        self.sidebar_tree.bind("<<TreeviewSelect>>", self.on_sidebar_select)
        self.populate_sidebar()

        # Right Content View
        content_frame = tk.Frame(main_split, bg=CLR_BG)
        main_split.add(content_frame, minsize=400)

        # File List Treeview (Details View)
        columns = ("name", "date", "type", "size")
        self.file_tree = ttk.Treeview(content_frame, style="File.Treeview", columns=columns, show="headings", selectmode="extended")
        
        self.file_tree.heading("name", text=" Name", anchor=tk.W, command=lambda: self.sort_by("name"))
        self.file_tree.heading("date", text="Date modified", anchor=tk.W, command=lambda: self.sort_by("date"))
        self.file_tree.heading("type", text="Type", anchor=tk.W, command=lambda: self.sort_by("type"))
        self.file_tree.heading("size", text="Size", anchor=tk.E, command=lambda: self.sort_by("size"))

        self.file_tree.column("name", width=360, minwidth=200, anchor=tk.W)
        self.file_tree.column("date", width=150, minwidth=120, anchor=tk.W)
        self.file_tree.column("type", width=140, minwidth=100, anchor=tk.W)
        self.file_tree.column("size", width=90, minwidth=70, anchor=tk.E)

        # Scrollbar
        scrollbar = ttk.Scrollbar(content_frame, orient=tk.VERTICAL, command=self.file_tree.yview)
        self.file_tree.configure(yscrollcommand=scrollbar.set)
        
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.file_tree.pack(fill=tk.BOTH, expand=True)

        # Events
        self.file_tree.bind("<Double-1>", self.on_item_double_click)
        self.file_tree.bind("<Button-3>", self.show_context_menu)
        self.file_tree.bind("<<TreeviewSelect>>", self.on_file_select)
        self.file_tree.bind("<Return>", lambda e: self.open_selected_item())
        self.file_tree.bind("<Delete>", lambda e: self.action_delete())
        self.file_tree.bind("<F2>", lambda e: self.action_rename())
        self.file_tree.bind("<F5>", lambda e: self.refresh())
        self.file_tree.bind("<BackSpace>", lambda e: self.nav_up())

        # 5. Status Bar at Bottom
        status_bar = tk.Frame(self, bg="#141414", height=24, bd=0)
        status_bar.pack(fill=tk.X, side=tk.BOTTOM)

        self.status_count_lbl = tk.Label(status_bar, text="0 items", bg="#141414", fg=CLR_TEXT_MUTED, font=("Segoe UI", 9))
        self.status_count_lbl.pack(side=tk.LEFT, padx=12, pady=2)

        self.status_selected_lbl = tk.Label(status_bar, text="", bg="#141414", fg=CLR_ACCENT, font=("Segoe UI", 9))
        self.status_selected_lbl.pack(side=tk.LEFT, padx=12, pady=2)

        self.status_free_lbl = tk.Label(status_bar, text="", bg="#141414", fg=CLR_TEXT_MUTED, font=("Segoe UI", 9))
        self.status_free_lbl.pack(side=tk.RIGHT, padx=12, pady=2)

        # 6. Context Menu
        self.context_menu = tk.Menu(self, tearoff=0, bg=CLR_SURFACE, fg=CLR_TEXT, activebackground=CLR_SELECTED, activeforeground="#ffffff", bd=1)
        self.context_menu.add_command(label="Open", command=self.open_selected_item)
        self.context_menu.add_command(label="Open in Terminal", command=self.action_terminal)
        self.context_menu.add_separator()
        self.context_menu.add_command(label="Cut (Ctrl+X)", command=self.action_cut)
        self.context_menu.add_command(label="Copy (Ctrl+C)", command=self.action_copy)
        self.context_menu.add_command(label="Paste (Ctrl+V)", command=self.action_paste)
        self.context_menu.add_separator()
        self.context_menu.add_command(label="Rename (F2)", command=self.action_rename)
        self.context_menu.add_command(label="Delete (Del)", command=self.action_delete)
        self.context_menu.add_separator()
        self.context_menu.add_command(label="New Folder", command=self.action_new_folder)
        self.context_menu.add_command(label="New Text Document", command=self.action_new_file)
        self.context_menu.add_separator()
        self.context_menu.add_command(label="Properties", command=self.show_properties)

    def create_nav_button(self, parent, text, cmd, tooltip=""):
        btn = tk.Button(parent, text=text, font=("Segoe UI", 11), bg=CLR_BG, fg=CLR_TEXT,
                        activebackground=CLR_HOVER, activeforeground=CLR_ACCENT,
                        bd=0, relief="flat", cursor="hand2", command=cmd, width=3)
        btn.pack(side=tk.LEFT, padx=1)
        return btn

    def create_cmd_button(self, parent, text, cmd):
        btn = tk.Button(parent, text=text, font=("Segoe UI", 9), bg=CLR_SURFACE, fg=CLR_TEXT,
                        activebackground=CLR_HOVER, activeforeground=CLR_ACCENT,
                        bd=0, relief="flat", cursor="hand2", command=cmd, padx=8, pady=3)
        btn.pack(side=tk.LEFT, padx=3)
        return btn

    def create_sep(self, parent):
        sep = tk.Frame(parent, bg=CLR_BORDER, width=1, height=18)
        sep.pack(side=tk.LEFT, padx=4)

    # =========================================================================
    # Sidebar
    # =========================================================================
    def populate_sidebar(self):
        self.sidebar_tree.delete(*self.sidebar_tree.get_children())

        # Quick Access Section
        qa_node = self.sidebar_tree.insert("", "end", text="⭐ Quick Access", open=True)
        user_home = os.path.expanduser("~")
        shortcuts = [
            ("🖥 Desktop", os.path.join(user_home, "Desktop")),
            ("📥 Downloads", os.path.join(user_home, "Downloads")),
            ("📄 Documents", os.path.join(user_home, "Documents")),
            ("🖼 Pictures", os.path.join(user_home, "Pictures")),
        ]
        for label, path in shortcuts:
            if os.path.exists(path):
                self.sidebar_tree.insert(qa_node, "end", text=f"  {label}", values=(path,))

        # This PC Section
        pc_node = self.sidebar_tree.insert("", "end", text="💻 This PC", open=True)
        drives = get_system_drives()
        for d in drives:
            label = f"  💾 {d['name']} ({d['free_fmt']} free)"
            self.sidebar_tree.insert(pc_node, "end", text=label, values=(d["path"],))

        # Linux Root Section
        if os.name != 'nt':
            root_node = self.sidebar_tree.insert("", "end", text="📁 Linux Root", open=True)
            for label, path in [("  💻 / (System Root)", "/"),
                                ("  👤 /root (Home)", "/root"),
                                ("  ⚡ /tmp (RAM Disk)", "/tmp"),
                                ("  🔌 /media (USB Drives)", "/media")]:
                if os.path.exists(path):
                    self.sidebar_tree.insert(root_node, "end", text=label, values=(path,))

    def on_sidebar_select(self, event):
        sel = self.sidebar_tree.selection()
        if not sel:
            return
        vals = self.sidebar_tree.item(sel[0], "values")
        if vals and len(vals) > 0 and vals[0]:
            target_path = vals[0]
            if os.path.exists(target_path):
                self.navigate_to(target_path)

    # =========================================================================
    # Tabs System
    # =========================================================================
    def create_tab(self, path):
        path = os.path.abspath(path)
        tab_frame = tk.Frame(self.notebook, bg=CLR_BG)
        tab_title = os.path.basename(path.rstrip("\\/")) or ("This PC" if os.name == 'nt' else "/")
        self.notebook.add(tab_frame, text=f" 📁 {tab_title} ")

        tab_id = self.notebook.tabs()[-1]
        self.tabs_data[tab_id] = TabData(path)
        self.notebook.select(tab_frame)
        self.navigate_to(path, record_history=False)

    def on_tab_changed(self, event):
        sel_tab = self.notebook.select()
        if sel_tab in self.tabs_data:
            data = self.tabs_data[sel_tab]
            self.navigate_to(data.path, record_history=False)

    def get_current_tab_data(self):
        sel_tab = self.notebook.select()
        return self.tabs_data.get(sel_tab)

    def get_current_path(self):
        td = self.get_current_tab_data()
        return td.path if td else (os.path.abspath("C:\\") if os.name == 'nt' else "/root")

    # =========================================================================
    # Navigation & Directory Listing
    # =========================================================================
    def navigate_to(self, path, record_history=True):
        if not os.path.exists(path) or not os.path.isdir(path):
            messagebox.showerror("Error", f"Path does not exist or is not a directory:\n{path}")
            return

        path = os.path.abspath(path)
        td = self.get_current_tab_data()
        if td:
            if record_history and td.path != path:
                if td.history_idx < len(td.history) - 1:
                    td.history = td.history[:td.history_idx + 1]
                td.history.append(path)
                td.history_idx = len(td.history) - 1
            td.path = path

            # Update tab title
            dir_name = os.path.basename(path.rstrip("\\/")) or ("This PC" if os.name == 'nt' else "/")
            curr_tab = self.notebook.select()
            self.notebook.tab(curr_tab, text=f" 📁 {dir_name} ")

        self.address_var.set(path)
        self.load_directory_items(path)
        self.update_nav_buttons()

    def nav_back(self):
        td = self.get_current_tab_data()
        if td and td.history_idx > 0:
            td.history_idx -= 1
            self.navigate_to(td.history[td.history_idx], record_history=False)

    def nav_forward(self):
        td = self.get_current_tab_data()
        if td and td.history_idx < len(td.history) - 1:
            td.history_idx += 1
            self.navigate_to(td.history[td.history_idx], record_history=False)

    def nav_up(self):
        curr = self.get_current_path()
        parent = os.path.dirname(curr.rstrip("\\/"))
        if parent and parent != curr:
            self.navigate_to(parent)

    def refresh(self):
        self.navigate_to(self.get_current_path(), record_history=False)
        self.populate_sidebar()

    def update_nav_buttons(self):
        td = self.get_current_tab_data()
        if td:
            self.btn_back.config(state="normal" if td.history_idx > 0 else "disabled")
            self.btn_fwd.config(state="normal" if td.history_idx < len(td.history) - 1 else "disabled")

    def load_directory_items(self, path):
        self.file_tree.delete(*self.file_tree.get_children())
        self.raw_items = []

        try:
            entries = list(os.scandir(path))
        except PermissionError:
            messagebox.showerror("Permission Denied", f"Cannot access:\n{path}")
            return
        except Exception as e:
            messagebox.showerror("Error", str(e))
            return

        for entry in entries:
            name = entry.name
            if not self.show_hidden and name.startswith('.'):
                continue

            try:
                st = entry.stat(follow_symlinks=False)
                is_dir = entry.is_dir(follow_symlinks=True)
                size = st.st_size if not is_dir else None
                mtime = st.st_mtime
                date_fmt = time.strftime("%m/%d/%Y %I:%M %p", time.localtime(mtime))
                type_name, icon = get_file_type_and_icon(name, is_dir)
            except Exception:
                is_dir = False
                size = 0
                mtime = 0
                date_fmt = "-"
                type_name = "Unknown"
                icon = "📄"

            self.raw_items.append({
                "name": name,
                "path": os.path.join(path, name),
                "is_dir": is_dir,
                "size": size,
                "size_fmt": format_size(size) if size is not None else "",
                "mtime": mtime,
                "date_fmt": date_fmt,
                "type": type_name,
                "icon": icon
            })

        self.apply_sort_and_render()

        # Update status bar
        count = len(self.raw_items)
        self.status_count_lbl.config(text=f"{count} item{'s' if count != 1 else ''}")
        self.status_selected_lbl.config(text="")

        try:
            usage = shutil.disk_usage(path)
            self.status_free_lbl.config(text=f"{format_size(usage.free)} free of {format_size(usage.total)}")
        except Exception:
            self.status_free_lbl.config(text="")

    def apply_sort_and_render(self):
        td = self.get_current_tab_data()
        col = td.sort_col if td else "name"
        desc = td.sort_desc if td else False

        def sort_key(item):
            # Directories always first
            dir_rank = 0 if item["is_dir"] else 1
            if col == "name":
                val = item["name"].lower()
            elif col == "date":
                val = item["mtime"]
            elif col == "type":
                val = item["type"].lower()
            elif col == "size":
                val = item["size"] if item["size"] is not None else -1
            else:
                val = item["name"].lower()
            return (dir_rank, val)

        self.raw_items.sort(key=sort_key, reverse=desc)
        self.file_tree.delete(*self.file_tree.get_children())

        query = self.search_var.get().strip().lower()
        for item in self.raw_items:
            if query and query not in item["name"].lower():
                continue

            display_name = f" {item['icon']}  {item['name']}"
            item_id = self.file_tree.insert("", "end", values=(
                display_name,
                item["date_fmt"],
                item["type"],
                item["size_fmt"]
            ))
            # Store real item data in tag or custom mapping
            self.file_tree.set(item_id, "name", display_name)

    def sort_by(self, col):
        td = self.get_current_tab_data()
        if td:
            if td.sort_col == col:
                td.sort_desc = not td.sort_desc
            else:
                td.sort_col = col
                td.sort_desc = False
        self.apply_sort_and_render()

    def filter_items(self, query):
        self.apply_sort_and_render()

    # =========================================================================
    # Selection & Open
    # =========================================================================
    def get_selected_items(self):
        selected_ids = self.file_tree.selection()
        items = []
        for sid in selected_ids:
            idx = self.file_tree.index(sid)
            # Find in raw items
            vals = self.file_tree.item(sid, "values")
            if vals:
                clean_name = vals[0].split("  ", 1)[-1]
                match = next((i for i in self.raw_items if i["name"] == clean_name), None)
                if match:
                    items.append(match)
        return items

    def on_file_select(self, event):
        items = self.get_selected_items()
        count = len(items)
        if count == 0:
            self.status_selected_lbl.config(text="")
        else:
            total_sz = sum(i["size"] for i in items if i["size"] is not None)
            sz_str = f" ({format_size(total_sz)})" if total_sz > 0 else ""
            self.status_selected_lbl.config(text=f"{count} item{'s' if count != 1 else ''} selected{sz_str}")

    def on_item_double_click(self, event):
        self.open_selected_item()

    def open_selected_item(self):
        items = self.get_selected_items()
        if not items:
            return
        item = items[0]
        if item["is_dir"]:
            self.navigate_to(item["path"])
        else:
            ext = os.path.splitext(item["name"])[1].lower()
            if ext in [".txt", ".py", ".sh", ".bash", ".json", ".md", ".conf", ".log", ".yaml", ".yml", ".c", ".h"]:
                self.open_notepad(item["path"])
            elif ext in [".sh", ".bash", ".py"]:
                if messagebox.askyesno("Run Script", f"Do you want to run '{item['name']}' in a terminal?"):
                    self.run_in_terminal(item["path"])
            else:
                try:
                    if os.name == 'nt':
                        os.startfile(item["path"])
                    else:
                        subprocess.Popen(["xdg-open", item["path"]])
                except Exception as e:
                    messagebox.showerror("Error Opening File", str(e))

    # =========================================================================
    # File Operations (Cut, Copy, Paste, Delete, Rename)
    # =========================================================================
    def action_cut(self):
        items = self.get_selected_items()
        if items:
            self.clipboard = {"action": "cut", "paths": [i["path"] for i in items]}

    def action_copy(self):
        items = self.get_selected_items()
        if items:
            self.clipboard = {"action": "copy", "paths": [i["path"] for i in items]}

    def action_paste(self):
        if not self.clipboard["paths"]:
            return
        dest = self.get_current_path()
        action = self.clipboard["action"]

        for src in self.clipboard["paths"]:
            if not os.path.exists(src):
                continue
            base = os.path.basename(src)
            target = os.path.join(dest, base)

            try:
                if action == "cut":
                    shutil.move(src, target)
                else:
                    if os.path.isdir(src):
                        cnt = 2
                        while os.path.exists(target):
                            target = os.path.join(dest, f"{base} - Copy ({cnt})")
                            cnt += 1
                        shutil.copytree(src, target)
                    else:
                        cnt = 2
                        stem, ext = os.path.splitext(base)
                        while os.path.exists(target):
                            target = os.path.join(dest, f"{stem} - Copy ({cnt}){ext}")
                            cnt += 1
                        shutil.copy2(src, target)
            except Exception as e:
                messagebox.showerror("Paste Error", f"Could not paste {base}:\n{e}")

        if action == "cut":
            self.clipboard = {"action": None, "paths": []}
        self.refresh()

    def action_delete(self):
        items = self.get_selected_items()
        if not items:
            return
        msg = f"Permanently delete '{items[0]['name']}'?" if len(items) == 1 else f"Permanently delete {len(items)} items?"
        if not messagebox.askyesno("Delete", msg):
            return

        for i in items:
            p = i["path"]
            try:
                if i["is_dir"] and not os.path.islink(p):
                    shutil.rmtree(p)
                else:
                    os.unlink(p)
            except Exception as e:
                messagebox.showerror("Delete Error", f"Could not delete {i['name']}:\n{e}")
        self.refresh()

    def action_rename(self):
        items = self.get_selected_items()
        if len(items) != 1:
            return
        item = items[0]
        new_name = simpledialog.askstring("Rename", "Enter new name:", initialvalue=item["name"], parent=self)
        if not new_name or new_name == item["name"]:
            return

        parent = os.path.dirname(item["path"])
        new_path = os.path.join(parent, new_name)
        if os.path.exists(new_path):
            messagebox.showerror("Error", f"An item named '{new_name}' already exists.")
            return

        try:
            os.rename(item["path"], new_path)
            self.refresh()
        except Exception as e:
            messagebox.showerror("Rename Error", str(e))

    def action_new_folder(self):
        parent = self.get_current_path()
        name = "New folder"
        target = os.path.join(parent, name)
        cnt = 2
        while os.path.exists(target):
            target = os.path.join(parent, f"{name} ({cnt})")
            cnt += 1

        try:
            os.makedirs(target, exist_ok=True)
            self.refresh()
        except Exception as e:
            messagebox.showerror("Error", str(e))

    def action_new_file(self):
        parent = self.get_current_path()
        name = "New Text Document.txt"
        target = os.path.join(parent, name)
        stem, ext = os.path.splitext(name)
        cnt = 2
        while os.path.exists(target):
            target = os.path.join(parent, f"{stem} ({cnt}){ext}")
            cnt += 1

        try:
            with open(target, "w", encoding="utf-8") as f:
                f.write("")
            self.refresh()
        except Exception as e:
            messagebox.showerror("Error", str(e))

    def action_terminal(self):
        target = self.get_current_path()
        items = self.get_selected_items()
        if items and items[0]["is_dir"]:
            target = items[0]["path"]
        self.run_in_terminal(target)

    def run_in_terminal(self, path):
        work_dir = path if os.path.isdir(path) else os.path.dirname(path)
        try:
            if os.name == 'nt':
                subprocess.Popen(f'start cmd /k "cd /d {work_dir}"', shell=True)
            else:
                subprocess.Popen(["xterm", "-e", f'cd "{work_dir}" && bash'])
        except Exception as e:
            messagebox.showerror("Terminal Error", str(e))

    # =========================================================================
    # Built-in Notepad Editor
    # =========================================================================
    def open_notepad(self, file_path):
        editor = tk.Toplevel(self)
        editor.title(f"{os.path.basename(file_path)} - BootOS Notepad")
        editor.geometry("720, 520")
        editor.configure(bg="#202020")

        # Top Button Toolbar
        bar = tk.Frame(editor, bg="#202020", height=32)
        bar.pack(fill=tk.X, side=tk.TOP, padx=6, pady=4)

        # Text Area
        txt = tk.Text(editor, font=("Consolas", 11), bg="#141414", fg="#e0e0e0",
                      insertbackground="#ffffff", selectbackground=CLR_SELECTED,
                      bd=0, padx=8, pady=8)
        txt.pack(fill=tk.BOTH, expand=True)

        try:
            with open(file_path, "r", encoding="utf-8", errors="replace") as f:
                txt.insert("1.0", f.read())
        except Exception as e:
            messagebox.showerror("Error Reading File", str(e))

        def save_file():
            content = txt.get("1.0", tk.END).rstrip("\n") + "\n"
            try:
                with open(file_path, "w", encoding="utf-8") as f:
                    f.write(content)
                self.refresh()
                messagebox.showinfo("Saved", "File saved successfully!")
            except Exception as e:
                messagebox.showerror("Save Error", str(e))

        btn_save = tk.Button(bar, text="💾 Save", font=("Segoe UI", 9, "bold"),
                             bg=CLR_ACCENT, fg="#000000", bd=0, relief="flat",
                             cursor="hand2", padx=12, pady=3, command=save_file)
        btn_save.pack(side=tk.LEFT)

    # =========================================================================
    # Properties Dialog
    # =========================================================================
    def show_properties(self):
        items = self.get_selected_items()
        item = items[0] if items else {"name": os.path.basename(self.get_current_path()),
                                        "path": self.get_current_path(),
                                        "is_dir": True,
                                        "type": "File folder",
                                        "size_fmt": "-",
                                        "date_fmt": "-"}

        prop_win = tk.Toplevel(self)
        prop_win.title(f"{item['name']} Properties")
        prop_win.geometry("380, 360")
        prop_win.configure(bg=CLR_SIDEBAR)
        prop_win.resizable(False, False)

        header = tk.Frame(prop_win, bg=CLR_SIDEBAR)
        header.pack(fill=tk.X, padx=16, pady=16)

        lbl_icon = tk.Label(header, text="📁" if item["is_dir"] else "📄", font=("Segoe UI", 28), bg=CLR_SIDEBAR)
        lbl_icon.pack(side=tk.LEFT, padx=(0, 12))

        lbl_name = tk.Label(header, text=item["name"], font=("Segoe UI", 12, "bold"), bg=CLR_SIDEBAR, fg=CLR_TEXT)
        lbl_name.pack(side=tk.LEFT)

        sep = tk.Frame(prop_win, bg=CLR_BORDER, height=1)
        sep.pack(fill=tk.X, padx=16, pady=(0, 12))

        grid_frame = tk.Frame(prop_win, bg=CLR_SIDEBAR)
        grid_frame.pack(fill=tk.BOTH, expand=True, padx=20)

        props = [
            ("Type of file:", item.get("type", "File")),
            ("Location:", item.get("path", "")),
            ("Size:", item.get("size_fmt", "-")),
            ("Modified:", item.get("date_fmt", "-")),
        ]

        for idx, (label, val) in enumerate(props):
            lbl_l = tk.Label(grid_frame, text=label, font=("Segoe UI", 9), bg=CLR_SIDEBAR, fg=CLR_TEXT_MUTED, anchor="w")
            lbl_l.grid(row=idx, column=0, sticky="w", pady=4)

            lbl_v = tk.Label(grid_frame, text=val, font=("Segoe UI", 9), bg=CLR_SIDEBAR, fg=CLR_TEXT, anchor="w", wraplength=220, justify="left")
            lbl_v.grid(row=idx, column=1, sticky="w", padx=12, pady=4)

        btn_ok = tk.Button(prop_win, text="OK", font=("Segoe UI", 9), bg=CLR_SURFACE, fg=CLR_TEXT,
                           activebackground=CLR_HOVER, bd=1, relief="solid", width=10,
                           command=prop_win.destroy)
        btn_ok.pack(side=tk.BOTTOM, pady=16)

    def show_context_menu(self, event):
        item_id = self.file_tree.identify_row(event.y)
        if item_id:
            if item_id not in self.file_tree.selection():
                self.file_tree.selection_set(item_id)
        self.context_menu.post(event.x_root, event.y_root)

def main():
    app = BootOSExplorerApp()
    app.mainloop()

if __name__ == '__main__':
    main()
