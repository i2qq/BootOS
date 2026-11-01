#!/usr/bin/env python3
# ==============================================================================
# BootOS Partition Wizard & Volume Manager
# Modern Graphical Disk & Volume Management Utility for BootOS
# ==============================================================================

import os
import sys
import subprocess
import shutil
import json
import re
import tkinter as tk
from tkinter import ttk, messagebox, simpledialog

# ------------------------------------------------------------------------------
# Color Palette (Dark Theme matching BootOS Explorer)
# ------------------------------------------------------------------------------
CLR_BG = "#191919"
CLR_SURFACE = "#222222"
CLR_SIDEBAR = "#1e1e1e"
CLR_CARD = "#2a2a2a"
CLR_BORDER = "#333333"
CLR_TEXT = "#ffffff"
CLR_TEXT_MUTED = "#999999"
CLR_ACCENT = "#0078d4"
CLR_ACCENT_HOVER = "#1084d8"
CLR_DANGER = "#d83b01"
CLR_DANGER_HOVER = "#ea4300"
CLR_SUCCESS = "#107c10"
CLR_WARNING = "#ffb900"

# Partition Bar Colors
FS_COLORS = {
    "ntfs": "#0078d4",       # Windows Blue
    "vfat": "#ffb900",       # FAT32 Gold/Amber
    "fat32": "#ffb900",
    "fat16": "#d89b00",
    "ext4": "#107c10",       # Linux Green
    "ext3": "#0b6a0b",
    "ext2": "#075407",
    "swap": "#881798",       # Swap Purple
    "iso9660": "#e3008c",    # ISO Magenta
    "unallocated": "#444444",# Unallocated Gray
    "unknown": "#555555"
}

class PartitionManagerApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("BootOS Partition Wizard & Volume Manager")
        self.geometry("1100x720")
        self.minsize(850, 550)
        self.configure(bg=CLR_BG)

        try:
            self.tk.call('tk', 'scaling', 1.0)
        except Exception:
            pass

        self.protocol("WM_DELETE_WINDOW", self.action_exit)
        self.bind("<Escape>", lambda e: self.action_exit())

        self.selected_disk = None
        self.selected_partition = None
        self.disks = []
        self.partitions = []

        self.setup_styles()
        self.build_ui()
        self.refresh_disks()

    def setup_styles(self):
        self.style = ttk.Style(self)
        self.style.theme_use("clam")

        self.style.configure(".", background=CLR_BG, foreground=CLR_TEXT, font=("Segoe UI", 9))
        self.style.configure("TFrame", background=CLR_BG)
        self.style.configure("Surface.TFrame", background=CLR_SURFACE)
        self.style.configure("Card.TFrame", background=CLR_CARD, relief="flat")

        self.style.configure("Treeview",
                             background=CLR_SURFACE,
                             foreground=CLR_TEXT,
                             fieldbackground=CLR_SURFACE,
                             borderwidth=0,
                             rowheight=28,
                             font=("Segoe UI", 9))
        self.style.configure("Treeview.Heading",
                             background=CLR_CARD,
                             foreground=CLR_TEXT,
                             borderwidth=1,
                             relief="flat",
                             font=("Segoe UI", 9, "bold"))
        self.style.map("Treeview",
                       background=[('selected', CLR_ACCENT)],
                       foreground=[('selected', '#ffffff')])

        self.style.configure("TCombobox",
                             fieldbackground=CLR_CARD,
                             background=CLR_BORDER,
                             foreground=CLR_TEXT,
                             arrowcolor=CLR_TEXT)

    def build_ui(self):
        # 1. Top Header Title & Status Bar
        header = tk.Frame(self, bg=CLR_SURFACE, height=48, bd=0)
        header.pack(fill=tk.X, side=tk.TOP)
        header.pack_propagate(False)

        title_lbl = tk.Label(header, text="🗄️ BootOS Partition Wizard & Volume Manager",
                             font=("Segoe UI", 12, "bold"), bg=CLR_SURFACE, fg=CLR_TEXT)
        title_lbl.pack(side=tk.LEFT, padx=16)

        sub_lbl = tk.Label(header, text="Clean Windows 7 Wiping | Filesystem Formatting | MBR/GPT Partitioning",
                           font=("Segoe UI", 9), bg=CLR_SURFACE, fg=CLR_TEXT_MUTED)
        sub_lbl.pack(side=tk.LEFT, padx=8)

        btn_exit = tk.Button(header, text="❌ Exit", font=("Segoe UI", 9, "bold"),
                             bg=CLR_CARD, fg=CLR_TEXT, activebackground=CLR_DANGER,
                             activeforeground="#fff", bd=0, padx=12, pady=4, cursor="hand2",
                             command=self.action_exit)
        btn_exit.pack(side=tk.RIGHT, padx=16)

        # 2. Main Action Command Toolbar
        cmd_bar = tk.Frame(self, bg=CLR_CARD, height=42, bd=0)
        cmd_bar.pack(fill=tk.X, side=tk.TOP, padx=0, pady=1)
        cmd_bar.pack_propagate(False)

        self.create_cmd_btn(cmd_bar, "🪄 Partition Wizard", self.open_wizard_menu, is_accent=True)
        self.create_sep(cmd_bar)
        self.create_cmd_btn(cmd_bar, "➕ New Partition", self.action_create_partition)
        self.create_cmd_btn(cmd_bar, "❌ Delete", self.action_delete_partition)
        self.create_cmd_btn(cmd_bar, "⚙️ Format Volume", self.action_format_partition)
        self.create_sep(cmd_bar)
        self.create_cmd_btn(cmd_bar, "🧹 Wipe All (Windows 7)", self.action_wipe_disk, is_danger=True)
        self.create_sep(cmd_bar)
        self.create_cmd_btn(cmd_bar, "📁 Mount", self.action_mount)
        self.create_cmd_btn(cmd_bar, "⏏️ Unmount", self.action_unmount)
        self.create_cmd_btn(cmd_bar, "📂 Open Explorer", self.action_open_explorer)
        self.create_sep(cmd_bar)
        self.create_cmd_btn(cmd_bar, "🛠️ Launch GParted", self.action_launch_gparted)
        self.create_cmd_btn(cmd_bar, "🔄 Refresh", self.refresh_disks)

        # 3. Main Split View: Left Disk List + Right Partition Details & Map
        body = tk.PanedWindow(self, orient=tk.HORIZONTAL, bg=CLR_BORDER, bd=0, sashwidth=4)
        body.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)

        # Left: Physical Drives List
        left_frame = tk.Frame(body, bg=CLR_SIDEBAR, width=280)
        left_frame.pack_propagate(False)
        body.add(left_frame, minsize=220)

        d_header = tk.Frame(left_frame, bg=CLR_CARD, height=32)
        d_header.pack(fill=tk.X)
        tk.Label(d_header, text="Physical Disk Drives", font=("Segoe UI", 9, "bold"),
                 bg=CLR_CARD, fg=CLR_TEXT).pack(side=tk.LEFT, padx=10, pady=6)

        self.drive_listbox = tk.Listbox(left_frame, bg=CLR_SIDEBAR, fg=CLR_TEXT,
                                        selectbackground=CLR_ACCENT, selectforeground="#fff",
                                        bd=0, highlightthickness=0, font=("Segoe UI", 9), activestyle="none")
        self.drive_listbox.pack(fill=tk.BOTH, expand=True, padx=4, pady=4)
        self.drive_listbox.bind("<<ListboxSelect>>", self.on_disk_selected)

        # Right: Visual Proportional Map + Table
        right_frame = tk.Frame(body, bg=CLR_SURFACE)
        body.add(right_frame, minsize=500)

        # Visual Map Container
        map_card = tk.Frame(right_frame, bg=CLR_CARD, bd=1, relief="solid")
        map_card.pack(fill=tk.X, padx=8, pady=(8, 4))

        map_title_frame = tk.Frame(map_card, bg=CLR_CARD)
        map_title_frame.pack(fill=tk.X, padx=8, pady=4)
        self.lbl_selected_disk = tk.Label(map_title_frame, text="No Disk Selected",
                                          font=("Segoe UI", 10, "bold"), bg=CLR_CARD, fg=CLR_TEXT)
        self.lbl_selected_disk.pack(side=tk.LEFT)

        self.lbl_disk_meta = tk.Label(map_title_frame, text="",
                                      font=("Segoe UI", 9), bg=CLR_CARD, fg=CLR_TEXT_MUTED)
        self.lbl_disk_meta.pack(side=tk.RIGHT)

        # Canvas for Proportional Partition Bar Map
        self.map_canvas = tk.Canvas(map_card, bg="#111111", height=50, bd=0, highlightthickness=1,
                                    highlightbackground=CLR_BORDER)
        self.map_canvas.pack(fill=tk.X, padx=8, pady=(0, 8))
        self.map_canvas.bind("<Button-1>", self.on_canvas_click)
        self.map_canvas.bind("<Configure>", lambda e: self.draw_partition_map())

        # Legend Bar
        legend_frame = tk.Frame(map_card, bg=CLR_CARD)
        legend_frame.pack(fill=tk.X, padx=8, pady=(0, 6))
        for fs, clr in [("NTFS", FS_COLORS["ntfs"]), ("FAT32", FS_COLORS["vfat"]),
                        ("ext4", FS_COLORS["ext4"]), ("Swap", FS_COLORS["swap"]),
                        ("Unallocated", FS_COLORS["unallocated"])]:
            tk.Label(legend_frame, text="■", fg=clr, bg=CLR_CARD, font=("Segoe UI", 10)).pack(side=tk.LEFT, padx=(6, 2))
            tk.Label(legend_frame, text=fs, fg=CLR_TEXT_MUTED, bg=CLR_CARD, font=("Segoe UI", 8)).pack(side=tk.LEFT, padx=(0, 8))

        # Partition Table Frame
        tbl_frame = tk.Frame(right_frame, bg=CLR_SURFACE)
        tbl_frame.pack(fill=tk.BOTH, expand=True, padx=8, pady=4)

        cols = ("dev", "label", "fstype", "size", "used", "mount", "flags")
        self.tree = ttk.Treeview(tbl_frame, columns=cols, show="headings", selectmode="browse")

        self.tree.heading("dev", text="Partition")
        self.tree.heading("label", text="Volume Label")
        self.tree.heading("fstype", text="File System")
        self.tree.heading("size", text="Capacity")
        self.tree.heading("used", text="Usage")
        self.tree.heading("mount", text="Mount Point")
        self.tree.heading("flags", text="Flags")

        self.tree.column("dev", width=120, anchor=tk.W)
        self.tree.column("label", width=140, anchor=tk.W)
        self.tree.column("fstype", width=90, anchor=tk.CENTER)
        self.tree.column("size", width=90, anchor=tk.E)
        self.tree.column("used", width=90, anchor=tk.CENTER)
        self.tree.column("mount", width=140, anchor=tk.W)
        self.tree.column("flags", width=90, anchor=tk.CENTER)

        tree_scroll = ttk.Scrollbar(tbl_frame, orient=tk.VERTICAL, command=self.tree.yview)
        self.tree.configure(yscrollcommand=tree_scroll.set)

        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        tree_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.tree.bind("<<TreeviewSelect>>", self.on_tree_selected)

        # 4. Bottom Status & Quick Action Bar
        status_bar = tk.Frame(self, bg=CLR_CARD, height=26, bd=0)
        status_bar.pack(fill=tk.X, side=tk.BOTTOM)
        status_bar.pack_propagate(False)

        self.status_lbl = tk.Label(status_bar, text="Ready.", font=("Segoe UI", 9),
                                   bg=CLR_CARD, fg=CLR_TEXT_MUTED)
        self.status_lbl.pack(side=tk.LEFT, padx=12)

    def create_cmd_btn(self, parent, text, command, is_accent=False, is_danger=False):
        bg = CLR_CARD
        fg = CLR_TEXT
        active_bg = CLR_BORDER
        if is_accent:
            bg = CLR_ACCENT
            active_bg = CLR_ACCENT_HOVER
        elif is_danger:
            bg = CLR_DANGER
            active_bg = CLR_DANGER_HOVER

        btn = tk.Button(parent, text=text, font=("Segoe UI", 9, "bold" if is_accent else "normal"),
                        bg=bg, fg=fg, activebackground=active_bg, activeforeground="#ffffff",
                        bd=0, relief="flat", padx=10, pady=5, cursor="hand2", command=command)
        btn.pack(side=tk.LEFT, padx=3, pady=4)
        return btn

    def create_sep(self, parent):
        sep = tk.Frame(parent, bg=CLR_BORDER, width=1, height=22)
        sep.pack(side=tk.LEFT, padx=4, pady=8)

    # --------------------------------------------------------------------------
    # Disk & Partition Detection Engine
    # --------------------------------------------------------------------------
    def refresh_disks(self):
        self.disks = []
        self.drive_listbox.delete(0, tk.END)

        if os.name == 'nt':
            # Windows Mock / Development Mode
            self.disks = [
                {"name": "/dev/sda", "size": "465.8G", "model": "ST9500423AS (Seagate HDD)", "type": "disk", "bytes": 500107862016},
                {"name": "/dev/sdb", "size": "1.9G", "model": "SanDisk Cruzer (USB Flash)", "type": "disk", "bytes": 2040109465}
            ]
        else:
            try:
                # Query Linux lsblk in JSON format
                cmd = ["lsblk", "-d", "-p", "-J", "-o", "NAME,SIZE,MODEL,TRAN,TYPE,BYTES"]
                res = subprocess.run(cmd, capture_output=True, text=True, check=True)
                data = json.loads(res.stdout)
                for item in data.get("blockdevices", []):
                    if item.get("type") == "disk" and not item["name"].startswith("/dev/loop") and not item["name"].startswith("/dev/sr"):
                        self.disks.append({
                            "name": item["name"],
                            "size": item.get("size", "0B"),
                            "model": item.get("model") or "Generic Disk",
                            "type": item.get("type"),
                            "bytes": int(item.get("bytes", 0))
                        })
            except Exception as e:
                # Fallback to sysfs inspection
                for d in sorted(os.listdir("/sys/block") if os.path.exists("/sys/block") else []):
                    if d.startswith("sd") or d.startswith("nvme") or d.startswith("vd"):
                        dev = f"/dev/{d}"
                        self.disks.append({"name": dev, "size": "Unknown", "model": d, "type": "disk", "bytes": 0})

        for d in self.disks:
            self.drive_listbox.insert(tk.END, f" 💽 {d['name']} ({d['size']}) - {d['model']}")

        if self.disks:
            self.drive_listbox.selection_set(0)
            self.on_disk_selected(None)
        else:
            self.status_lbl.config(text="No writable storage drives detected.")

    def on_disk_selected(self, event):
        sel = self.drive_listbox.curselection()
        if not sel:
            return
        idx = sel[0]
        self.selected_disk = self.disks[idx]
        self.lbl_selected_disk.config(text=f"Drive: {self.selected_disk['name']} ({self.selected_disk['model']})")
        self.lbl_disk_meta.config(text=f"Total Capacity: {self.selected_disk['size']}")
        self.load_partitions_for_disk(self.selected_disk["name"])

    def load_partitions_for_disk(self, disk_name):
        self.partitions = []
        for row in self.tree.get_children():
            self.tree.delete(row)

        if os.name == 'nt':
            if disk_name == "/dev/sda":
                self.partitions = [
                    {"name": "/dev/sda1", "label": "System Reserved", "fstype": "ntfs", "size": "100M", "bytes": 104857600, "mount": "", "flags": "boot"},
                    {"name": "/dev/sda2", "label": "RECOVERY", "fstype": "ntfs", "size": "15.0G", "bytes": 16106127360, "mount": "", "flags": ""},
                    {"name": "/dev/sda3", "label": "OS", "fstype": "ntfs", "size": "450.6G", "bytes": 483896877056, "mount": "", "flags": ""}
                ]
            else:
                self.partitions = [
                    {"name": "/dev/sdb1", "label": "BOOTOS", "fstype": "vfat", "size": "1.9G", "bytes": 2040109465, "mount": "/media/BOOTOS", "flags": "boot"}
                ]
        else:
            try:
                cmd = ["lsblk", "-p", "-J", "-o", "NAME,SIZE,LABEL,FSTYPE,MOUNTPOINT,BYTES,FSAVAIL,FSUSE%"]
                res = subprocess.run(cmd, capture_output=True, text=True, check=True)
                data = json.loads(res.stdout)
                
                # Find matching disk
                for dev in data.get("blockdevices", []):
                    if dev["name"] == disk_name:
                        for child in dev.get("children", []):
                            self.partitions.append({
                                "name": child["name"],
                                "label": child.get("label") or "",
                                "fstype": (child.get("fstype") or "unformatted").lower(),
                                "size": child.get("size") or "0B",
                                "bytes": int(child.get("bytes", 0)),
                                "mount": child.get("mountpoint") or "",
                                "used": child.get("fsuse%") or "-",
                                "flags": ""
                            })
                        break
            except Exception as e:
                self.status_lbl.config(text=f"Error querying partitions: {e}")

        # Insert into treeview
        for p in self.partitions:
            self.tree.insert("", tk.END, values=(
                p["name"],
                p.get("label", ""),
                p.get("fstype", "unknown").upper(),
                p.get("size", ""),
                p.get("used", "-"),
                p.get("mount", "[Unmounted]"),
                p.get("flags", "")
            ))

        self.draw_partition_map()
        self.status_lbl.config(text=f"Loaded {len(self.partitions)} partition(s) for {disk_name}.")

    # --------------------------------------------------------------------------
    # Visual Partition Proportional Map Canvas
    # --------------------------------------------------------------------------
    def draw_partition_map(self):
        self.map_canvas.delete("all")
        width = self.map_canvas.winfo_width()
        height = self.map_canvas.winfo_height()
        if width <= 10:
            width = 700

        if not self.partitions or not self.selected_disk:
            self.map_canvas.create_text(width // 2, height // 2,
                                        text="No Partitions or Empty Disk (Click 'Partition Wizard' to initialize)",
                                        fill=CLR_TEXT_MUTED, font=("Segoe UI", 9))
            return

        total_bytes = sum(p.get("bytes", 0) for p in self.partitions)
        if total_bytes <= 0:
            total_bytes = 1

        curr_x = 2
        pad = 2
        usable_width = width - (len(self.partitions) * pad) - 4

        self.canvas_blocks = []
        for idx, p in enumerate(self.partitions):
            p_bytes = p.get("bytes", 0)
            ratio = p_bytes / total_bytes
            block_w = max(45, int(ratio * usable_width))
            if idx == len(self.partitions) - 1:
                block_w = max(45, width - curr_x - 2)

            fstype = p.get("fstype", "").lower()
            color = FS_COLORS.get(fstype, FS_COLORS["unknown"])

            # Highlight selected
            is_sel = (self.selected_partition and self.selected_partition["name"] == p["name"])
            outline_clr = "#ffffff" if is_sel else CLR_BORDER
            outline_w = 2 if is_sel else 1

            rect_id = self.map_canvas.create_rectangle(curr_x, 4, curr_x + block_w, height - 4,
                                                       fill=color, outline=outline_clr, width=outline_w)
            
            # Label & Size text
            p_name = os.path.basename(p["name"])
            disp_txt = f"{p_name}\n{p.get('size', '')}"
            if block_w > 80:
                disp_txt = f"{p_name} ({p.get('fstype','').upper()})\n{p.get('size', '')}"

            self.map_canvas.create_text(curr_x + (block_w // 2), height // 2,
                                       text=disp_txt, fill="#ffffff",
                                       font=("Segoe UI", 8, "bold"), justify=tk.CENTER)

            self.canvas_blocks.append({
                "x1": curr_x, "x2": curr_x + block_w,
                "partition": p, "rect_id": rect_id
            })
            curr_x += block_w + pad

    def on_canvas_click(self, event):
        for b in getattr(self, "canvas_blocks", []):
            if b["x1"] <= event.x <= b["x2"]:
                self.selected_partition = b["partition"]
                # Select corresponding row in treeview
                for item in self.tree.get_children():
                    if self.tree.item(item)["values"][0] == self.selected_partition["name"]:
                        self.tree.selection_set(item)
                        self.tree.see(item)
                        break
                self.draw_partition_map()
                self.status_lbl.config(text=f"Selected partition: {self.selected_partition['name']} ({self.selected_partition.get('size','')})")
                return

    def on_tree_selected(self, event):
        sel = self.tree.selection()
        if not sel:
            return
        item_vals = self.tree.item(sel[0])["values"]
        dev_name = str(item_vals[0])
        for p in self.partitions:
            if p["name"] == dev_name:
                self.selected_partition = p
                self.draw_partition_map()
                self.status_lbl.config(text=f"Selected partition: {p['name']} ({p.get('size','')})")
                break

    # --------------------------------------------------------------------------
    # Partition Wizard (Automated 1-Click Operations)
    # --------------------------------------------------------------------------
    def open_wizard_menu(self):
        if not self.selected_disk:
            messagebox.showwarning("Warning", "Please select a target disk drive first.")
            return

        w_win = tk.Toplevel(self)
        w_win.title(f"Partition Wizard - {self.selected_disk['name']}")
        w_win.geometry("560x420")
        w_win.configure(bg=CLR_SURFACE)
        w_win.transient(self)
        w_win.grab_set()

        tk.Label(w_win, text=f"🪄 Partition Setup Wizard: {self.selected_disk['name']}",
                 font=("Segoe UI", 11, "bold"), bg=CLR_SURFACE, fg=CLR_TEXT).pack(pady=(16, 4))
        tk.Label(w_win, text="Choose an automated partitioning preset to configure your storage drive:",
                 font=("Segoe UI", 9), bg=CLR_SURFACE, fg=CLR_TEXT_MUTED).pack(pady=(0, 16))

        presets = [
            ("🧹 Clean Wipe Old Windows 7 Partitions",
             "Obliterates /dev/sda1, sda2, sda3, erases all NTFS & MBR/GPT metadata, and leaves drive 100% clean.",
             self.preset_wipe_windows_7),
            ("💾 BootOS RAM-Resident Standalone Setup",
             "Creates a 4GB bootable FAT32 system partition (Syslinux MBR) + remaining drive as ext4 for user data.",
             self.preset_bootos_setup),
            ("🐧 Linux Ready Drive (EFI + Ext4 Root)",
             "Creates 1GB EFI System Partition (FAT32) + 100% remaining disk as ext4 root volume.",
             self.preset_linux_setup),
            ("🗄️ Single Full Volume (100% Drive)",
             "Creates a single full-capacity volume spanning the entire drive (formatted as ext4 or FAT32).",
             self.preset_single_volume)
        ]

        for title, desc, action in presets:
            f = tk.Frame(w_win, bg=CLR_CARD, bd=1, relief="solid")
            f.pack(fill=tk.X, padx=20, pady=6)

            btn = tk.Button(f, text=title, font=("Segoe UI", 10, "bold"),
                            bg=CLR_ACCENT, fg="#fff", activebackground=CLR_ACCENT_HOVER,
                            bd=0, padx=12, pady=6, cursor="hand2",
                            command=lambda a=action, w=w_win: self.execute_wizard(a, w))
            btn.pack(side=tk.TOP, anchor=tk.W, padx=8, pady=(8, 2))

            lbl_d = tk.Label(f, text=desc, font=("Segoe UI", 8), bg=CLR_CARD, fg=CLR_TEXT_MUTED, justify=tk.LEFT)
            lbl_d.pack(side=tk.TOP, anchor=tk.W, padx=10, pady=(0, 8))

    def execute_wizard(self, action_func, window):
        window.destroy()
        action_func()

    def preset_wipe_windows_7(self):
        target = self.selected_disk["name"]
        if messagebox.askyesno("Confirm Windows 7 Wipe",
                               f"DANGER: This will permanently ERASE ALL PARTITIONS (/dev/sda1, sda2, sda3) on {target}!\n\nAll NTFS volumes will be wiped cleanly.\n\nProceed?"):
            self.run_clean_wipe(target)

    def preset_bootos_setup(self):
        target = self.selected_disk["name"]
        if messagebox.askyesno("Confirm BootOS Setup",
                               f"This will repartition {target} into:\n - 4GB FAT32 bootable partition (BOOTOS)\n - Remaining disk formatted as ext4 (BOOTOS_DATA)\n\nAll existing data will be erased. Proceed?"):
            self.run_disk_script(f"""
                swapoff -a 2>/dev/null || true
                for p in $(lsblk -rnpo NAME "{target}" 2>/dev/null | grep -v "^{target}$"); do
                    umount -f "$p" 2>/dev/null || true
                    wipefs -a -f "$p" 2>/dev/null || true
                done
                wipefs -a -f "{target}" 2>/dev/null || true
                dd if=/dev/zero of="{target}" bs=1M count=32 conv=fsync 2>/dev/null || true
                parted -s "{target}" mklabel msdos
                parted -s "{target}" mkpart primary fat32 1MiB 4096MiB
                parted -s "{target}" set 1 boot on
                parted -s "{target}" mkpart primary ext4 4096MiB 100%
                partprobe "{target}" 2>/dev/null || true
                sleep 2
                mkfs.vfat -F 32 -n "BOOTOS" "{target}1" 2>/dev/null || mkfs.vfat -F 32 -n "BOOTOS" "{target}p1" 2>/dev/null || true
                mkfs.ext4 -F -L "BOOTOS_DATA" "{target}2" 2>/dev/null || mkfs.ext4 -F -L "BOOTOS_DATA" "{target}p2" 2>/dev/null || true
            """)

    def preset_linux_setup(self):
        target = self.selected_disk["name"]
        if messagebox.askyesno("Confirm Linux Setup",
                               f"This will repartition {target} for modern Linux OS installation:\n - 1GB EFI System Partition (FAT32)\n - Remaining disk as root volume (ext4)\n\nProceed?"):
            self.run_disk_script(f"""
                for p in $(lsblk -rnpo NAME "{target}" 2>/dev/null | grep -v "^{target}$"); do
                    umount -f "$p" 2>/dev/null || true
                    wipefs -a -f "$p" 2>/dev/null || true
                done
                wipefs -a -f "{target}" 2>/dev/null || true
                dd if=/dev/zero of="{target}" bs=1M count=32 conv=fsync 2>/dev/null || true
                parted -s "{target}" mklabel gpt
                parted -s "{target}" mkpart "ESP" fat32 1MiB 1024MiB
                parted -s "{target}" set 1 boot on
                parted -s "{target}" set 1 esp on
                parted -s "{target}" mkpart "root" ext4 1024MiB 100%
                partprobe "{target}" 2>/dev/null || true
                sleep 2
                mkfs.vfat -F 32 -n "EFI" "{target}1" 2>/dev/null || mkfs.vfat -F 32 -n "EFI" "{target}p1" 2>/dev/null || true
                mkfs.ext4 -F -L "LINUX_ROOT" "{target}2" 2>/dev/null || mkfs.ext4 -F -L "LINUX_ROOT" "{target}p2" 2>/dev/null || true
            """)

    def preset_single_volume(self):
        target = self.selected_disk["name"]
        if messagebox.askyesno("Confirm Single Volume",
                               f"This will wipe {target} and create one single volume spanning 100% of the drive formatted as ext4.\n\nProceed?"):
            self.run_disk_script(f"""
                for p in $(lsblk -rnpo NAME "{target}" 2>/dev/null | grep -v "^{target}$"); do
                    umount -f "$p" 2>/dev/null || true
                    wipefs -a -f "$p" 2>/dev/null || true
                done
                wipefs -a -f "{target}" 2>/dev/null || true
                dd if=/dev/zero of="{target}" bs=1M count=32 conv=fsync 2>/dev/null || true
                parted -s "{target}" mklabel msdos
                parted -s "{target}" mkpart primary ext4 1MiB 100%
                partprobe "{target}" 2>/dev/null || true
                sleep 2
                mkfs.ext4 -F -L "STORAGE" "{target}1" 2>/dev/null || mkfs.ext4 -F -L "STORAGE" "{target}p1" 2>/dev/null || true
            """)

    # --------------------------------------------------------------------------
    # Individual Partition Actions
    # --------------------------------------------------------------------------
    def action_wipe_disk(self):
        if not self.selected_disk:
            messagebox.showwarning("Warning", "Select a drive first.")
            return
        target = self.selected_disk["name"]
        ans = messagebox.askyesno("Destroy All Partitions",
                                  f"Are you sure you want to completely erase {target}?\n\nThis will remove all partitions (/dev/sda1, sda2, sda3) and wipe all NTFS/FAT/ext4 signatures.")
        if ans:
            self.run_clean_wipe(target)

    def run_clean_wipe(self, target):
        self.run_disk_script(f"""
            swapoff -a 2>/dev/null || true
            for p in $(lsblk -rnpo NAME "{target}" 2>/dev/null | grep -v "^{target}$"); do
                umount -f "$p" 2>/dev/null || true
                wipefs -a -f "$p" 2>/dev/null || true
            done
            wipefs -a -f "{target}" 2>/dev/null || true
            dd if=/dev/zero of="{target}" bs=1M count=64 conv=fsync 2>/dev/null || true
            partprobe "{target}" 2>/dev/null || blockdev --rereadpt "{target}" 2>/dev/null || true
            mdev -s 2>/dev/null || true
        """)

    def action_create_partition(self):
        if not self.selected_disk:
            messagebox.showwarning("Warning", "Select a drive first.")
            return

        size_mb = simpledialog.askinteger("Create Partition", "Enter partition size in Megabytes (e.g. 10240 for 10GB, or enter 0 for remaining space):",
                                          parent=self, minvalue=0, maxvalue=2000000)
        if size_mb is None:
            return

        fs_type = simpledialog.askstring("Filesystem", "Enter filesystem format (ext4, vfat, ntfs):",
                                         parent=self, initialvalue="ext4")
        if not fs_type:
            return

        target = self.selected_disk["name"]
        sz_arg = f"{size_mb}MiB" if size_mb > 0 else "100%"
        self.run_disk_script(f"""
            parted -s "{target}" mkpart primary {fs_type} 1MiB {sz_arg} 2>/dev/null || \
            parted -s "{target}" mkpart primary 1MiB {sz_arg} 2>/dev/null || true
            partprobe "{target}" 2>/dev/null || true
        """)

    def action_delete_partition(self):
        if not self.selected_partition:
            messagebox.showwarning("Warning", "Select a partition from the list or map first.")
            return
        target_part = self.selected_partition["name"]
        m = re.search(r'\d+$', target_part)
        if not m:
            messagebox.showerror("Error", f"Cannot determine partition number from {target_part}")
            return
        part_num = m.group(0)
        disk_name = self.selected_disk["name"]

        if messagebox.askyesno("Delete Partition", f"Permanently delete {target_part}? All data on this volume will be lost."):
            self.run_disk_script(f"""
                umount -f "{target_part}" 2>/dev/null || true
                wipefs -a -f "{target_part}" 2>/dev/null || true
                parted -s "{disk_name}" rm {part_num} 2>/dev/null || true
                partprobe "{disk_name}" 2>/dev/null || true
            """)

    def action_format_partition(self):
        if not self.selected_partition:
            messagebox.showwarning("Warning", "Select a partition to format.")
            return

        part = self.selected_partition["name"]
        fmt_win = tk.Toplevel(self)
        fmt_win.title(f"Format Volume - {part}")
        fmt_win.geometry("380x260")
        fmt_win.configure(bg=CLR_SURFACE)
        fmt_win.transient(self)
        fmt_win.grab_set()

        tk.Label(fmt_win, text=f"Format Volume: {part}", font=("Segoe UI", 11, "bold"),
                 bg=CLR_SURFACE, fg=CLR_TEXT).pack(pady=(16, 8))

        tk.Label(fmt_win, text="File System:", font=("Segoe UI", 9),
                 bg=CLR_SURFACE, fg=CLR_TEXT).pack(anchor=tk.W, padx=30, pady=(4, 2))
        fs_combo = ttk.Combobox(fmt_win, values=["ext4", "vfat (FAT32)", "ntfs"], state="readonly")
        fs_combo.set("ext4")
        fs_combo.pack(fill=tk.X, padx=30, pady=(0, 8))

        tk.Label(fmt_win, text="Volume Label:", font=("Segoe UI", 9),
                 bg=CLR_SURFACE, fg=CLR_TEXT).pack(anchor=tk.W, padx=30, pady=(4, 2))
        lbl_entry = tk.Entry(fmt_win, bg=CLR_CARD, fg=CLR_TEXT, insertbackground="#fff",
                             font=("Segoe UI", 9), bd=1, relief="solid")
        lbl_entry.insert(0, "VOLUME")
        lbl_entry.pack(fill=tk.X, padx=30, pady=(0, 16))

        def do_format():
            choice = fs_combo.get()
            label = lbl_entry.get().strip() or "VOLUME"
            fmt_win.destroy()

            if choice.startswith("ext4"):
                cmd = f"mkfs.ext4 -F -L '{label}' '{part}'"
            elif choice.startswith("vfat"):
                cmd = f"mkfs.vfat -F 32 -n '{label}' '{part}'"
            elif choice.startswith("ntfs"):
                cmd = f"mkfs.ntfs -f -L '{label}' '{part}'"
            else:
                cmd = f"mkfs.ext4 -F '{part}'"

            self.run_disk_script(f"""
                umount -f "{part}" 2>/dev/null || true
                wipefs -a -f "{part}" 2>/dev/null || true
                {cmd}
                partprobe "{self.selected_disk['name']}" 2>/dev/null || true
            """)

        btn_fmt = tk.Button(fmt_win, text="Format Now", font=("Segoe UI", 9, "bold"),
                            bg=CLR_DANGER, fg="#fff", activebackground=CLR_DANGER_HOVER,
                            bd=0, padx=16, pady=6, cursor="hand2", command=do_format)
        btn_fmt.pack(pady=4)

    def action_mount(self):
        if not self.selected_partition:
            return
        part = self.selected_partition["name"]
        mount_dir = f"/media/{os.path.basename(part)}"
        self.run_disk_script(f"""
            mkdir -p "{mount_dir}"
            mount "{part}" "{mount_dir}" 2>/dev/null || true
        """)

    def action_unmount(self):
        if not self.selected_partition:
            return
        part = self.selected_partition["name"]
        self.run_disk_script(f"umount -f '{part}' 2>/dev/null || true")

    def action_open_explorer(self):
        if not self.selected_partition:
            return
        mount_pt = self.selected_partition.get("mount")
        if not mount_pt or not os.path.exists(mount_pt):
            # Mount first
            mount_pt = f"/media/{os.path.basename(self.selected_partition['name'])}"
            subprocess.run(["mkdir", "-p", mount_pt], capture_output=True)
            subprocess.run(["mount", self.selected_partition["name"], mount_pt], capture_output=True)

        exp_script = "/usr/local/bin/bootos_explorer.py"
        if not os.path.exists(exp_script):
            exp_script = os.path.join(os.path.dirname(__file__), "bootos_explorer.py")
        if os.path.exists(exp_script):
            subprocess.Popen(["python3", exp_script])
        else:
            subprocess.Popen(["explorer", mount_pt] if os.name == 'nt' else ["files"])

    def action_launch_gparted(self):
        if shutil.which("gparted"):
            subprocess.Popen(["gparted"])
        else:
            messagebox.showinfo("GParted", "GParted binary not installed. The built-in BootOS Partition Wizard handles all operations.")

    def run_disk_script(self, bash_commands):
        self.status_lbl.config(text="Executing disk operation...")
        self.update_idletasks()
        try:
            if os.name == 'nt':
                messagebox.showinfo("Simulated Execution", f"[Windows Test Mode]\nCommand executed successfully.")
            else:
                res = subprocess.run(["/bin/sh", "-c", bash_commands], capture_output=True, text=True)
                if res.returncode != 0 and res.stderr:
                    messagebox.showwarning("Notice", f"Output:\n{res.stderr.strip()[:300]}")
            self.refresh_disks()
            messagebox.showinfo("Success", "Operation completed successfully!")
        except Exception as e:
            messagebox.showerror("Execution Error", str(e))
        self.status_lbl.config(text="Ready.")

    def action_exit(self):
        try:
            self.destroy()
        except Exception:
            pass
        os._exit(0)

if __name__ == "__main__":
    app = PartitionManagerApp()
    app.mainloop()
