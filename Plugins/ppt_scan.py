"""ppt_scan.py — ソース探索スキャン (Python 委譲スクリプト)

Usage: python ppt_scan.py <pptxPath> <scanId> [jsonPath] [statusPath] [cancelPath] [stdoutPath] [stderrPath]

pptx 内の埋め込みメディアに対してソースファイルを検索し、
結果を _scan_<scanId>.json として出力する。
"""

import sys
import os
import json
import shutil
import hashlib
import subprocess
import tempfile
import time
import zipfile
from datetime import datetime
from urllib.parse import unquote
from xml.etree import ElementTree as ET


# === Configuration ===
ES_EXE_PATHS = [
    r"C:\Program Files\Everything\es.exe",
    r"C:\Program Files (x86)\Everything\es.exe",
]

NS = {
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "p": "http://schemas.openxmlformats.org/presentationml/2006/main",
    "rel": "http://schemas.openxmlformats.org/package/2006/relationships",
}

STATUS_KEY_ORDER = (
    "stage",
    "message",
    "backend",
    "current_index",
    "total_items",
    "files_scanned",
    "candidate_count",
    "matched_count",
    "cancel_requested",
    "cancelled",
    "done",
    "current_media",
    "snapshot_path",
)


class ScanCancelled(Exception):
    """ユーザー要求による中断。"""


def configure_output(stdout_path, stderr_path):
    """標準出力/標準エラーを UTF-8 ログファイルへ向ける。"""
    stdout_handle = None
    stderr_handle = None

    if stdout_path:
        stdout_dir = os.path.dirname(stdout_path)
        if stdout_dir:
            os.makedirs(stdout_dir, exist_ok=True)
        stdout_handle = open(stdout_path, "w", encoding="utf-8", buffering=1)
        sys.stdout = stdout_handle
    if stderr_path:
        stderr_dir = os.path.dirname(stderr_path)
        if stderr_dir:
            os.makedirs(stderr_dir, exist_ok=True)
        stderr_handle = open(stderr_path, "w", encoding="utf-8", buffering=1)
        sys.stderr = stderr_handle

    return stdout_handle, stderr_handle


def sanitize_status_value(value):
    """進捗ファイル向けに改行を潰した文字列へ正規化。"""
    if value is None:
        return ""
    return str(value).replace("\r", " ").replace("\n", " ")


def write_text_file(path, text, atomic=True):
    """UTF-8 テキストを書き込む。進捗ファイルは共有競合回避のため直接上書きする。"""
    if not path:
        return
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    if not atomic:
        last_error = None
        for _ in range(20):
            try:
                with open(path, "w", encoding="utf-8", newline="\n") as f:
                    f.write(text)
                return
            except PermissionError as exc:
                last_error = exc
                time.sleep(0.05)
        if last_error is not None:
            raise last_error
        return
    tmp_path = path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    last_error = None
    for _ in range(20):
        try:
            os.replace(tmp_path, path)
            return
        except PermissionError as exc:
            last_error = exc
            time.sleep(0.05)
    if last_error is not None:
        raise last_error


def write_status(status_path, state):
    """AHK 側が読みやすい key=value 形式で進捗を書き出す。"""
    if not status_path:
        return

    lines = []
    written = set()
    for key in STATUS_KEY_ORDER:
        if key in state:
            lines.append(f"{key}={sanitize_status_value(state.get(key, ''))}")
            written.add(key)
    for key in sorted(state):
        if key in written:
            continue
        lines.append(f"{key}={sanitize_status_value(state.get(key, ''))}")

    write_text_file(status_path, "\n".join(lines) + "\n", atomic=False)


def update_status(state, status_path, **changes):
    """状態を更新して進捗ファイルへ反映する。"""
    state.update(changes)
    write_status(status_path, state)


def is_cancel_requested(cancel_path):
    """キャンセルフラグの有無を返す。"""
    return bool(cancel_path) and os.path.isfile(cancel_path)


def raise_if_cancelled(cancel_path, state=None, status_path=""):
    """キャンセル要求が来ていれば例外を投げる。"""
    if not is_cancel_requested(cancel_path):
        return
    if state is not None and status_path:
        update_status(
            state,
            status_path,
            stage="キャンセル中",
            message="キャンセル要求を受け付けました。",
            cancel_requested=1,
        )
    raise ScanCancelled()


def find_es_exe():
    """Everything CLI (es.exe) のパスを探す。"""
    for p in ES_EXE_PATHS:
        if os.path.isfile(p):
            return p
    # PATH から探す
    for d in os.environ.get("PATH", "").split(os.pathsep):
        candidate = os.path.join(d, "es.exe")
        if os.path.isfile(candidate):
            return candidate
    return None


def md5_file(path):
    """ファイルの MD5 ハッシュを計算。"""
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def try_md5_file(path):
    """読めないファイルは None を返す。"""
    try:
        return md5_file(path)
    except OSError:
        return None


def safe_getmtime(path):
    """更新日時を安全に取得する。失敗時は最小値扱い。"""
    try:
        return os.path.getmtime(path)
    except OSError:
        return float("-inf")


def get_slide_order(snap_path):
    """presentation.xml から正規のスライド順序を取得。
    Returns: [(rId, sldId), ...] — 表示順。
    """
    with zipfile.ZipFile(snap_path, "r") as zf:
        pres_xml = ET.fromstring(zf.read("ppt/presentation.xml"))
    order = []
    for sld_id_elem in pres_xml.findall(".//p:sldIdLst/p:sldId", NS):
        r_id = sld_id_elem.get("{%s}id" % NS["r"])
        sld_id = int(sld_id_elem.get("id"))
        order.append((r_id, sld_id))
    return order


def get_pres_rels(snap_path):
    """ppt/_rels/presentation.xml.rels から rId → slide パート名のマップを取得。"""
    with zipfile.ZipFile(snap_path, "r") as zf:
        rels_xml = ET.fromstring(zf.read("ppt/_rels/presentation.xml.rels"))
    rels = {}
    for rel in rels_xml.findall("rel:Relationship", NS):
        rels[rel.get("Id")] = rel.get("Target")  # e.g. "slides/slide1.xml"
    return rels


def build_media_shape_map(snap_path):
    """pptx 内部の slide/shape → media ファイルのマッピングを構築。

    Returns:
        media_map: {media_filename: {"shapes": [(slide_index, slide_id, shape_id), ...], "external": False}}
        external_links: [(slide_index, slide_id, shape_id, external_path)]
    """
    slide_order = get_slide_order(snap_path)
    pres_rels = get_pres_rels(snap_path)

    media_map = {}  # media_filename → {shapes, external}
    external_links = []

    with zipfile.ZipFile(snap_path, "r") as zf:
        for slide_idx_0, (pres_rid, sld_id) in enumerate(slide_order):
            slide_index = slide_idx_0 + 1
            slide_target = pres_rels.get(pres_rid, "")
            if not slide_target:
                continue
            slide_part = "ppt/" + slide_target.lstrip("/")
            rels_part = slide_part.replace("slides/", "slides/_rels/") + ".rels"

            # slide rels: rId → (target, is_external)
            slide_rels = {}
            if rels_part in zf.namelist():
                rels_xml = ET.fromstring(zf.read(rels_part))
                for rel in rels_xml.findall("rel:Relationship", NS):
                    target = rel.get("Target", "")
                    mode = rel.get("TargetMode", "")
                    is_ext = mode.lower() == "external"
                    slide_rels[rel.get("Id")] = (target, is_ext)

            # slide XML: shape → rId
            if slide_part not in zf.namelist():
                continue
            slide_xml = ET.fromstring(zf.read(slide_part))

            for pic in slide_xml.iter("{%s}pic" % NS["p"]):
                cnv_pr = pic.find(".//p:nvPicPr/p:cNvPr", NS)
                if cnv_pr is None:
                    continue
                shape_id = int(cnv_pr.get("id", "0"))

                # r:link (実メディア) を優先、なければ r:embed
                blip = pic.find(".//a:blip", NS)
                if blip is None:
                    continue
                r_link = blip.get("{%s}link" % NS["r"])
                r_embed = blip.get("{%s}embed" % NS["r"])
                rid = r_link or r_embed

                if not rid or rid not in slide_rels:
                    continue
                target, is_ext = slide_rels[rid]

                if is_ext:
                    # 外部リンク: URI → Windows パス正規化
                    ext_path = normalize_uri(target)
                    external_links.append((slide_index, sld_id, shape_id, ext_path))
                else:
                    # 内部メディア
                    media_name = target.split("/")[-1]
                    if media_name not in media_map:
                        media_map[media_name] = {"shapes": [], "external": False}
                    media_map[media_name]["shapes"].append(
                        (slide_index, sld_id, shape_id)
                    )

    return media_map, external_links


def normalize_uri(uri):
    """file:/// URI や URL エンコードを Windows パスに正規化。"""
    if uri.startswith("file:///"):
        path = uri[8:]  # remove file:///
        path = unquote(path)
        path = path.replace("/", "\\")
        return path
    elif uri.startswith("file://"):
        path = uri[7:]
        path = unquote(path)
        path = path.replace("/", "\\")
        return path
    return unquote(uri)


def search_everything(es_exe, file_size, cancel_path="", exclude_dirs=None):
    """Everything で指定サイズのファイルを検索。"""
    try:
        raise_if_cancelled(cancel_path)
        # es.exe は複数引数を AND 検索として結合する
        args = [es_exe, f"size:={file_size}"]
        if exclude_dirs:
            for d in exclude_dirs:
                # !path: で配下を除外。末尾 \ は不要 (部分一致で効く)
                normalized = os.path.normpath(d)
                args.append(f"!path:{normalized}")
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=30,
            encoding="utf-8",
            errors="replace",
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0x08000000),
        )
        candidates = [
            line.strip() for line in result.stdout.splitlines() if line.strip()
        ]
        raise_if_cancelled(cancel_path)
        return candidates
    except ScanCancelled:
        raise
    except Exception:
        return []


def search_wds(file_size, cancel_path="", exclude_dirs=None):
    """WDS (Windows Desktop Search) で指定サイズのファイルを検索。"""
    try:
        raise_if_cancelled(cancel_path)
        where_clause = f"System.Size = {file_size}"
        if exclude_dirs:
            for d in exclude_dirs:
                # WDS SQL の LIKE: バックスラッシュはリテラル (エスケープ不要)
                escaped = os.path.normpath(d).replace("'", "''")
                where_clause += f" AND System.ItemPathDisplay NOT LIKE '{escaped}\\%'"
        ps_cmd = (
            f'$conn = New-Object -ComObject ADODB.Connection; '
            f"$conn.Open('Provider=Search.CollatorDSO;Extended Properties=''Application=Windows'''); "
            f'$rs = $conn.Execute("SELECT System.ItemPathDisplay FROM SYSTEMINDEX WHERE {where_clause}"); '
            f'while (-not $rs.EOF) {{ Write-Output $rs.Fields("System.ItemPathDisplay").Value; $rs.MoveNext() }}; '
            f'$rs.Close(); $conn.Close()'
        )
        result = subprocess.run(
            ["powershell", "-NoProfile", "-Command", ps_cmd],
            capture_output=True,
            text=True,
            timeout=30,
            encoding="utf-8",
            errors="replace",
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0x08000000),
        )
        raise_if_cancelled(cancel_path)
        return [line.strip() for line in result.stdout.splitlines() if line.strip()]
    except ScanCancelled:
        raise
    except Exception:
        return []


def search_directories(file_size, pptx_dir, status_path="", state=None, cancel_path="",
                       exclude_dirs=None):
    """ディレクトリスキャンで指定サイズのファイルを検索。"""
    candidates = []
    scanned = 0
    last_report_at = 0.0
    user_profile = os.environ.get("USERPROFILE", "")
    raw_dirs = [pptx_dir]
    parent = os.path.dirname(pptx_dir)
    if parent and parent != pptx_dir:
        raw_dirs.append(parent)
    for d in [
        os.path.join(user_profile, "Desktop"),
        os.path.join(user_profile, "Downloads"),
        os.path.join(user_profile, "Pictures"),
        os.path.join(user_profile, "Documents"),
    ]:
        if os.path.isdir(d):
            raw_dirs.append(d)

    dirs = []
    seen = set()
    for d in raw_dirs:
        norm = os.path.normcase(os.path.abspath(d))
        if norm in seen:
            continue
        seen.add(norm)
        dirs.append(d)

    for d in dirs:
        raise_if_cancelled(cancel_path, state, status_path)
        if not os.path.isdir(d):
            continue
        display_dir = os.path.basename(os.path.normpath(d)) or d
        try:
            for root, subdirs, files in os.walk(d):
                # 除外ディレクトリ配下を丸ごとスキップ (os.walk の subdirs を剪定)
                if exclude_dirs:
                    subdirs[:] = [
                        s for s in subdirs
                        if not _is_under_excluded_dir(os.path.join(root, s), exclude_dirs)
                    ]
                    if _is_under_excluded_dir(root, exclude_dirs):
                        continue
                raise_if_cancelled(cancel_path, state, status_path)
                for fname in files:
                    raise_if_cancelled(cancel_path, state, status_path)
                    fpath = os.path.join(root, fname)
                    scanned += 1
                    try:
                        if os.path.getsize(fpath) == file_size:
                            candidates.append(fpath)
                    except OSError:
                        pass
                    now = time.monotonic()
                    if state is not None and status_path and (
                        scanned == 1
                        or scanned % 200 == 0
                        or (now - last_report_at) >= 0.4
                    ):
                        update_status(
                            state,
                            status_path,
                            message=f"フォルダ探索中: {display_dir}",
                            files_scanned=scanned,
                            candidate_count=len(candidates),
                        )
                        last_report_at = now
        except OSError:
            pass
    if state is not None and status_path:
        update_status(
            state,
            status_path,
            files_scanned=scanned,
            candidate_count=len(candidates),
        )
    return candidates


def select_best_match(matches, pptx_dir):
    """複数マッチ時の優先順位選択。"""
    if len(matches) == 1:
        return matches[0]

    # Priority 1: pptx と同じディレクトリ
    for m in matches:
        if os.path.dirname(m) == pptx_dir:
            return m

    # Priority 2: pptx の親ディレクトリ配下
    parent = os.path.dirname(pptx_dir)
    for m in matches:
        if m.startswith(parent + os.sep):
            return m

    # Priority 3: 最終更新日が新しい方
    best = max(matches, key=safe_getmtime, default=matches[0])
    return best


def _get_volatile_cache_dirs():
    """揮発性キャッシュディレクトリの一覧を返す。

    クラウドストレージのローカルキャッシュなど、パスが一時的で
    キャッシュ消去により消える可能性があるディレクトリ。
    """
    dirs = []
    local_appdata = os.environ.get("LOCALAPPDATA", "")
    if local_appdata:
        # Google Drive for Desktop (DriveFS content_cache)
        drivefs = os.path.join(local_appdata, "Google", "DriveFS")
        if os.path.isdir(drivefs):
            dirs.append(drivefs)
        # OneDrive cache
        onedrive_cache = os.path.join(local_appdata, "Microsoft", "OneDrive")
        if os.path.isdir(onedrive_cache):
            # OneDrive のメインフォルダは除外しない (同期フォルダは正規パス)
            # キャッシュ用の内部ディレクトリだけ除外
            for subdir in ["cache", "logs"]:
                candidate = os.path.join(onedrive_cache, subdir)
                if os.path.isdir(candidate):
                    dirs.append(candidate)
    # Windows Temp (ppt_scan 以外の一時ファイルも除外)
    temp_dir = os.environ.get("TEMP", os.environ.get("TMP", ""))
    if temp_dir and os.path.isdir(temp_dir):
        dirs.append(temp_dir)
    return dirs


def _is_under_excluded_dir(path, exclude_dirs):
    """パスが除外ディレクトリ配下かどうかを判定する。"""
    if not exclude_dirs:
        return False
    norm = os.path.normcase(os.path.abspath(path))
    for d in exclude_dirs:
        prefix = os.path.normcase(os.path.abspath(d))
        if not prefix.endswith(os.sep):
            prefix += os.sep
        if norm.startswith(prefix) or norm == prefix.rstrip(os.sep):
            return True
    return False


def filter_hash_matches(candidates, internal_hash, cancel_path="", state=None, status_path="",
                        exclude_dirs=None):
    """候補群からハッシュ一致するファイルだけを残す。"""
    matches = []
    checked = 0
    total = len(candidates)
    unreadable_count = 0
    excluded_count = 0
    for candidate in candidates:
        raise_if_cancelled(cancel_path, state, status_path)
        checked += 1
        if _is_under_excluded_dir(candidate, exclude_dirs):
            excluded_count += 1
            continue
        if os.path.isfile(candidate):
            candidate_hash = try_md5_file(candidate)
            if candidate_hash is None:
                unreadable_count += 1
            elif candidate_hash == internal_hash:
                matches.append(candidate)
        if state is not None and status_path and (
            checked == total or checked % 25 == 0
        ):
            update_status(
                state,
                status_path,
                message=f"候補ハッシュを検証中 ({checked}/{total})"
                + (f" / 読めない候補 {unreadable_count}" if unreadable_count else "")
                + (f" / 除外 {excluded_count}" if excluded_count else ""),
                candidate_count=total,
            )
    return matches


def resolve_source(media_path, es_exe, pptx_dir, status_path="", state=None, cancel_path="",
                    exclude_dirs=None):
    """1つの内部メディアファイルに対してソースを検索。

    exclude_dirs: 候補から除外するディレクトリパスのリスト。
                  temp 展開先を自分自身のソースとして検出しないために使う。

    Returns: (source_path, search_backend) or (None, None)
    """
    raise_if_cancelled(cancel_path, state, status_path)
    file_size = os.path.getsize(media_path)
    internal_hash = md5_file(media_path)

    # Stage 1: Everything
    if es_exe:
        if state is not None and status_path:
            update_status(
                state,
                status_path,
                backend="Everything",
                message="Everything で候補を検索中",
                files_scanned=0,
                candidate_count=0,
            )
        candidates = search_everything(es_exe, file_size, cancel_path=cancel_path,
                                       exclude_dirs=exclude_dirs)
        matches = filter_hash_matches(
            candidates,
            internal_hash,
            cancel_path=cancel_path,
            state=state,
            status_path=status_path,
            exclude_dirs=exclude_dirs,
        )
        if state is not None and status_path:
            update_status(state, status_path, candidate_count=len(candidates))
        if matches:
            return select_best_match(matches, pptx_dir), "Everything"

    # Stage 2: WDS
    if state is not None and status_path:
        update_status(
            state,
            status_path,
            backend="Windows Search",
            message="Windows Search を照会中",
            files_scanned=0,
            candidate_count=0,
        )
    candidates = search_wds(file_size, cancel_path=cancel_path,
                            exclude_dirs=exclude_dirs)
    matches = filter_hash_matches(
        candidates,
        internal_hash,
        cancel_path=cancel_path,
        state=state,
        status_path=status_path,
        exclude_dirs=exclude_dirs,
    )
    if state is not None and status_path:
        update_status(state, status_path, candidate_count=len(candidates))
    if matches:
        return select_best_match(matches, pptx_dir), "Windows Search"

    # Stage 3: ディレクトリスキャン
    if state is not None and status_path:
        update_status(
            state,
            status_path,
            backend="Directory",
            message="フォルダを再帰探索中",
            files_scanned=0,
            candidate_count=0,
        )
    candidates = search_directories(
        file_size,
        pptx_dir,
        status_path=status_path,
        state=state,
        cancel_path=cancel_path,
        exclude_dirs=exclude_dirs,
    )
    matches = filter_hash_matches(
        candidates,
        internal_hash,
        cancel_path=cancel_path,
        state=state,
        status_path=status_path,
        exclude_dirs=exclude_dirs,
    )
    if state is not None and status_path:
        update_status(state, status_path, candidate_count=len(candidates))
    if matches:
        return select_best_match(matches, pptx_dir), "Directory"

    return None, None


def run_scan(pptx_path, scan_id, json_path, status_path="", cancel_path="",
             stdout_path="", stderr_path="", keep_media=False,
             on_map_built=None, on_media_resolved=None):
    """スキャンを実行し結果を返す。

    keep_media=True の場合、media_dir を削除せず呼び出し元に返す (GUI プレビュー用)。

    Callbacks (GUI 逐次更新用、すべてオプション):
        on_map_built(media_map, external_links, media_dir):
            メディアマップ構築＋展開完了時に呼ばれる。GUI 側で初期テーブルを構築できる。
        on_media_resolved(index, total, media_file, source_path, search_backend, shapes, *, source_exists):
            各メディアの解決完了時に呼ばれる。GUI 側で対応行を更新できる。
            source_exists: source_path の実体がディスク上に存在するかどうか。

    Returns:
        dict: {"result": dict|None, "media_dir": str|None,
               "snap_dir": str, "completed": bool}

    Raises:
        ScanCancelled: キャンセル要求を受けた場合
        FileNotFoundError: pptx が見つからない場合
        その他の例外: スキャン中のエラー
    """
    pptx_dir = os.path.dirname(os.path.abspath(pptx_path))

    stdout_handle, stderr_handle = configure_output(stdout_path, stderr_path)

    status = {
        "stage": "初期化中",
        "message": "スキャン準備中",
        "backend": "",
        "current_index": 0,
        "total_items": 0,
        "files_scanned": 0,
        "candidate_count": 0,
        "matched_count": 0,
        "cancel_requested": 1 if is_cancel_requested(cancel_path) else 0,
        "cancelled": 0,
        "done": 0,
        "current_media": "",
        "snapshot_path": "",
    }
    write_status(status_path, status)

    if not os.path.isfile(pptx_path):
        update_status(status, status_path, stage="エラー", message=f"pptx が見つかりません: {pptx_path}")
        print(f"ERROR: pptx not found: {pptx_path}", file=sys.stderr)
        raise FileNotFoundError(f"pptx not found: {pptx_path}")

    print(f"=== ppt_scan.py ===")
    print(f"pptx: {pptx_path}")
    print(f"scanId: {scan_id}")
    print()

    # 除外対象ディレクトリを構築
    pptx_base = os.path.splitext(os.path.basename(pptx_path))[0]
    sources_dir = os.path.join(pptx_dir, pptx_base + "_sources")
    volatile_cache_dirs = _get_volatile_cache_dirs()

    # スナップショット作成
    snap_dir = tempfile.mkdtemp(prefix="ppt_scan_")
    snap_path = os.path.join(snap_dir, f"scan_{scan_id}.pptx")
    shutil.copy2(pptx_path, snap_path)
    print(f"snapshot: {snap_path}")
    media_dir = None
    completed = False
    update_status(status, status_path, snapshot_path=snap_path)

    try:
        raise_if_cancelled(cancel_path, status, status_path)

        # Everything CLI
        es_exe = find_es_exe()
        if es_exe:
            print(f"Everything: {es_exe}")
        else:
            print("Everything: not found (WDS fallback)")

        # メディア→シェイプ マッピング構築
        update_status(
            status,
            status_path,
            stage="メディア解析中",
            message="PowerPoint 内の図形とメディア対応を解析しています。",
            backend="",
        )
        print("\n--- Building media-shape map ---")
        media_map, external_links = build_media_shape_map(snap_path)
        print(f"  internal media: {len(media_map)} files")
        print(f"  external links: {len(external_links)} shapes")

        # 内部メディア展開
        media_dir = os.path.join(snap_dir, "media")
        os.makedirs(media_dir, exist_ok=True)
        with zipfile.ZipFile(snap_path, "r") as zf:
            for name in zf.namelist():
                raise_if_cancelled(cancel_path, status, status_path)
                if name.startswith("ppt/media/"):
                    fname = name.split("/")[-1]
                    if fname:
                        with open(os.path.join(media_dir, fname), "wb") as f:
                            f.write(zf.read(name))

        # ソース解決
        print("\n--- Resolving sources ---")
        media_results = []
        total = len(media_map) + len(external_links)
        count = 0
        matched_count = 0
        update_status(
            status,
            status_path,
            stage="ソース探索中",
            message="ソース探索を開始します。",
            total_items=total,
        )

        if on_map_built:
            on_map_built(media_map, external_links, media_dir)

        for media_file, info in media_map.items():
            raise_if_cancelled(cancel_path, status, status_path)
            count += 1
            media_path = os.path.join(media_dir, media_file)
            update_status(
                status,
                status_path,
                stage="ソース探索中",
                message="ソース候補を探索しています。",
                current_index=count,
                current_media=media_file,
                backend="",
                files_scanned=0,
                candidate_count=0,
                matched_count=matched_count,
            )
            if not os.path.isfile(media_path):
                print(f"  [{count}/{total}] {media_file} -> SKIP (not extracted)")
                media_results.append({
                    "media_file": media_file,
                    "source_path": None,
                    "search_backend": None,
                    "shapes": [
                        {"slide_index": s[0], "slide_id": s[1], "shape_id": s[2]}
                        for s in info["shapes"]
                    ],
                })
                update_status(
                    status,
                    status_path,
                    message="メディア展開に失敗したためスキップしました。",
                )
                continue

            source_path, backend = resolve_source(
                media_path,
                es_exe,
                pptx_dir,
                status_path=status_path,
                state=status,
                cancel_path=cancel_path,
                exclude_dirs=[snap_dir, sources_dir] + volatile_cache_dirs,
            )
            if source_path:
                print(f"  [{count}/{total}] {media_file} -> MATCH ({backend}): {source_path}")
                matched_count += 1
                update_status(
                    status,
                    status_path,
                    message="一致するソースを検出しました。",
                    backend=backend,
                    matched_count=matched_count,
                )
            else:
                print(f"  [{count}/{total}] {media_file} -> UNRESOLVED")
                update_status(
                    status,
                    status_path,
                    message="一致するソースは見つかりませんでした。",
                    matched_count=matched_count,
                )

            shapes_list = [
                {"slide_index": s[0], "slide_id": s[1], "shape_id": s[2]}
                for s in info["shapes"]
            ]
            src_exists = bool(source_path) and os.path.isfile(source_path)
            media_results.append({
                "media_file": media_file,
                "source_path": source_path,
                "search_backend": backend,
                "source_exists": src_exists,
                "shapes": shapes_list,
            })
            if on_media_resolved:
                on_media_resolved(count, total, media_file, source_path, backend, shapes_list,
                                  source_exists=src_exists)

        # 外部リンク
        for slide_idx, sld_id, shape_id, ext_path in external_links:
            raise_if_cancelled(cancel_path, status, status_path)
            count += 1
            ext_label = os.path.basename(ext_path) or ext_path or "(external)"
            is_volatile_external = _is_under_excluded_dir(ext_path, volatile_cache_dirs)
            update_status(
                status,
                status_path,
                stage="ソース探索中",
                message="外部リンクを確認しています。",
                current_index=count,
                current_media=ext_label,
                backend="External Link",
                files_scanned=0,
                candidate_count=0,
                matched_count=matched_count,
            )
            if is_volatile_external:
                print(f"  [{count}/{total}] EXTERNAL -> VOLATILE (ignored): {ext_path}")
            else:
                print(f"  [{count}/{total}] EXTERNAL -> {ext_path}")
            ext_shapes = [
                {"slide_index": slide_idx, "slide_id": sld_id, "shape_id": shape_id}
            ]
            ext_exists = bool(ext_path) and os.path.isfile(ext_path) and not is_volatile_external
            resolved_ext_path = None if is_volatile_external else ext_path
            resolved_backend = None if is_volatile_external else "external_link"
            media_results.append({
                "media_file": None,
                "source_path": resolved_ext_path,
                "search_backend": resolved_backend,
                "source_exists": ext_exists,
                "shapes": ext_shapes,
            })
            if ext_exists:
                matched_count += 1
            if on_media_resolved:
                on_media_resolved(count, total, None, resolved_ext_path, resolved_backend, ext_shapes,
                                  source_exists=ext_exists)
            update_status(
                status,
                status_path,
                message=is_volatile_external
                    and "揮発パスの外部リンクを未解決として扱いました。"
                    or "外部リンク確認が完了しました。",
                matched_count=matched_count,
            )

        # JSON 出力 (atomic rename)
        result = {
            "pptx": os.path.abspath(pptx_path),
            "scan_id": scan_id,
            "snapshot_path": snap_path,
            "scanned_at": datetime.now().isoformat(),
            "media_results": media_results,
            "summary": {
                "total_media": len(media_map),
                "external_links": len(external_links),
                "matched": matched_count,
                "unresolved": total - matched_count,
            },
        }

        tmp_path = json_path + ".tmp"
        os.makedirs(os.path.dirname(json_path), exist_ok=True)
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        os.replace(tmp_path, json_path)
        completed = True
        update_status(
            status,
            status_path,
            stage="完了",
            message="JSON を生成しました。",
            current_index=total,
            current_media="",
            backend="",
            files_scanned=0,
            candidate_count=0,
            matched_count=matched_count,
            done=1,
        )

        print(f"\n=== Done ===")
        print(f"matched: {matched_count}/{total}")
        print(f"JSON: {json_path}")

        return {"result": result, "media_dir": media_dir,
                "snap_dir": snap_dir, "completed": True}

    except ScanCancelled:
        update_status(
            status,
            status_path,
            stage="キャンセル完了",
            message="スキャンを中断しました。",
            cancel_requested=1,
            cancelled=1,
        )
        print("\nCANCELLED", file=sys.stderr)
        raise
    except Exception as e:
        update_status(
            status,
            status_path,
            stage="エラー",
            message=str(e),
        )
        print(f"\nERROR: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        raise
    finally:
        if media_dir and os.path.isdir(media_dir) and not keep_media:
            shutil.rmtree(media_dir, ignore_errors=True)
        if not completed and os.path.isdir(snap_dir):
            shutil.rmtree(snap_dir, ignore_errors=True)
        if stdout_handle:
            stdout_handle.flush()
        if stderr_handle:
            stderr_handle.flush()


def main():
    if len(sys.argv) < 3:
        print(
            "Usage: python ppt_scan.py <pptxPath> <scanId> [jsonPath] [statusPath] [cancelPath] [stdoutPath] [stderrPath]",
            file=sys.stderr,
        )
        sys.exit(1)

    pptx_path = sys.argv[1]
    scan_id = sys.argv[2]
    pptx_dir = os.path.dirname(os.path.abspath(pptx_path))
    json_path = sys.argv[3] if len(sys.argv) >= 4 else os.path.join(pptx_dir, f"_scan_{scan_id}.json")
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

    try:
        run_scan(pptx_path, scan_id, json_path, status_path, cancel_path,
                 stdout_path, stderr_path, keep_media=False)
    except ScanCancelled:
        sys.exit(2)
    except Exception:
        sys.exit(1)


if __name__ == "__main__":
    main()
