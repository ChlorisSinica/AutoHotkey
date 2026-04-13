"""ppt_scan_gui.py — tkinter GUI for PowerPoint retro source scan

Usage: pythonw ppt_scan_gui.py <pptxPath> <scanId> [jsonPath] [statusPath] [cancelPath] [stdoutPath] [stderrPath]

Single-view GUI: Treeview (left) + image preview (right) are shown from the
start.  Rows begin as "Pending" and update to matched/unresolved as each media
item is resolved by the background worker thread.
"""

import sys
import os
import atexit
import ctypes
import ctypes.wintypes
import queue
import shutil
import threading
import tkinter as tk
from tkinter import ttk

try:
    from PIL import Image, ImageTk
    HAS_PILLOW = True
except ImportError:
    HAS_PILLOW = False

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ppt_scan

PILLOW_FORMATS = {"png", "jpg", "jpeg", "bmp", "tif", "tiff", "gif", "webp"}
VECTOR_FORMATS = {"svg", "emf", "wmf", "eps", "ai"}
MEDIA_FORMATS = {"mp4", "avi", "wmv", "mov", "mkv", "mp3", "wav", "wma",
                 "m4a", "m4v", "webm"}

# DPI awareness は設定しない。Windows のデフォルト DPI 仮想化に任せる。
# (設定すると tkinter の座標系と Win32 API の座標系が不整合を起こし、
#  ドラッグ時のスケール変動やウィンドウサイズの誤算が発生するため)

try:
    ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(
        "myapp.ppt.sourcescan")
except Exception:
    pass


class ScanGUI:

    def __init__(self, pptx_path, scan_id, json_path, status_path,
                 cancel_path, stdout_path, stderr_path):
        self.pptx_path = pptx_path
        self.scan_id = scan_id
        self.json_path = json_path
        self.status_path = status_path
        self.cancel_path = cancel_path
        self.stdout_path = stdout_path
        self.stderr_path = stderr_path

        self._queue = queue.Queue()
        self._rows = []           # [{media_file, slide, status, source, backend, shapes}, ...]
        self.scan_result = None
        self.media_dir = None
        self.snap_dir = None
        self._scan_thread = None
        self._closing = False
        self._preview_photo = None
        self._preview_resize_timer = None
        self._thumb_cache = {}    # {file_path: (orig_w, orig_h, PIL.Image thumbnail)}
        self._thumb_max = 50      # キャッシュ上限
        self._thumb_size = (600, 600)  # サムネイル最大サイズ
        self._start_tick = None

        self.root = tk.Tk()
        self.root.withdraw()  # 位置決定まで非表示 (点滅防止)
        self.root.title("PowerPoint Source Scan")
        self.root.minsize(700, 420)

        self._place_on_cursor_monitor(ratio_w=0.50, ratio_h=0.60)
        self._build_ui()
        self._start_scan_thread()

        self.root.protocol("WM_DELETE_WINDOW", self._on_close)
        atexit.register(self._cleanup_temp)
        self.root.deiconify()  # 準備完了後に表示
        self.root.mainloop()

    # ==================================================================
    #  UI construction
    # ==================================================================

    def _build_ui(self):
        # -- Menu bar --
        menubar = tk.Menu(self.root)
        self.root.config(menu=menubar)
        help_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="Help", menu=help_menu)
        help_menu.add_command(label="Status Icons & Shortcuts",
                              command=self._show_help)

        # -- Style --
        style = ttk.Style()
        style.configure("TLabelframe", relief="solid", borderwidth=1)
        style.configure("TLabelframe.Label", font=("Segoe UI", 9, "bold"))
        import tkinter.font as tkfont
        tree_font = tkfont.nametofont("TkDefaultFont")
        style.configure("Treeview", rowheight=tree_font.metrics("linespace") + 4)

        # -- Top status bar --
        top = ttk.Frame(self.root, padding=(10, 4))
        top.pack(fill="x")
        pptx_name = os.path.basename(self.pptx_path)
        ttk.Label(top, text="Target:", font=("Segoe UI", 9),
                  foreground="#555555").pack(side="left")
        ttk.Label(top, text=pptx_name, font=("Segoe UI", 9)).pack(
            side="left", padx=(4, 0))
        self._lbl_stage = ttk.Label(top, text="Initializing...",
                                    font=("Segoe UI", 9))
        self._lbl_stage.pack(side="right")

        # -- Content: PanedWindow (tree | preview) --
        paned = ttk.PanedWindow(self.root, orient="horizontal")
        paned.pack(fill="both", expand=True, padx=6, pady=(0, 4))
        self._paned = paned

        # Left: Treeview in LabelFrame
        left_frame = ttk.LabelFrame(paned, text="Scan Results", padding=4)
        paned.add(left_frame, weight=3)

        cols = ("slide", "media", "source", "backend", "status")
        self.tree = ttk.Treeview(
            left_frame, columns=cols, show="headings", selectmode="browse")
        self.tree.heading("slide", text="Slide")
        self.tree.heading("media", text="Media")
        self.tree.heading("source", text="Source")
        self.tree.heading("backend", text="Backend")
        self.tree.heading("status", text="Status")
        self.tree.column("slide", width=48, anchor="center", minwidth=36)
        self.tree.column("media", width=130, anchor="w", minwidth=80)
        self.tree.column("source", width=260, anchor="w", minwidth=100)
        self.tree.column("backend", width=90, anchor="center", minwidth=60)
        self.tree.column("status", width=60, anchor="center", minwidth=40)

        self.tree.tag_configure("matched", foreground="#1a7f1a")
        self.tree.tag_configure("missing", foreground="#cc6600")
        self.tree.tag_configure("unresolved", foreground="#cc0000")
        self.tree.tag_configure("external", foreground="#0055aa")
        self.tree.tag_configure("pending", foreground="#888888")
        self.tree.tag_configure("running", foreground="#cc8800")

        vsb = ttk.Scrollbar(left_frame, orient="vertical",
                             command=self.tree.yview)
        self.tree.configure(yscrollcommand=vsb.set)
        self.tree.pack(side="left", fill="both", expand=True)
        vsb.pack(side="right", fill="y")
        self.tree.bind("<<TreeviewSelect>>", self._on_tree_select)
        self.tree.bind("<Button-3>", self._on_tree_right_click)

        # Right: Preview in LabelFrame
        right_frame = ttk.LabelFrame(paned, text="Preview", padding=4)
        paned.add(right_frame, weight=2)

        self._preview_canvas = tk.Canvas(right_frame, bg="#f0f0f0",
                                         highlightthickness=0)
        self._preview_canvas.pack(fill="both", expand=True)
        self._preview_canvas.bind("<Configure>", self._on_preview_resize)

        self._lbl_preview_info = ttk.Label(right_frame, text="",
                                           font=("Segoe UI", 9))
        self._lbl_preview_info.pack(fill="x", pady=(4, 0))

        # -- Bottom: Progress in LabelFrame --
        bottom_frame = ttk.LabelFrame(self.root, text="Progress", padding=(8, 4))
        bottom_frame.pack(fill="x", padx=6, pady=(0, 6))

        # Progress bar
        pbar_frame = ttk.Frame(bottom_frame)
        pbar_frame.pack(fill="x", pady=(0, 2))
        self._progress_var = tk.IntVar(value=0)
        self._progress_bar = ttk.Progressbar(
            pbar_frame, variable=self._progress_var,
            maximum=100, mode="indeterminate")
        self._progress_bar.pack(fill="x", side="left", expand=True)
        self._progress_bar.start(20)
        self._lbl_progress = ttk.Label(pbar_frame, text="", width=16,
                                       anchor="e")
        self._lbl_progress.pack(side="right", padx=(8, 0))

        # Detail row
        detail_frame = ttk.Frame(bottom_frame)
        detail_frame.pack(fill="x", pady=(0, 2))
        self._lbl_detail_backend = ttk.Label(
            detail_frame, text="", font=("Segoe UI", 9), foreground="#555555")
        self._lbl_detail_backend.pack(side="left", padx=(0, 12))
        self._lbl_detail_files = ttk.Label(
            detail_frame, text="", font=("Segoe UI", 9), foreground="#555555")
        self._lbl_detail_files.pack(side="left", padx=(0, 12))
        self._lbl_detail_candidates = ttk.Label(
            detail_frame, text="", font=("Segoe UI", 9), foreground="#555555")
        self._lbl_detail_candidates.pack(side="left", padx=(0, 12))
        self._lbl_detail_elapsed = ttk.Label(
            detail_frame, text="", font=("Segoe UI", 9), foreground="#555555")
        self._lbl_detail_elapsed.pack(side="right")

        # Log area
        self._log_text = tk.Text(bottom_frame, height=3,
                                 font=("Consolas", 9), wrap="none",
                                 state="disabled", bg="#fafafa",
                                 relief="sunken", bd=1)
        self._log_text.pack(fill="x", pady=(2, 4))

        # Stats + buttons
        stats = ttk.Frame(bottom_frame)
        stats.pack(fill="x")
        self._lbl_summary = ttk.Label(stats, text="", font=("Segoe UI", 9))
        self._lbl_summary.pack(side="left", fill="x", expand=True)

        self._cancel_btn = ttk.Button(
            stats, text="Cancel", command=self._on_cancel)
        self._cancel_btn.pack(side="right", padx=(8, 0))
        self._close_btn = ttk.Button(
            stats, text="Close", command=self._on_close)
        self._close_btn.pack(side="right")
        self._close_btn.pack_forget()

        # Set initial sash position after layout
        self.root.after(50, self._init_sash)

    def _place_on_cursor_monitor(self, ratio_w=0.50, ratio_h=0.60):
        """マウスカーソルがあるモニターの中央にウィンドウを配置する。

        DPI awareness を設定していないため、Win32 API も tkinter も
        論理ピクセル (DPI 仮想化後) で一致する。
        """
        try:
            point = ctypes.wintypes.POINT()
            ctypes.windll.user32.GetCursorPos(ctypes.byref(point))

            MONITOR_DEFAULTTONEAREST = 2
            hmon = ctypes.windll.user32.MonitorFromPoint(
                ctypes.wintypes.POINT(point.x, point.y),
                MONITOR_DEFAULTTONEAREST)

            class MONITORINFO(ctypes.Structure):
                _fields_ = [("cbSize", ctypes.c_ulong),
                             ("rcMonitor", ctypes.wintypes.RECT),
                             ("rcWork", ctypes.wintypes.RECT),
                             ("dwFlags", ctypes.c_ulong)]
            mi = MONITORINFO()
            mi.cbSize = ctypes.sizeof(MONITORINFO)
            ctypes.windll.user32.GetMonitorInfoW(hmon, ctypes.byref(mi))

            work = mi.rcWork
            mon_w = work.right - work.left
            mon_h = work.bottom - work.top
            win_w = int(mon_w * ratio_w)
            win_h = int(mon_h * ratio_h)
            cx = work.left + (mon_w - win_w) // 2
            cy = work.top + (mon_h - win_h) // 2
            self.root.geometry(f"{win_w}x{win_h}+{cx}+{cy}")
        except Exception:
            self.root.geometry("800x560")

    def _init_sash(self):
        self.root.update_idletasks()
        total_w = self._paned.winfo_width()
        if total_w > 1:
            self._paned.sashpos(0, int(total_w * 0.55))

    # ==================================================================
    #  Scan thread + callbacks
    # ==================================================================

    def _start_scan_thread(self):
        self._start_tick = self.root.tk.call("clock", "milliseconds")
        self._scan_thread = threading.Thread(
            target=self._scan_worker, daemon=True)
        self._scan_thread.start()
        self._poll_queue()
        self._update_elapsed()

    def _scan_worker(self):
        try:
            outcome = ppt_scan.run_scan(
                self.pptx_path, self.scan_id, self.json_path,
                self.status_path, self.cancel_path,
                self.stdout_path, self.stderr_path,
                keep_media=True,
                on_map_built=self._cb_map_built,
                on_media_resolved=self._cb_media_resolved,
            )
            self._queue.put({"_type": "done",
                             "result": outcome.get("result"),
                             "media_dir": outcome.get("media_dir"),
                             "snap_dir": outcome.get("snap_dir")})
        except ppt_scan.ScanCancelled:
            self._queue.put({"_type": "cancelled"})
        except Exception as exc:
            self._queue.put({"_type": "error", "error": str(exc)})

    # -- Callbacks (called from worker thread, schedule via queue) --

    def _cb_map_built(self, media_map, external_links, media_dir):
        self._queue.put({"_type": "map_built",
                         "media_map": media_map,
                         "external_links": external_links,
                         "media_dir": media_dir})

    def _cb_media_resolved(self, index, total, media_file, source_path,
                           search_backend, shapes, *, source_exists=True):
        self._queue.put({"_type": "resolved",
                         "index": index, "total": total,
                         "media_file": media_file,
                         "source_path": source_path,
                         "search_backend": search_backend,
                         "shapes": shapes,
                         "source_exists": source_exists})

    # ==================================================================
    #  Queue polling (main thread)
    # ==================================================================

    def _poll_queue(self):
        if self._closing:
            return
        try:
            while True:
                msg = self._queue.get_nowait()
                self._handle_message(msg)
        except queue.Empty:
            pass
        # ステータスファイルから詳細情報を読み取り (バックエンド・候補数等)
        self._poll_status_file()
        self.root.after(150, self._poll_queue)

    def _poll_status_file(self):
        """ステータスファイルから探索中の詳細情報を読み取り表示する。"""
        if not self.status_path or not os.path.isfile(self.status_path):
            return
        try:
            with open(self.status_path, "r", encoding="utf-8", errors="replace") as f:
                text = f.read()
        except (OSError, PermissionError):
            return
        status = {}
        for line in text.splitlines():
            sep = line.find("=")
            if sep > 0:
                status[line[:sep].strip()] = line[sep + 1:]

        backend = status.get("backend", "")
        files_scanned = status.get("files_scanned", "0")
        candidates = status.get("candidate_count", "0")
        message = status.get("message", "")

        if backend:
            self._lbl_detail_backend.config(text=f"Backend: {backend}")
        fs = int(files_scanned or 0)
        if fs > 0:
            self._lbl_detail_files.config(text=f"Files: {fs:,}")
        cd = int(candidates or 0)
        if cd > 0:
            self._lbl_detail_candidates.config(text=f"Candidates: {cd:,}")

        if self._start_tick is not None:
            now = self.root.tk.call("clock", "milliseconds")
            elapsed = (now - self._start_tick) / 1000
            self._lbl_detail_elapsed.config(text=f"{elapsed:.1f}s")

    def _handle_message(self, msg):
        t = msg.get("_type")
        if t == "map_built":
            self.media_dir = msg["media_dir"]
            self._populate_initial_rows(msg["media_map"],
                                        msg["external_links"])
            self._log(f"Media map: {len(msg['media_map'])} internal, "
                      f"{len(msg['external_links'])} external")
        elif t == "resolved":
            self._update_resolved_row(msg)
        elif t == "done":
            self._on_scan_done(msg)
        elif t == "cancelled":
            self._log("Scan cancelled.")
            self._on_scan_cancelled()
        elif t == "error":
            self._log(f"ERROR: {msg['error']}")
            self._on_scan_error(msg["error"])

    # ==================================================================
    #  Treeview: initial population (Pending rows)
    # ==================================================================

    def _populate_initial_rows(self, media_map, external_links):
        self._rows.clear()
        idx = 0
        for media_file, info in media_map.items():
            shapes = info["shapes"]
            slide = shapes[0][0] if shapes else ""
            self._rows.append({
                "idx": idx,
                "media_file": media_file,
                "slide": slide,
                "status": "Pending",
                "source": "",
                "backend": "",
                "shapes": shapes,
            })
            idx += 1
        for slide_idx, sld_id, shape_id, ext_path in external_links:
            self._rows.append({
                "idx": idx,
                "media_file": None,
                "slide": slide_idx,
                "status": "Pending",
                "source": ext_path,
                "backend": "External",
                "shapes": [(slide_idx, sld_id, shape_id)],
            })
            idx += 1

        total = len(self._rows)
        self._progress_bar.stop()
        self._progress_bar.config(mode="determinate", maximum=max(total, 1))
        self._progress_var.set(0)
        self._lbl_stage.config(text=f"Scanning 0 / {total}")
        self._refresh_tree()

    # ==================================================================
    #  Treeview: per-item update
    # ==================================================================

    def _update_resolved_row(self, msg):
        index = msg["index"] - 1  # 1-based from ppt_scan → 0-based
        if index < 0 or index >= len(self._rows):
            return

        # 次の行を Running にマーク (あれば)
        next_index = index + 1
        if next_index < len(self._rows) and self._rows[next_index]["status"] == "Pending":
            self._rows[next_index]["status"] = "Running"
            self._refresh_row(next_index)

        row = self._rows[index]
        media_name = row["media_file"] or "(external)"
        source_path = msg["source_path"]
        backend = msg["search_backend"] or ""
        source_exists = msg.get("source_exists", True)

        if backend == "external_link":
            if source_exists:
                row["status"] = "\u2192"      # →
            else:
                row["status"] = "\u2717\u2192"  # ✗→  (リンク切れ)
            row["source"] = source_path or ""
            row["backend"] = "External"
        elif source_path:
            if source_exists:
                row["status"] = "\u2713"      # ✓
            else:
                row["status"] = "\u2713?"     # パスは導出したが実体なし
            row["source"] = source_path
            row["backend"] = backend
        else:
            row["status"] = "\u2717"      # ✗
            row["source"] = "\u672a\u89e3\u6c7a"  # 未解決
            row["backend"] = ""

        total = msg["total"]
        done_count = msg["index"]
        self._progress_var.set(done_count)
        self._lbl_progress.config(text=f"{done_count} / {total}")
        self._lbl_stage.config(text=f"Scanning {done_count} / {total}")

        # ログ出力
        status_icon = row["status"]
        log_backend = f" [{backend}]" if backend else ""
        if source_path and source_exists:
            self._log(f"[{done_count}/{total}] {media_name}{log_backend} -> {os.path.basename(source_path)}")
        elif source_path:
            self._log(f"[{done_count}/{total}] {media_name}{log_backend} -> {os.path.basename(source_path)} (missing)")
        else:
            self._log(f"[{done_count}/{total}] {media_name} -> unresolved")

        # 詳細ラベルをクリア (次のアイテムで更新される)
        self._lbl_detail_backend.config(text="")
        self._lbl_detail_files.config(text="")
        self._lbl_detail_candidates.config(text="")

        self._refresh_row(index)
        # ユーザーが行を選択していない場合のみ自動スクロール
        if not self.tree.selection():
            self.tree.see(str(index))

    # ==================================================================
    #  Treeview rendering
    # ==================================================================

    def _refresh_tree(self):
        prev_sel = self.tree.selection()
        self.tree.delete(*self.tree.get_children())
        for i, row in enumerate(self._rows):
            self.tree.insert("", "end", iid=str(i),
                             values=self._row_values(row),
                             tags=(self._row_tag(row),))
        for iid in prev_sel:
            if self.tree.exists(iid):
                self.tree.selection_set(iid)

    def _refresh_row(self, index):
        iid = str(index)
        if not self.tree.exists(iid):
            return
        row = self._rows[index]
        self.tree.item(iid, values=self._row_values(row),
                       tags=(self._row_tag(row),))

    def _row_values(self, row):
        media_display = row["media_file"] if row["media_file"] else "(external)"
        return (row["slide"], media_display, row["source"],
                row["backend"], row["status"])

    def _row_tag(self, row):
        st = row["status"]
        if st == "Running":
            return "running"
        if st == "Pending":
            return "pending"
        if st == "\u2713":
            return "matched"
        if st == "\u2713?" or st == "\u2717\u2192":
            return "missing"   # パス導出済だが実体なし / 外部リンク切れ
        if st == "\u2717":
            return "unresolved"
        if st == "\u2192":
            return "external"
        return "pending"

    # ==================================================================
    #  Scan completion / error / cancel
    # ==================================================================

    def _on_scan_done(self, msg):
        self.scan_result = msg.get("result")
        self.snap_dir = msg.get("snap_dir")
        if not self.media_dir:
            self.media_dir = msg.get("media_dir")

        summary = self.scan_result.get("summary", {}) if self.scan_result else {}
        total = summary.get("total_media", 0) + summary.get("external_links", 0)
        matched = summary.get("matched", 0)
        unresolved = summary.get("unresolved", 0)
        ext = summary.get("external_links", 0)

        self._progress_var.set(total)
        self._lbl_stage.config(text="Done")
        self._lbl_summary.config(
            text=f"Total: {total}  |  Matched: {matched}  |  "
                 f"Unresolved: {unresolved}  |  External: {ext}")
        self.root.title(
            f"PowerPoint Source Scan \u2014 "
            f"{matched} matched, {unresolved} unresolved")
        self._cancel_btn.pack_forget()
        self._close_btn.pack(side="right")

    def _on_scan_cancelled(self):
        self._lbl_stage.config(text="Cancelled")
        self._cancel_btn.pack_forget()
        self._close_btn.pack(side="right")

    def _on_scan_error(self, error_msg):
        self._lbl_stage.config(text="Error")
        self._lbl_summary.config(text=error_msg, foreground="red")
        self._cancel_btn.pack_forget()
        self._close_btn.pack(side="right")

    # ==================================================================
    #  Elapsed timer
    # ==================================================================

    def _update_elapsed(self):
        if self._closing:
            return
        if self._start_tick is not None:
            now = self.root.tk.call("clock", "milliseconds")
            elapsed = (now - self._start_tick) / 1000
            cur = self._lbl_progress.cget("text")
            if "/" not in cur:
                self._lbl_progress.config(text=f"{elapsed:.1f}s")
        if self._scan_thread and self._scan_thread.is_alive():
            self.root.after(500, self._update_elapsed)

    # ==================================================================
    #  Context menu (right-click)
    # ==================================================================

    def _on_tree_right_click(self, event):
        iid = self.tree.identify_row(event.y)
        if not iid:
            return
        self.tree.selection_set(iid)
        index = int(iid)
        if index < 0 or index >= len(self._rows):
            return
        row = self._rows[index]

        menu = tk.Menu(self.root, tearoff=0)
        source = row.get("source", "")
        media = row.get("media_file", "")

        if source and source != "\u672a\u89e3\u6c7a":  # 未解決 でない
            menu.add_command(label="Copy source path",
                             command=lambda: self._copy_to_clipboard(source))
        if media:
            menu.add_command(label="Copy media name",
                             command=lambda: self._copy_to_clipboard(media))
        if source and source != "\u672a\u89e3\u6c7a":
            menu.add_separator()
            menu.add_command(label="Open source folder",
                             command=lambda: self._open_folder(source))

        if menu.index("end") is not None:
            menu.tk_popup(event.x_root, event.y_root)

    def _copy_to_clipboard(self, text):
        self.root.clipboard_clear()
        self.root.clipboard_append(text)
        self._log(f"Copied: {text}")

    def _open_folder(self, path):
        folder = os.path.dirname(path)
        if os.path.isdir(folder):
            os.startfile(folder)

    # ==================================================================
    #  Image preview
    # ==================================================================

    def _on_tree_select(self, event=None):
        self._update_preview()

    def _on_preview_resize(self, event=None):
        if self._preview_resize_timer:
            self.root.after_cancel(self._preview_resize_timer)
        self._preview_resize_timer = self.root.after(200, self._update_preview)

    def _update_preview(self):
        self._preview_canvas.delete("all")
        self._preview_photo = None
        sel = self.tree.selection()
        if not sel:
            self._lbl_preview_info.config(text="")
            return

        index = int(sel[0])
        if index < 0 or index >= len(self._rows):
            return
        row = self._rows[index]
        media_file = row["media_file"]
        source_path = row.get("source", "")

        if media_file is None:
            self._draw_placeholder("External link")
            self._lbl_preview_info.config(text=source_path)
            return

        # ソースが解決済みかつ実体が存在する場合、ソースファイルを優先表示
        # (pptx 内部の圧縮画像より高品質)
        preview_path = None
        preview_label = ""
        if source_path and source_path != "\u672a\u89e3\u6c7a" and os.path.isfile(source_path):
            preview_path = source_path
            preview_label = os.path.basename(source_path)
        elif self.media_dir:
            candidate = os.path.join(self.media_dir, media_file)
            if os.path.isfile(candidate):
                preview_path = candidate
                preview_label = media_file + "  (embedded)"

        if not preview_path:
            if not self.media_dir:
                self._draw_placeholder("Media not yet extracted")
            else:
                self._draw_placeholder("File not found")
            self._lbl_preview_info.config(text=media_file)
            return

        ext = os.path.splitext(preview_path)[1].lower().lstrip(".")
        size_kb = os.path.getsize(preview_path) / 1024

        if ext in PILLOW_FORMATS and HAS_PILLOW:
            try:
                orig_w, orig_h, thumb = self._get_thumbnail(preview_path)
                cw = max(self._preview_canvas.winfo_width(), 100)
                ch = max(self._preview_canvas.winfo_height(), 100)
                # サムネイルからさらに Canvas サイズに合わせてリサイズ
                tw, th = thumb.size
                scale = min(cw / tw, ch / th)
                new_w = max(int(tw * scale), 1)
                new_h = max(int(th * scale), 1)
                display = thumb.resize((new_w, new_h), Image.LANCZOS)
                self._preview_photo = ImageTk.PhotoImage(display)
                self._preview_canvas.create_image(
                    cw // 2, ch // 2, image=self._preview_photo)
                self._lbl_preview_info.config(
                    text=f"{preview_label}  ({orig_w}\u00d7{orig_h}, "
                         f"{size_kb:.1f} KB)")
                return
            except Exception:
                pass

        if ext in PILLOW_FORMATS and not HAS_PILLOW:
            self._draw_placeholder(
                f"{preview_label}\n\npip install Pillow\nfor preview")
        elif ext in VECTOR_FORMATS:
            self._draw_placeholder(f"Vector: .{ext}\n{preview_label}")
        elif ext in MEDIA_FORMATS:
            self._draw_placeholder(f"Media: .{ext}\n{preview_label}")
        else:
            self._draw_placeholder(f".{ext}\n{preview_label}")
        self._lbl_preview_info.config(
            text=f"{preview_label}  ({size_kb:.1f} KB)")

    def _get_thumbnail(self, file_path):
        """サムネイルキャッシュから取得。なければ生成してキャッシュ。

        thumbnail() は元画像を全展開せず効率的に縮小する。
        10000x8000 の画像でも thumb_size (600x600) 以下に収まり ~1.4 MB で済む。
        """
        if file_path in self._thumb_cache:
            return self._thumb_cache[file_path]

        img = Image.open(file_path)
        orig_w, orig_h = img.size
        # thumbnail() はインプレースで縮小 (元画像のメモリを解放)
        img.thumbnail(self._thumb_size, Image.LANCZOS)

        # LRU 簡易: 上限超えたら最古を削除
        if len(self._thumb_cache) >= self._thumb_max:
            oldest = next(iter(self._thumb_cache))
            del self._thumb_cache[oldest]

        self._thumb_cache[file_path] = (orig_w, orig_h, img)
        return orig_w, orig_h, img

    def _draw_placeholder(self, text):
        cw = max(self._preview_canvas.winfo_width(), 100)
        ch = max(self._preview_canvas.winfo_height(), 100)
        self._preview_canvas.create_text(
            cw // 2, ch // 2, text=text, fill="#888888",
            font=("Segoe UI", 10), justify="center")

    # ==================================================================
    #  Log
    # ==================================================================

    def _log(self, text):
        """ログエリアに 1 行追加。"""
        self._log_text.config(state="normal")
        self._log_text.insert("end", text + "\n")
        self._log_text.see("end")
        self._log_text.config(state="disabled")

    # ==================================================================
    #  Help
    # ==================================================================

    def _show_help(self):
        from tkinter import messagebox
        messagebox.showinfo("Source Scan Help", (
            "Status column:\n"
            "  \u2713      Matched \u2014 source found and file exists\n"
            "  \u2713?    Matched \u2014 path resolved but file missing\n"
            "  \u2192      External link \u2014 file exists\n"
            "  \u2717\u2192  External link \u2014 broken (file missing)\n"
            "  \u2717      Unresolved \u2014 no source found\n"
            "  Pending  Waiting to be scanned\n"
            "\n"
            "Search backends:\n"
            "  Everything \u2014 Everything (es.exe) index\n"
            "  Windows Search \u2014 WDS / SYSTEMINDEX\n"
            "  Directory \u2014 folder recursive scan\n"
            "  External \u2014 pptx embedded URI\n"
            "\n"
            "AHK shortcuts (in PowerPoint):\n"
            "  Ctrl+Alt+S \u2014 Start retro scan\n"
            "  Ctrl+Alt+Q \u2014 Show source info for selection\n"
            "  Ctrl+Alt+E \u2014 Export sources\n"
            "  Ctrl+Alt+F1 \u2014 Show help"
        ), parent=self.root)

    # ==================================================================
    #  Cancel / Close / Cleanup
    # ==================================================================

    def _on_cancel(self):
        if self.cancel_path:
            os.makedirs(os.path.dirname(self.cancel_path) or ".", exist_ok=True)
            try:
                with open(self.cancel_path, "w", encoding="utf-8") as f:
                    f.write("cancel\n")
            except OSError:
                pass
        self._cancel_btn.config(state="disabled", text="Cancelling...")

    def _on_close(self):
        self._closing = True
        scan_was_active = (self._scan_thread is not None
                           and self._scan_thread.is_alive())
        if scan_was_active:
            if self.cancel_path:
                os.makedirs(os.path.dirname(self.cancel_path) or ".",
                            exist_ok=True)
                try:
                    with open(self.cancel_path, "w", encoding="utf-8") as f:
                        f.write("cancel\n")
                except OSError:
                    pass
            self._scan_thread.join(timeout=35)
        # join 後に再チェック: スキャンが join 中に正常完了/エラーで終了した場合は
        # ステータスを上書きしない (done=1 や stage=エラー を cancelled=1 で潰さない)
        if scan_was_active and self.status_path:
            current_status = {}
            try:
                with open(self.status_path, "r", encoding="utf-8",
                          errors="replace") as f:
                    for line in f:
                        sep = line.find("=")
                        if sep > 0:
                            current_status[line[:sep].strip()] = line[sep + 1:].strip()
            except OSError:
                pass
            already_terminal = (current_status.get("done") == "1"
                                or current_status.get("cancelled") == "1"
                                or current_status.get("stage") == "エラー")
            if not already_terminal:
                try:
                    ppt_scan.write_status(self.status_path, {
                        "stage": "キャンセル完了",
                        "message": "GUI が閉じられました。",
                        "cancelled": 1, "done": 0,
                    })
                except OSError:
                    pass
        self._cleanup_temp()
        self.root.destroy()

    def _cleanup_temp(self):
        if self.snap_dir and os.path.isdir(self.snap_dir):
            shutil.rmtree(self.snap_dir, ignore_errors=True)
            self.snap_dir = None
        if self.media_dir and os.path.isdir(self.media_dir):
            shutil.rmtree(self.media_dir, ignore_errors=True)
            self.media_dir = None


def main():
    if len(sys.argv) < 3:
        print(
            "Usage: pythonw ppt_scan_gui.py <pptxPath> <scanId> "
            "[jsonPath] [statusPath] [cancelPath] [stdoutPath] [stderrPath]",
            file=sys.stderr,
        )
        sys.exit(1)

    pptx_path = sys.argv[1]
    scan_id = sys.argv[2]
    pptx_dir = os.path.dirname(os.path.abspath(pptx_path))
    json_path = sys.argv[3] if len(sys.argv) >= 4 else os.path.join(
        pptx_dir, f"_scan_{scan_id}.json")
    status_path = sys.argv[4] if len(sys.argv) >= 5 else ""
    cancel_path = sys.argv[5] if len(sys.argv) >= 6 else ""
    stdout_path = sys.argv[6] if len(sys.argv) >= 7 else ""
    stderr_path = sys.argv[7] if len(sys.argv) >= 8 else ""
    json_path = os.path.abspath(json_path)
    if status_path:
        status_path = os.path.abspath(status_path)
    if cancel_path:
        cancel_path = os.path.abspath(cancel_path)
    if stdout_path:
        stdout_path = os.path.abspath(stdout_path)
    if stderr_path:
        stderr_path = os.path.abspath(stderr_path)

    ScanGUI(pptx_path, scan_id, json_path, status_path, cancel_path,
            stdout_path, stderr_path)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # パースエラーはここに到達しないが、import エラーや起動時例外をキャプチャ
        import traceback
        # stderr_path が引数にあればそこに書く
        stderr_path = ""
        if len(sys.argv) >= 8:
            stderr_path = os.path.abspath(sys.argv[7])
        if stderr_path:
            os.makedirs(os.path.dirname(stderr_path) or ".", exist_ok=True)
            with open(stderr_path, "w", encoding="utf-8") as f:
                traceback.print_exc(file=f)
        traceback.print_exc()
        sys.exit(1)
