#!/usr/bin/env python3
"""
BootOS Windows 11 File Explorer Backend Server
Provides local REST API and static UI serving for the native file manager.
Pure Python standard library - zero external dependencies.
"""

import os
import sys
import json
import time
import shutil
import mimetypes
import subprocess
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
from pathlib import Path

PORT = 54321
STATIC_DIR = os.path.dirname(os.path.abspath(__file__))

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

def get_file_type_and_icon(name, is_dir, is_symlink=False):
    if is_dir:
        return "File folder", "folder"
    
    ext = os.path.splitext(name)[1].lower()
    mapping = {
        ".txt": ("Text Document", "file-text"),
        ".md": ("Markdown Document", "file-text"),
        ".log": ("Log File", "file-text"),
        ".json": ("JSON File", "file-code"),
        ".xml": ("XML Document", "file-code"),
        ".yaml": ("YAML Configuration", "file-code"),
        ".yml": ("YAML Configuration", "file-code"),
        ".sh": ("Shell Script", "file-code"),
        ".bash": ("Bash Script", "file-code"),
        ".py": ("Python File", "file-code"),
        ".c": ("C Source File", "file-code"),
        ".h": ("C Header File", "file-code"),
        ".cpp": ("C++ Source File", "file-code"),
        ".html": ("HTML Document", "file-code"),
        ".css": ("Cascading Style Sheet", "file-code"),
        ".js": ("JavaScript File", "file-code"),
        ".png": ("PNG Image", "file-image"),
        ".jpg": ("JPEG Image", "file-image"),
        ".jpeg": ("JPEG Image", "file-image"),
        ".gif": ("GIF Image", "file-image"),
        ".svg": ("SVG Image", "file-image"),
        ".ico": ("Icon File", "file-image"),
        ".bmp": ("Bitmap Image", "file-image"),
        ".webp": ("WebP Image", "file-image"),
        ".iso": ("Disc Image File", "file-iso"),
        ".img": ("Disk Image File", "file-iso"),
        ".tar": ("TAR Archive", "file-archive"),
        ".gz": ("GZIP Compressed Archive", "file-archive"),
        ".zip": ("ZIP Archive", "file-archive"),
        ".7z": ("7-Zip Archive", "file-archive"),
        ".xz": ("XZ Compressed Archive", "file-archive"),
        ".bz2": ("BZIP2 Compressed Archive", "file-archive"),
        ".mp3": ("MP3 Audio File", "file-audio"),
        ".wav": ("WAV Audio File", "file-audio"),
        ".flac": ("FLAC Audio File", "file-audio"),
        ".mp4": ("MP4 Video File", "file-video"),
        ".mkv": ("MKV Video File", "file-video"),
        ".webm": ("WebM Video File", "file-video"),
        ".pdf": ("PDF Document", "file-pdf"),
        ".exe": ("Executable Application", "file-exe"),
        ".bat": ("Windows Batch File", "file-code"),
        ".ps1": ("PowerShell Script", "file-code"),
        ".conf": ("Configuration File", "file-settings"),
        ".cfg": ("Configuration File", "file-settings"),
        ".ini": ("Configuration Settings", "file-settings"),
    }
    
    if ext in mapping:
        return mapping[ext]
    
    # Check if executable
    return (f"{ext[1:].upper()} File" if ext else "File"), "file"

def get_drives_info():
    drives = []
    if os.name == 'nt':
        # Windows drives
        for letter in 'CDEFGHIJKLMNOPQRSTUVWXYZ':
            root = f"{letter}:\\"
            if os.path.exists(root):
                try:
                    usage = shutil.disk_usage(root)
                    name = "Local Disk" if letter in "CD" else "USB Drive" if letter == "E" else "Removable Disk"
                    drives.append({
                        "name": f"{name} ({letter}:)",
                        "path": root.replace('\\', '/'),
                        "letter": f"{letter}:",
                        "total_bytes": usage.total,
                        "used_bytes": usage.used,
                        "free_bytes": usage.free,
                        "total_fmt": format_size(usage.total),
                        "used_fmt": format_size(usage.used),
                        "free_fmt": format_size(usage.free),
                        "percent_used": round((usage.used / usage.total) * 100, 1) if usage.total else 0,
                        "type": "fixed" if letter in "CD" else "removable"
                    })
                except Exception:
                    pass
    else:
        # Linux / BootOS drives
        # 1. Root Filesystem (C:)
        try:
            root_usage = shutil.disk_usage("/")
            drives.append({
                "name": "BootOS System (C:)",
                "path": "/",
                "letter": "C:",
                "total_bytes": root_usage.total,
                "used_bytes": root_usage.used,
                "free_bytes": root_usage.free,
                "total_fmt": format_size(root_usage.total),
                "used_fmt": format_size(root_usage.used),
                "free_fmt": format_size(root_usage.free),
                "percent_used": round((root_usage.used / root_usage.total) * 100, 1) if root_usage.total else 0,
                "type": "fixed"
            })
        except Exception:
            pass

        # 2. RAM Disk (/tmp) (Z:)
        try:
            if os.path.exists("/tmp"):
                tmp_usage = shutil.disk_usage("/tmp")
                drives.append({
                    "name": "RAM Disk (Z:)",
                    "path": "/tmp",
                    "letter": "Z:",
                    "total_bytes": tmp_usage.total,
                    "used_bytes": tmp_usage.used,
                    "free_bytes": tmp_usage.free,
                    "total_fmt": format_size(tmp_usage.total),
                    "used_fmt": format_size(tmp_usage.used),
                    "free_fmt": format_size(tmp_usage.free),
                    "percent_used": round((tmp_usage.used / tmp_usage.total) * 100, 1) if tmp_usage.total else 0,
                    "type": "ram"
                })
        except Exception:
            pass

        # 3. Mounts & USB Drives (/media, /mnt)
        removable_paths = ["/media", "/mnt"]
        seen_paths = {"/", "/tmp"}
        drive_letters = "EFGHIJKLMNOPQRSTUVWXY"
        letter_idx = 0
        
        for base in removable_paths:
            if os.path.exists(base):
                for item in os.listdir(base):
                    full_p = os.path.join(base, item)
                    if os.path.ismount(full_p) or os.path.isdir(full_p):
                        if full_p not in seen_paths:
                            seen_paths.add(full_p)
                            letter = drive_letters[letter_idx % len(drive_letters)]
                            letter_idx += 1
                            try:
                                usage = shutil.disk_usage(full_p)
                                drives.append({
                                    "name": f"USB Storage ({letter}:)",
                                    "path": full_p,
                                    "letter": f"{letter}:",
                                    "total_bytes": usage.total,
                                    "used_bytes": usage.used,
                                    "free_bytes": usage.free,
                                    "total_fmt": format_size(usage.total),
                                    "used_fmt": format_size(usage.used),
                                    "free_fmt": format_size(usage.free),
                                    "percent_used": round((usage.used / usage.total) * 100, 1) if usage.total else 0,
                                    "type": "removable"
                                })
                            except Exception:
                                pass
    return drives

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True

class ExplorerHandler(BaseHTTPRequestHandler):
    def send_json(self, data, code=200):
        body = json.dumps(data).encode('utf-8')
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def send_error_json(self, message, code=400):
        self.send_json({"error": str(message)}, code=code)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        params = urllib.parse.parse_qs(parsed.query)

        if path == "/api/drives":
            drives = get_drives_info()
            self.send_json({"drives": drives})
            return

        if path == "/api/list":
            target_dir = params.get("path", ["/"])[0]
            show_hidden = params.get("show_hidden", ["false"])[0].lower() == "true"

            # Normalize Windows / Linux paths
            if os.name == 'nt' and (target_dir == "/" or not target_dir):
                target_dir = "C:\\"
            elif not target_dir:
                target_dir = "/"

            target_dir = os.path.abspath(target_dir)

            if not os.path.exists(target_dir):
                self.send_error_json(f"Path does not exist: {target_dir}", code=404)
                return

            if not os.path.isdir(target_dir):
                self.send_error_json(f"Path is not a directory: {target_dir}", code=400)
                return

            items = []
            try:
                entries = list(os.scandir(target_dir))
            except PermissionError:
                self.send_error_json(f"Access Denied: {target_dir}", code=403)
                return
            except Exception as e:
                self.send_error_json(f"Error reading directory: {str(e)}", code=500)
                return

            for entry in entries:
                name = entry.name
                if not show_hidden and name.startswith('.'):
                    continue

                try:
                    stat_info = entry.stat(follow_symlinks=False)
                    is_symlink = entry.is_symlink()
                    is_dir = entry.is_dir(follow_symlinks=True)
                    size = stat_info.st_size if not is_dir else None
                    mtime = stat_info.st_mtime
                    mtime_fmt = time.strftime("%m/%d/%Y %I:%M %p", time.localtime(mtime))
                    type_name, icon_name = get_file_type_and_icon(name, is_dir, is_symlink)
                    permissions = oct(stat_info.st_mode)[-3:]
                except Exception:
                    is_dir = False
                    size = 0
                    mtime = 0
                    mtime_fmt = "-"
                    type_name = "Unknown"
                    icon_name = "file"
                    permissions = "---"
                    is_symlink = False

                items.append({
                    "name": name,
                    "path": os.path.join(target_dir, name).replace('\\', '/'),
                    "is_dir": is_dir,
                    "is_symlink": is_symlink,
                    "size": size,
                    "size_fmt": format_size(size) if size is not None else "",
                    "mtime": mtime,
                    "date_fmt": mtime_fmt,
                    "type": type_name,
                    "icon": icon_name,
                    "permissions": permissions,
                    "is_hidden": name.startswith('.')
                })

            # Sort directories first, then alphabetically
            items.sort(key=lambda x: (not x["is_dir"], x["name"].lower()))

            # Parent directory
            parent = os.path.dirname(target_dir) if target_dir != os.path.dirname(target_dir) else None

            # Disk usage for current folder
            try:
                usage = shutil.disk_usage(target_dir)
                free_space_fmt = format_size(usage.free)
            except Exception:
                free_space_fmt = ""

            self.send_json({
                "current_path": target_dir.replace('\\', '/'),
                "parent_path": parent.replace('\\', '/') if parent else None,
                "item_count": len(items),
                "folder_count": sum(1 for i in items if i["is_dir"]),
                "file_count": sum(1 for i in items if not i["is_dir"]),
                "free_space_fmt": free_space_fmt,
                "items": items
            })
            return

        if path == "/api/search":
            base_path = params.get("path", ["/"])[0]
            query = params.get("q", [""])[0].lower()
            if not query:
                self.send_json({"results": []})
                return

            results = []
            count = 0
            for root, dirs, files in os.walk(base_path):
                # Avoid looping into deep system mounts or trash
                if "/proc" in root or "/sys" in root or "/dev" in root:
                    continue
                for name in dirs + files:
                    if query in name.lower():
                        full_p = os.path.join(root, name).replace('\\', '/')
                        is_d = os.path.isdir(full_p)
                        type_name, icon_name = get_file_type_and_icon(name, is_d)
                        results.append({
                            "name": name,
                            "path": full_p,
                            "is_dir": is_d,
                            "type": type_name,
                            "icon": icon_name
                        })
                        count += 1
                        if count >= 100:
                            break
                if count >= 100:
                    break
            self.send_json({"query": query, "count": len(results), "results": results})
            return

        if path == "/api/read_file":
            file_path = params.get("path", [""])[0]
            if not os.path.isfile(file_path):
                self.send_error_json("File not found", code=404)
                return

            try:
                # Read text preview
                with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
                    content = f.read(1024 * 512) # 512 KB preview
                self.send_json({
                    "path": file_path,
                    "name": os.path.basename(file_path),
                    "size_fmt": format_size(os.path.getsize(file_path)),
                    "content": content
                })
            except Exception as e:
                self.send_error_json(str(e), code=500)
            return

        # Serve static UI files
        if path == "/" or not path:
            path = "/index.html"
        
        file_to_serve = os.path.join(STATIC_DIR, path.lstrip('/'))
        if os.path.isfile(file_to_serve):
            ctype, _ = mimetypes.guess_type(file_to_serve)
            if not ctype:
                ctype = "text/plain"
            if file_to_serve.endswith(".css"):
                ctype = "text/css"
            elif file_to_serve.endswith(".js"):
                ctype = "application/javascript"
            elif file_to_serve.endswith(".html"):
                ctype = "text/html; charset=utf-8"

            try:
                with open(file_to_serve, 'rb') as f:
                    content = f.read()
                self.send_response(200)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(content)))
                self.send_header("Cache-Control", "no-cache")
                self.end_headers()
                self.wfile.write(content)
                return
            except Exception as e:
                self.send_error_json(str(e), code=500)
                return

        self.send_error_json("Not Found", code=404)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        try:
            content_len = int(self.headers.get('Content-Length', 0))
            post_body = self.rfile.read(content_len)
            data = json.loads(post_body.decode('utf-8')) if post_body else {}
        except Exception as e:
            self.send_error_json(f"Invalid JSON body: {str(e)}", code=400)
            return

        if path == "/api/mkdir":
            parent = data.get("path")
            name = data.get("name", "New folder").strip()
            if not parent or not name:
                self.send_error_json("Missing path or name")
                return

            target = os.path.join(parent, name)
            counter = 2
            while os.path.exists(target):
                target = os.path.join(parent, f"{name} ({counter})")
                counter += 1

            try:
                os.makedirs(target, exist_ok=True)
                self.send_json({"success": True, "created": target.replace('\\', '/')})
            except Exception as e:
                self.send_error_json(str(e), code=500)
            return

        if path == "/api/create_file":
            parent = data.get("path")
            name = data.get("name", "New Text Document.txt").strip()
            content = data.get("content", "")
            if not parent or not name:
                self.send_error_json("Missing path or name")
                return

            target = os.path.join(parent, name)
            stem, ext = os.path.splitext(name)
            counter = 2
            while os.path.exists(target):
                target = os.path.join(parent, f"{stem} ({counter}){ext}")
                counter += 1

            try:
                with open(target, 'w', encoding='utf-8') as f:
                    f.write(content)
                self.send_json({"success": True, "created": target.replace('\\', '/')})
            except Exception as e:
                self.send_error_json(str(e), code=500)
            return

        if path == "/api/rename":
            old_path = data.get("old_path")
            new_name = data.get("new_name", "").strip()
            if not old_path or not new_name:
                self.send_error_json("Missing old_path or new_name")
                return

            parent = os.path.dirname(old_path)
            new_path = os.path.join(parent, new_name)
            if os.path.exists(new_path) and os.path.normpath(old_path) != os.path.normpath(new_path):
                self.send_error_json(f"An item named '{new_name}' already exists.")
                return

            try:
                os.rename(old_path, new_path)
                self.send_json({"success": True, "new_path": new_path.replace('\\', '/')})
            except Exception as e:
                self.send_error_json(str(e), code=500)
            return

        if path == "/api/delete":
            paths = data.get("paths", [])
            if not paths:
                self.send_error_json("No paths specified")
                return

            deleted = []
            errors = []
            for p in paths:
                try:
                    if os.path.isdir(p) and not os.path.islink(p):
                        shutil.rmtree(p)
                    else:
                        os.unlink(p)
                    deleted.append(p)
                except Exception as e:
                    errors.append(f"{p}: {str(e)}")

            self.send_json({"success": len(errors) == 0, "deleted": deleted, "errors": errors})
            return

        if path == "/api/copy" or path == "/api/move":
            is_move = (path == "/api/move")
            sources = data.get("sources", [])
            dest_dir = data.get("destination")
            if not sources or not dest_dir:
                self.send_error_json("Missing sources or destination")
                return

            results = []
            errors = []
            for src in sources:
                try:
                    base = os.path.basename(src.rstrip('/\\'))
                    dst = os.path.join(dest_dir, base)
                    if is_move:
                        shutil.move(src, dst)
                    else:
                        if os.path.isdir(src):
                            # Auto rename duplicate
                            cnt = 2
                            while os.path.exists(dst):
                                dst = os.path.join(dest_dir, f"{base} - Copy ({cnt})")
                                cnt += 1
                            shutil.copytree(src, dst)
                        else:
                            cnt = 2
                            stem, ext = os.path.splitext(base)
                            while os.path.exists(dst):
                                dst = os.path.join(dest_dir, f"{stem} - Copy ({cnt}){ext}")
                                cnt += 1
                            shutil.copy2(src, dst)
                    results.append(dst.replace('\\', '/'))
                except Exception as e:
                    errors.append(f"{src}: {str(e)}")

            self.send_json({"success": len(errors) == 0, "results": results, "errors": errors})
            return

        if path == "/api/launch":
            target_path = data.get("path")
            action = data.get("action", "open") # open, terminal, editor

            if not target_path or not os.path.exists(target_path):
                self.send_error_json("Target path does not exist", code=404)
                return

            try:
                if action == "terminal":
                    # Open terminal in directory
                    work_dir = target_path if os.path.isdir(target_path) else os.path.dirname(target_path)
                    if os.name == 'nt':
                        subprocess.Popen(f'start cmd /k "cd /d {work_dir}"', shell=True)
                    else:
                        subprocess.Popen(['xterm', '-e', f'cd "{work_dir}" && bash'], start_new_session=True)
                elif action == "open":
                    if os.path.isdir(target_path):
                        pass
                    elif target_path.endswith(('.sh', '.bash', '.py')):
                        if os.name != 'nt':
                            subprocess.Popen(['xterm', '-hold', '-e', target_path], start_new_session=True)
                        else:
                            subprocess.Popen(f'start cmd /k "{target_path}"', shell=True)
                    else:
                        # Default editor/viewer
                        if os.name == 'nt':
                            os.startfile(target_path)
                        else:
                            subprocess.Popen(['xdg-open', target_path], start_new_session=True)
                self.send_json({"success": True})
            except Exception as e:
                self.send_error_json(str(e), code=500)
            return

        self.send_error_json("Endpoint not found", code=404)

def run():
    server_address = ('127.0.0.1', PORT)
    httpd = ThreadedHTTPServer(server_address, ExplorerHandler)
    print(f"BootOS Windows 11 File Explorer server running at http://127.0.0.1:{PORT}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        httpd.shutdown()

if __name__ == '__main__':
    run()
