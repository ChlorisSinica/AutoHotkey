$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

if ($args.Count -ne 3) {
    Write-Error 'Usage: ppt_extract_media.ps1 <pptxPath> <mediaFile> <destPath>'
    exit 2
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$pptPath = [string]$args[0]
$mediaFile = [string]$args[1]
$destPath = [string]$args[2]

try {
    $mediaName = [System.IO.Path]::GetFileName(($mediaFile + '').Replace('/', '\'))
    if (-not $mediaName) {
        throw 'mediaFile is empty.'
    }
    $zipEntryName = 'ppt/media/' + $mediaName
    $destFullPath = [System.IO.Path]::GetFullPath($destPath)
    $destDir = [System.IO.Path]::GetDirectoryName($destFullPath)
    if ($destDir -and -not (Test-Path -LiteralPath $destDir -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $destDir -Force)
    }

    $zip = [System.IO.Compression.ZipFile]::OpenRead($pptPath)
    try {
        $entry = $zip.GetEntry($zipEntryName)
        if (-not $entry) {
            throw ('Embedded media not found: {0}' -f $mediaName)
        }

        $sourceStream = $entry.Open()
        $destStream = [System.IO.File]::Open($destFullPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            $sourceStream.CopyTo($destStream)
        } finally {
            $destStream.Dispose()
            $sourceStream.Dispose()
        }
    } finally {
        $zip.Dispose()
    }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

exit 0
