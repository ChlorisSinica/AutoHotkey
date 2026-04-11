"""ppt_scan.py — 遡及ソーススキャン (Python 委譲スクリプト)

Usage: python ppt_scan.py <pptxPath> <scanId> [jsonPath]

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
import zipfile
from pathlib import Path
from datetime import datetime
from urllib.parse import unquote
from xml.etree import ElementTree as ET

from pptx import Presentation
from pptx.enum.shapes import MSO_SHAPE_TYPE


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


def search_everything(es_exe, file_size):
    """Everything で指定サイズのファイルを検索。"""
    try:
        result = subprocess.run(
            [es_exe, f"size:={file_size}"],
            capture_output=True,
            text=True,
            timeout=30,
            encoding="utf-8",
            errors="replace",
        )
        candidates = [
            line.strip() for line in result.stdout.splitlines() if line.strip()
        ]
        return candidates
    except Exception:
        return []


def search_wds(file_size):
    """WDS (Windows Desktop Search) で指定サイズのファイルを検索。"""
    try:
        ps_cmd = (
            f'$conn = New-Object -ComObject ADODB.Connection; '
            f"$conn.Open('Provider=Search.CollatorDSO;Extended Properties=''Application=Windows'''); "
            f"$rs = $conn.Execute(\"SELECT System.ItemPathDisplay FROM SYSTEMINDEX WHERE System.Size = {file_size}\"); "
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
        )
        return [line.strip() for line in result.stdout.splitlines() if line.strip()]
    except Exception:
        return []


def search_directories(file_size, pptx_dir):
    """ディレクトリスキャンで指定サイズのファイルを検索。"""
    candidates = []
    user_profile = os.environ.get("USERPROFILE", "")
    dirs = [pptx_dir]
    parent = os.path.dirname(pptx_dir)
    if parent and parent != pptx_dir:
        dirs.append(parent)
    for d in [
        os.path.join(user_profile, "Desktop"),
        os.path.join(user_profile, "Downloads"),
        os.path.join(user_profile, "Pictures"),
        os.path.join(user_profile, "Documents"),
    ]:
        if os.path.isdir(d):
            dirs.append(d)

    for d in dirs:
        if not os.path.isdir(d):
            continue
        try:
            for root, _, files in os.walk(d):
                for fname in files:
                    fpath = os.path.join(root, fname)
                    try:
                        if os.path.getsize(fpath) == file_size:
                            candidates.append(fpath)
                    except OSError:
                        pass
        except OSError:
            pass
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
    best = max(matches, key=lambda p: os.path.getmtime(p), default=matches[0])
    return best


def resolve_source(media_path, es_exe, pptx_dir):
    """1つの内部メディアファイルに対してソースを検索。

    Returns: (source_path, search_backend) or (None, None)
    """
    file_size = os.path.getsize(media_path)
    internal_hash = md5_file(media_path)

    # Stage 1: Everything
    if es_exe:
        candidates = search_everything(es_exe, file_size)
        matches = [c for c in candidates if os.path.isfile(c) and md5_file(c) == internal_hash]
        if matches:
            return select_best_match(matches, pptx_dir), "everything"

    # Stage 2: WDS
    candidates = search_wds(file_size)
    matches = [c for c in candidates if os.path.isfile(c) and md5_file(c) == internal_hash]
    if matches:
        return select_best_match(matches, pptx_dir), "wds"

    # Stage 3: ディレクトリスキャン
    candidates = search_directories(file_size, pptx_dir)
    matches = [c for c in candidates if md5_file(c) == internal_hash]
    if matches:
        return select_best_match(matches, pptx_dir), "directory"

    return None, None


def main():
    if len(sys.argv) < 3:
        print("Usage: python ppt_scan.py <pptxPath> <scanId> [jsonPath]", file=sys.stderr)
        sys.exit(1)

    pptx_path = sys.argv[1]
    scan_id = sys.argv[2]
    pptx_dir = os.path.dirname(os.path.abspath(pptx_path))
    json_path = sys.argv[3] if len(sys.argv) >= 4 else os.path.join(pptx_dir, f"_scan_{scan_id}.json")
    json_path = os.path.abspath(json_path)

    if not os.path.isfile(pptx_path):
        print(f"ERROR: pptx not found: {pptx_path}", file=sys.stderr)
        sys.exit(1)

    print(f"=== ppt_scan.py ===")
    print(f"pptx: {pptx_path}")
    print(f"scanId: {scan_id}")
    print()

    # スナップショット作成
    snap_dir = tempfile.mkdtemp(prefix="ppt_scan_")
    snap_path = os.path.join(snap_dir, f"scan_{scan_id}.pptx")
    shutil.copy2(pptx_path, snap_path)
    print(f"snapshot: {snap_path}")

    try:
        # Everything CLI
        es_exe = find_es_exe()
        if es_exe:
            print(f"Everything: {es_exe}")
        else:
            print("Everything: not found (WDS fallback)")

        # メディア→シェイプ マッピング構築
        print("\n--- Building media-shape map ---")
        media_map, external_links = build_media_shape_map(snap_path)
        print(f"  internal media: {len(media_map)} files")
        print(f"  external links: {len(external_links)} shapes")

        # 内部メディア展開
        media_dir = os.path.join(snap_dir, "media")
        os.makedirs(media_dir, exist_ok=True)
        with zipfile.ZipFile(snap_path, "r") as zf:
            for name in zf.namelist():
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

        for media_file, info in media_map.items():
            count += 1
            media_path = os.path.join(media_dir, media_file)
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
                continue

            source_path, backend = resolve_source(media_path, es_exe, pptx_dir)
            if source_path:
                print(f"  [{count}/{total}] {media_file} -> MATCH ({backend}): {source_path}")
                matched_count += 1
            else:
                print(f"  [{count}/{total}] {media_file} -> UNRESOLVED")

            media_results.append({
                "media_file": media_file,
                "source_path": source_path,
                "search_backend": backend,
                "shapes": [
                    {"slide_index": s[0], "slide_id": s[1], "shape_id": s[2]}
                    for s in info["shapes"]
                ],
            })

        # 外部リンク
        for slide_idx, sld_id, shape_id, ext_path in external_links:
            count += 1
            print(f"  [{count}/{total}] EXTERNAL -> {ext_path}")
            media_results.append({
                "media_file": None,
                "source_path": ext_path,
                "search_backend": "external_link",
                "shapes": [
                    {"slide_index": slide_idx, "slide_id": sld_id, "shape_id": shape_id}
                ],
            })
            if os.path.isfile(ext_path):
                matched_count += 1

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

        print(f"\n=== Done ===")
        print(f"matched: {matched_count}/{total}")
        print(f"JSON: {json_path}")

    except Exception as e:
        print(f"\nERROR: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        # メディア展開先のみ削除。スナップショットは AHK 側で削除
        if os.path.isdir(media_dir):
            shutil.rmtree(media_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
