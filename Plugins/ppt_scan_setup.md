# PowerPoint Source Scan - Setup Guide

## Overview

`Ctrl+Alt+S` (in PowerPoint) launches a retro source scan that finds the
original files for images embedded in the presentation.  Three search backends
are tried in order:

1. **Everything** (fastest, recommended)
2. **Windows Desktop Search** (built-in, moderate speed)
3. **Directory scan** (fallback, slowest)

---

## 1. Everything (recommended)

[Everything](https://www.voidtools.com/) indexes the entire filesystem in
real-time.  The scan uses its CLI tool `es.exe` for instant file-size queries.

### Install

1. Download **Everything** from <https://www.voidtools.com/downloads/>
2. Install with default settings (run as service recommended)
3. Download **Everything Command-line Interface (ES)** from the same page
4. Place `es.exe` in one of:
   - `C:\Program Files\Everything\es.exe`
   - `C:\Program Files (x86)\Everything\es.exe`
   - Or any directory on `PATH`
5. Verify: open a terminal and run `es.exe --version`

### Verify indexing

```
es.exe size:=12345
```

If results appear instantly, Everything is working.

### Notes

- Everything must be **running** (service or app) during the scan
- First index build takes a few minutes; subsequent updates are instant
- Network drives can be added in Everything settings (Options > Indexes > Folders)

---

## 2. Windows Desktop Search (built-in fallback)

WDS is built into Windows and indexes common user folders by default.  No extra
setup is needed, but it may not index all locations.

### Check indexing scope

1. Open **Settings > Privacy & Security > Searching Windows**
2. Choose **Enhanced** to index the entire PC (recommended)
3. Or add specific folders under "Customize search locations"

### Limitations

- Slower than Everything (SQL query via ADODB)
- May not index external drives or network paths
- Index can lag behind file changes by minutes

---

## 3. Directory scan (final fallback)

If neither Everything nor WDS returns results, the scan walks these directories
recursively:

- pptx file's directory + parent
- `%USERPROFILE%\Desktop`
- `%USERPROFILE%\Downloads`
- `%USERPROFILE%\Pictures`
- `%USERPROFILE%\Documents`

Files outside these locations will not be found by the directory scan.
Install Everything for comprehensive coverage.

---

## Excluded paths

The following paths are automatically excluded from search results to prevent
false matches:

| Path | Reason |
|------|--------|
| `%TEMP%\ppt_scan_*` | Scan's own extracted media |
| `<pptBaseName>_sources\` | Previously exported sources |
| `%LOCALAPPDATA%\Google\DriveFS\` | Google Drive cache (volatile) |
| `%LOCALAPPDATA%\Microsoft\OneDrive\cache\` | OneDrive internal cache |
| `%TEMP%` | All temp files |

---

## Python dependencies

The scan GUI requires Python 3.8+ with tkinter (included with standard
Python installer).

### Optional: image preview

```
pip install Pillow
```

Without Pillow, the GUI still works but shows placeholder text instead of
image previews.

---

## Workflow

1. Open a saved `.pptx` in PowerPoint
2. Press `Ctrl+Alt+S` to start the retro source scan
3. The scan GUI window appears showing progress
4. After completion, review results in the table
5. Press `Ctrl+Alt+Q` to inspect a selected shape's source info
6. Press `Ctrl+Alt+E` to export sources to `<pptBaseName>_sources/`
7. Press `Ctrl+Alt+F1` to see the help shortcut list
