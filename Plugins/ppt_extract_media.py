"""Extract one embedded media file from a pptx package."""

import os
import sys
import zipfile


def main() -> int:
    if len(sys.argv) != 4:
        print("Usage: python ppt_extract_media.py <pptxPath> <mediaFile> <destPath>", file=sys.stderr)
        return 2

    pptx_path, media_file, dest_path = sys.argv[1:4]
    media_name = os.path.basename(media_file.replace("\\", "/"))
    zip_name = "ppt/media/" + media_name

    try:
        os.makedirs(os.path.dirname(dest_path), exist_ok=True)
        with zipfile.ZipFile(pptx_path, "r") as zf:
            with zf.open(zip_name, "r") as src, open(dest_path, "wb") as dst:
                dst.write(src.read())
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
