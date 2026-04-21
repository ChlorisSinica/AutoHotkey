$Mode = if ($args.Count -ge 1 -and $args[0]) { [string]$args[0] } else { 'scan' }
$PptPath = if ($args.Count -ge 2) { [string]$args[1] } else { '' }
$ScanId = if ($args.Count -ge 3) { [string]$args[2] } else { '' }
$JsonPath = if ($args.Count -ge 4) { [string]$args[3] } else { '' }
$StatusPath = if ($args.Count -ge 5) { [string]$args[4] } else { '' }
$CancelPath = if ($args.Count -ge 6) { [string]$args[5] } else { '' }
$ManifestPath = if ($args.Count -ge 7) { [string]$args[6] } else { '' }
$StdoutPath = if ($args.Count -ge 8) { [string]$args[7] } else { '' }
$StderrPath = if ($args.Count -ge 9) { [string]$args[8] } else { '' }
$RescanPath = if ($args.Count -ge 10) { [string]$args[9] } else { '' }
$SyncPath = if ($args.Count -ge 11) { [string]$args[10] } else { '' }
if (-not ($args.Count -ge 1 -and $args[0])) { $Mode = 'view' }

if ($Mode -ne 'scan' -and $Mode -ne 'view') {
    throw "Mode must be 'scan' or 'view': $Mode"
}
if (-not $PptPath -or -not $ScanId -or -not $JsonPath -or -not $StatusPath -or -not $CancelPath) {
    throw 'Usage: ppt_scan_gui.ps1 <mode> <pptPath> <scanId> <jsonPath> <statusPath> <cancelPath> [manifestPath] [stdoutPath] [stderrPath] [rescanPath]'
}
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:Ns = @{
    a   = 'http://schemas.openxmlformats.org/drawingml/2006/main'
    r   = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    p   = 'http://schemas.openxmlformats.org/presentationml/2006/main'
    rel = 'http://schemas.openxmlformats.org/package/2006/relationships'
}

$script:StatusKeyOrder = @(
    'stage', 'message', 'backend', 'current_index', 'total_items',
    'files_scanned', 'candidate_count', 'matched_count', 'cancel_requested',
    'cancelled', 'done', 'current_media', 'snapshot_path', 'saved_time'
)

function Get-OpenXmlNamespaceMap {
    return @{
        a   = 'http://schemas.openxmlformats.org/drawingml/2006/main'
        r   = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
        p   = 'http://schemas.openxmlformats.org/presentationml/2006/main'
        rel = 'http://schemas.openxmlformats.org/package/2006/relationships'
    }
}

function Ensure-Directory {
    param([string]$Path)
    if ($Path -and -not (Test-Path -LiteralPath $Path -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $Path -Force)
    }
}

function Test-PathSafe {
    param(
        [string]$Path,
        [ValidateSet('Any', 'Leaf', 'Container')]
        [string]$PathType = 'Any'
    )
    if (-not $Path) { return $false }
    try {
        switch ($PathType) {
            'Leaf' { return (Test-Path -LiteralPath $Path -PathType Leaf) }
            'Container' { return (Test-Path -LiteralPath $Path -PathType Container) }
            default { return (Test-Path -LiteralPath $Path) }
        }
    } catch {
        return $false
    }
}

function Remove-DirectorySafe {
    param([string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-NormalizedPath {
    param([string]$Path)
    if (-not $Path) { return '' }
    return ([System.IO.Path]::GetFullPath($Path)).TrimEnd('\').ToLowerInvariant()
}

function Get-ParentPath {
    param([string]$Path)
    if (-not $Path) { return '' }
    return [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path))
}

function Test-ExcludedPath {
    param([string]$Path, [string[]]$ExcludeDirs)
    if (-not $Path -or -not $ExcludeDirs) { return $false }
    $norm = Get-NormalizedPath -Path $Path
    foreach ($dir in $ExcludeDirs) {
        if (-not $dir) { continue }
        $prefix = (Get-NormalizedPath -Path $dir).TrimEnd('\')
        if ($norm -eq $prefix -or $norm.StartsWith($prefix + '\')) { return $true }
    }
    return $false
}

function Test-FileIoRetryableException {
    param([System.Exception]$Exception)
    $ex = $Exception
    while ($ex) {
        if ($ex -is [System.IO.IOException] -or $ex -is [System.UnauthorizedAccessException]) {
            return $true
        }
        $ex = $ex.InnerException
    }
    return $false
}

function Test-StatusIoPath {
    param([string]$Path)
    if (-not $Path) { return $false }
    return (($Path + '').ToLowerInvariant().EndsWith('.status'))
}

function Get-StatusIoLogger {
    try { return $script:StatusIoLogger } catch { return $null }
}

function Write-Utf8TextFile {
    param([string]$Path, [string]$Text, [switch]$Atomic)
    $dir = Get-ParentPath -Path $Path
    Ensure-Directory -Path $dir
    $encoding = [System.Text.UTF8Encoding]::new($false)
    $maxAttempts = 6
    $isStatusIo = Test-StatusIoPath -Path $Path
    $logger = Get-StatusIoLogger
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $tmpPath = $null
        $backupPath = $null
        try {
            if ($Atomic) {
                $tmpPath = '{0}.tmp.{1}.{2}' -f $Path, $PID, $attempt
                [System.IO.File]::WriteAllText($tmpPath, $Text, $encoding)
                if ([System.IO.File]::Exists($Path)) {
                    $backupPath = '{0}.bak.{1}.{2}' -f $Path, $PID, $attempt
                    [System.IO.File]::Replace($tmpPath, $Path, $backupPath, $true)
                    if (Test-Path -LiteralPath $backupPath) {
                        Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
                    }
                }
                else {
                    [System.IO.File]::Move($tmpPath, $Path)
                }
                return
            }
            [System.IO.File]::WriteAllText($Path, $Text, $encoding)
            return
        }
        catch {
            if ($tmpPath -and (Test-Path -LiteralPath $tmpPath)) {
                Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
            }
            if ($backupPath -and (Test-Path -LiteralPath $backupPath)) {
                Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
            }
            $retryable = Test-FileIoRetryableException -Exception $_.Exception
            if ($isStatusIo -and $logger) {
                $detail = Format-ExceptionDetail -ExceptionRecord $_
                if (-not $retryable) {
                    Write-TraceLog -Logger $logger -Message ('status write non-retryable failure: attempt={0}/{1} path={2} detail={3}' -f $attempt, $maxAttempts, $Path, $detail) -Error
                } elseif ($attempt -ge $maxAttempts) {
                    Write-TraceLog -Logger $logger -Message ('status write retry exhausted: attempts={0} path={1} detail={2}' -f $maxAttempts, $Path, $detail) -Error
                } else {
                    Write-TraceLog -Logger $logger -Message ('status write retry: attempt={0}/{1} path={2} detail={3}' -f $attempt, $maxAttempts, $Path, $detail)
                }
            }
            if (-not $retryable -or $attempt -ge $maxAttempts) { throw }
            Start-Sleep -Milliseconds (25 * $attempt)
        }
    }
}

function Get-FileTextUtf8 {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return '' }
    $encoding = [System.Text.UTF8Encoding]::new($false)
    $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
    $maxAttempts = 6
    $isStatusIo = Test-StatusIoPath -Path $Path
    $logger = Get-StatusIoLogger
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $stream = $null
        $reader = $null
        try {
            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
            $reader = New-Object System.IO.StreamReader($stream, $encoding, $true)
            $stream = $null
            return $reader.ReadToEnd()
        } catch {
            $retryable = Test-FileIoRetryableException -Exception $_.Exception
            if ($isStatusIo -and $logger) {
                $detail = Format-ExceptionDetail -ExceptionRecord $_
                if (-not $retryable) {
                    Write-TraceLog -Logger $logger -Message ('status read non-retryable failure: attempt={0}/{1} path={2} detail={3}' -f $attempt, $maxAttempts, $Path, $detail) -Error
                } elseif ($attempt -ge $maxAttempts) {
                    Write-TraceLog -Logger $logger -Message ('status read retry exhausted: attempts={0} path={1} detail={2}' -f $maxAttempts, $Path, $detail) -Error
                } else {
                    Write-TraceLog -Logger $logger -Message ('status read retry: attempt={0}/{1} path={2} detail={3}' -f $attempt, $maxAttempts, $Path, $detail)
                }
            }
            if (-not $retryable -or $attempt -ge $maxAttempts) { throw }
            Start-Sleep -Milliseconds (20 * $attempt)
        } finally {
            if ($reader) { $reader.Dispose() }
            elseif ($stream) { $stream.Dispose() }
        }
    }
}

function New-Logger {
    param([string]$StdoutPath, [string]$StderrPath)
    [pscustomobject]@{ StdoutPath = $StdoutPath; StderrPath = $StderrPath }
}

function Write-TraceLog {
    param([pscustomobject]$Logger, [string]$Message, [switch]$Error)
    $path = if ($Error) { $Logger.StderrPath } else { $Logger.StdoutPath }
    if (-not $path) { return }
    $line = '[{0}] {1}{2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message, [Environment]::NewLine
    Ensure-Directory -Path (Get-ParentPath -Path $path)
    [System.IO.File]::AppendAllText($path, $line, [System.Text.UTF8Encoding]::new($false))
}

function Format-ExceptionDetail {
    param([object]$ExceptionRecord)
    if (-not $ExceptionRecord) { return '' }
    $parts = New-Object System.Collections.Generic.List[string]
    $message = ''
    try { $message = $ExceptionRecord.Exception.Message } catch {}
    if (-not $message) {
        try { $message = [string]$ExceptionRecord } catch {}
    }
    if ($message) { $parts.Add($message) | Out-Null }
    try {
        if ($ExceptionRecord.InvocationInfo -and $ExceptionRecord.InvocationInfo.PositionMessage) {
            $parts.Add($ExceptionRecord.InvocationInfo.PositionMessage.Trim()) | Out-Null
        }
    } catch {}
    try {
        if ($ExceptionRecord.ScriptStackTrace) {
            $parts.Add($ExceptionRecord.ScriptStackTrace.Trim()) | Out-Null
        }
    } catch {}
    return [string]::Join(' | ', $parts)
}

function New-StatusState {
    [ordered]@{
        stage = '初期化中'; message = '準備中'; backend = ''; current_index = 0; total_items = 0
        files_scanned = 0; candidate_count = 0; matched_count = 0; cancel_requested = 0
        cancelled = 0; done = 0; current_media = ''; snapshot_path = ''
    }
}

function ConvertTo-StatusText {
    param([hashtable]$State)
    $lines = New-Object System.Collections.Generic.List[string]
    $written = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $script:StatusKeyOrder) {
        if ($State.Contains($key)) {
            $value = ([string]$State[$key]).Replace("`r", ' ').Replace("`n", ' ')
            $lines.Add(('{0}={1}' -f $key, $value))
            [void]$written.Add($key)
        }
    }
    foreach ($key in ($State.Keys | Sort-Object)) {
        if ($written.Contains($key)) { continue }
        $value = ([string]$State[$key]).Replace("`r", ' ').Replace("`n", ' ')
        $lines.Add(('{0}={1}' -f $key, $value))
    }
    return [string]::Join([Environment]::NewLine, $lines) + [Environment]::NewLine
}

function Write-StatusFile {
    param([string]$StatusPath, [hashtable]$State)
    if ($StatusPath) { Write-Utf8TextFile -Path $StatusPath -Text (ConvertTo-StatusText -State $State) -Atomic }
}

function Update-StatusState {
    param([hashtable]$State, [string]$StatusPath, [hashtable]$Changes)
    foreach ($key in $Changes.Keys) { $State[$key] = $Changes[$key] }
    Write-StatusFile -StatusPath $StatusPath -State $State
}

function Test-CancelRequested {
    param([string]$CancelPath)
    return ($CancelPath -and (Test-Path -LiteralPath $CancelPath))
}

function Throw-IfCancelled {
    param([string]$CancelPath, [hashtable]$State, [string]$StatusPath)
    if (-not (Test-CancelRequested -CancelPath $CancelPath)) { return }
    if ($State -and $StatusPath) {
        Update-StatusState -State $State -StatusPath $StatusPath -Changes @{
            stage = 'キャンセル中'; message = 'キャンセル要求を受け付けました。'; cancel_requested = 1
        }
    }
    throw '__SCAN_CANCELLED__'
}

function Join-ProcessArguments {
    param([string[]]$Arguments)
    (($Arguments | Where-Object { $null -ne $_ } | ForEach-Object {
                if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
            }) -join ' ')
}

function Invoke-HiddenProcess {
    param([string]$FilePath, [string[]]$Arguments)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = Join-ProcessArguments -Arguments $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    [pscustomobject]@{ ExitCode = $proc.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

function Find-EverythingExe {
    $candidates = @(
        'C:\Program Files\Everything\es.exe',
        'C:\Program Files (x86)\Everything\es.exe'
    )
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA 'AutoHotkey\es\es.exe')
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    foreach ($dir in ($env:PATH -split ';')) {
        if (-not $dir) { continue }
        $candidate = Join-Path $dir 'es.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Get-FileMd5 {
    param([string]$Path)
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        try { return ([System.BitConverter]::ToString($md5.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
        finally { $md5.Dispose() }
    } finally { $stream.Dispose() }
}

function Try-GetFileMd5 {
    param([string]$Path)
    try { return Get-FileMd5 -Path $Path } catch { return $null }
}

function Get-SafeLastWriteTime {
    param([string]$Path)
    try { return (Get-Item -LiteralPath $Path -ErrorAction Stop).LastWriteTimeUtc } catch { return [datetime]::MinValue }
}

function Select-BestMatch {
    param([string[]]$Matches, [string]$PptDirectory)
    if (-not $Matches -or $Matches.Count -eq 0) { return $null }
    if ($Matches.Count -eq 1) { return $Matches[0] }
    $pptDirectory = [System.IO.Path]::GetFullPath($PptDirectory)
    $parentDirectory = Get-ParentPath -Path $pptDirectory
    foreach ($match in $Matches) {
        if ((Get-ParentPath -Path $match) -eq $pptDirectory) { return $match }
    }
    if ($parentDirectory) {
        foreach ($match in $Matches) {
            $dir = Get-ParentPath -Path $match
            if ($dir -and ($dir -eq $parentDirectory -or $dir.StartsWith($parentDirectory + '\', [System.StringComparison]::OrdinalIgnoreCase))) {
                return $match
            }
        }
    }
    return ($Matches | Sort-Object { Get-SafeLastWriteTime -Path $_ } -Descending | Select-Object -First 1)
}

function Normalize-UriPath {
    param([string]$UriText)
    if (-not $UriText) { return '' }
    if ($UriText.StartsWith('file:///', [System.StringComparison]::OrdinalIgnoreCase) -or
        $UriText.StartsWith('file://', [System.StringComparison]::OrdinalIgnoreCase)) {
        try { return [System.Uri]::UnescapeDataString(([System.Uri]$UriText).LocalPath) } catch {}
    }
    try { return [System.Uri]::UnescapeDataString($UriText) } catch { return $UriText }
}

function Save-PowerPointPresentation {
    param([string]$PptPath)
    if (-not $PptPath -or -not (Test-Path -LiteralPath $PptPath -PathType Leaf)) { return $false }
    $targetPath = [System.IO.Path]::GetFullPath($PptPath)
    $app = $null
    $presentation = $null
    try {
        $app = [System.Runtime.InteropServices.Marshal]::GetActiveObject('PowerPoint.Application')
    } catch {
        return $false
    }
    try {
        foreach ($candidate in $app.Presentations) {
            try {
                if ([System.IO.Path]::GetFullPath(($candidate.FullName + '')) -eq $targetPath) {
                    $presentation = $candidate
                    break
                }
            } catch {}
        }
        if (-not $presentation) { return $false }
        $presentation.Save()
        return $true
    } finally {
        if ($presentation) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($presentation) } catch {} }
        if ($app) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($app) } catch {} }
    }
}

function New-ScanSnapshot {
    param([string]$PptPath, [string]$ScanTempDir)
    if (-not $PptPath -or -not (Test-Path -LiteralPath $PptPath -PathType Leaf)) {
        throw ('pptx が見つかりません: {0}' -f $PptPath)
    }
    if (-not (Save-PowerPointPresentation -PptPath $PptPath)) {
        throw ('PowerPoint の保存に失敗しました: {0}' -f $PptPath)
    }
    $savedTime = (Get-Item -LiteralPath $PptPath -ErrorAction Stop).LastWriteTime.ToString('yyyyMMddHHmmss')
    Ensure-Directory -Path $ScanTempDir
    $snapshotPath = Join-Path $ScanTempDir ('scan_{0}.pptx' -f ([System.IO.Path]::GetRandomFileName() -replace '\.', ''))
    Copy-Item -LiteralPath $PptPath -Destination $snapshotPath -Force
    return [pscustomobject]@{
        SavedTime = $savedTime
        SnapshotPath = $snapshotPath
    }
}

function Get-PowerPointPresentationByPath {
    param([object]$App, [string]$PptPath)
    if (-not $App -or -not $PptPath) { return $null }
    $targetPath = [System.IO.Path]::GetFullPath($PptPath)
    foreach ($candidate in $App.Presentations) {
        try {
            if ([System.IO.Path]::GetFullPath(($candidate.FullName + '')) -eq $targetPath) {
                return $candidate
            }
        } catch {}
    }
    return $null
}

function Get-PowerPointSlideByRef {
    param([object]$Presentation, [object]$ShapeRef)
    if (-not $Presentation -or -not $ShapeRef) { return $null }
    $slideId = [int]($ShapeRef.slide_id + 0)
    $slideIndex = [int]($ShapeRef.slide_index + 0)
    if ($slideId -gt 0) {
        $slideCount = 0
        try { $slideCount = [int]$Presentation.Slides.Count } catch { $slideCount = 0 }
        for ($i = 1; $i -le $slideCount; $i++) {
            $candidate = $null
            try {
                $candidate = $Presentation.Slides.Item($i)
                if ([int]($candidate.SlideID + 0) -eq $slideId) {
                    $slide = $candidate
                    $candidate = $null
                    return $slide
                }
            } catch {
            } finally {
                if ($candidate) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($candidate) } catch {} }
            }
        }
    }
    if ($slideIndex -le 0) { return $null }
    try { return $Presentation.Slides.Item($slideIndex) } catch { return $null }
}

function Find-PowerPointShapeByRef {
    param([object]$Presentation, [object]$ShapeRef)
    if (-not $Presentation -or -not $ShapeRef) { return $null }
    $shapeId = [int]($ShapeRef.shape_id + 0)
    $shapeIndex = [int]($ShapeRef.shape_index + 0)
    if ($shapeId -le 0 -and $shapeIndex -le 0) { return $null }
    $slide = $null
    try {
        $slide = Get-PowerPointSlideByRef -Presentation $Presentation -ShapeRef $ShapeRef
        if (-not $slide) { return $null }
        if ($shapeId -gt 0) {
            $shapeCount = 0
            try { $shapeCount = [int]$slide.Shapes.Count } catch { $shapeCount = 0 }
            for ($i = 1; $i -le $shapeCount; $i++) {
                $candidate = $null
                try {
                    $candidate = $slide.Shapes.Item($i)
                    if ([int]($candidate.Id + 0) -eq $shapeId) {
                        $shape = $candidate
                        $candidate = $null
                        return $shape
                    }
                } catch {
                } finally {
                    if ($candidate) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($candidate) } catch {} }
                }
            }
        }
        if ($shapeIndex -gt 0) {
            try { return $slide.Shapes.Item($shapeIndex) } catch {}
        }
        return $null
    } finally {
        if ($slide) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($slide) } catch {} }
    }
}

function Get-ShapeRefIdentityKeys {
    param([object]$ShapeRef)
    if (-not $ShapeRef) { return @() }
    $keys = New-Object System.Collections.Generic.List[string]
    $slideId = [int]($ShapeRef.slide_id + 0)
    $shapeId = [int]($ShapeRef.shape_id + 0)
    $slideIndex = [int]($ShapeRef.slide_index + 0)
    $shapeIndex = [int]($ShapeRef.shape_index + 0)
    if ($slideId -gt 0 -and $shapeId -gt 0) {
        [void]$keys.Add(('id:{0}:{1}' -f $slideId, $shapeId))
    }
    if ($slideIndex -gt 0 -and $shapeIndex -gt 0) {
        [void]$keys.Add(('idx:{0}:{1}' -f $slideIndex, $shapeIndex))
    }
    if ($keys.Count -eq 0) {
        [void]$keys.Add(('ref:{0}:{1}:{2}:{3}' -f $slideId, $shapeId, $slideIndex, $shapeIndex))
    }
    return ,@($keys)
}

function Get-ShapeRefIdentityKey {
    param([object]$ShapeRef)
    $keys = @(Get-ShapeRefIdentityKeys -ShapeRef $ShapeRef)
    if ($keys.Count -gt 0) { return ($keys[0] + '') }
    return ''
}

function Get-ExistingMediaIdForShapeRefs {
    param([object[]]$ShapeRefs, [hashtable]$MediaIdByShapeKey)
    if (-not $ShapeRefs -or -not $MediaIdByShapeKey -or $MediaIdByShapeKey.Count -eq 0) { return '' }
    $counts = @{}
    $orderedMatches = New-Object System.Collections.Generic.List[string]
    foreach ($shapeRef in @($ShapeRefs)) {
        $mediaId = ''
        foreach ($shapeKey in @(Get-ShapeRefIdentityKeys -ShapeRef $shapeRef)) {
            if ($shapeKey -and $MediaIdByShapeKey.ContainsKey($shapeKey)) {
                $mediaId = ($MediaIdByShapeKey[$shapeKey] + '')
                if ($mediaId) { break }
            }
        }
        if (-not $mediaId) { continue }
        if (-not $counts.ContainsKey($mediaId)) {
            $counts[$mediaId] = 0
            [void]$orderedMatches.Add($mediaId)
        }
        $counts[$mediaId] = [int]$counts[$mediaId] + 1
    }
    if ($orderedMatches.Count -eq 0) { return '' }
    $bestMediaId = ''
    $bestCount = -1
    foreach ($mediaId in $orderedMatches) {
        $count = [int]$counts[$mediaId]
        if ($count -gt $bestCount) {
            $bestMediaId = $mediaId
            $bestCount = $count
        }
    }
    return $bestMediaId
}

function Get-PowerPointMediaIdMap {
    param([string]$PptPath, [pscustomobject]$Logger)
    $mediaIdByShapeKey = @{}
    if (-not $PptPath) { return $mediaIdByShapeKey }
    $app = $null
    $presentation = $null
    try {
        $app = [System.Runtime.InteropServices.Marshal]::GetActiveObject('PowerPoint.Application')
        $presentation = Get-PowerPointPresentationByPath -App $app -PptPath $PptPath
        if (-not $presentation) {
            Write-TraceLog -Logger $Logger -Message ('existing media-id map skipped: presentation not found for {0}' -f $PptPath)
            return $mediaIdByShapeKey
        }
        $slideCount = 0
        try { $slideCount = [int]$presentation.Slides.Count } catch { $slideCount = 0 }
        for ($slideIndex = 1; $slideIndex -le $slideCount; $slideIndex++) {
            $slide = $null
            try {
                $slide = $presentation.Slides.Item($slideIndex)
                $slideId = 0
                try { $slideId = [int]($slide.SlideID + 0) } catch { $slideId = 0 }
                $shapeCount = 0
                try { $shapeCount = [int]$slide.Shapes.Count } catch { $shapeCount = 0 }
                for ($shapeIndex = 1; $shapeIndex -le $shapeCount; $shapeIndex++) {
                    $shape = $null
                    try {
                        $shape = $slide.Shapes.Item($shapeIndex)
                        $mediaId = ''
                        try { $mediaId = ($shape.Tags('MEDIA_ID') + '') } catch {}
                        if (-not $mediaId) { continue }
                        $shapeId = 0
                        try { $shapeId = [int]($shape.Id + 0) } catch { $shapeId = 0 }
                        foreach ($shapeKey in @(Get-ShapeRefIdentityKeys -ShapeRef ([pscustomobject]@{
                                slide_id = $slideId
                                shape_id = $shapeId
                                slide_index = $slideIndex
                                shape_index = $shapeIndex
                            }))) {
                            if ($shapeKey -and -not $mediaIdByShapeKey.ContainsKey($shapeKey)) {
                                $mediaIdByShapeKey[$shapeKey] = $mediaId
                            }
                        }
                    } finally {
                        if ($shape) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shape) } catch {} }
                    }
                }
            } finally {
                if ($slide) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($slide) } catch {} }
            }
        }
        Write-TraceLog -Logger $Logger -Message ('existing media-id map built: {0} shapes' -f $mediaIdByShapeKey.Count)
        return $mediaIdByShapeKey
    } catch {
        Write-TraceLog -Logger $Logger -Message ('existing media-id map error: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_)) -Error
        return @{}
    } finally {
        if ($presentation) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($presentation) } catch {} }
        if ($app) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($app) } catch {} }
    }
}

function Get-MediaIdMapFromRows {
    param([object[]]$Rows)
    $mediaIdByShapeKey = @{}
    foreach ($row in @($Rows)) {
        $mediaId = ($row.MediaId + '')
        if (-not $mediaId -or -not $row.Shapes) { continue }
        foreach ($shapeRef in @($row.Shapes)) {
            foreach ($shapeKey in @(Get-ShapeRefIdentityKeys -ShapeRef $shapeRef)) {
                if ($shapeKey -and -not $mediaIdByShapeKey.ContainsKey($shapeKey)) {
                    $mediaIdByShapeKey[$shapeKey] = $mediaId
                }
            }
        }
    }
    return $mediaIdByShapeKey
}

function Get-ManifestMediaIdMap {
    param([string]$ManifestPath, [pscustomobject]$Logger)
    if (-not $ManifestPath -or -not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { return @{} }
    try {
        $rows = Load-ManifestData -ManifestPath $ManifestPath
        $mediaIdByShapeKey = Get-MediaIdMapFromRows -Rows @($rows)
        Write-TraceLog -Logger $Logger -Message ('manifest media-id map built: {0} shapes' -f $mediaIdByShapeKey.Count)
        return $mediaIdByShapeKey
    } catch {
        Write-TraceLog -Logger $Logger -Message ('manifest media-id map error: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_)) -Error
        return @{}
    }
}

function Set-PowerPointShapeSourceTags {
    param([object]$Shape, [string]$SourcePath, [string]$MediaId)
    if (-not $Shape -or -not $SourcePath -or -not $MediaId) { return }
    $srcFileName = [System.IO.Path]::GetFileName($SourcePath)
    $scanTime = Get-Date -Format 'yyyy/MM/dd HH:mm:ss'
    $insertedBy = '{0}@{1}' -f $env:USERNAME, $env:COMPUTERNAME
    foreach ($tagName in @('MEDIA_ID', 'SOURCE_PATH', 'SOURCE_NAME', 'EMBED_FILE', 'INSERT_DATE', 'INSERTED_BY', 'MATCH_METHOD')) {
        try { $Shape.Tags.Delete($tagName) } catch {}
    }
    $Shape.Tags.Add('MEDIA_ID', $MediaId)
    $Shape.Tags.Add('SOURCE_PATH', $SourcePath)
    $Shape.Tags.Add('SOURCE_NAME', $srcFileName)
    $Shape.Tags.Add('INSERT_DATE', $scanTime)
    $Shape.Tags.Add('INSERTED_BY', $insertedBy)
    $Shape.Tags.Add('MATCH_METHOD', 'RETRO_MANUAL')
    try {
        $altText = ($Shape.AlternativeText + '')
        if (-not $altText -or $altText.StartsWith('[source] ')) {
            $Shape.AlternativeText = '[source] ' + $SourcePath
        }
    } catch {}
}

function Get-PowerPointShapeSourceState {
    param([object]$Shape)
    if (-not $Shape) { return $null }
    $tags = [ordered]@{}
    foreach ($tagName in @('MEDIA_ID', 'SOURCE_PATH', 'SOURCE_NAME', 'EMBED_FILE', 'INSERT_DATE', 'INSERTED_BY', 'MATCH_METHOD')) {
        $value = ''
        try { $value = ($Shape.Tags($tagName) + '') } catch {}
        if ($value -ne '') { $tags[$tagName] = $value }
    }
    $alternativeText = ''
    try { $alternativeText = ($Shape.AlternativeText + '') } catch {}
    return [pscustomobject]@{
        Tags = $tags
        AlternativeText = $alternativeText
    }
}

function Restore-PowerPointShapeSourceState {
    param([object]$Shape, [object]$State)
    if (-not $Shape -or -not $State) { return }
    foreach ($tagName in @('MEDIA_ID', 'SOURCE_PATH', 'SOURCE_NAME', 'EMBED_FILE', 'INSERT_DATE', 'INSERTED_BY', 'MATCH_METHOD')) {
        try { $Shape.Tags.Delete($tagName) } catch {}
    }
    if ($State.Tags) {
        foreach ($entry in $State.Tags.GetEnumerator()) {
            if (($entry.Value + '') -ne '') {
                try { $Shape.Tags.Add(($entry.Key + ''), ($entry.Value + '')) } catch {}
            }
        }
    }
    try { $Shape.AlternativeText = ($State.AlternativeText + '') } catch {}
}

function Capture-ManualRowPowerPointState {
    param([string]$PptPath, [object]$Row, [pscustomobject]$Logger)
    if (-not $PptPath -or -not $Row -or -not $Row.Shapes) { return @() }
    $app = $null
    $presentation = $null
    $snapshots = New-Object System.Collections.Generic.List[object]
    try {
        $app = [System.Runtime.InteropServices.Marshal]::GetActiveObject('PowerPoint.Application')
        $presentation = Get-PowerPointPresentationByPath -App $app -PptPath $PptPath
        if (-not $presentation) { return @() }
        foreach ($shapeRef in @($Row.Shapes)) {
            $shape = Find-PowerPointShapeByRef -Presentation $presentation -ShapeRef $shapeRef
            if (-not $shape) { continue }
            try {
                $snapshots.Add([pscustomobject]@{
                        ShapeRef = $shapeRef
                        State = (Get-PowerPointShapeSourceState -Shape $shape)
                    })
            } finally {
                try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shape) } catch {}
            }
        }
        return @($snapshots)
    } catch {
        Write-TraceLog -Logger $Logger -Message ('manual state snapshot error: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_)) -Error
        return @()
    } finally {
        if ($presentation) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($presentation) } catch {} }
        if ($app) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($app) } catch {} }
    }
}

function Restore-ManualRowPowerPointState {
    param([string]$PptPath, [object[]]$Snapshots, [pscustomobject]$Logger)
    if (-not $PptPath -or -not $Snapshots -or $Snapshots.Count -eq 0) { return $true }
    $app = $null
    $presentation = $null
    $restoredCount = 0
    try {
        $app = [System.Runtime.InteropServices.Marshal]::GetActiveObject('PowerPoint.Application')
        $presentation = Get-PowerPointPresentationByPath -App $app -PptPath $PptPath
        if (-not $presentation) {
            Write-TraceLog -Logger $Logger -Message ('manual state restore skipped: presentation not found for {0}' -f $PptPath) -Error
            return $false
        }
        foreach ($snapshot in @($Snapshots)) {
            if (-not $snapshot.ShapeRef) { continue }
            $shape = Find-PowerPointShapeByRef -Presentation $presentation -ShapeRef $snapshot.ShapeRef
            if (-not $shape) { continue }
            try {
                Restore-PowerPointShapeSourceState -Shape $shape -State $snapshot.State
                $restoredCount++
            } finally {
                try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shape) } catch {}
            }
        }
        if ($restoredCount -le 0) {
            Write-TraceLog -Logger $Logger -Message 'manual state restore found no target shapes.' -Error
            return $false
        }
        try {
            $presentation.Save()
        } catch {
            Write-TraceLog -Logger $Logger -Message ('manual state restore save failed: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_)) -Error
            return $false
        }
        Write-TraceLog -Logger $Logger -Message ('manual state restore applied: shapes={0}' -f $restoredCount)
        return $true
    } catch {
        Write-TraceLog -Logger $Logger -Message ('manual state restore error: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_)) -Error
        return $false
    } finally {
        if ($presentation) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($presentation) } catch {} }
        if ($app) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($app) } catch {} }
    }
}

function Apply-ManualRowToPowerPoint {
    param([string]$PptPath, [object]$Row, [pscustomobject]$Logger)
    if (-not $PptPath -or -not $Row -or -not $Row.SourcePath -or -not $Row.MediaId -or -not $Row.Shapes) { return $false }
    $app = $null
    $presentation = $null
    $updatedCount = 0
    try {
        $app = [System.Runtime.InteropServices.Marshal]::GetActiveObject('PowerPoint.Application')
        $presentation = Get-PowerPointPresentationByPath -App $app -PptPath $PptPath
        if (-not $presentation) {
            Write-TraceLog -Logger $Logger -Message ('manual tag sync skipped: presentation not found for {0}' -f $PptPath) -Error
            return $false
        }
        foreach ($shapeRef in @($Row.Shapes)) {
            $shape = Find-PowerPointShapeByRef -Presentation $presentation -ShapeRef $shapeRef
            if (-not $shape) { continue }
            try {
                Set-PowerPointShapeSourceTags -Shape $shape -SourcePath ($Row.SourcePath + '') -MediaId ($Row.MediaId + '')
                $updatedCount++
            } finally {
                try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shape) } catch {}
            }
        }
        if ($updatedCount -le 0) {
            Write-TraceLog -Logger $Logger -Message ('manual tag sync found no target shapes for media_id={0}' -f ($Row.MediaId + '')) -Error
            return $false
        }
        try {
            $presentation.Save()
        } catch {
            Write-TraceLog -Logger $Logger -Message ('manual tag sync save failed: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_)) -Error
            return $false
        }
        Write-TraceLog -Logger $Logger -Message ('manual tag sync applied: media_id={0} shapes={1}' -f ($Row.MediaId + ''), $updatedCount)
        return $true
    } catch {
        Write-TraceLog -Logger $Logger -Message ('manual tag sync error: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_)) -Error
        return $false
    } finally {
        if ($presentation) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($presentation) } catch {} }
        if ($app) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($app) } catch {} }
    }
}

function Get-VolatileExcludeDirs {
    param([string]$PptPath, [string]$ScanTempDir)
    $dirs = New-Object System.Collections.Generic.List[string]
    if ($env:TEMP) { $dirs.Add($env:TEMP) }
    if ($env:LOCALAPPDATA) {
        $dirs.Add((Join-Path $env:LOCALAPPDATA 'Google\DriveFS'))
        $dirs.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\cache'))
    }
    $pptDir = Get-ParentPath -Path $PptPath
    $pptBase = [System.IO.Path]::GetFileNameWithoutExtension($PptPath)
    if ($pptDir -and $pptBase) { $dirs.Add((Join-Path $pptDir ($pptBase + '_sources'))) }
    if ($ScanTempDir) { $dirs.Add($ScanTempDir) }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($dir in $dirs) {
        if (-not $dir) { continue }
        try { $full = [System.IO.Path]::GetFullPath($dir) } catch { continue }
        if ($seen.Add($full)) { $out.Add($full) }
    }
    return ,$out.ToArray()
}

function Search-Everything {
    param([string]$EsExe, [Int64]$FileSize, [string[]]$ExcludeDirs, [string]$CancelPath)
    if (-not $EsExe -or -not (Test-Path -LiteralPath $EsExe)) { return @() }
    Throw-IfCancelled -CancelPath $CancelPath
    $args = New-Object System.Collections.Generic.List[string]
    $args.Add(('size:={0}' -f $FileSize))
    foreach ($dir in $ExcludeDirs) {
        if ($dir) { $args.Add(('!path:{0}' -f [System.IO.Path]::GetFullPath($dir))) }
    }
    try {
        $result = Invoke-HiddenProcess -FilePath $EsExe -Arguments $args.ToArray()
        return ,($result.StdOut -split "`r?`n" | Where-Object { $_ -and $_.Trim() -ne '' })
    } catch {
        return @()
    }
}

function Search-WindowsSearch {
    param([Int64]$FileSize, [string[]]$ExcludeDirs, [string]$CancelPath)
    Throw-IfCancelled -CancelPath $CancelPath
    $where = 'System.Size = {0}' -f $FileSize
    foreach ($dir in $ExcludeDirs) {
        if (-not $dir) { continue }
        $escaped = ([System.IO.Path]::GetFullPath($dir)).Replace("'", "''")
        $where += " AND System.ItemPathDisplay NOT LIKE '$escaped\\%'"
        $where += " AND System.ItemPathDisplay <> '$escaped'"
    }
    $conn = $null
    $rs = $null
    $items = New-Object System.Collections.Generic.List[string]
    try {
        $conn = New-Object -ComObject ADODB.Connection
        $conn.Open("Provider=Search.CollatorDSO;Extended Properties='Application=Windows'")
        $rs = $conn.Execute("SELECT System.ItemPathDisplay FROM SYSTEMINDEX WHERE $where")
        while (-not $rs.EOF) {
            Throw-IfCancelled -CancelPath $CancelPath
            $path = [string]$rs.Fields('System.ItemPathDisplay').Value
            if ($path) { $items.Add($path) }
            $rs.MoveNext()
        }
    } catch {
        return @()
    } finally {
        if ($rs) { try { $rs.Close() } catch {} }
        if ($conn) { try { $conn.Close() } catch {} }
    }
    return ,$items.ToArray()
}

function Search-Directories {
    param([Int64]$FileSize, [string]$PptDirectory, [string[]]$ExcludeDirs, [string]$CancelPath, [hashtable]$StatusState, [string]$StatusPath)
    $results = New-Object System.Collections.Generic.List[string]
    $roots = New-Object System.Collections.Generic.List[string]
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($root in @(
            $PptDirectory,
            (Get-ParentPath -Path $PptDirectory),
            (Join-Path $env:USERPROFILE 'Desktop'),
            (Join-Path $env:USERPROFILE 'Downloads'),
            (Join-Path $env:USERPROFILE 'Pictures'),
            (Join-Path $env:USERPROFILE 'Documents')
        )) {
        if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $full = [System.IO.Path]::GetFullPath($root)
        if ($seen.Add($full)) { $roots.Add($full) }
    }
    $filesScanned = 0
    $lastReport = [datetime]::MinValue
    foreach ($root in $roots) {
        $stack = New-Object System.Collections.Stack
        $stack.Push($root)
        while ($stack.Count -gt 0) {
            $currentDir = [string]$stack.Pop()
            if (Test-ExcludedPath -Path $currentDir -ExcludeDirs $ExcludeDirs) { continue }
            Throw-IfCancelled -CancelPath $CancelPath -State $StatusState -StatusPath $StatusPath
            try { $subDirs = [System.IO.Directory]::GetDirectories($currentDir) } catch { $subDirs = @() }
            foreach ($subDir in $subDirs) {
                if (-not (Test-ExcludedPath -Path $subDir -ExcludeDirs $ExcludeDirs)) { $stack.Push($subDir) }
            }
            try { $files = [System.IO.Directory]::GetFiles($currentDir) } catch { $files = @() }
            foreach ($file in $files) {
                Throw-IfCancelled -CancelPath $CancelPath -State $StatusState -StatusPath $StatusPath
                $filesScanned++
                try {
                    $fi = [System.IO.FileInfo]::new($file)
                    if ($fi.Length -eq $FileSize) { $results.Add($fi.FullName) }
                } catch {}
                $now = Get-Date
                if ($StatusState -and $StatusPath -and (($filesScanned -eq 1) -or ($filesScanned % 200 -eq 0) -or (($now - $lastReport).TotalMilliseconds -ge 400))) {
                    Update-StatusState -State $StatusState -StatusPath $StatusPath -Changes @{
                        message = ('フォルダ探索中: {0}' -f ([System.IO.Path]::GetFileName($root)))
                        files_scanned = $filesScanned
                        candidate_count = $results.Count
                    }
                    $lastReport = $now
                }
            }
        }
    }
    if ($StatusState -and $StatusPath) {
        Update-StatusState -State $StatusState -StatusPath $StatusPath -Changes @{ files_scanned = $filesScanned; candidate_count = $results.Count }
    }
    return ,$results.ToArray()
}

function Filter-HashMatches {
    param([string[]]$Candidates, [string]$InternalHash, [string[]]$ExcludeDirs, [string]$CancelPath, [hashtable]$StatusState, [string]$StatusPath)
    $matches = New-Object System.Collections.Generic.List[string]
    $checked = 0
    $total = if ($Candidates) { $Candidates.Count } else { 0 }
    foreach ($candidate in $Candidates) {
        Throw-IfCancelled -CancelPath $CancelPath -State $StatusState -StatusPath $StatusPath
        $checked++
        if (Test-ExcludedPath -Path $candidate -ExcludeDirs $ExcludeDirs) { continue }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $hash = Try-GetFileMd5 -Path $candidate
        if ($hash -and $hash -eq $InternalHash) { $matches.Add($candidate) }
        if ($StatusState -and $StatusPath -and (($checked -eq $total) -or ($checked % 25 -eq 0))) {
            Update-StatusState -State $StatusState -StatusPath $StatusPath -Changes @{
                message = ('候補ハッシュを検証中 ({0}/{1})' -f $checked, $total)
                candidate_count = $total
            }
        }
    }
    return ,$matches.ToArray()
}

function Resolve-Source {
    param([string]$MediaPath, [string]$PptDirectory, [string]$EsExe, [string[]]$ExcludeDirs, [string]$CancelPath, [hashtable]$StatusState, [string]$StatusPath)
    Throw-IfCancelled -CancelPath $CancelPath -State $StatusState -StatusPath $StatusPath
    $fileSize = (Get-Item -LiteralPath $MediaPath).Length
    $internalHash = Get-FileMd5 -Path $MediaPath
    if ($EsExe) {
        Update-StatusState -State $StatusState -StatusPath $StatusPath -Changes @{ backend = 'Everything'; message = 'Everything で候補を検索中'; files_scanned = 0; candidate_count = 0 }
        $candidates = Search-Everything -EsExe $EsExe -FileSize $fileSize -ExcludeDirs $ExcludeDirs -CancelPath $CancelPath
        $matches = Filter-HashMatches -Candidates $candidates -InternalHash $internalHash -ExcludeDirs $ExcludeDirs -CancelPath $CancelPath -StatusState $StatusState -StatusPath $StatusPath
        Update-StatusState -State $StatusState -StatusPath $StatusPath -Changes @{ candidate_count = $candidates.Count }
        if ($matches.Count -gt 0) { return [pscustomobject]@{ SourcePath = (Select-BestMatch -Matches $matches -PptDirectory $PptDirectory); Backend = 'Everything' } }
    }
    Update-StatusState -State $StatusState -StatusPath $StatusPath -Changes @{ backend = 'Windows Search'; message = 'Windows Search を照会中'; files_scanned = 0; candidate_count = 0 }
    $wdsCandidates = Search-WindowsSearch -FileSize $fileSize -ExcludeDirs $ExcludeDirs -CancelPath $CancelPath
    $wdsMatches = Filter-HashMatches -Candidates $wdsCandidates -InternalHash $internalHash -ExcludeDirs $ExcludeDirs -CancelPath $CancelPath -StatusState $StatusState -StatusPath $StatusPath
    Update-StatusState -State $StatusState -StatusPath $StatusPath -Changes @{ candidate_count = $wdsCandidates.Count }
    if ($wdsMatches.Count -gt 0) { return [pscustomobject]@{ SourcePath = (Select-BestMatch -Matches $wdsMatches -PptDirectory $PptDirectory); Backend = 'Windows Search' } }
    Update-StatusState -State $StatusState -StatusPath $StatusPath -Changes @{ backend = 'Directory'; message = 'フォルダを再帰探索中'; files_scanned = 0; candidate_count = 0 }
    $dirCandidates = Search-Directories -FileSize $fileSize -PptDirectory $PptDirectory -ExcludeDirs $ExcludeDirs -CancelPath $CancelPath -StatusState $StatusState -StatusPath $StatusPath
    $dirMatches = Filter-HashMatches -Candidates $dirCandidates -InternalHash $internalHash -ExcludeDirs $ExcludeDirs -CancelPath $CancelPath -StatusState $StatusState -StatusPath $StatusPath
    Update-StatusState -State $StatusState -StatusPath $StatusPath -Changes @{ candidate_count = $dirCandidates.Count }
    if ($dirMatches.Count -gt 0) { return [pscustomobject]@{ SourcePath = (Select-BestMatch -Matches $dirMatches -PptDirectory $PptDirectory); Backend = 'Directory' } }
    return [pscustomobject]@{ SourcePath = $null; Backend = $null }
}

function Get-ZipEntryText {
    param([System.IO.Compression.ZipArchive]$Zip, [string]$EntryName)
    $entry = $Zip.GetEntry($EntryName)
    if (-not $entry -and $EntryName) { $entry = $Zip.GetEntry($EntryName.Replace('/', '\')) }
    if (-not $entry -and $EntryName) { $entry = $Zip.GetEntry($EntryName.Replace('\', '/')) }
    if (-not $entry) { return $null }
    $stream = $entry.Open()
    $reader = [System.IO.StreamReader]::new($stream, [System.Text.UTF8Encoding]::new($false), $true)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose(); $stream.Dispose() }
}

function Copy-ZipEntryToFile {
    param([System.IO.Compression.ZipArchive]$Zip, [string]$EntryName, [string]$DestinationPath)
    $entry = $Zip.GetEntry($EntryName)
    if (-not $entry -and $EntryName) { $entry = $Zip.GetEntry($EntryName.Replace('/', '\')) }
    if (-not $entry -and $EntryName) { $entry = $Zip.GetEntry($EntryName.Replace('\', '/')) }
    if (-not $entry) { return $false }
    Ensure-Directory -Path (Get-ParentPath -Path $DestinationPath)
    $inStream = $entry.Open()
    $outStream = [System.IO.File]::Open($DestinationPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try { $inStream.CopyTo($outStream) } finally { $outStream.Dispose(); $inStream.Dispose() }
    return $true
}

function New-NamespaceManager {
    param([xml]$Xml)
    $nsMap = Get-OpenXmlNamespaceMap
    $nameTable = $null
    if ($Xml -and $Xml.NameTable) {
        $nameTable = $Xml.NameTable
    } elseif ($Xml -and $Xml.DocumentElement -and $Xml.DocumentElement.OwnerDocument -and $Xml.DocumentElement.OwnerDocument.NameTable) {
        $nameTable = $Xml.DocumentElement.OwnerDocument.NameTable
    }
    if (-not $nameTable) {
        $fallbackDoc = [System.Xml.XmlDocument]::new()
        $nameTable = $fallbackDoc.NameTable
    }
    $nsmgr = [System.Xml.XmlNamespaceManager]::new($nameTable)
    foreach ($key in $nsMap.Keys) { $nsmgr.AddNamespace($key, $nsMap[$key]) }
    return $nsmgr
}

function Select-XmlNodes {
    param(
        [System.Xml.XmlNode]$Node,
        [string]$XPath,
        [object]$NamespaceManager
    )
    if (-not $Node) { return @() }
    if ($NamespaceManager -is [array]) {
        $NamespaceManager = @($NamespaceManager | Where-Object { $_ -is [System.Xml.XmlNamespaceManager] })[0]
    }
    return $Node.SelectNodes($XPath, [System.Xml.XmlNamespaceManager]$NamespaceManager)
}

function Select-XmlNode {
    param(
        [System.Xml.XmlNode]$Node,
        [string]$XPath,
        [object]$NamespaceManager
    )
    if (-not $Node) { return $null }
    if ($NamespaceManager -is [array]) {
        $NamespaceManager = @($NamespaceManager | Where-Object { $_ -is [System.Xml.XmlNamespaceManager] })[0]
    }
    return $Node.SelectSingleNode($XPath, [System.Xml.XmlNamespaceManager]$NamespaceManager)
}

function Build-MediaShapeMap {
    param([string]$SnapshotPath)
    $nsMap = Get-OpenXmlNamespaceMap
    $zip = [System.IO.Compression.ZipFile]::OpenRead($SnapshotPath)
    try {
        [xml]$presentationXml = Get-ZipEntryText -Zip $zip -EntryName 'ppt/presentation.xml'
        [xml]$presentationRelsXml = Get-ZipEntryText -Zip $zip -EntryName 'ppt/_rels/presentation.xml.rels'
        $slideOrder = New-Object System.Collections.Generic.List[object]
        foreach ($node in @($presentationXml.GetElementsByTagName('sldId', $nsMap.p))) {
            $slideOrder.Add([pscustomobject]@{
                    RelationshipId = $node.GetAttribute('id', $nsMap.r)
                    SlideId = [int]$node.GetAttribute('id')
                })
        }
        $presentationRels = @{}
        foreach ($node in @($presentationRelsXml.GetElementsByTagName('Relationship', $nsMap.rel))) { $presentationRels[$node.Id] = $node.Target }
        $mediaMap = [ordered]@{}
        $externalLinks = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt $slideOrder.Count; $i++) {
            $pair = $slideOrder[$i]
            $slideTarget = $presentationRels[$pair.RelationshipId]
            if (-not $slideTarget) { continue }
            $slidePart = 'ppt/' + $slideTarget.TrimStart('/')
            $relsPart = ($slidePart -replace 'slides/', 'slides/_rels/') + '.rels'
            $slideRelMap = @{}
            [xml]$slideRelsXml = Get-ZipEntryText -Zip $zip -EntryName $relsPart
            if ($slideRelsXml) {
                foreach ($relNode in @($slideRelsXml.GetElementsByTagName('Relationship', $nsMap.rel))) {
                    $targetMode = ''
                    if ($relNode -and $relNode.Attributes) {
                        $targetModeNode = $relNode.Attributes.GetNamedItem('TargetMode')
                        if ($targetModeNode) {
                            $targetMode = ($targetModeNode.Value + '')
                        }
                    }
                    $slideRelMap[$relNode.Id] = [pscustomobject]@{ Target = $relNode.Target; IsExternal = ($targetMode -eq 'External') }
                }
            }
            [xml]$slideXml = Get-ZipEntryText -Zip $zip -EntryName $slidePart
            if (-not $slideXml) { continue }
            $spTree = @($slideXml.GetElementsByTagName('spTree', $nsMap.p))[0]
            if (-not $spTree) { continue }
            $shapeIndex = 0
            foreach ($shapeNode in @($spTree.ChildNodes)) {
                if ($shapeNode.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
                if ($shapeNode.NamespaceURI -ne $nsMap.p) { continue }
                if ($shapeNode.LocalName -notin @('sp', 'pic', 'graphicFrame', 'cxnSp', 'grpSp', 'contentPart')) { continue }
                $shapeIndex++
                if ($shapeNode.LocalName -ne 'pic') { continue }
                $cnvPr = @($shapeNode.GetElementsByTagName('cNvPr', $nsMap.p))[0]
                $blip = @($shapeNode.GetElementsByTagName('blip', $nsMap.a))[0]
                if (-not $cnvPr -or -not $blip) { continue }
                $shapeId = [int]$cnvPr.GetAttribute('id')
                $relId = $blip.GetAttribute('link', $nsMap.r)
                if (-not $relId) { $relId = $blip.GetAttribute('embed', $nsMap.r) }
                if (-not $relId -or -not $slideRelMap.ContainsKey($relId)) { continue }
                $rel = $slideRelMap[$relId]
                if ($rel.IsExternal) {
                    $externalLinks.Add([pscustomobject]@{
                            SlideIndex = $i + 1; SlideId = [int]$pair.SlideId; ShapeId = $shapeId; ShapeIndex = $shapeIndex; ExternalPath = Normalize-UriPath -UriText $rel.Target
                        })
                    continue
                }
                $mediaName = [System.IO.Path]::GetFileName(($rel.Target -replace '/', '\'))
                if (-not $mediaMap.Contains($mediaName)) {
                    $mediaMap[$mediaName] = [ordered]@{ shapes = New-Object System.Collections.Generic.List[object] }
                }
                $mediaMap[$mediaName].shapes.Add([pscustomobject]@{
                        slide_index = $i + 1
                        slide_id = [int]$pair.SlideId
                        shape_id = $shapeId
                        shape_index = $shapeIndex
                    })
            }
        }
        return [pscustomobject]@{ MediaMap = $mediaMap; ExternalLinks = $externalLinks.ToArray() }
    } finally {
        $zip.Dispose()
    }
}

function Export-ScanJson {
    param([string]$JsonPath, [string]$PptPath, [string]$ScanId, [string]$SnapshotPath, [object[]]$MediaResults)
    $internalCount = 0
    $externalCount = 0
    $matchedCount = 0
    foreach ($row in $MediaResults) {
        if ($row.media_file) { $internalCount++ } else { $externalCount++ }
        if ($row.source_path) { $matchedCount++ }
    }
    $result = [pscustomobject]([ordered]@{
            pptx = [System.IO.Path]::GetFullPath($PptPath)
            scan_id = [string]$ScanId
            snapshot_path = $SnapshotPath
            scanned_at = (Get-Date).ToString('s')
            media_results = $MediaResults
            summary = [pscustomobject]([ordered]@{
                    total_media = $internalCount
                    external_links = $externalCount
                    matched = $matchedCount
                    unresolved = ($MediaResults.Count - $matchedCount)
                })
        })
    Write-Utf8TextFile -Path $JsonPath -Text ($result | ConvertTo-Json -Depth 10) -Atomic
    return $result
}

function New-MediaId {
    param([int]$Counter)
    return ('{0}-{1:000000}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Counter)
}

function New-StableLegacyMediaId {
    param([string]$Seed)
    if (-not $Seed) { $Seed = 'legacy' }
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Seed)
    $hash = [System.Security.Cryptography.SHA1]::Create()
    try {
        $digest = $hash.ComputeHash($bytes)
    } finally {
        $hash.Dispose()
    }
    $hex = ([System.BitConverter]::ToString($digest) -replace '-', '').ToLowerInvariant()
    return 'legacy-' + $hex.Substring(0, 12)
}

function Get-MediaDisplayLabel {
    param([string]$MediaFile)
    if (-not $MediaFile) { return '(external)' }
    if ($MediaFile -match '^(?i:image)(\d+)(\.[^.]+)?$') { return ('img{0}' -f $matches[1]) }
    if ($MediaFile -match '^(?i:media)(\d+)(\.[^.]+)?$') { return ('media{0}' -f $matches[1]) }
    if ($MediaFile -match '^(?i:oleObject)(\d+)(\.[^.]+)?$') { return ('ole{0}' -f $matches[1]) }
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($MediaFile)
    if ($stem) { return $stem }
    return $MediaFile
}

function Test-EmbeddedMediaAutoTrackable {
    param([string]$MediaFile, [bool]$HasExistingTracking = $false)
    if ($HasExistingTracking) { return $true }
    if (-not $MediaFile) { return $true }
    $ext = ([System.IO.Path]::GetExtension($MediaFile) + '').TrimStart('.').ToLowerInvariant()
    if ($ext -in @('emf', 'wmf')) {
        return $false
    }
    return $true
}

function Get-LocalIdentityTag {
    return ('{0}@{1}' -f $env:USERNAME, $env:COMPUTERNAME)
}

function Get-RowFallbackMatchMethod {
    param([object]$Row)
    if (-not $Row) { return '' }
    if (($Row.MatchMethod + '')) { return ($Row.MatchMethod + '') }
    if (($Row.ExportStatus + '') -eq 'manual') { return 'RETRO_MANUAL' }
    if (($Row.ExportStatus + '') -eq 'unresolved') { return 'RETRO_UNRESOLVED' }
    if (($Row.Backend + '') -eq 'external_link') { return 'EXTERNAL' }
    if (($Row.SourcePath + '')) { return 'RETRO_SCAN' }
    return ''
}

function Get-RowProvenanceSummary {
    param([object]$Row)
    if (-not $Row) { return '' }
    $tokens = New-Object System.Collections.Generic.List[string]
    $method = Get-RowFallbackMatchMethod -Row $Row
    if ($method) { $tokens.Add($method) | Out-Null }
    $insertedBy = ($Row.InsertedBy + '')
    if ($insertedBy) { $tokens.Add($insertedBy) | Out-Null }
    $verified = ($Row.LastVerifiedAt + '')
    if ($verified) { $tokens.Add($verified) | Out-Null }
    if ([bool]$Row.IsForeign) { $tokens.Add('Foreign') | Out-Null }
    if ($tokens.Count -eq 0) {
        $backend = ($Row.BackendDisplay + '')
        $exportStatus = ($Row.ExportStatus + '')
        if ($backend) { $tokens.Add($backend) | Out-Null }
        if ($exportStatus) { $tokens.Add($exportStatus) | Out-Null }
    }
    return ($tokens -join ' | ')
}

function Get-StatusDisplayForKind {
    param([string]$Kind)
    switch ($Kind) {
        'matched' { return '✓' }
        'missing' { return '✓?' }
        'external' { return '→' }
        'external_missing' { return '✗→' }
        'unresolved' { return '✗' }
        'pending' { return 'Pending' }
        'running' { return 'Running' }
        default { return ($Kind + '') }
    }
}

function Get-BackendDisplayLabel {
    param([string]$Backend)
    switch (($Backend + '').ToLowerInvariant()) {
        'external_link' { return 'External' }
        'tag' { return 'Tag' }
        'manifest' { return 'Manifest' }
        default { return ($Backend + '') }
    }
}

function Get-CanonicalRowStatusKind {
    param([object]$Row)
    if (-not $Row) { return 'unresolved' }
    $sourcePath = ($Row.SourcePath + '')
    $matchMethod = Get-RowFallbackMatchMethod -Row $Row
    $backend = ($Row.Backend + '')
    $isExternal = (($backend -eq 'external_link') -or ($matchMethod -eq 'EXTERNAL') -or (($Row.ExternalPath + '') -ne ''))
    if ($isExternal) {
        if ($sourcePath -and (Test-PathSafe -Path $sourcePath -PathType Leaf)) { return 'external' }
        return 'external_missing'
    }
    if ($sourcePath) {
        if (Test-PathSafe -Path $sourcePath -PathType Leaf) { return 'matched' }
        return 'missing'
    }
    return 'unresolved'
}

function Set-CanonicalStatusOnRow {
    param([object]$Row)
    if (-not $Row) { return }
    $kind = Get-CanonicalRowStatusKind -Row $Row
    $Row.StatusKind = $kind
    $Row.StatusDisplay = Get-StatusDisplayForKind -Kind $kind
    $Row.SourceExists = ($kind -eq 'matched' -or $kind -eq 'external')
}

function Get-RowShapeRefsText {
    param([object]$Row)
    if (-not $Row -or -not $Row.Shapes) { return '' }
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($shapeRef in @($Row.Shapes)) {
        $parts.Add(('slide={0}, slide_id={1}, shape_id={2}, shape_index={3}' -f ([int]($shapeRef.slide_index + 0)), ([int]($shapeRef.slide_id + 0)), ([int]($shapeRef.shape_id + 0)), ([int]($shapeRef.shape_index + 0)))) | Out-Null
    }
    return ($parts -join [Environment]::NewLine)
}

function Copy-ShapeRefs {
    param([object[]]$ShapeRefs)
    $copies = New-Object System.Collections.Generic.List[object]
    foreach ($shapeRef in @($ShapeRefs)) {
        $copies.Add([pscustomobject]@{
            slide_index = [int]($shapeRef.slide_index + 0)
            slide_id = [int]($shapeRef.slide_id + 0)
            shape_id = [int]($shapeRef.shape_id + 0)
            shape_index = [int]($shapeRef.shape_index + 0)
        }) | Out-Null
    }
    return $copies.ToArray()
}

function Copy-ManagerRows {
    param([object[]]$Rows)
    $copies = New-Object System.Collections.Generic.List[object]
    foreach ($row in @($Rows)) {
        $copies.Add([pscustomobject]@{
            MediaId = ($row.MediaId + '')
            Slide = [int]($row.Slide + 0)
            MediaFile = ($row.MediaFile + '')
            MediaDisplay = ($row.MediaDisplay + '')
            MediaFullName = ($row.MediaFullName + '')
            SourcePath = ($row.SourcePath + '')
            SourceDisplay = ($row.SourceDisplay + '')
            Backend = ($row.Backend + '')
            BackendDisplay = ($row.BackendDisplay + '')
            StatusDisplay = ($row.StatusDisplay + '')
            StatusKind = ($row.StatusKind + '')
            SourceExists = [bool]$row.SourceExists
            PreviewPath = ($row.PreviewPath + '')
            EmbeddedPath = ($row.EmbeddedPath + '')
            ExternalPath = ($row.ExternalPath + '')
            ExportStatus = ($row.ExportStatus + '')
            Shapes = (Copy-ShapeRefs -ShapeRefs @($row.Shapes))
            DestinationPath = ($row.DestinationPath + '')
            MatchMethod = ($row.MatchMethod + '')
            InsertedBy = ($row.InsertedBy + '')
            LastVerifiedAt = ($row.LastVerifiedAt + '')
            IsForeign = [bool]$row.IsForeign
        }) | Out-Null
    }
    return $copies.ToArray()
}

function Replace-ManagerRows {
    param([object]$AppState, [object]$WindowRefs, [object[]]$Rows)
    $AppState.Rows.Clear()
    foreach ($row in @($Rows)) {
        $AppState.Rows.Add($row) | Out-Null
    }
    Refresh-ResultsListPreservingState -WindowRefs $WindowRefs
    if ($WindowRefs.ResultsList.SelectedItem) {
        Set-PreviewFromRow -WindowRefs $WindowRefs -Row $WindowRefs.ResultsList.SelectedItem
    } else {
        Set-PreviewFromRow -WindowRefs $WindowRefs -Row $null
    }
}

function Refresh-ResultsListPreservingState {
    param([object]$WindowRefs)
    if (-not $WindowRefs -or -not $WindowRefs.ResultsList) { return }
    $list = $WindowRefs.ResultsList
    $selectedItem = $list.SelectedItem
    $selectedIndex = [int]$list.SelectedIndex
    $hadKeyboardFocus = [bool]$list.IsKeyboardFocusWithin

    $list.Items.Refresh()

    $restoreItem = $null
    if ($selectedItem -and ($list.Items.IndexOf($selectedItem) -ge 0)) {
        if ($list.SelectedItem -ne $selectedItem) {
            $list.SelectedItem = $selectedItem
        }
        $restoreItem = $selectedItem
    } elseif ($selectedIndex -ge 0 -and $selectedIndex -lt $list.Items.Count) {
        if ($list.SelectedIndex -ne $selectedIndex) {
            $list.SelectedIndex = $selectedIndex
        }
        $restoreItem = $list.Items[$selectedIndex]
    }

    try {
        $view = if ($list.ItemsSource) { [System.Windows.Data.CollectionViewSource]::GetDefaultView($list.ItemsSource) } else { $null }
        if ($view -and $restoreItem) {
            [void]$view.MoveCurrentTo($restoreItem)
        } elseif ($view -and $selectedIndex -ge 0 -and $list.Items.Count -gt 0) {
            [void]$view.MoveCurrentToPosition([Math]::Min($selectedIndex, ($list.Items.Count - 1)))
        }
    } catch {}

    if (-not $hadKeyboardFocus) { return }
    try {
        if ($restoreItem) {
            $list.ScrollIntoView($restoreItem)
            $list.UpdateLayout()
            $container = $list.ItemContainerGenerator.ContainerFromItem($restoreItem)
            if ($container -is [System.Windows.Controls.ListViewItem]) {
                [void]$container.Focus()
            } else {
                [void]$list.Focus()
            }
        } else {
            [void]$list.Focus()
        }
    } catch {
        try { [void]$list.Focus() } catch {}
    }
}

function Get-ShapeRefsExactKey {
    param([object[]]$ShapeRefs)
    if (-not $ShapeRefs -or $ShapeRefs.Count -eq 0) { return '' }
    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($shapeRef in @($ShapeRefs)) {
        if (-not $shapeRef) { continue }
        $slideId = [int]($shapeRef.slide_id + 0)
        $shapeId = [int]($shapeRef.shape_id + 0)
        $slideIndex = [int]($shapeRef.slide_index + 0)
        $shapeIndex = [int]($shapeRef.shape_index + 0)
        if ($slideId -gt 0 -and $shapeId -gt 0) {
            $keys.Add(('id:{0}:{1}' -f $slideId, $shapeId)) | Out-Null
        } else {
            $keys.Add(('idx:{0}:{1}' -f $slideIndex, $shapeIndex)) | Out-Null
        }
    }
    return ((@($keys) | Sort-Object -Unique) -join ';')
}

function Get-ManifestMetadata {
    param([string]$ManifestPath)
    $default = [pscustomobject]@{
        Version = 1
        Generated = ''
        LastScannedBy = ''
        LastExportedBy = ''
    }
    if (-not $ManifestPath -or -not (Test-PathSafe -Path $ManifestPath -PathType Leaf)) { return $default }
    $json = Get-FileTextUtf8 -Path $ManifestPath
    if (-not $json) { return $default }
    try { $data = $json | ConvertFrom-Json -ErrorAction Stop } catch { return $default }
    return [pscustomobject]@{
        Version = [int](($data.version + '') -as [int])
        Generated = ($data.generated + '')
        LastScannedBy = if ($data.PSObject.Properties['last_scanned_by']) { ($data.last_scanned_by + '') } else { '' }
        LastExportedBy = if ($data.PSObject.Properties['last_exported_by']) { ($data.last_exported_by + '') } elseif ($data.PSObject.Properties['exported_by']) { ($data.exported_by + '') } else { '' }
    }
}

function Get-ManifestRowExactMap {
    param([object[]]$Rows)
    $map = @{}
    foreach ($row in @($Rows)) {
        if (-not $row -or -not $row.Shapes) { continue }
        $key = Get-ShapeRefsExactKey -ShapeRefs @($row.Shapes)
        if ($key -and -not $map.ContainsKey($key)) {
            $map[$key] = $row
        }
    }
    return $map
}

function Get-PowerPointShapeTagMap {
    param([string]$PptPath, [pscustomobject]$Logger)
    $tagByShapeKey = @{}
    if (-not $PptPath) { return $tagByShapeKey }
    $app = $null
    $presentation = $null
    try {
        $app = [System.Runtime.InteropServices.Marshal]::GetActiveObject('PowerPoint.Application')
        $presentation = Get-PowerPointPresentationByPath -App $app -PptPath $PptPath
        if (-not $presentation) {
            Write-TraceLog -Logger $Logger -Message ('startup tag map skipped: presentation not found for {0}' -f $PptPath)
            return $tagByShapeKey
        }
        $slideCount = 0
        try { $slideCount = [int]$presentation.Slides.Count } catch { $slideCount = 0 }
        for ($slideIndex = 1; $slideIndex -le $slideCount; $slideIndex++) {
            $slide = $null
            try {
                $slide = $presentation.Slides.Item($slideIndex)
                $slideId = 0
                try { $slideId = [int]($slide.SlideID + 0) } catch { $slideId = 0 }
                $shapeCount = 0
                try { $shapeCount = [int]$slide.Shapes.Count } catch { $shapeCount = 0 }
                for ($shapeIndex = 1; $shapeIndex -le $shapeCount; $shapeIndex++) {
                    $shape = $null
                    try {
                        $shape = $slide.Shapes.Item($shapeIndex)
                        $shapeState = Get-PowerPointShapeSourceState -Shape $shape
                        $tags = $shapeState.Tags
                        if (-not $tags -or $tags.Count -eq 0) { continue }
                        $shapeId = 0
                        try { $shapeId = [int]($shape.Id + 0) } catch { $shapeId = 0 }
                        $entry = [pscustomobject]@{
                            MediaId = ($tags['MEDIA_ID'] + '')
                            SourcePath = ($tags['SOURCE_PATH'] + '')
                            SourceName = ($tags['SOURCE_NAME'] + '')
                            EmbedFile = ($tags['EMBED_FILE'] + '')
                            MatchMethod = ($tags['MATCH_METHOD'] + '')
                            InsertedBy = ($tags['INSERTED_BY'] + '')
                            InsertDate = ($tags['INSERT_DATE'] + '')
                        }
                        foreach ($shapeKey in @(Get-ShapeRefIdentityKeys -ShapeRef ([pscustomobject]@{
                                    slide_id = $slideId
                                    shape_id = $shapeId
                                    slide_index = $slideIndex
                                    shape_index = $shapeIndex
                                }))) {
                            if ($shapeKey -and -not $tagByShapeKey.ContainsKey($shapeKey)) {
                                $tagByShapeKey[$shapeKey] = $entry
                            }
                        }
                    } finally {
                        if ($shape) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shape) } catch {} }
                    }
                }
            } finally {
                if ($slide) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($slide) } catch {} }
            }
        }
        Write-TraceLog -Logger $Logger -Message ('startup tag map built: {0} shapes' -f $tagByShapeKey.Count)
        return $tagByShapeKey
    } catch {
        Write-TraceLog -Logger $Logger -Message ('startup tag map error: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_)) -Error
        return @{}
    } finally {
        if ($presentation) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($presentation) } catch {} }
        if ($app) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($app) } catch {} }
    }
}

function Get-TagSummaryForShapeRefs {
    param([object[]]$ShapeRefs, [hashtable]$TagMap)
    $fieldValues = @{
        MediaId = New-Object System.Collections.Generic.List[string]
        SourcePath = New-Object System.Collections.Generic.List[string]
        SourceName = New-Object System.Collections.Generic.List[string]
        EmbedFile = New-Object System.Collections.Generic.List[string]
        MatchMethod = New-Object System.Collections.Generic.List[string]
        InsertedBy = New-Object System.Collections.Generic.List[string]
        InsertDate = New-Object System.Collections.Generic.List[string]
    }
    foreach ($shapeRef in @($ShapeRefs)) {
        $entry = $null
        foreach ($shapeKey in @(Get-ShapeRefIdentityKeys -ShapeRef $shapeRef)) {
            if ($shapeKey -and $TagMap.ContainsKey($shapeKey)) {
                $entry = $TagMap[$shapeKey]
                break
            }
        }
        if (-not $entry) { continue }
        foreach ($fieldName in @('MediaId', 'SourcePath', 'SourceName', 'EmbedFile', 'MatchMethod', 'InsertedBy', 'InsertDate')) {
            $value = ($entry.$fieldName + '')
            if ($value -and -not $fieldValues[$fieldName].Contains($value)) {
                $fieldValues[$fieldName].Add($value) | Out-Null
            }
        }
    }
    $result = [ordered]@{}
    $hasConflict = $false
    foreach ($fieldName in @('MediaId', 'SourcePath', 'SourceName', 'EmbedFile', 'MatchMethod', 'InsertedBy', 'InsertDate')) {
        $values = @($fieldValues[$fieldName])
        if ($values.Count -gt 1) { $hasConflict = $true }
        $result[$fieldName] = if ($values.Count -gt 0) { ($values[0] + '') } else { '' }
    }
    $result['HasConflict'] = [bool]$hasConflict
    $result['HasMediaIdConflict'] = (@($fieldValues['MediaId']).Count -gt 1)
    return [pscustomobject]$result
}

function New-StartupRows {
    param([string]$PptPath, [string]$ManifestPath, [pscustomobject]$Logger)
    $rows = New-Object System.Collections.Generic.List[object]
    if (-not $PptPath -or -not (Test-PathSafe -Path $PptPath -PathType Leaf)) { return @() }
    $manifestRows = @(Load-ManifestData -ManifestPath $ManifestPath)
    $manifestRowByExactKey = Get-ManifestRowExactMap -Rows $manifestRows
    $tagMap = Get-PowerPointShapeTagMap -PptPath $PptPath -Logger $Logger
    try {
        $mapResult = Build-MediaShapeMap -SnapshotPath $PptPath
    } catch {
        Write-TraceLog -Logger $Logger -Message ('startup media-map error: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_)) -Error
        return $manifestRows
    }

    foreach ($mediaName in $mapResult.MediaMap.Keys) {
        $shapeRefs = @($mapResult.MediaMap[$mediaName].shapes.ToArray())
        $exactKey = Get-ShapeRefsExactKey -ShapeRefs $shapeRefs
        $manifestRow = if ($exactKey -and $manifestRowByExactKey.ContainsKey($exactKey)) { $manifestRowByExactKey[$exactKey] } else { $null }
        $tagSummary = Get-TagSummaryForShapeRefs -ShapeRefs $shapeRefs -TagMap $tagMap
        $hasExistingTracking = [bool]$manifestRow -or [bool](($tagSummary.SourcePath + '') -or ($tagSummary.MatchMethod + '') -or (($tagSummary.MediaId + '') -and -not [bool]$tagSummary.HasMediaIdConflict))
        if (-not (Test-EmbeddedMediaAutoTrackable -MediaFile $mediaName -HasExistingTracking $hasExistingTracking)) {
            continue
        }
        $mediaId = ''
        if (($tagSummary.MediaId + '') -and -not [bool]$tagSummary.HasMediaIdConflict) {
            $mediaId = ($tagSummary.MediaId + '')
        } elseif ($manifestRow -and ($manifestRow.MediaId + '')) {
            $mediaId = ($manifestRow.MediaId + '')
        } else {
            $mediaId = New-StableLegacyMediaId -Seed ('embedded|{0}|{1}' -f $mediaName, $exactKey)
        }
        if ([bool]$tagSummary.HasMediaIdConflict) {
            Write-TraceLog -Logger $Logger -Message ('startup tag conflict: embedded row uses fallback media_id for {0}' -f $mediaName) -Error
        }
        $rowSourcePath = if (($tagSummary.SourcePath + '')) { ($tagSummary.SourcePath + '') } elseif ($manifestRow) { ($manifestRow.SourcePath + '') } else { '' }
        $rowBackend = if (($tagSummary.SourcePath + '') -or ($tagSummary.MatchMethod + '')) { 'tag' } elseif ($manifestRow) { if (($manifestRow.Backend + '')) { ($manifestRow.Backend + '') } else { 'manifest' } } else { '' }
        $rowPreviewPath = if (($tagSummary.SourcePath + '') -and (Test-PathSafe -Path $tagSummary.SourcePath -PathType Leaf)) { ($tagSummary.SourcePath + '') } elseif ($manifestRow -and ($manifestRow.DestinationPath + '') -and (Test-PathSafe -Path $manifestRow.DestinationPath -PathType Leaf)) { ($manifestRow.DestinationPath + '') } else { '' }
        $rowExportStatus = if ($manifestRow) { if (($manifestRow.ExportStatus + '')) { ($manifestRow.ExportStatus + '') } else { 'none' } } else { 'none' }
        $rowDestinationPath = if ($manifestRow) { ($manifestRow.DestinationPath + '') } else { '' }
        $rowMatchMethod = if (($tagSummary.MatchMethod + '')) { ($tagSummary.MatchMethod + '') } elseif ($manifestRow) { ($manifestRow.MatchMethod + '') } else { '' }
        $rowInsertedBy = if (($tagSummary.InsertedBy + '')) { ($tagSummary.InsertedBy + '') } elseif ($manifestRow) { ($manifestRow.InsertedBy + '') } else { '' }
        $rowLastVerifiedAt = if (($tagSummary.InsertDate + '')) { ($tagSummary.InsertDate + '') } elseif ($manifestRow) { ($manifestRow.LastVerifiedAt + '') } else { '' }
        $row = [pscustomobject]@{
            MediaId = ($mediaId + '')
            Slide = [int]$shapeRefs[0].slide_index
            MediaFile = ($mediaName + '')
            MediaDisplay = (Get-MediaDisplayLabel -MediaFile ($mediaName + ''))
            MediaFullName = ($mediaName + '')
            SourcePath = $rowSourcePath
            SourceDisplay = ''
            Backend = $rowBackend
            BackendDisplay = ''
            StatusDisplay = ''
            StatusKind = ''
            SourceExists = $false
            PreviewPath = $rowPreviewPath
            EmbeddedPath = ''
            ExternalPath = ''
            ExportStatus = $rowExportStatus
            Shapes = $shapeRefs
            DestinationPath = $rowDestinationPath
            MatchMethod = $rowMatchMethod
            InsertedBy = $rowInsertedBy
            LastVerifiedAt = $rowLastVerifiedAt
            IsForeign = $false
        }
        $row.BackendDisplay = switch (($row.Backend + '').ToLowerInvariant()) {
            'external_link' { 'External'; break }
            'tag' { 'Tag'; break }
            'manifest' { 'Manifest'; break }
            default { ($row.Backend + '') }
        }
        $row.SourceDisplay = if (($row.SourcePath + '')) { ($row.SourcePath + '') } else { '未解決' }
        $row.IsForeign = [bool](($row.InsertedBy + '') -and (($row.InsertedBy + '') -ne (Get-LocalIdentityTag)))
        Set-CanonicalStatusOnRow -Row $row
        $rows.Add($row) | Out-Null
    }

    foreach ($external in @($mapResult.ExternalLinks)) {
        $shapeRefs = @([pscustomobject]@{
            slide_index = [int]$external.SlideIndex
            slide_id = [int]$external.SlideId
            shape_id = [int]$external.ShapeId
            shape_index = [int]($external.ShapeIndex + 0)
        })
        $exactKey = Get-ShapeRefsExactKey -ShapeRefs $shapeRefs
        $manifestRow = if ($exactKey -and $manifestRowByExactKey.ContainsKey($exactKey)) { $manifestRowByExactKey[$exactKey] } else { $null }
        $tagSummary = Get-TagSummaryForShapeRefs -ShapeRefs $shapeRefs -TagMap $tagMap
        $mediaId = ''
        if (($tagSummary.MediaId + '') -and -not [bool]$tagSummary.HasMediaIdConflict) {
            $mediaId = ($tagSummary.MediaId + '')
        } elseif ($manifestRow -and ($manifestRow.MediaId + '')) {
            $mediaId = ($manifestRow.MediaId + '')
        } else {
            $mediaId = New-StableLegacyMediaId -Seed ('external|{0}|{1}' -f ($external.ExternalPath + ''), $exactKey)
        }
        $rowPreviewPath = if (($manifestRow -and ($manifestRow.DestinationPath + '') -and (Test-PathSafe -Path $manifestRow.DestinationPath -PathType Leaf))) { ($manifestRow.DestinationPath + '') } else { '' }
        $rowExportStatus = if ($manifestRow) { if (($manifestRow.ExportStatus + '')) { ($manifestRow.ExportStatus + '') } else { 'none' } } else { 'none' }
        $rowDestinationPath = if ($manifestRow) { ($manifestRow.DestinationPath + '') } else { '' }
        $rowInsertedBy = if (($tagSummary.InsertedBy + '')) { ($tagSummary.InsertedBy + '') } elseif ($manifestRow) { ($manifestRow.InsertedBy + '') } else { '' }
        $rowLastVerifiedAt = if (($tagSummary.InsertDate + '')) { ($tagSummary.InsertDate + '') } elseif ($manifestRow) { ($manifestRow.LastVerifiedAt + '') } else { '' }
        $row = [pscustomobject]@{
            MediaId = ($mediaId + '')
            Slide = [int]$external.SlideIndex
            MediaFile = ''
            MediaDisplay = '(external)'
            MediaFullName = '(external)'
            SourcePath = ($external.ExternalPath + '')
            SourceDisplay = ($external.ExternalPath + '')
            Backend = 'external_link'
            BackendDisplay = 'External'
            StatusDisplay = ''
            StatusKind = ''
            SourceExists = $false
            PreviewPath = $rowPreviewPath
            EmbeddedPath = ''
            ExternalPath = ($external.ExternalPath + '')
            ExportStatus = $rowExportStatus
            Shapes = $shapeRefs
            DestinationPath = $rowDestinationPath
            MatchMethod = 'EXTERNAL'
            InsertedBy = $rowInsertedBy
            LastVerifiedAt = $rowLastVerifiedAt
            IsForeign = $false
        }
        $row.IsForeign = [bool](($row.InsertedBy + '') -and (($row.InsertedBy + '') -ne (Get-LocalIdentityTag)))
        Set-CanonicalStatusOnRow -Row $row
        $rows.Add($row) | Out-Null
    }

    $sortedRows = @($rows | Sort-Object @{ Expression = { [int]($_.Slide + 0) } }, @{ Expression = { ($_.MediaDisplay + '') } }, @{ Expression = { ($_.MediaId + '') } })
    return $sortedRows
}

function Get-PresentationDirtyState {
    param([string]$PptPath, [pscustomobject]$Logger)
    if (-not $PptPath) { return $false }
    $app = $null
    $presentation = $null
    try {
        $app = [System.Runtime.InteropServices.Marshal]::GetActiveObject('PowerPoint.Application')
        $presentation = Get-PowerPointPresentationByPath -App $app -PptPath $PptPath
        if (-not $presentation) { return $false }
        try { return (-not [bool]$presentation.Saved) } catch { return $false }
    } catch {
        Write-TraceLog -Logger $Logger -Message ('presentation dirty-state error: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_)) -Error
        return $false
    } finally {
        if ($presentation) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($presentation) } catch {} }
        if ($app) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($app) } catch {} }
    }
}

function ConvertTo-ManagerDateTime {
    param([string]$Text)
    if (-not $Text) { return $null }
    $parsed = [datetime]::MinValue
    foreach ($format in @('yyyy/MM/dd HH:mm:ss', 'yyyyMMddHHmmss', 's')) {
        if ([datetime]::TryParseExact($Text, $format, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeLocal, [ref]$parsed)) {
            return $parsed
        }
    }
    if ([datetime]::TryParse($Text, [ref]$parsed)) { return $parsed }
    return $null
}

function Test-StartupStale {
    param([string]$PptPath, [object]$ManifestMeta, [bool]$HasUnsavedChanges, [object[]]$Rows = @())
    if ($HasUnsavedChanges) { return $true }
    if (-not (Test-PathSafe -Path $PptPath -PathType Leaf)) { return $false }
    $latestKnown = $null
    if ($ManifestMeta) {
        $generated = ConvertTo-ManagerDateTime -Text ($ManifestMeta.Generated + '')
        if ($generated) {
            $latestKnown = $generated
        }
    }
    foreach ($row in @($Rows)) {
        $verified = ConvertTo-ManagerDateTime -Text ($row.LastVerifiedAt + '')
        if ($verified -and ((-not $latestKnown) -or ($verified -gt $latestKnown))) {
            $latestKnown = $verified
        }
    }
    if (-not $latestKnown) { return $false }
    try {
        $pptLastWrite = (Get-Item -LiteralPath $PptPath -ErrorAction Stop).LastWriteTime
        return ($pptLastWrite -gt $latestKnown)
    } catch {
        return $false
    }
}

function Confirm-PresentationSavedForAction {
    param([string]$PptPath, [string]$ActionLabel, [pscustomobject]$Logger)
    if (-not $PptPath) { return $false }
    $app = $null
    $presentation = $null
    try {
        $app = [System.Runtime.InteropServices.Marshal]::GetActiveObject('PowerPoint.Application')
        $presentation = Get-PowerPointPresentationByPath -App $app -PptPath $PptPath
        if (-not $presentation) { return $false }
        $needsSave = $false
        try { $needsSave = (-not [bool]$presentation.Saved) } catch { $needsSave = $false }
        if (-not $needsSave) { return $true }
        $result = [System.Windows.MessageBox]::Show(
            ('{0} を実行する前に PowerPoint を保存します。続行しますか？' -f $ActionLabel),
            'Save and Continue',
            [System.Windows.MessageBoxButton]::OKCancel,
            [System.Windows.MessageBoxImage]::Question
        )
        if ($result -ne [System.Windows.MessageBoxResult]::OK) { return $false }
        $presentation.Save()
        return $true
    } catch {
        Write-TraceLog -Logger $Logger -Message ('save before action failed: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_)) -Error
        [System.Windows.MessageBox]::Show(
            ('PowerPoint の保存に失敗したため {0} を開始できませんでした。' -f $ActionLabel),
            'エラー',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
        return $false
    } finally {
        if ($presentation) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($presentation) } catch {} }
        if ($app) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($app) } catch {} }
    }
}

function Get-RowSummaryCounts {
    param([object[]]$Rows)
    $counts = [ordered]@{
        Total = 0
        Matched = 0
        Missing = 0
        External = 0
        BrokenExternal = 0
        Unresolved = 0
        Manual = 0
    }
    foreach ($row in @($Rows)) {
        $counts.Total++
        switch ($row.StatusKind) {
            'matched' { $counts.Matched++ }
            'missing' { $counts.Missing++ }
            'external' { $counts.External++ }
            'external_missing' { $counts.BrokenExternal++ }
            'unresolved' { $counts.Unresolved++ }
        }
        if ((Get-RowFallbackMatchMethod -Row $row) -eq 'RETRO_MANUAL') {
            $counts.Manual++
        }
    }
    return [pscustomobject]$counts
}

function Update-PrimaryActionButton {
    param([object]$WindowRefs, [object]$Rows)
    $hasRows = ($Rows -and $Rows.Count -gt 0)
    $WindowRefs.RescanButton.Content = if ($hasRows) { 'Re-scan' } else { 'Scan' }
}

function Update-IdleSummary {
    param([object]$AppState, [object]$WindowRefs)
    $counts = Get-RowSummaryCounts -Rows @($AppState.Rows)
    $summary = 'Total: {0}  |  Matched: {1}  |  Missing: {2}  |  External: {3}  |  Broken External: {4}  |  Unresolved: {5}' -f $counts.Total, $counts.Matched, $counts.Missing, $counts.External, $counts.BrokenExternal, $counts.Unresolved
    if ($counts.Manual -gt 0) {
        $summary += ('  |  Manual: {0}' -f $counts.Manual)
    }
    if ($AppState.IsStale) {
        $WindowRefs.SummaryLabel.Text = "結果は古い可能性があります。Scan / Re-scan で更新してください。`n$summary"
    } elseif ($counts.Total -gt 0) {
        $WindowRefs.SummaryLabel.Text = $summary
    } else {
        $WindowRefs.SummaryLabel.Text = '現在表示できる source row はありません。Scan を実行してください。'
    }
    Update-PrimaryActionButton -WindowRefs $WindowRefs -Rows $AppState.Rows
    $WindowRefs.ExportButton.IsEnabled = ($AppState.Rows.Count -gt 0)
    $WindowRefs.ManualButton.IsEnabled = ($WindowRefs.ResultsList.SelectedItem -ne $null)
}

function Get-RowHintMap {
    param([object[]]$Rows)
    $map = @{}
    foreach ($row in @($Rows)) {
        if (-not $row -or -not $row.Shapes) { continue }
        $key = Get-ShapeRefsExactKey -ShapeRefs @($row.Shapes)
        if (-not $key -or $map.ContainsKey($key)) { continue }
        $map[$key] = [pscustomobject]@{
            MediaId = ($row.MediaId + '')
            SourcePath = ($row.SourcePath + '')
            ExternalPath = ($row.ExternalPath + '')
            MatchMethod = (Get-RowFallbackMatchMethod -Row $row)
            InsertedBy = ($row.InsertedBy + '')
            StatusKind = ($row.StatusKind + '')
            Backend = ($row.Backend + '')
            ExportStatus = ($row.ExportStatus + '')
            PreviewPath = ($row.PreviewPath + '')
            LastVerifiedAt = ($row.LastVerifiedAt + '')
        }
    }
    return $map
}

function Get-NextResolvableRowIndex {
    param([object[]]$Rows, [int]$StartIndex = 0)
    if (-not $Rows) { return -1 }
    $begin = if ($StartIndex -gt 0) { $StartIndex } else { 0 }
    for ($index = $begin; $index -lt $Rows.Count; $index++) {
        $row = $Rows[$index]
        if (-not $row) { continue }
        if ($row.PSObject.Properties['NeedsResolve'] -and [bool]$row.NeedsResolve) {
            return $index
        }
    }
    return -1
}

function Verify-StartupRows {
    param([object]$AppState, [object]$WindowRefs)
    $total = [int]$AppState.Rows.Count
    $WindowRefs.ProgressBar.IsIndeterminate = ($total -le 0)
    $WindowRefs.ProgressBar.Value = 0
    $WindowRefs.ProgressBar.Maximum = if ($total -gt 0) { $total } else { 1 }
    $WindowRefs.ProgressLabel.Text = ''
    $WindowRefs.StageLabel.Text = 'Verifying'
    $WindowRefs.BackendLabel.Text = ''
    $WindowRefs.FilesLabel.Text = ''
    $WindowRefs.CandidatesLabel.Text = ''
    if ($total -le 0) {
        $WindowRefs.StageLabel.Text = 'Ready'
        Update-IdleSummary -AppState $AppState -WindowRefs $WindowRefs
        return
    }
    $verifiedAt = Get-Date -Format 'yyyy/MM/dd HH:mm:ss'
    for ($index = 0; $index -lt $total; $index++) {
        $row = $AppState.Rows[$index]
        if (($row.SourcePath + '')) {
            $row.SourceExists = Test-PathSafe -Path $row.SourcePath -PathType Leaf
        } else {
            $row.SourceExists = $false
        }
        $row.LastVerifiedAt = $verifiedAt
        $row.IsForeign = [bool](($row.InsertedBy + '') -and (($row.InsertedBy + '') -ne (Get-LocalIdentityTag)))
        Set-CanonicalStatusOnRow -Row $row
        $WindowRefs.ProgressBar.Value = $index + 1
        $WindowRefs.ProgressLabel.Text = ('{0} / {1}' -f ($index + 1), $total)
        $WindowRefs.SummaryLabel.Text = ('起動時検証中: {0} / {1}' -f ($index + 1), $total)
        if ((($index + 1) -eq $total) -or ((($index + 1) % 10) -eq 0)) {
            Flush-UiRender -WindowRefs $WindowRefs
        }
    }
    $AppState.IsStale = Test-StartupStale -PptPath $AppState.PptPath -ManifestMeta $AppState.ManifestMeta -HasUnsavedChanges $AppState.HasUnsavedChanges -Rows @($AppState.Rows)
    $WindowRefs.ResultsList.Items.Refresh()
    $WindowRefs.StageLabel.Text = 'Ready'
    Update-IdleSummary -AppState $AppState -WindowRefs $WindowRefs
}

function Show-RowDetailsDialog {
    param([object]$Owner, [object]$Row)
    if (-not $Row) { return }
    $detailsWindow = New-Object System.Windows.Window
    $detailsWindow.Title = 'Row Details'
    $detailsWindow.Width = 760
    $detailsWindow.Height = 520
    $detailsWindow.MinWidth = 640
    $detailsWindow.MinHeight = 420
    $detailsWindow.WindowStartupLocation = 'CenterOwner'
    $detailsWindow.Background = [System.Windows.Media.Brushes]::White
    if ($Owner) { $detailsWindow.Owner = $Owner }

    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = [System.Windows.Thickness]::new(12)
    $row1 = New-Object System.Windows.Controls.RowDefinition
    $row1.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $row2 = New-Object System.Windows.Controls.RowDefinition
    $row2.Height = [System.Windows.GridLength]::Auto
    $grid.RowDefinitions.Add($row1)
    $grid.RowDefinitions.Add($row2)

    $textBox = New-Object System.Windows.Controls.TextBox
    $textBox.IsReadOnly = $true
    $textBox.TextWrapping = 'Wrap'
    $textBox.AcceptsReturn = $true
    $textBox.VerticalScrollBarVisibility = 'Auto'
    $textBox.HorizontalScrollBarVisibility = 'Auto'
    $textBox.FontFamily = 'Consolas'
    $textBox.Background = [System.Windows.Media.Brushes]::White
    $textBox.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#D8CBB9')

    $details = @(
        ('MediaId: {0}' -f ($Row.MediaId + ''))
        ('MediaFile: {0}' -f ($Row.MediaFullName + ''))
        ('SourcePath: {0}' -f ($Row.SourcePath + ''))
        ('ExternalPath: {0}' -f ($Row.ExternalPath + ''))
        ('DestinationPath: {0}' -f ($Row.DestinationPath + ''))
        ('MatchMethod: {0}' -f (Get-RowFallbackMatchMethod -Row $Row))
        ('InsertedBy: {0}' -f ($Row.InsertedBy + ''))
        ('LastVerifiedAt: {0}' -f ($Row.LastVerifiedAt + ''))
        ('RowStatus: {0}' -f ($Row.StatusKind + ''))
        ('ExportStatus: {0}' -f ($Row.ExportStatus + ''))
        ('Foreign: {0}' -f ([bool]$Row.IsForeign))
        ''
        'Shape refs:'
        (Get-RowShapeRefsText -Row $Row)
    )
    $textBox.Text = ($details -join [Environment]::NewLine)
    [System.Windows.Controls.Grid]::SetRow($textBox, 0)
    $grid.Children.Add($textBox) | Out-Null

    $buttonPanel = New-Object System.Windows.Controls.StackPanel
    $buttonPanel.Orientation = 'Horizontal'
    $buttonPanel.HorizontalAlignment = 'Right'
    $buttonPanel.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)
    $closeButton = New-Object System.Windows.Controls.Button
    $closeButton.Content = 'Close'
    $closeButton.Padding = [System.Windows.Thickness]::new(14, 4, 14, 4)
    $closeButton.Add_Click({ $detailsWindow.Close() })
    $buttonPanel.Children.Add($closeButton) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($buttonPanel, 1)
    $grid.Children.Add($buttonPanel) | Out-Null

    $detailsWindow.Content = $grid
    [void]$detailsWindow.ShowDialog()
}

function Find-VisualParentOfType {
    param([object]$Child, [Type]$TargetType)
    $current = $Child
    while ($current) {
        if ($TargetType -and $current -is $TargetType) { return $current }
        try { $current = [System.Windows.Media.VisualTreeHelper]::GetParent($current) } catch { $current = $null }
    }
    return $null
}

function ConvertTo-ScalarText {
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        foreach ($item in $Value) {
            $text = ConvertTo-ScalarText -Value $item
            if ($text) { return $text }
        }
        return ''
    }
    try { return ($Value + '') } catch {}
    try { return [string]$Value } catch {}
    return ''
}

function Load-ManifestData {
    param([string]$ManifestPath)
    if (-not $ManifestPath -or -not (Test-PathSafe -Path $ManifestPath -PathType Leaf)) { return @() }
    $json = Get-FileTextUtf8 -Path $ManifestPath
    if (-not $json) { return @() }
    try { $data = $json | ConvertFrom-Json -ErrorAction Stop } catch { return @() }
    if (-not $data.sources) { return @() }
    $manifestMeta = Get-ManifestMetadata -ManifestPath $ManifestPath
    $manifestGenerated = ($manifestMeta.Generated + '')
    $manifestIdentity = if (($manifestMeta.LastExportedBy + '')) { ($manifestMeta.LastExportedBy + '') } else { ($manifestMeta.LastScannedBy + '') }
    $groupedEntries = [ordered]@{}
    $entryIndex = 0
    foreach ($entry in $data.sources) {
        $entryIndex++
        $mediaId = ($entry.media_id + '')
        if ($mediaId) {
            $groupKey = 'media:' + $mediaId
        } else {
            $fileKey = ($entry.file + '')
            $sourceKey = ($entry.source + '')
            $destKey = ($entry.dest + '')
            if ($fileKey -or $sourceKey -or $destKey) {
                $groupKey = 'fallback:' + $fileKey + '|' + $sourceKey + '|' + $destKey
            } else {
                $groupKey = 'entry:' + $entryIndex
            }
        }
        if (-not $groupedEntries.Contains($groupKey)) {
            $groupedEntries[$groupKey] = [ordered]@{
                MediaId = $mediaId
                Slide = [int]($entry.slide + 0)
                MediaFile = ($entry.file + '')
                SourcePath = ''
                DestinationPath = ''
                ExternalPath = ''
                ExportStatus = 'none'
                RowStatus = ''
                Backend = ''
                MatchMethod = ''
                InsertedBy = ''
                LastVerifiedAt = ''
                PreviewPath = ''
                Shapes = (New-Object System.Collections.Generic.List[object])
            }
        }
        $group = $groupedEntries[$groupKey]
        if (-not $group.MediaId -and $mediaId) { $group.MediaId = $mediaId }
        $entryFile = ConvertTo-ScalarText -Value $entry.file
        if ($entryFile) { $group.MediaFile = $entryFile }
        $slideIndex = [int]($entry.slide + 0)
        if (($group.Shapes.Count -eq 0) -or ($slideIndex -lt [int]$group.Slide)) { $group.Slide = $slideIndex }
        $entrySource = ConvertTo-ScalarText -Value $entry.source
        $entryDest = ConvertTo-ScalarText -Value $entry.dest
        $entryExternalPath = if ($entry.PSObject.Properties['external_path']) { ConvertTo-ScalarText -Value $entry.external_path } else { '' }
        $entryExportStatus = if ($entry.PSObject.Properties['export_status']) { ConvertTo-ScalarText -Value $entry.export_status } else { '' }
        $entryStatus = ConvertTo-ScalarText -Value $entry.status
        $entryRowStatus = if ($entry.PSObject.Properties['row_status']) { ConvertTo-ScalarText -Value $entry.row_status } else { '' }
        $entryBackend = if ($entry.PSObject.Properties['backend']) { ConvertTo-ScalarText -Value $entry.backend } else { '' }
        $entryMatchMethod = if ($entry.PSObject.Properties['match_method']) { ConvertTo-ScalarText -Value $entry.match_method } else { '' }
        $entryInsertedBy = if ($entry.PSObject.Properties['inserted_by']) { ConvertTo-ScalarText -Value $entry.inserted_by } else { '' }
        $entryLastVerifiedAt = if ($entry.PSObject.Properties['last_verified_at']) { ConvertTo-ScalarText -Value $entry.last_verified_at } else { '' }
        if ($entrySource) { $group.SourcePath = $entrySource }
        if ($entryDest) { $group.DestinationPath = $entryDest }
        if ($entryExternalPath) { $group.ExternalPath = $entryExternalPath }
        if ($entryExportStatus) { $group.ExportStatus = $entryExportStatus }
        elseif ($entryStatus) { $group.ExportStatus = $entryStatus }
        if ($entryRowStatus) { $group.RowStatus = $entryRowStatus }
        if ($entryBackend) { $group.Backend = $entryBackend }
        if ($entryMatchMethod) { $group.MatchMethod = $entryMatchMethod }
        if ($entryInsertedBy) { $group.InsertedBy = $entryInsertedBy }
        if ($entryLastVerifiedAt) { $group.LastVerifiedAt = $entryLastVerifiedAt }
        $group.PreviewPath = ''
        if ($entrySource -and (Test-PathSafe -Path $entrySource)) { $group.PreviewPath = $entrySource }
        elseif ($entryDest -and (Test-PathSafe -Path $entryDest)) { $group.PreviewPath = $entryDest }
        $hasSlideId = ($entry.PSObject.Properties['slide_id'] -ne $null)
        $hasShapeId = ($entry.PSObject.Properties['shape_id'] -ne $null)
        $hasShapeIndex = ($entry.PSObject.Properties['shape_index'] -ne $null)
        $slideId = if ($hasSlideId) { [int]($entry.slide_id + 0) } else { 0 }
        $shapeId = if ($hasShapeId) { [int]($entry.shape_id + 0) } else { 0 }
        $shapeIndex = if ($hasShapeIndex) { [int]($entry.shape_index + 0) } else { 0 }
        if (($shapeId -le 0) -and ($shapeIndex -le 0)) {
            $shapeValue = [int]($entry.shape + 0)
            $shapeIndex = $shapeValue
        }
        $group.Shapes.Add([pscustomobject]@{
                slide_index = $slideIndex
                slide_id = $slideId
                shape_id = $shapeId
                shape_index = $shapeIndex
            })
    }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($group in $groupedEntries.Values) {
        if (-not ($group.MediaId + '')) {
            $shapeSeedParts = New-Object System.Collections.Generic.List[string]
            foreach ($shape in @($group.Shapes)) {
                $shapeSeedParts.Add(('{0}:{1}:{2}:{3}' -f ([int]($shape.slide_index + 0)), ([int]($shape.slide_id + 0)), ([int]($shape.shape_id + 0)), ([int]($shape.shape_index + 0))))
            }
            $legacySeed = '{0}|{1}|{2}|{3}|{4}' -f ($group.MediaFile + ''), ($group.SourcePath + ''), ($group.DestinationPath + ''), ([int]$group.Slide), ($shapeSeedParts -join ';')
            $group.MediaId = New-StableLegacyMediaId -Seed $legacySeed
        }
        $previewPath = ConvertTo-ScalarText -Value $group.PreviewPath
        $sourcePath = ConvertTo-ScalarText -Value $group.SourcePath
        $destPath = ConvertTo-ScalarText -Value $group.DestinationPath
        $externalPath = ConvertTo-ScalarText -Value $group.ExternalPath
        $groupExportStatus = [string](ConvertTo-ScalarText -Value $group.ExportStatus)
        $groupBackend = [string](ConvertTo-ScalarText -Value $group.Backend)
        $groupMatchMethod = [string](ConvertTo-ScalarText -Value $group.MatchMethod)
        $groupInsertedBy = [string](ConvertTo-ScalarText -Value $group.InsertedBy)
        $groupLastVerifiedAt = [string](ConvertTo-ScalarText -Value $group.LastVerifiedAt)
        $groupRowStatus = [string](ConvertTo-ScalarText -Value $group.RowStatus)
        $mediaFileValue = [string](ConvertTo-ScalarText -Value $group.MediaFile)
        if (-not $sourcePath -and $externalPath) { $sourcePath = $externalPath }
        $sourceDisplayValue = if ($sourcePath) { $sourcePath } elseif ($destPath) { $destPath } else { '未解決' }
        $backendValue = if ([string]::IsNullOrEmpty($groupBackend)) { 'manifest' } else { $groupBackend }
        $exportStatusValue = if ([string]::IsNullOrEmpty($groupExportStatus)) { 'none' } else { $groupExportStatus }
        $matchMethodValue = if (-not [string]::IsNullOrEmpty($groupMatchMethod)) { $groupMatchMethod } elseif ($groupExportStatus -eq 'manual') { 'RETRO_MANUAL' } elseif ($groupExportStatus -eq 'unresolved') { 'RETRO_UNRESOLVED' } elseif ($groupBackend -eq 'external_link' -or $externalPath) { 'EXTERNAL' } elseif ($sourcePath) { 'RETRO_SCAN' } else { '' }
        $insertedByValue = if ([string]::IsNullOrEmpty($groupInsertedBy)) { $manifestIdentity } else { $groupInsertedBy }
        $lastVerifiedAtValue = if ([string]::IsNullOrEmpty($groupLastVerifiedAt)) { $manifestGenerated } else { $groupLastVerifiedAt }
        $mediaFullNameValue = if ($mediaFileValue) { $mediaFileValue } else { '(external)' }
        $shapeArray = @($group.Shapes.ToArray())
        $row = [pscustomobject]@{
                MediaId = ($group.MediaId + '')
                Slide = [int]$group.Slide
                MediaFile = $mediaFileValue
                MediaDisplay = (Get-MediaDisplayLabel -MediaFile $mediaFileValue)
                MediaFullName = $mediaFullNameValue
                SourcePath = ($sourcePath + '')
                SourceDisplay = $sourceDisplayValue
                Backend = $backendValue
                BackendDisplay = ''
                StatusDisplay = ''
                StatusKind = ''
                SourceExists = $false
                PreviewPath = $previewPath
                EmbeddedPath = ''
                ExternalPath = $externalPath
                ExportStatus = $exportStatusValue
                Shapes = $shapeArray
                DestinationPath = $destPath
                MatchMethod = $matchMethodValue
                InsertedBy = $insertedByValue
                LastVerifiedAt = $lastVerifiedAtValue
                IsForeign = $false
            }
        $row.BackendDisplay = switch (($row.Backend + '').ToLowerInvariant()) {
            'external_link' { 'External'; break }
            'manifest' { 'Manifest'; break }
            default { ($row.Backend + '') }
        }
        $row.IsForeign = [bool](($row.InsertedBy + '') -and (($row.InsertedBy + '') -ne (Get-LocalIdentityTag)))
        if ($groupRowStatus) {
            $row.StatusKind = $groupRowStatus
            $row.StatusDisplay = Get-StatusDisplayForKind -Kind $row.StatusKind
            $row.SourceExists = ($row.StatusKind -eq 'matched' -or $row.StatusKind -eq 'external')
        } else {
            Set-CanonicalStatusOnRow -Row $row
        }
        $rows.Add($row)
    }
    return $rows.ToArray()
}

function Write-ManifestFile {
    param([string]$ManifestPath, [string]$PptPath, [object[]]$Rows)
    $localIdentity = Get-LocalIdentityTag
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($row in $Rows) {
        if (-not $row.Shapes) { continue }
        foreach ($shape in $row.Shapes) {
            $shapeId = [int]($shape.shape_id + 0)
            $shapeIndex = [int]($shape.shape_index + 0)
            $entries.Add([pscustomobject]([ordered]@{
                    media_id = $row.MediaId
                    slide = [int]$shape.slide_index
                    slide_id = [int]($shape.slide_id + 0)
                    shape = if ($shapeId -gt 0) { $shapeId } else { $shapeIndex }
                    shape_id = $shapeId
                    shape_index = $shapeIndex
                    file = ($row.MediaFile + '')
                    source = ($row.SourcePath + '')
                    external_path = ($row.ExternalPath + '')
                    dest = ($row.DestinationPath + '')
                    status = ($row.ExportStatus + '')
                    export_status = ($row.ExportStatus + '')
                    row_status = ($row.StatusKind + '')
                    backend = ($row.Backend + '')
                    match_method = (Get-RowFallbackMatchMethod -Row $row)
                    inserted_by = ($row.InsertedBy + '')
                    last_verified_at = ($row.LastVerifiedAt + '')
                }))
        }
    }
    $manifest = [pscustomobject]([ordered]@{
            version = 2
            generated = (Get-Date -Format 'yyyy/MM/dd HH:mm:ss')
            pptx = $PptPath
            last_scanned_by = $localIdentity
            last_exported_by = $localIdentity
            exported_by = $localIdentity
            sources = $entries
        })
    $manifestDir = Get-ParentPath -Path $ManifestPath
    Ensure-Directory -Path $manifestDir
    $tempPath = Join-Path $manifestDir ([System.IO.Path]::GetFileName($ManifestPath) + '.tmp')
    $backupPath = ''
    try {
        Write-Utf8TextFile -Path $tempPath -Text ($manifest | ConvertTo-Json -Depth 10)
        if (Test-Path -LiteralPath $ManifestPath -PathType Leaf) {
            $backupPath = '{0}.bak.{1}' -f $ManifestPath, ([System.Guid]::NewGuid().ToString('N'))
            [System.IO.File]::Replace($tempPath, $ManifestPath, $backupPath, $true)
            if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
                Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
            }
        } else {
            [System.IO.File]::Move($tempPath, $ManifestPath)
        }
    } finally {
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        if ($backupPath -and (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Show-OpenFileDialog {
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Title = 'ソースファイルを選択'
    $dialog.Filter = 'Media files|*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff;*.gif;*.webp;*.svg;*.emf;*.wmf;*.mp4;*.avi;*.wmv;*.mov;*.mkv;*.mp3;*.wav;*.wma;*.m4a;*.m4v;*.webm|All files|*.*'
    if ($dialog.ShowDialog()) { return $dialog.FileName }
    return $null
}

function Get-PreviewImageExtensions {
    return @('png', 'jpg', 'jpeg', 'bmp', 'gif', 'tif', 'tiff', 'ico', 'wdp')
}

function Test-PreviewImageExtension {
    param([string]$PathOrName)
    if (-not $PathOrName) { return $false }
    $ext = [System.IO.Path]::GetExtension(($PathOrName + '')).TrimStart('.').ToLowerInvariant()
    if (-not $ext) { return $false }
    return (@(Get-PreviewImageExtensions) -contains $ext)
}

function Get-PreviewablePath {
    param([object]$Row)
    foreach ($candidate in @($Row.SourcePath, $Row.PreviewPath, $Row.DestinationPath, $Row.EmbeddedPath)) {
        if ($candidate -and (Test-PathSafe -Path $candidate -PathType Leaf)) { return $candidate }
    }
    return $null
}

function Get-PreviewImagePath {
    param([object]$Row)
    foreach ($candidate in @($Row.SourcePath, $Row.PreviewPath, $Row.DestinationPath, $Row.EmbeddedPath)) {
        if (-not $candidate) { continue }
        if (-not (Test-PreviewImageExtension -PathOrName $candidate)) { continue }
        if (Test-PathSafe -Path $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Test-EmbeddedPreviewCandidate {
    param([object]$Row)
    if (-not $Row) { return $false }
    if (($Row.ExternalPath + '')) { return $false }
    if (-not (($Row.MediaFile + ''))) { return $false }
    return (Test-PreviewImageExtension -PathOrName ($Row.MediaFile + ''))
}

function Get-PreviewCacheDirectory {
    param([object]$AppState)
    if (-not $AppState -or -not ($AppState.ScanTempDir + '')) { return '' }
    $previewDir = Join-Path $AppState.ScanTempDir 'preview_cache'
    Ensure-Directory -Path $previewDir
    return $previewDir
}

function Get-EmbeddedPreviewCachePath {
    param([object]$AppState, [object]$Row)
    if (-not $AppState -or -not $Row) { return '' }
    $previewDir = Get-PreviewCacheDirectory -AppState $AppState
    if (-not $previewDir) { return '' }
    $mediaFile = [System.IO.Path]::GetFileName(($Row.MediaFile + ''))
    if (-not $mediaFile) { return '' }
    $cacheKey = if (($Row.MediaId + '')) {
        ($Row.MediaId + '')
    } else {
        New-StableLegacyMediaId -Seed ('preview|' + (Get-ShapeRefsExactKey -ShapeRefs @($Row.Shapes)))
    }
    return (Join-Path $previewDir ($cacheKey + '_' + $mediaFile))
}

function Ensure-EmbeddedPreviewPath {
    param([object]$AppState, [object]$Row)
    if (-not (Test-EmbeddedPreviewCandidate -Row $Row)) { return $null }
    if (($Row.EmbeddedPath + '') -and (Test-PathSafe -Path $Row.EmbeddedPath -PathType Leaf)) {
        return ($Row.EmbeddedPath + '')
    }
    $cachePath = Get-EmbeddedPreviewCachePath -AppState $AppState -Row $Row
    if (-not $cachePath) { return $null }
    if (Test-PathSafe -Path $cachePath -PathType Leaf) {
        $Row.EmbeddedPath = $cachePath
        return $cachePath
    }
    if (-not (Test-PathSafe -Path $AppState.PptPath -PathType Leaf)) { return $null }
    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($AppState.PptPath)
        $entryName = 'ppt/media/' + [System.IO.Path]::GetFileName(($Row.MediaFile + ''))
        [void](Copy-ZipEntryToFile -Zip $zip -EntryName $entryName -DestinationPath $cachePath)
        if (Test-PathSafe -Path $cachePath -PathType Leaf) {
            $Row.EmbeddedPath = $cachePath
            return $cachePath
        }
    } catch {
        Write-TraceLog -Logger $AppState.Logger -Message ('embedded preview extraction failed: media_id={0} media_file={1} detail={2}' -f ($Row.MediaId + ''), ($Row.MediaFile + ''), (Format-ExceptionDetail -ExceptionRecord $_)) -Error
    } finally {
        if ($zip) { $zip.Dispose() }
    }
    return $null
}

function Ensure-RowPreviewReady {
    param([object]$AppState, [object]$Row)
    if (-not $AppState -or -not $Row) { return }
    if (Get-PreviewImagePath -Row $Row) { return }
    [void](Ensure-EmbeddedPreviewPath -AppState $AppState -Row $Row)
}

function Get-InitialPreviewCandidateIndex {
    param([object[]]$Rows)
    if (-not $Rows) { return -1 }
    for ($index = 0; $index -lt $Rows.Count; $index++) {
        if (Get-PreviewImagePath -Row $Rows[$index]) {
            return $index
        }
    }
    for ($index = 0; $index -lt $Rows.Count; $index++) {
        if (Test-EmbeddedPreviewCandidate -Row $Rows[$index]) {
            return $index
        }
    }
    return -1
}

function Initialize-StartupPreviewSelection {
    param([object]$AppState, [object]$WindowRefs)
    if (-not $AppState -or -not $WindowRefs -or -not $WindowRefs.ResultsList) { return }
    if ($WindowRefs.ResultsList.SelectedItem) {
        Ensure-RowPreviewReady -AppState $AppState -Row $WindowRefs.ResultsList.SelectedItem
        Set-PreviewFromRow -WindowRefs $WindowRefs -Row $WindowRefs.ResultsList.SelectedItem
        return
    }
    $rows = @($AppState.Rows)
    $candidateIndex = Get-InitialPreviewCandidateIndex -Rows $rows
    if ($candidateIndex -lt 0 -or $candidateIndex -ge $rows.Count) {
        Set-PreviewFromRow -WindowRefs $WindowRefs -Row $null
        return
    }
    $candidateRow = $rows[$candidateIndex]
    Ensure-RowPreviewReady -AppState $AppState -Row $candidateRow
    $WindowRefs.ResultsList.SelectedIndex = $candidateIndex
    $WindowRefs.ResultsList.ScrollIntoView($candidateRow)
    Set-PreviewFromRow -WindowRefs $WindowRefs -Row $candidateRow
}

function Set-PreviewFromRow {
    param([object]$WindowRefs, [object]$Row)
    $path = if ($Row) { Get-PreviewablePath -Row $Row } else { $null }
    $line1 = if ($Row) { ($Row.MediaFullName + '') } else { '' }
    $line2 = if ($Row) { (Get-RowProvenanceSummary -Row $Row) } else { '' }
    if ($Row -and -not $line2) { $line2 = ' ' }
    if (-not $path) {
        $WindowRefs.PreviewImage.Source = $null
        $WindowRefs.PreviewText.Text = if ($line1 -or $line2) { (($line1, $line2) -join [Environment]::NewLine) } else { '' }
        return
    }
    if (-not (Test-PreviewImageExtension -PathOrName $path)) {
        $WindowRefs.PreviewImage.Source = $null
        $line1 = [System.IO.Path]::GetFileName($path)
        $WindowRefs.PreviewText.Text = (($line1, $line2) -join [Environment]::NewLine)
        return
    }
    try {
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.UriSource = [System.Uri]::new($path)
        $bitmap.EndInit()
        $bitmap.Freeze()
        $WindowRefs.PreviewImage.Source = $bitmap
        $line1 = ('{0} ({1} x {2})' -f [System.IO.Path]::GetFileName($path), $bitmap.PixelWidth, $bitmap.PixelHeight)
        $WindowRefs.PreviewText.Text = (($line1, $line2) -join [Environment]::NewLine)
    } catch {
        $WindowRefs.PreviewImage.Source = $null
        $line1 = [System.IO.Path]::GetFileName($path)
        $WindowRefs.PreviewText.Text = (($line1, $line2) -join [Environment]::NewLine)
    }
}

function Add-LogLine {
    param([object]$WindowRefs, [string]$Text)
    $WindowRefs.LogTextBox.AppendText($Text + [Environment]::NewLine)
    $WindowRefs.LogTextBox.ScrollToEnd()
}

function Get-RowStateSnapshot {
    param([object]$Row)
    if (-not $Row) { return $null }
    return [ordered]@{
        SourcePath = ($Row.SourcePath + '')
        SourceDisplay = ($Row.SourceDisplay + '')
        SourceExists = [bool]$Row.SourceExists
        Backend = ($Row.Backend + '')
        BackendDisplay = ($Row.BackendDisplay + '')
        StatusDisplay = ($Row.StatusDisplay + '')
        StatusKind = ($Row.StatusKind + '')
        PreviewPath = ($Row.PreviewPath + '')
        ExportStatus = ($Row.ExportStatus + '')
        DestinationPath = ($Row.DestinationPath + '')
        MatchMethod = ($Row.MatchMethod + '')
        InsertedBy = ($Row.InsertedBy + '')
        LastVerifiedAt = ($Row.LastVerifiedAt + '')
        IsForeign = [bool]$Row.IsForeign
    }
}

function Restore-RowStateSnapshot {
    param([object]$Row, [hashtable]$Snapshot)
    if (-not $Row -or -not $Snapshot) { return }
    $Row.SourcePath = $Snapshot.SourcePath
    $Row.SourceDisplay = $Snapshot.SourceDisplay
    $Row.SourceExists = [bool]$Snapshot.SourceExists
    $Row.Backend = $Snapshot.Backend
    $Row.BackendDisplay = $Snapshot.BackendDisplay
    $Row.StatusDisplay = $Snapshot.StatusDisplay
    $Row.StatusKind = $Snapshot.StatusKind
    $Row.PreviewPath = $Snapshot.PreviewPath
    $Row.ExportStatus = $Snapshot.ExportStatus
    $Row.DestinationPath = $Snapshot.DestinationPath
    $Row.MatchMethod = $Snapshot.MatchMethod
    $Row.InsertedBy = $Snapshot.InsertedBy
    $Row.LastVerifiedAt = $Snapshot.LastVerifiedAt
    $Row.IsForeign = [bool]$Snapshot.IsForeign
}

function Update-ProgressLabels {
    param([object]$WindowRefs, [hashtable]$Status)
    $WindowRefs.StageLabel.Text = ($Status['stage'] + '')
    $current = [int]($Status['current_index'] + 0)
    $total = [int]($Status['total_items'] + 0)
    if ($total -gt 0) {
        $WindowRefs.ProgressBar.IsIndeterminate = $false
        $WindowRefs.ProgressBar.Maximum = $total
        $WindowRefs.ProgressBar.Value = [Math]::Min($current, $total)
        $WindowRefs.ProgressLabel.Text = ('{0} / {1}' -f $current, $total)
    }
    $WindowRefs.BackendLabel.Text = if ($Status['backend']) { 'Backend: ' + $Status['backend'] } else { '' }
    $WindowRefs.FilesLabel.Text = if ([int]($Status['files_scanned'] + 0) -gt 0) { 'Files: {0:n0}' -f [int]$Status['files_scanned'] } else { '' }
    $WindowRefs.CandidatesLabel.Text = if ([int]($Status['candidate_count'] + 0) -gt 0) { 'Candidates: {0:n0}' -f [int]$Status['candidate_count'] } else { '' }
    if ($Status['message']) { $WindowRefs.SummaryLabel.Text = $Status['message'] }
}

function Flush-UiRender {
    param([object]$WindowRefs)
    if (-not $WindowRefs -or -not $WindowRefs.ProgressBar) { return }
    try {
        [void]$WindowRefs.ProgressBar.Dispatcher.Invoke([System.Action] {}, [System.Windows.Threading.DispatcherPriority]::Render)
    } catch {}
}

function Set-ProgressStageState {
    param(
        [object]$WindowRefs,
        [string]$Stage,
        [string]$Message = '',
        [string]$Backend = '',
        [string]$Files = '',
        [string]$Candidates = '',
        [switch]$Indeterminate
    )
    if (-not $WindowRefs) { return }
    $WindowRefs.StageLabel.Text = ($Stage + '')
    $WindowRefs.ProgressBar.IsIndeterminate = [bool]$Indeterminate
    $WindowRefs.ProgressBar.Maximum = 1
    $WindowRefs.ProgressBar.Value = 0
    $WindowRefs.ProgressLabel.Text = ''
    $WindowRefs.BackendLabel.Text = ($Backend + '')
    $WindowRefs.FilesLabel.Text = ($Files + '')
    $WindowRefs.CandidatesLabel.Text = ($Candidates + '')
    if (($Message + '') -ne '') {
        $WindowRefs.SummaryLabel.Text = ($Message + '')
    }
    Flush-UiRender -WindowRefs $WindowRefs
}

function Set-IndeterminateProgressState {
    param(
        [object]$WindowRefs,
        [string]$Stage,
        [string]$Message = '',
        [string]$Backend = '',
        [string]$Files = '',
        [string]$Candidates = ''
    )
    Set-ProgressStageState -WindowRefs $WindowRefs -Stage $Stage -Message $Message -Backend $Backend -Files $Files -Candidates $Candidates -Indeterminate
}

function Set-StaticProgressState {
    param(
        [object]$WindowRefs,
        [string]$Stage,
        [string]$Message = '',
        [string]$Backend = '',
        [string]$Files = '',
        [string]$Candidates = ''
    )
    Set-ProgressStageState -WindowRefs $WindowRefs -Stage $Stage -Message $Message -Backend $Backend -Files $Files -Candidates $Candidates
}

function Reset-ProgressIndicators {
    param([object]$WindowRefs, [string]$Stage = 'Ready')
    if (-not $WindowRefs) { return }
    $WindowRefs.StageLabel.Text = $Stage
    $WindowRefs.ProgressBar.IsIndeterminate = $false
    $WindowRefs.ProgressBar.Maximum = 1
    $WindowRefs.ProgressBar.Value = 0
    $WindowRefs.ProgressLabel.Text = ''
    $WindowRefs.BackendLabel.Text = ''
    $WindowRefs.FilesLabel.Text = ''
    $WindowRefs.CandidatesLabel.Text = ''
}

function Update-ResultsListLayout {
    param([object]$WindowRefs)
    if (-not $WindowRefs -or -not $WindowRefs.ResultsList) { return }
    $gridView = $WindowRefs.ResultsList.View
    if (-not $gridView -or -not $gridView.Columns -or $gridView.Columns.Count -lt 5) { return }
    $listWidth = [double]$WindowRefs.ResultsList.ActualWidth
    if ($listWidth -le 0) { return }

    $slideWidth = 48
    $mediaWidth = 78
    $backendWidth = 78
    $statusWidth = 60
    $chromeWidth = 34
    $minSourceWidth = 220
    $sourceWidth = [Math]::Max($minSourceWidth, [Math]::Floor($listWidth - $slideWidth - $mediaWidth - $backendWidth - $statusWidth - $chromeWidth))

    $gridView.Columns[0].Width = $slideWidth
    $gridView.Columns[1].Width = $mediaWidth
    $gridView.Columns[2].Width = $sourceWidth
    $gridView.Columns[3].Width = $backendWidth
    $gridView.Columns[4].Width = $statusWidth
}

function Get-SourcesLayout {
    param([string]$PptPath)
    $pptDir = Get-ParentPath -Path $PptPath
    $pptBase = [System.IO.Path]::GetFileNameWithoutExtension($PptPath)
    $sourcesRoot = Join-Path $pptDir ($pptBase + '_sources')
    return [pscustomobject]@{
        Root = $sourcesRoot
        ResolvedDir = (Join-Path $sourcesRoot 'resolved')
        UnresolvedDir = (Join-Path $sourcesRoot '_unresolved')
        ManifestPath = (Join-Path $sourcesRoot 'sources_list.json')
    }
}

function Remove-StaleExportedFile {
    param([string]$PreviousPath, [string]$NewPath, [string]$SourcesRoot, [object]$WindowRefs)
    if (-not $PreviousPath) { return }
    if (-not (Test-Path -LiteralPath $PreviousPath -PathType Leaf)) { return }
    try {
        $normalizedPrev = [System.IO.Path]::GetFullPath($PreviousPath)
        $normalizedNew = if ($NewPath) { [System.IO.Path]::GetFullPath($NewPath) } else { '' }
        $normalizedRoot = [System.IO.Path]::GetFullPath($SourcesRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    } catch { return }
    if ($normalizedNew -and ($normalizedPrev -ieq $normalizedNew)) { return }
    $rootPrefix = $normalizedRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $normalizedPrev.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { return }
    try {
        Remove-Item -LiteralPath $PreviousPath -Force -ErrorAction Stop
    } catch {
        Add-LogLine -WindowRefs $WindowRefs -Text ('WARN: stale export cleanup failed for {0}: {1}' -f $PreviousPath, (Format-ExceptionDetail -ExceptionRecord $_))
    }
}

function Export-RowsToSources {
    param([object]$AppState, [object]$WindowRefs, [switch]$OnlySelected)
    $layout = Get-SourcesLayout -PptPath $AppState.PptPath
    $sourcesRoot = $layout.Root
    $resolvedDir = $layout.ResolvedDir
    $unresolvedDir = $layout.UnresolvedDir
    $manifestPath = $layout.ManifestPath
    $targetRows = if ($OnlySelected) {
        if ($WindowRefs.ResultsList.SelectedItem) { @($WindowRefs.ResultsList.SelectedItem) } else { @() }
    } else {
        @($AppState.Rows)
    }
    if ($targetRows.Count -eq 0) { return $false }
    $errors = New-Object System.Collections.Generic.List[string]
    $buttonState = @{
        Export = [bool]$WindowRefs.ExportButton.IsEnabled
        Manual = [bool]$WindowRefs.ManualButton.IsEnabled
        Rescan = [bool]$WindowRefs.RescanButton.IsEnabled
        Close  = [bool]$WindowRefs.CloseButton.IsEnabled
    }

    try {
        $WindowRefs.ExportButton.IsEnabled = $false
        $WindowRefs.ManualButton.IsEnabled = $false
        $WindowRefs.RescanButton.IsEnabled = $false
        $WindowRefs.CloseButton.IsEnabled = $false
        Set-IndeterminateProgressState -WindowRefs $WindowRefs -Stage 'Preparing Export' -Message 'Export フォルダを準備しています...'
        try {
            Ensure-Directory -Path $resolvedDir
            Ensure-Directory -Path $unresolvedDir
        } catch {
            $message = 'Export root creation failed: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_)
            Add-LogLine -WindowRefs $WindowRefs -Text ('WARN: {0}' -f $message)
            $WindowRefs.SummaryLabel.Text = $message
            Reset-ProgressIndicators -WindowRefs $WindowRefs -Stage 'Warning'
            return $false
        }
        Update-ProgressLabels -WindowRefs $WindowRefs -Status @{
            stage = 'Exporting'
            current_index = 0
            total_items = $targetRows.Count
            message = ('Exporting sources... 0 / {0}' -f $targetRows.Count)
        }
        Flush-UiRender -WindowRefs $WindowRefs

        $pptZip = $null
        try {
            for ($index = 0; $index -lt $targetRows.Count; $index++) {
                $row = $targetRows[$index]
                $previousDest = ($row.DestinationPath + '')
                $didWrite = $false
                $displayName = if (($row.MediaFile + '')) { ($row.MediaFile + '') } elseif (($row.ExternalPath + '')) { [System.IO.Path]::GetFileName(($row.ExternalPath + '')) } else { ('item-{0}' -f ($index + 1)) }
                Update-ProgressLabels -WindowRefs $WindowRefs -Status @{
                    stage = 'Exporting'
                    current_index = $index
                    total_items = $targetRows.Count
                    message = ('Exporting {0} ({1} / {2})' -f $displayName, $index, $targetRows.Count)
                }
                Flush-UiRender -WindowRefs $WindowRefs

                if ($row.SourcePath -and (Test-Path -LiteralPath $row.SourcePath -PathType Leaf)) {
                    $destPath = Join-Path $resolvedDir ($row.MediaId + '_' + [System.IO.Path]::GetFileName($row.SourcePath))
                    try {
                        Copy-Item -LiteralPath $row.SourcePath -Destination $destPath -Force -ErrorAction Stop
                        $row.DestinationPath = $destPath
                        $row.ExportStatus = if ($row.Backend -eq 'Manual') { 'manual' } else { 'copied' }
                        $row.StatusDisplay = '✓'
                        $row.StatusKind = 'matched'
                        $didWrite = $true
                    } catch {
                        $errors.Add(('Export copy failed for {0}: {1}' -f ($row.MediaFile + ''), (Format-ExceptionDetail -ExceptionRecord $_)))
                        continue
                    }
                    Remove-StaleExportedFile -PreviousPath $previousDest -NewPath $destPath -SourcesRoot $sourcesRoot -WindowRefs $WindowRefs
                } elseif ($row.EmbeddedPath -and (Test-Path -LiteralPath $row.EmbeddedPath -PathType Leaf)) {
                    $destPath = Join-Path $unresolvedDir ($row.MediaId + '_' + [System.IO.Path]::GetFileName($row.EmbeddedPath))
                    try {
                        Copy-Item -LiteralPath $row.EmbeddedPath -Destination $destPath -Force -ErrorAction Stop
                        $row.DestinationPath = $destPath
                        $row.ExportStatus = 'unresolved'
                        $row.StatusDisplay = '✗'
                        $row.StatusKind = 'unresolved'
                        $didWrite = $true
                    } catch {
                        $errors.Add(('Export copy failed for {0}: {1}' -f ($row.MediaFile + ''), (Format-ExceptionDetail -ExceptionRecord $_)))
                        continue
                    }
                    Remove-StaleExportedFile -PreviousPath $previousDest -NewPath $destPath -SourcesRoot $sourcesRoot -WindowRefs $WindowRefs
                } elseif (($row.MediaFile + '') -and -not ($row.ExternalPath + '')) {
                    if (-not $pptZip) {
                        try {
                            $pptZip = [System.IO.Compression.ZipFile]::OpenRead($AppState.PptPath)
                        } catch {
                            $errors.Add(('Export open pptx failed: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_)))
                            continue
                        }
                    }
                    $mediaFileName = [System.IO.Path]::GetFileName(($row.MediaFile + ''))
                    $destPath = Join-Path $unresolvedDir ($row.MediaId + '_' + $mediaFileName)
                    try {
                        if (Copy-ZipEntryToFile -Zip $pptZip -EntryName ('ppt/media/' + $mediaFileName) -DestinationPath $destPath) {
                            $row.DestinationPath = $destPath
                            $row.EmbeddedPath = $destPath
                            $row.ExportStatus = 'unresolved'
                            $row.StatusDisplay = '✗'
                            $row.StatusKind = 'unresolved'
                            $didWrite = $true
                        } else {
                            $errors.Add(('Embedded media not found in pptx: {0}' -f ($row.MediaFile + '')))
                            continue
                        }
                    } catch {
                        $errors.Add(('Export copy failed for {0}: {1}' -f ($row.MediaFile + ''), (Format-ExceptionDetail -ExceptionRecord $_)))
                        continue
                    }
                    Remove-StaleExportedFile -PreviousPath $previousDest -NewPath $destPath -SourcesRoot $sourcesRoot -WindowRefs $WindowRefs
                } elseif (-not $row.ExportStatus) {
                    $row.ExportStatus = 'skipped'
                }
                if (-not $didWrite -and $previousDest -and ($row.DestinationPath -eq $previousDest)) {
                    $sourceStillValid = if ($row.SourcePath) { Test-Path -LiteralPath $row.SourcePath -PathType Leaf } else { $false }
                    if (-not $sourceStillValid) {
                        Remove-StaleExportedFile -PreviousPath $previousDest -NewPath '' -SourcesRoot $sourcesRoot -WindowRefs $WindowRefs
                        $row.DestinationPath = ''
                    }
                }
                Update-ProgressLabels -WindowRefs $WindowRefs -Status @{
                    stage = 'Exporting'
                    current_index = ($index + 1)
                    total_items = $targetRows.Count
                    message = ('Exporting {0} ({1} / {2})' -f $displayName, ($index + 1), $targetRows.Count)
                }
                Flush-UiRender -WindowRefs $WindowRefs
            }
        } finally {
            if ($pptZip) { try { $pptZip.Dispose() } catch {} }
        }

        $WindowRefs.ResultsList.Items.Refresh()
        foreach ($message in $errors) { Add-LogLine -WindowRefs $WindowRefs -Text ('WARN: {0}' -f $message) }
        if ($OnlySelected -and $errors.Count -gt 0) {
            $WindowRefs.SummaryLabel.Text = if ($errors.Count -eq 1) { $errors[0] } else { 'Export completed with errors.' }
            Reset-ProgressIndicators -WindowRefs $WindowRefs -Stage 'Warning'
            return $false
        }
        Set-IndeterminateProgressState -WindowRefs $WindowRefs -Stage 'Writing Manifest' -Message 'sources_list.json を更新しています...'
        try {
            Write-ManifestFile -ManifestPath $manifestPath -PptPath $AppState.PptPath -Rows @($AppState.Rows)
            $AppState.ManifestPath = $manifestPath
            $AppState.ManifestMeta = Get-ManifestMetadata -ManifestPath $manifestPath
        } catch {
            $errors.Add(('Manifest write failed: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_)))
        }
        foreach ($message in $errors) { Add-LogLine -WindowRefs $WindowRefs -Text ('WARN: {0}' -f $message) }
        if ($errors.Count -gt 0) {
            $WindowRefs.SummaryLabel.Text = if ($errors.Count -eq 1) { $errors[0] } else { 'Export completed with errors.' }
            Reset-ProgressIndicators -WindowRefs $WindowRefs -Stage 'Warning'
            return $false
        }
        Reset-ProgressIndicators -WindowRefs $WindowRefs -Stage 'Ready'
        $WindowRefs.SummaryLabel.Text = ('Exported to {0}' -f $sourcesRoot)
        return $true
    } finally {
        $WindowRefs.ExportButton.IsEnabled = $buttonState.Export
        $WindowRefs.ManualButton.IsEnabled = $buttonState.Manual
        $WindowRefs.RescanButton.IsEnabled = $buttonState.Rescan
        $WindowRefs.CloseButton.IsEnabled = $buttonState.Close
    }
}

function Set-SelectedRowManualPath {
    param([object]$AppState, [object]$WindowRefs)
    $row = $WindowRefs.ResultsList.SelectedItem
    if (-not $row) { return }
    $verifiedAt = Get-Date -Format 'yyyy/MM/dd HH:mm:ss'
    $picked = Show-OpenFileDialog
    if (-not $picked) { return }
    $snapshot = Get-RowStateSnapshot -Row $row
    $powerPointSnapshot = Capture-ManualRowPowerPointState -PptPath $AppState.PptPath -Row $row -Logger $AppState.Logger
    $draftRow = [pscustomobject]@{
        MediaId = ($row.MediaId + '')
        SourcePath = ($picked + '')
        Shapes = @($row.Shapes)
    }
    if (-not (Apply-ManualRowToPowerPoint -PptPath $AppState.PptPath -Row $draftRow -Logger $AppState.Logger)) {
        $WindowRefs.SummaryLabel.Text = 'Manual Pick を適用できませんでした。'
        Add-LogLine -WindowRefs $WindowRefs -Text ('WARN: Manual Pick tags could not be synced for media_id={0}' -f ($row.MediaId + ''))
        return
    }
    $row.SourcePath = $picked
    $row.SourceDisplay = $picked
    $row.SourceExists = $true
    $row.Backend = 'Manual'
    $row.BackendDisplay = 'Manual'
    $row.StatusDisplay = '✓'
    $row.StatusKind = 'matched'
    $row.PreviewPath = $picked
    $row.ExportStatus = 'manual'
    $row.MatchMethod = 'RETRO_MANUAL'
    $row.InsertedBy = Get-LocalIdentityTag
    $row.LastVerifiedAt = $verifiedAt
    $row.IsForeign = $false
    $WindowRefs.ResultsList.Items.Refresh()
    Set-PreviewFromRow -WindowRefs $WindowRefs -Row $row
    $manualExportPath = ''
    $manualExportBackupPath = ''
    $manualManifestPath = ''
    $manualManifestBackupPath = ''
    try {
        $pptDir = Get-ParentPath -Path $AppState.PptPath
        $pptBase = [System.IO.Path]::GetFileNameWithoutExtension($AppState.PptPath)
        $sourcesRoot = Join-Path $pptDir ($pptBase + '_sources')
        $resolvedDir = Join-Path $sourcesRoot 'resolved'
        $manualManifestPath = Join-Path $sourcesRoot 'sources_list.json'
        $manualExportPath = Join-Path $resolvedDir ($row.MediaId + '_' + [System.IO.Path]::GetFileName($picked))
        $rollbackDir = Join-Path $AppState.ScanTempDir 'manual_rollback'
        if (Test-Path -LiteralPath $manualManifestPath -PathType Leaf) {
            try {
                Ensure-Directory -Path $rollbackDir
                $manualManifestBackupPath = Join-Path $rollbackDir ([System.Guid]::NewGuid().ToString('N') + '.manifest.bak')
                Copy-Item -LiteralPath $manualManifestPath -Destination $manualManifestBackupPath -Force -ErrorAction Stop
            } catch {
                $manualManifestBackupPath = ''
                Add-LogLine -WindowRefs $WindowRefs -Text ('WARN: Manual Pick manifest backup failed for media_id={0}: {1}' -f ($row.MediaId + ''), (Format-ExceptionDetail -ExceptionRecord $_))
                if (-not (Restore-ManualRowPowerPointState -PptPath $AppState.PptPath -Snapshots $powerPointSnapshot -Logger $AppState.Logger)) {
                    Add-LogLine -WindowRefs $WindowRefs -Text ('WARN: Manual Pick PowerPoint rollback failed for media_id={0}' -f ($row.MediaId + ''))
                }
                Restore-RowStateSnapshot -Row $row -Snapshot $snapshot
                $WindowRefs.ResultsList.Items.Refresh()
                Set-PreviewFromRow -WindowRefs $WindowRefs -Row $row
                $WindowRefs.SummaryLabel.Text = 'Manual Pick の準備に失敗しました。'
                Add-LogLine -WindowRefs $WindowRefs -Text ('WARN: Manual Pick aborted because the existing manifest could not be backed up for media_id={0}' -f ($row.MediaId + ''))
                return
            }
        }
        if ($manualExportPath -and (Test-Path -LiteralPath $manualExportPath -PathType Leaf)) {
            try {
                Ensure-Directory -Path $rollbackDir
                $manualExportBackupPath = Join-Path $rollbackDir ([System.Guid]::NewGuid().ToString('N') + '.bak')
                Copy-Item -LiteralPath $manualExportPath -Destination $manualExportBackupPath -Force -ErrorAction Stop
            } catch {
                $manualExportBackupPath = ''
                Add-LogLine -WindowRefs $WindowRefs -Text ('WARN: Manual Pick backup failed for media_id={0}: {1}' -f ($row.MediaId + ''), (Format-ExceptionDetail -ExceptionRecord $_))
                if (-not (Restore-ManualRowPowerPointState -PptPath $AppState.PptPath -Snapshots $powerPointSnapshot -Logger $AppState.Logger)) {
                    Add-LogLine -WindowRefs $WindowRefs -Text ('WARN: Manual Pick PowerPoint rollback failed for media_id={0}' -f ($row.MediaId + ''))
                }
                Restore-RowStateSnapshot -Row $row -Snapshot $snapshot
                $WindowRefs.ResultsList.Items.Refresh()
                Set-PreviewFromRow -WindowRefs $WindowRefs -Row $row
                $WindowRefs.SummaryLabel.Text = 'Manual Pick の準備に失敗しました。'
                Add-LogLine -WindowRefs $WindowRefs -Text ('WARN: Manual Pick aborted because the previous export could not be backed up for media_id={0}' -f ($row.MediaId + ''))
                return
            }
        }
        if (-not (Export-RowsToSources -AppState $AppState -WindowRefs $WindowRefs -OnlySelected)) {
            if ($manualExportPath -and (Test-Path -LiteralPath $manualExportPath -PathType Leaf)) {
                try {
                    Remove-Item -LiteralPath $manualExportPath -Force -ErrorAction Stop
                } catch {
                    Add-LogLine -WindowRefs $WindowRefs -Text ('WARN: Manual Pick rollback could not remove export for media_id={0}: {1}' -f ($row.MediaId + ''), (Format-ExceptionDetail -ExceptionRecord $_))
                }
            }
            if ($manualExportBackupPath -and (Test-Path -LiteralPath $manualExportBackupPath -PathType Leaf)) {
                try {
                    Ensure-Directory -Path (Get-ParentPath -Path $manualExportPath)
                    Copy-Item -LiteralPath $manualExportBackupPath -Destination $manualExportPath -Force -ErrorAction Stop
                } catch {
                    Add-LogLine -WindowRefs $WindowRefs -Text ('WARN: Manual Pick rollback could not restore previous export for media_id={0}: {1}' -f ($row.MediaId + ''), (Format-ExceptionDetail -ExceptionRecord $_))
                }
            }
            if ($manualManifestPath -and (Test-Path -LiteralPath $manualManifestPath -PathType Leaf)) {
                try {
                    Remove-Item -LiteralPath $manualManifestPath -Force -ErrorAction Stop
                } catch {
                    Add-LogLine -WindowRefs $WindowRefs -Text ('WARN: Manual Pick rollback could not remove manifest for media_id={0}: {1}' -f ($row.MediaId + ''), (Format-ExceptionDetail -ExceptionRecord $_))
                }
            }
            if ($manualManifestBackupPath -and (Test-Path -LiteralPath $manualManifestBackupPath -PathType Leaf)) {
                try {
                    Ensure-Directory -Path (Get-ParentPath -Path $manualManifestPath)
                    Copy-Item -LiteralPath $manualManifestBackupPath -Destination $manualManifestPath -Force -ErrorAction Stop
                } catch {
                    Add-LogLine -WindowRefs $WindowRefs -Text ('WARN: Manual Pick rollback could not restore manifest for media_id={0}: {1}' -f ($row.MediaId + ''), (Format-ExceptionDetail -ExceptionRecord $_))
                }
            }
            if (-not (Restore-ManualRowPowerPointState -PptPath $AppState.PptPath -Snapshots $powerPointSnapshot -Logger $AppState.Logger)) {
                Add-LogLine -WindowRefs $WindowRefs -Text ('WARN: Manual Pick PowerPoint rollback failed for media_id={0}' -f ($row.MediaId + ''))
            }
            Restore-RowStateSnapshot -Row $row -Snapshot $snapshot
            $WindowRefs.ResultsList.Items.Refresh()
            Set-PreviewFromRow -WindowRefs $WindowRefs -Row $row
            $WindowRefs.SummaryLabel.Text = 'Manual Pick の保存に失敗しました。'
            Add-LogLine -WindowRefs $WindowRefs -Text ('WARN: Manual Pick export is incomplete for media_id={0}' -f ($row.MediaId + ''))
        }
    } finally {
        if ($manualExportBackupPath -and (Test-Path -LiteralPath $manualExportBackupPath -PathType Leaf)) {
            try { Remove-Item -LiteralPath $manualExportBackupPath -Force -ErrorAction SilentlyContinue } catch {}
        }
        if ($manualManifestBackupPath -and (Test-Path -LiteralPath $manualManifestBackupPath -PathType Leaf)) {
            try { Remove-Item -LiteralPath $manualManifestBackupPath -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
}

function New-WorkerSessionState {
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($name in @(
            'Ensure-Directory', 'Get-NormalizedPath', 'Get-ParentPath', 'Test-ExcludedPath',
            'Test-FileIoRetryableException', 'Test-StatusIoPath', 'Get-StatusIoLogger', 'Write-Utf8TextFile',
            'New-StatusState', 'ConvertTo-StatusText', 'Write-StatusFile', 'Update-StatusState',
            'Test-CancelRequested', 'Throw-IfCancelled', 'Join-ProcessArguments',
            'Invoke-HiddenProcess', 'Find-EverythingExe', 'Get-FileMd5', 'Try-GetFileMd5',
            'Get-SafeLastWriteTime', 'Select-BestMatch', 'Normalize-UriPath',
            'Get-VolatileExcludeDirs', 'Search-Everything', 'Search-WindowsSearch',
            'Search-Directories', 'Filter-HashMatches', 'Resolve-Source', 'Save-PowerPointPresentation', 'Get-ZipEntryText',
            'Copy-ZipEntryToFile', 'Get-OpenXmlNamespaceMap', 'New-NamespaceManager', 'Select-XmlNodes', 'Select-XmlNode', 'Build-MediaShapeMap',
            'Export-ScanJson', 'New-MediaId', 'New-Logger', 'Write-TraceLog', 'Format-ExceptionDetail',
            'Get-ShapeRefIdentityKeys', 'Get-ShapeRefIdentityKey', 'Get-ShapeRefsExactKey', 'Get-ExistingMediaIdForShapeRefs',
            'Test-EmbeddedMediaAutoTrackable'
        )) {
        $definition = (Get-Item -LiteralPath ("Function:\" + $name)).Definition
        $iss.Commands.Add(([System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new($name, $definition)))
    }
    return $iss
}

function Get-ScanWorkerScript {
    return {
        param($Queue, $Spec)
        $script:Ns = $Spec.Ns
        $script:StatusKeyOrder = $Spec.StatusKeyOrder
        $logger = New-Logger -StdoutPath $Spec.StdoutPath -StderrPath $Spec.StderrPath
        $script:StatusIoLogger = $logger
        function Emit-Ui {
            param([string]$Type, [hashtable]$Payload)
            $event = [ordered]@{ Type = $Type }
            foreach ($key in $Payload.Keys) { $event[$key] = $Payload[$key] }
            $Queue.Enqueue([pscustomobject]$event)
        }

        function Test-WorkerPathExists {
            param([string]$Path)
            if (-not $Path) { return $false }
            try {
                return (Test-Path -LiteralPath $Path -PathType Leaf)
            } catch {
                return $false
            }
        }

        function Get-WorkerStatusDisplay {
            param([string]$Kind)
            switch ($Kind) {
                'matched' { return '✓' }
                'missing' { return '✓?' }
                'external' { return '→' }
                'external_missing' { return '✗→' }
                'pending' { return 'Pending' }
                'running' { return 'Running' }
                default { return '✗' }
            }
        }

        function Get-EmbeddedBootstrapState {
            param([object]$Row, [object]$Spec, [string]$LocalIdentity)
            $state = [ordered]@{
                SourcePath = ''
                Backend = ''
                SourceExists = $false
                StatusKind = 'unresolved'
                StatusDisplay = '✗'
                MatchMethod = ''
                InsertedBy = ''
                PreviewPath = ''
                LastVerifiedAt = ''
                NeedsResolve = $true
            }
            $rowExactKey = Get-ShapeRefsExactKey -ShapeRefs @($Row.Shapes)
            $rowHint = if ($Spec.RowHints -and $rowExactKey -and $Spec.RowHints.ContainsKey($rowExactKey)) { $Spec.RowHints[$rowExactKey] } else { $null }
            if (-not $rowHint) {
                return [pscustomobject]$state
            }

            $hintSourcePath = ($rowHint.SourcePath + '')
            $hintMethod = ($rowHint.MatchMethod + '')
            $hintBy = ($rowHint.InsertedBy + '')
            $hintBackend = ($rowHint.Backend + '')
            $hintPreviewPath = ($rowHint.PreviewPath + '')
            $hintVerifiedAt = ($rowHint.LastVerifiedAt + '')
            $state.MatchMethod = $hintMethod
            $state.InsertedBy = $hintBy
            $state.LastVerifiedAt = $hintVerifiedAt
            $state.PreviewPath = $hintPreviewPath

            if ($hintSourcePath) {
                $state.SourcePath = $hintSourcePath
                $state.SourceExists = [bool](Test-WorkerPathExists -Path $hintSourcePath)
                if ($state.SourceExists) {
                    $state.PreviewPath = $hintSourcePath
                }
                if ($hintMethod -eq 'RETRO_MANUAL') {
                    $state.Backend = if ($hintBackend) { $hintBackend } else { 'Manual' }
                    $state.NeedsResolve = $false
                } elseif ($state.SourceExists) {
                    $state.Backend = if ($hintBackend) { $hintBackend } else { 'Tag' }
                    $state.NeedsResolve = $false
                } elseif ($hintMethod -eq 'PASTE' -or $hintMethod -eq 'RETRO_SCAN' -or -not $hintMethod) {
                    if ($hintBackend) {
                        $state.Backend = $hintBackend
                    } elseif ($hintMethod) {
                        $state.Backend = 'Tag'
                    }
                    $state.NeedsResolve = $true
                } else {
                    if ($hintBackend) {
                        $state.Backend = $hintBackend
                    } elseif ($hintMethod -eq 'RETRO_MANUAL') {
                        $state.Backend = 'Manual'
                    } elseif ($hintMethod) {
                        $state.Backend = 'Tag'
                    }
                    $state.NeedsResolve = $false
                }
            }

            if ($state.SourcePath) {
                $state.StatusKind = if ($state.SourceExists) { 'matched' } else { 'missing' }
            }
            $state.StatusDisplay = Get-WorkerStatusDisplay -Kind $state.StatusKind
            return [pscustomobject]$state
        }

        function Get-ExternalBootstrapState {
            param([string]$ExternalPath, [string[]]$ExcludeDirs)
            $state = [ordered]@{
                SourcePath = ''
                Backend = ''
                SourceExists = $false
                StatusKind = 'unresolved'
                StatusDisplay = '✗'
                MatchMethod = 'EXTERNAL'
                InsertedBy = ''
                PreviewPath = ''
                LastVerifiedAt = ''
                NeedsResolve = $false
            }
            if (-not $ExternalPath) {
                return [pscustomobject]$state
            }
            if (Test-ExcludedPath -Path $ExternalPath -ExcludeDirs $ExcludeDirs) {
                return [pscustomobject]$state
            }
            $state.SourcePath = $ExternalPath
            $state.Backend = 'external_link'
            $state.SourceExists = [bool](Test-WorkerPathExists -Path $ExternalPath)
            $state.StatusKind = if ($state.SourceExists) { 'external' } else { 'external_missing' }
            $state.StatusDisplay = Get-WorkerStatusDisplay -Kind $state.StatusKind
            return [pscustomobject]$state
        }

        $status = New-StatusState
        try {
            Write-TraceLog -Logger $logger -Message ('worker start: mode={0} ppt={1} scanId={2}' -f $Spec.Mode, $Spec.PptPath, $Spec.ScanId)
            Write-TraceLog -Logger $logger -Message ('worker initial status update begin: {0}' -f $Spec.StatusPath)
            Update-StatusState -State $status -StatusPath $Spec.StatusPath -Changes @{ message = 'スキャン準備中'; cancel_requested = 0; cancelled = 0; done = 0 }
            Write-TraceLog -Logger $logger -Message 'worker initial status update complete'
            if (-not (Test-Path -LiteralPath $Spec.PptPath -PathType Leaf)) {
                throw ('pptx が見つかりません: {0}' -f $Spec.PptPath)
            }

            $snapshotPath = ($Spec.SnapshotPath + '')
            $savedTime = ($Spec.SavedTime + '')
            if (-not $snapshotPath) {
                Update-StatusState -State $status -StatusPath $Spec.StatusPath -Changes @{ stage = '保存中'; message = 'PowerPoint の内容を保存しています。'; backend = '' }
                if (-not (Save-PowerPointPresentation -PptPath $Spec.PptPath)) {
                    throw ('PowerPoint の保存に失敗しました: {0}' -f $Spec.PptPath)
                }
                $savedTime = (Get-Item -LiteralPath $Spec.PptPath -ErrorAction Stop).LastWriteTime.ToString('yyyyMMddHHmmss')
                Ensure-Directory -Path $Spec.ScanTempDir
                $snapshotPath = Join-Path $Spec.ScanTempDir ('scan_{0}.pptx' -f $Spec.ScanId)
                Copy-Item -LiteralPath $Spec.PptPath -Destination $snapshotPath -Force
                Write-TraceLog -Logger $logger -Message ('snapshot created in worker: {0}' -f $snapshotPath)
            }
            Update-StatusState -State $status -StatusPath $Spec.StatusPath -Changes @{ saved_time = $savedTime }
            Write-TraceLog -Logger $logger -Message ('presentation saved: {0}' -f $savedTime)
            Update-StatusState -State $status -StatusPath $Spec.StatusPath -Changes @{ snapshot_path = $snapshotPath }
            Write-TraceLog -Logger $logger -Message ('snapshot created: {0}' -f $snapshotPath)

            $excludeDirs = Get-VolatileExcludeDirs -PptPath $Spec.PptPath -ScanTempDir $Spec.ScanTempDir
            $esExe = Find-EverythingExe
            $pptDirectory = Get-ParentPath -Path $Spec.PptPath
            $mediaDir = Join-Path $Spec.ScanTempDir 'media'
            Ensure-Directory -Path $mediaDir

            Update-StatusState -State $status -StatusPath $Spec.StatusPath -Changes @{ stage = 'メディア解析中'; message = 'PowerPoint 内の図形とメディア対応を解析しています。'; backend = '' }
            $mapResult = Build-MediaShapeMap -SnapshotPath $snapshotPath
            Write-TraceLog -Logger $logger -Message ('media map built: embedded={0} external={1}' -f $mapResult.MediaMap.Count, $mapResult.ExternalLinks.Count)

            $zip = [System.IO.Compression.ZipFile]::OpenRead($snapshotPath)
            try {
                foreach ($entry in $zip.Entries) {
                    Throw-IfCancelled -CancelPath $Spec.CancelPath -State $status -StatusPath $Spec.StatusPath
                    if ($entry.FullName.StartsWith('ppt/media/', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $fileName = [System.IO.Path]::GetFileName($entry.FullName)
                        if ($fileName) { [void](Copy-ZipEntryToFile -Zip $zip -EntryName $entry.FullName -DestinationPath (Join-Path $mediaDir $fileName)) }
                    }
                }
            } finally {
                $zip.Dispose()
            }

            $initialRows = New-Object System.Collections.Generic.List[object]
            $counter = 1
            $localIdentity = ('{0}@{1}' -f $env:USERNAME, $env:COMPUTERNAME)
            foreach ($mediaName in $mapResult.MediaMap.Keys) {
                $shapeRefs = @($mapResult.MediaMap[$mediaName].shapes.ToArray())
                $rowExactKey = Get-ShapeRefsExactKey -ShapeRefs $shapeRefs
                $existingMediaId = Get-ExistingMediaIdForShapeRefs -ShapeRefs $shapeRefs -MediaIdByShapeKey $Spec.MediaIdByShapeKey
                $rowHint = if ($Spec.RowHints -and $rowExactKey -and $Spec.RowHints.ContainsKey($rowExactKey)) { $Spec.RowHints[$rowExactKey] } else { $null }
                $hasExistingTracking = [bool]$existingMediaId -or [bool]$rowHint
                if (-not (Test-EmbeddedMediaAutoTrackable -MediaFile $mediaName -HasExistingTracking $hasExistingTracking)) {
                    continue
                }
                $row = [pscustomobject]@{
                    MediaId = if ($existingMediaId) { $existingMediaId } else { (New-MediaId -Counter $counter) }
                    MediaFile = $mediaName
                    Slide = [int]$shapeRefs[0].slide_index
                    Shapes = $shapeRefs
                    EmbeddedPath = (Join-Path $mediaDir $mediaName)
                    ExternalPath = ''
                }
                $bootstrap = Get-EmbeddedBootstrapState -Row $row -Spec $Spec -LocalIdentity $localIdentity
                $initialRows.Add([pscustomobject]@{
                        MediaId = ($row.MediaId + '')
                        MediaFile = $row.MediaFile
                        Slide = [int]$row.Slide
                        Shapes = $shapeRefs
                        EmbeddedPath = ($row.EmbeddedPath + '')
                        ExternalPath = ''
                        SourcePath = ($bootstrap.SourcePath + '')
                        Backend = ($bootstrap.Backend + '')
                        SourceExists = [bool]$bootstrap.SourceExists
                        StatusKind = ($bootstrap.StatusKind + '')
                        StatusDisplay = ($bootstrap.StatusDisplay + '')
                        MatchMethod = ($bootstrap.MatchMethod + '')
                        InsertedBy = ($bootstrap.InsertedBy + '')
                        PreviewPath = ($bootstrap.PreviewPath + '')
                        LastVerifiedAt = ($bootstrap.LastVerifiedAt + '')
                        NeedsResolve = [bool]$bootstrap.NeedsResolve
                    })
                $counter++
            }
            foreach ($external in $mapResult.ExternalLinks) {
                $shapeRefs = @([pscustomobject]@{
                        slide_index = [int]$external.SlideIndex
                        slide_id = [int]$external.SlideId
                        shape_id = [int]$external.ShapeId
                        shape_index = [int]($external.ShapeIndex + 0)
                    })
                $existingMediaId = Get-ExistingMediaIdForShapeRefs -ShapeRefs $shapeRefs -MediaIdByShapeKey $Spec.MediaIdByShapeKey
                $bootstrap = Get-ExternalBootstrapState -ExternalPath ($external.ExternalPath + '') -ExcludeDirs $excludeDirs
                $initialRows.Add([pscustomobject]@{
                        MediaId = if ($existingMediaId) { $existingMediaId } else { (New-MediaId -Counter $counter) }
                        MediaFile = $null
                        Slide = [int]$external.SlideIndex
                        Shapes = $shapeRefs
                        EmbeddedPath = ''
                        ExternalPath = ($external.ExternalPath + '')
                        SourcePath = ($bootstrap.SourcePath + '')
                        Backend = ($bootstrap.Backend + '')
                        SourceExists = [bool]$bootstrap.SourceExists
                        StatusKind = ($bootstrap.StatusKind + '')
                        StatusDisplay = ($bootstrap.StatusDisplay + '')
                        MatchMethod = ($bootstrap.MatchMethod + '')
                        InsertedBy = ''
                        PreviewPath = ''
                        LastVerifiedAt = ''
                        NeedsResolve = [bool]$bootstrap.NeedsResolve
                    })
                $counter++
            }
            Emit-Ui -Type 'map_built' -Payload @{ Rows = $initialRows.ToArray(); MediaDir = $mediaDir; SnapshotPath = $snapshotPath }

            $resolvedRows = New-Object System.Collections.Generic.List[object]
            $total = $initialRows.Count
            $matchedCount = 0
            Update-StatusState -State $status -StatusPath $Spec.StatusPath -Changes @{ stage = 'ソース探索中'; message = 'ソース探索を開始します。'; total_items = $total }

            foreach ($row in $initialRows) {
                Throw-IfCancelled -CancelPath $Spec.CancelPath -State $status -StatusPath $Spec.StatusPath
                $index = $resolvedRows.Count + 1
                $label = if ($row.MediaFile) { $row.MediaFile } else { ([System.IO.Path]::GetFileName($row.ExternalPath)) }
                Update-StatusState -State $status -StatusPath $Spec.StatusPath -Changes @{
                    stage = 'ソース探索中'; message = 'ソース候補を探索しています。'; current_index = $index
                    current_media = $label; backend = ''; files_scanned = 0; candidate_count = 0; matched_count = $matchedCount
                }

                if ($row.MediaFile) {
                    $sourcePath = ($row.SourcePath + '')
                    $backend = ($row.Backend + '')
                    $sourceExists = [bool]$row.SourceExists
                    $shouldResolve = [bool]$row.NeedsResolve
                    $resolvedMatchMethod = ($row.MatchMethod + '')
                    $resolvedInsertedBy = ($row.InsertedBy + '')
                    if ($shouldResolve) {
                        $resolved = Resolve-Source -MediaPath $row.EmbeddedPath -PptDirectory $pptDirectory -EsExe $esExe -ExcludeDirs $excludeDirs -CancelPath $Spec.CancelPath -StatusState $status -StatusPath $Spec.StatusPath
                        $sourcePath = $resolved.SourcePath
                        $backend = $resolved.Backend
                        $sourceExists = ($sourcePath -and (Test-WorkerPathExists -Path $sourcePath))
                        $resolvedInsertedBy = $localIdentity
                        if ($sourcePath) {
                            $resolvedMatchMethod = 'RETRO_SCAN'
                        } else {
                            $resolvedMatchMethod = 'RETRO_UNRESOLVED'
                        }
                    } elseif (-not $resolvedInsertedBy) {
                        $resolvedInsertedBy = $localIdentity
                    }
                    if ($sourcePath) { $matchedCount++ }
                    $resultRow = [pscustomobject]([ordered]@{
                            media_id = $row.MediaId; media_file = $row.MediaFile; source_path = $sourcePath
                            search_backend = $backend; source_exists = [bool]$sourceExists; shapes = @($row.Shapes)
                        })
                    $resolvedRows.Add($resultRow)
                    Emit-Ui -Type 'resolved' -Payload @{
                        Index = $index; Total = $total; MediaId = $row.MediaId; MediaFile = $row.MediaFile
                        SourcePath = $sourcePath; Backend = $backend; SourceExists = [bool]$sourceExists
                        Shapes = $row.Shapes; EmbeddedPath = $row.EmbeddedPath
                        MatchMethod = $resolvedMatchMethod; InsertedBy = $resolvedInsertedBy
                    }
                    continue
                }

                $externalPath = ($row.ExternalPath + '')
                $resolvedPath = ($row.SourcePath + '')
                $backend = ($row.Backend + '')
                $sourceExists = [bool]$row.SourceExists
                if ($resolvedPath) { $matchedCount++ }
                Update-StatusState -State $status -StatusPath $Spec.StatusPath -Changes @{
                    message = if ($backend -eq 'external_link') { '外部リンク確認が完了しました。' } else { '揮発パスの外部リンクを未解決として扱いました。' }
                    backend = 'External Link'; matched_count = $matchedCount
                }
                $resultRow = [pscustomobject]([ordered]@{
                        media_id = $row.MediaId; media_file = $null; source_path = $resolvedPath
                        search_backend = $backend; source_exists = [bool]$sourceExists; shapes = @($row.Shapes)
                    })
                $resolvedRows.Add($resultRow)
                $resolvedMatchMethod = if (($row.MatchMethod + '')) { ($row.MatchMethod + '') } else { 'EXTERNAL' }
                Emit-Ui -Type 'resolved' -Payload @{
                    Index = $index; Total = $total; MediaId = $row.MediaId; MediaFile = $null
                    SourcePath = $resolvedPath; Backend = $backend; SourceExists = [bool]$sourceExists
                    Shapes = $row.Shapes; EmbeddedPath = ''; ExternalPath = $externalPath
                    MatchMethod = $resolvedMatchMethod; InsertedBy = ''
                }
            }

            $result = Export-ScanJson -JsonPath $Spec.JsonPath -PptPath $Spec.PptPath -ScanId $Spec.ScanId -SnapshotPath $snapshotPath -MediaResults @($resolvedRows.ToArray())
            Write-TraceLog -Logger $logger -Message ('json exported: {0}' -f $Spec.JsonPath)
            Update-StatusState -State $status -StatusPath $Spec.StatusPath -Changes @{
                stage = '完了'; message = 'JSON を生成しました。'; current_index = $total; current_media = ''
                backend = ''; files_scanned = 0; candidate_count = 0; matched_count = $result.summary.matched; done = 1
            }
            Emit-Ui -Type 'done' -Payload @{ Result = $result; MediaDir = $mediaDir; SnapshotPath = $snapshotPath }
        } catch {
            if ($_.Exception.Message -eq '__SCAN_CANCELLED__') {
                Write-TraceLog -Logger $logger -Message 'worker cancelled'
                Update-StatusState -State $status -StatusPath $Spec.StatusPath -Changes @{ stage = 'キャンセル完了'; message = 'スキャンを中断しました。'; cancel_requested = 1; cancelled = 1; done = 0 }
                Emit-Ui -Type 'cancelled' -Payload @{}
            } else {
                Write-TraceLog -Logger $logger -Message ('worker error: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_)) -Error
                try {
                    Update-StatusState -State $status -StatusPath $Spec.StatusPath -Changes @{ stage = 'エラー'; message = $_.Exception.Message }
                } catch {
                    Write-TraceLog -Logger $logger -Message ('worker error status update failed: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_)) -Error
                }
                Emit-Ui -Type 'error' -Payload @{ Error = $_.Exception.Message }
            }
        }
    }
}

function Reset-UiForScan {
    param([object]$WindowRefs)
    $WindowRefs.ProgressBar.IsIndeterminate = $true
    $WindowRefs.ProgressBar.Value = 0
    $WindowRefs.ProgressLabel.Text = ''
    $WindowRefs.BackendLabel.Text = ''
    $WindowRefs.FilesLabel.Text = ''
    $WindowRefs.CandidatesLabel.Text = ''
    $WindowRefs.SummaryLabel.Text = 'Scanning...'
    $WindowRefs.CancelButton.Visibility = 'Visible'
    $WindowRefs.CancelButton.IsEnabled = $true
    $WindowRefs.CancelButton.Content = 'Cancel'
}

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PowerPoint Source Manager"
        Width="1180" Height="760" MinWidth="1080" MinHeight="560"
        WindowStartupLocation="CenterScreen" Background="#FFF6F3EC">
  <Window.Resources>
    <Style TargetType="ListViewItem">
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Style.Triggers>
        <DataTrigger Binding="{Binding StatusKind}" Value="matched"><Setter Property="Foreground" Value="#176B2E"/></DataTrigger>
        <DataTrigger Binding="{Binding StatusKind}" Value="missing"><Setter Property="Foreground" Value="#9C5A00"/></DataTrigger>
        <DataTrigger Binding="{Binding StatusKind}" Value="unresolved"><Setter Property="Foreground" Value="#A32020"/></DataTrigger>
        <DataTrigger Binding="{Binding StatusKind}" Value="external"><Setter Property="Foreground" Value="#135A9C"/></DataTrigger>
        <DataTrigger Binding="{Binding StatusKind}" Value="external_missing"><Setter Property="Foreground" Value="#8C2F1F"/></DataTrigger>
        <DataTrigger Binding="{Binding StatusKind}" Value="pending"><Setter Property="Foreground" Value="#777777"/></DataTrigger>
        <DataTrigger Binding="{Binding StatusKind}" Value="running"><Setter Property="Foreground" Value="#A86500"/></DataTrigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="CenteredHeaderStyle" TargetType="GridViewColumnHeader">
      <Setter Property="HorizontalContentAlignment" Value="Center"/>
    </Style>
    <DataTemplate x:Key="SlideCellTemplate">
      <Grid><TextBlock Text="{Binding Slide}" TextAlignment="Center" HorizontalAlignment="Stretch"/></Grid>
    </DataTemplate>
    <DataTemplate x:Key="MediaCellTemplate">
      <Grid><TextBlock Text="{Binding MediaDisplay}" TextAlignment="Center" HorizontalAlignment="Stretch"/></Grid>
    </DataTemplate>
    <DataTemplate x:Key="SourceCellTemplate">
      <Grid><TextBlock Text="{Binding SourceDisplay}" TextAlignment="Left" HorizontalAlignment="Stretch" Margin="4,0,4,0"/></Grid>
    </DataTemplate>
    <DataTemplate x:Key="BackendCellTemplate">
      <Grid><TextBlock Text="{Binding BackendDisplay}" TextAlignment="Center" HorizontalAlignment="Stretch"/></Grid>
    </DataTemplate>
    <DataTemplate x:Key="StatusCellTemplate">
      <Grid><TextBlock Text="{Binding StatusDisplay}" TextAlignment="Center" HorizontalAlignment="Stretch"/></Grid>
    </DataTemplate>
  </Window.Resources>
  <DockPanel>
    <Menu DockPanel.Dock="Top"><MenuItem Header="_Help"><MenuItem Header="Status Icons &amp; Shortcuts" Name="HelpMenuItem" /></MenuItem></Menu>
    <Border DockPanel.Dock="Top" Padding="12,8" Background="#FFF1E8D6" BorderBrush="#FFD8C6A5" BorderThickness="0,0,0,1">
      <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal"><TextBlock Text="Target:" Foreground="#665D52" FontWeight="SemiBold"/><TextBlock Name="TargetLabel" Margin="6,0,0,0"/></StackPanel>
        <TextBlock Name="StageLabel" Grid.Column="1" FontWeight="SemiBold" Foreground="#51453B"/>
      </Grid>
    </Border>
    <Grid Margin="8">
      <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <Grid Grid.Row="0">
        <Grid.ColumnDefinitions><ColumnDefinition Width="5*"/><ColumnDefinition Width="6"/><ColumnDefinition Width="2*"/></Grid.ColumnDefinitions>
        <GroupBox Header="Scan Results" Padding="4" Margin="0,0,6,0" MinWidth="720">
          <ListView Name="ResultsList" Background="White" BorderBrush="#D9C7A5" ScrollViewer.HorizontalScrollBarVisibility="Disabled">
            <ListView.View>
              <GridView>
                <GridViewColumn Header="Slide" Width="48" HeaderContainerStyle="{StaticResource CenteredHeaderStyle}" CellTemplate="{StaticResource SlideCellTemplate}"/>
                <GridViewColumn Header="Media" Width="78" HeaderContainerStyle="{StaticResource CenteredHeaderStyle}" CellTemplate="{StaticResource MediaCellTemplate}"/>
                <GridViewColumn Header="Source" Width="390" HeaderContainerStyle="{StaticResource CenteredHeaderStyle}" CellTemplate="{StaticResource SourceCellTemplate}"/>
                <GridViewColumn Header="Backend" Width="78" HeaderContainerStyle="{StaticResource CenteredHeaderStyle}" CellTemplate="{StaticResource BackendCellTemplate}"/>
                <GridViewColumn Header="Status" Width="60" HeaderContainerStyle="{StaticResource CenteredHeaderStyle}" CellTemplate="{StaticResource StatusCellTemplate}"/>
              </GridView>
            </ListView.View>
          </ListView>
        </GroupBox>
        <GridSplitter Grid.Column="1" Width="6" Background="#D8C8AB" ResizeDirection="Columns" ResizeBehavior="PreviousAndNext"/>
        <GroupBox Grid.Column="2" Header="Preview" Padding="8" Margin="6,0,0,0" MinWidth="250">
          <Grid><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <Border Name="PreviewBorder" Background="#FFF9F7F2" BorderBrush="#E1D7C7" BorderThickness="1"><Image Name="PreviewImage" Stretch="Uniform"/></Border>
            <TextBlock Name="PreviewText" Grid.Row="1" Margin="0,8,0,0" TextWrapping="Wrap" MinHeight="40"/>
          </Grid>
        </GroupBox>
      </Grid>
      <Border Grid.Row="1" Margin="0,8,0,0" Padding="10,8" Background="#FFF8F3EA" BorderBrush="#E0D2BF" BorderThickness="1">
        <DockPanel>
          <StackPanel DockPanel.Dock="Top">
            <Grid Margin="0,0,0,6"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <ProgressBar Name="ProgressBar" Height="18" Minimum="0" Maximum="100" IsIndeterminate="True"/>
              <TextBlock Name="ProgressLabel" Grid.Column="1" Margin="10,0,0,0" VerticalAlignment="Center"/>
            </Grid>
            <WrapPanel Margin="0,0,0,6">
              <TextBlock Name="BackendLabel" Margin="0,0,14,0" Foreground="#6A625A"/>
              <TextBlock Name="FilesLabel" Margin="0,0,14,0" Foreground="#6A625A"/>
              <TextBlock Name="CandidatesLabel" Margin="0,0,14,0" Foreground="#6A625A"/>
              <TextBlock Name="ElapsedLabel" Foreground="#6A625A"/>
            </WrapPanel>
            <TextBox Name="LogTextBox" Height="84" IsReadOnly="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="NoWrap" FontFamily="Consolas" Background="#FFFBFAF7" BorderBrush="#D8CBB9"/>
          </StackPanel>
          <Grid DockPanel.Dock="Bottom" Margin="0,8,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Name="SummaryLabel" VerticalAlignment="Center" TextWrapping="Wrap"/>
            <Button Name="ManualButton" Grid.Column="1" Margin="8,0,0,0" Padding="14,4" Content="Manual Pick"/>
            <Button Name="ExportButton" Grid.Column="2" Margin="8,0,0,0" Padding="14,4" Content="Export Sources"/>
            <Button Name="RescanButton" Grid.Column="3" Margin="8,0,0,0" Padding="14,4" Content="Scan"/>
            <Button Name="CancelButton" Grid.Column="4" Margin="8,0,0,0" Padding="14,4" Content="Cancel"/>
            <Button Name="CloseButton" Grid.Column="5" Margin="8,0,0,0" Padding="14,4" Content="Close"/>
          </Grid>
        </DockPanel>
      </Border>
    </Grid>
  </DockPanel>
</Window>
'@

[xml]$xamlXml = $xaml
$reader = New-Object System.Xml.XmlNodeReader $xamlXml
$window = [Windows.Markup.XamlReader]::Load($reader)
$windowRefs = [pscustomobject]@{
    Window = $window; TargetLabel = $window.FindName('TargetLabel'); StageLabel = $window.FindName('StageLabel')
    ResultsList = $window.FindName('ResultsList'); PreviewBorder = $window.FindName('PreviewBorder')
    PreviewImage = $window.FindName('PreviewImage'); PreviewText = $window.FindName('PreviewText')
    ProgressBar = $window.FindName('ProgressBar'); ProgressLabel = $window.FindName('ProgressLabel')
    BackendLabel = $window.FindName('BackendLabel'); FilesLabel = $window.FindName('FilesLabel')
    CandidatesLabel = $window.FindName('CandidatesLabel'); ElapsedLabel = $window.FindName('ElapsedLabel')
    LogTextBox = $window.FindName('LogTextBox'); SummaryLabel = $window.FindName('SummaryLabel')
    ManualButton = $window.FindName('ManualButton'); ExportButton = $window.FindName('ExportButton')
    RescanButton = $window.FindName('RescanButton'); CancelButton = $window.FindName('CancelButton')
    CloseButton = $window.FindName('CloseButton'); HelpMenuItem = $window.FindName('HelpMenuItem')
}

$windowRefs.TargetLabel.Text = [System.IO.Path]::GetFileName($PptPath)
$rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
$windowRefs.ResultsList.ItemsSource = $rows
$windowRefs.ResultsList.Add_SizeChanged({
    try {
        Update-ResultsListLayout -WindowRefs $windowRefs
    } catch {
    }
})
$appState = [pscustomobject]@{
    Mode = $Mode; PptPath = [System.IO.Path]::GetFullPath($PptPath); ScanId = [string]$ScanId
    JsonPath = [System.IO.Path]::GetFullPath($JsonPath); StatusPath = [System.IO.Path]::GetFullPath($StatusPath)
    CancelPath = [System.IO.Path]::GetFullPath($CancelPath); ManifestPath = if ($ManifestPath) { [System.IO.Path]::GetFullPath($ManifestPath) } else { '' }
    RescanPath = if ($RescanPath) { [System.IO.Path]::GetFullPath($RescanPath) } else { '' }
    SyncPath = if ($SyncPath) { [System.IO.Path]::GetFullPath($SyncPath) } else { '' }
    Rows = $rows; Queue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new(); Status = New-StatusState
    StartTime = Get-Date; ScanTempDir = Join-Path $env:TEMP ('ppt_scan_{0}' -f $ScanId)
    Worker = $null; WorkerHandle = $null; WorkerRunspace = $null; Logger = (New-Logger -StdoutPath $StdoutPath -StderrPath $StderrPath)
    ManifestMeta = $null; HasUnsavedChanges = $false; IsStale = $false; LastCommittedRows = @(); StartupInitialized = $false
}
$script:StatusIoLogger = $appState.Logger
Write-TraceLog -Logger $appState.Logger -Message ('manager start: mode={0} ppt={1} scanId={2}' -f $Mode, $appState.PptPath, $appState.ScanId)

function Start-ScanWorker {
    param([object]$AppState, [object]$WindowRefs)
    Write-TraceLog -Logger $AppState.Logger -Message ('Start-ScanWorker called: mode={0} scanId={1}' -f $AppState.Mode, $AppState.ScanId)
    if ($AppState.Worker -and $AppState.WorkerHandle -and -not $AppState.WorkerHandle.IsCompleted) {
        Write-TraceLog -Logger $AppState.Logger -Message 'Start-ScanWorker skipped because a worker is already running.'
        Add-LogLine -WindowRefs $WindowRefs -Text 'A scan is already running.'
        return
    }
    if ($AppState.Worker -or $AppState.WorkerRunspace) {
        Complete-Worker -AppState $AppState
    }
    $queuedItem = $null
    while ($AppState.Queue.TryDequeue([ref]$queuedItem)) {}
    Remove-DirectorySafe -Path $AppState.ScanTempDir
    Ensure-Directory -Path (Get-ParentPath -Path $AppState.JsonPath)
    Ensure-Directory -Path (Get-ParentPath -Path $AppState.StatusPath)
    if (Test-Path -LiteralPath $AppState.JsonPath) { Remove-Item -LiteralPath $AppState.JsonPath -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $AppState.StatusPath) { Remove-Item -LiteralPath $AppState.StatusPath -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $AppState.CancelPath) { Remove-Item -LiteralPath $AppState.CancelPath -Force -ErrorAction SilentlyContinue }
    if ($AppState.RescanPath -and (Test-Path -LiteralPath $AppState.RescanPath)) { Remove-Item -LiteralPath $AppState.RescanPath -Force -ErrorAction SilentlyContinue }
    if ($AppState.SyncPath -and (Test-Path -LiteralPath $AppState.SyncPath)) { Remove-Item -LiteralPath $AppState.SyncPath -Force -ErrorAction SilentlyContinue }
    $AppState.Rows.Clear()
    $AppState.StartTime = Get-Date
    $AppState.Status = New-StatusState
    Write-StatusFile -StatusPath $AppState.StatusPath -State $AppState.Status
    Reset-UiForScan -WindowRefs $WindowRefs
    $WindowRefs.RescanButton.IsEnabled = $false
    $WindowRefs.ExportButton.IsEnabled = $false
    $snapshotInfo = $null
    try {
        Update-StatusState -State $AppState.Status -StatusPath $AppState.StatusPath -Changes @{ stage = '保存中'; message = 'PowerPoint の内容を保存しています。'; backend = '' }
        $snapshotInfo = New-ScanSnapshot -PptPath $AppState.PptPath -ScanTempDir $AppState.ScanTempDir
        Update-StatusState -State $AppState.Status -StatusPath $AppState.StatusPath -Changes @{
            saved_time = ($snapshotInfo.SavedTime + '')
            snapshot_path = ($snapshotInfo.SnapshotPath + '')
            stage = '準備完了'
            message = 'スキャンの準備ができました。'
        }
        Write-TraceLog -Logger $AppState.Logger -Message ('presentation saved: {0}' -f ($snapshotInfo.SavedTime + ''))
        Write-TraceLog -Logger $AppState.Logger -Message ('snapshot created: {0}' -f ($snapshotInfo.SnapshotPath + ''))
    } catch {
        Write-TraceLog -Logger $AppState.Logger -Message ('snapshot preparation error: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_)) -Error
        Replace-ManagerRows -AppState $AppState -WindowRefs $WindowRefs -Rows (Copy-ManagerRows -Rows @($AppState.LastCommittedRows))
        $WindowRefs.StageLabel.Text = 'Error'
        $WindowRefs.CancelButton.Visibility = 'Collapsed'
        $WindowRefs.CancelButton.IsEnabled = $true
        $WindowRefs.CancelButton.Content = 'Cancel'
        $WindowRefs.RescanButton.IsEnabled = $true
        $WindowRefs.ExportButton.IsEnabled = ($AppState.Rows.Count -gt 0)
        Update-IdleSummary -AppState $AppState -WindowRefs $WindowRefs
        $WindowRefs.SummaryLabel.Text = ('Scan preparation failed: {0}' -f $_.Exception.Message)
        [System.Windows.MessageBox]::Show(
            ('PowerShell ソースマネージャーが失敗しました。`r`nJSON が生成されませんでした。`r`n`r`n{0}' -f $_.Exception.Message),
            'エラー',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
        return
    }
    $mediaIdByShapeKey = @{}
    $rowHints = Get-RowHintMap -Rows @(if ($AppState.LastCommittedRows -and $AppState.LastCommittedRows.Count -gt 0) { $AppState.LastCommittedRows } else { $AppState.Rows })
    $manifestMediaIdByShapeKey = Get-ManifestMediaIdMap -ManifestPath $AppState.ManifestPath -Logger $AppState.Logger
    foreach ($entry in $manifestMediaIdByShapeKey.GetEnumerator()) {
        $mediaIdByShapeKey[$entry.Key] = ($entry.Value + '')
    }
    $tagMediaIdByShapeKey = Get-PowerPointMediaIdMap -PptPath $AppState.PptPath -Logger $AppState.Logger
    foreach ($entry in $tagMediaIdByShapeKey.GetEnumerator()) {
        if (-not $mediaIdByShapeKey.ContainsKey($entry.Key)) {
            $mediaIdByShapeKey[$entry.Key] = ($entry.Value + '')
        }
    }
    $workerRunspace = [runspacefactory]::CreateRunspace((New-WorkerSessionState))
    $workerRunspace.ApartmentState = 'STA'
    $workerRunspace.ThreadOptions = 'ReuseThread'
    $workerRunspace.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $workerRunspace
    $scanSpec = [pscustomobject]@{
        PptPath = $AppState.PptPath; ScanId = $AppState.ScanId; JsonPath = $AppState.JsonPath
        StatusPath = $AppState.StatusPath; CancelPath = $AppState.CancelPath; ScanTempDir = $AppState.ScanTempDir
        Ns = $script:Ns; StatusKeyOrder = $script:StatusKeyOrder
        StdoutPath = $AppState.Logger.StdoutPath; StderrPath = $AppState.Logger.StderrPath; Mode = $AppState.Mode
        MediaIdByShapeKey = $mediaIdByShapeKey
        RowHints = $rowHints
        SnapshotPath = ($snapshotInfo.SnapshotPath + '')
        SavedTime = ($snapshotInfo.SavedTime + '')
    }
    [void]$ps.AddScript((Get-ScanWorkerScript).ToString()).AddArgument($AppState.Queue).AddArgument($scanSpec)
    $AppState.Worker = $ps
    $AppState.WorkerRunspace = $workerRunspace
    $AppState.WorkerHandle = $ps.BeginInvoke()
    Write-TraceLog -Logger $AppState.Logger -Message 'worker runspace started'
}

function Stop-ScanWorker {
    param([object]$AppState)
    if ($AppState.CancelPath) {
        Ensure-Directory -Path (Get-ParentPath -Path $AppState.CancelPath)
        Write-Utf8TextFile -Path $AppState.CancelPath -Text "cancel`n"
    }
}

function Force-StopScanWorker {
    param([object]$AppState)
    if ($AppState.Worker -and $AppState.WorkerHandle -and -not $AppState.WorkerHandle.IsCompleted) {
        try { $AppState.Worker.Stop() } catch {}
    }
    Complete-Worker -AppState $AppState
}

function Complete-Worker {
    param([object]$AppState)
    if ($AppState.Worker) {
        try { if ($AppState.WorkerHandle) { $AppState.Worker.EndInvoke($AppState.WorkerHandle) | Out-Null } } catch {}
        $AppState.Worker.Dispose()
        $AppState.Worker = $null
    }
    if ($AppState.WorkerRunspace) {
        $AppState.WorkerRunspace.Close()
        $AppState.WorkerRunspace.Dispose()
        $AppState.WorkerRunspace = $null
    }
    $AppState.WorkerHandle = $null
}

function Apply-ResolvedUiRow {
    param([object]$AppState, [object]$WindowRefs, [object]$Message)
    $index = [int]$Message.Index - 1
    if ($index -lt 0 -or $index -ge $AppState.Rows.Count) { return }
    $localIdentity = Get-LocalIdentityTag
    $verifiedAt = Get-Date -Format 'yyyy/MM/dd HH:mm:ss'
    $messageExternalPath = if ($Message.PSObject.Properties['ExternalPath']) { ($Message.ExternalPath + '') } else { '' }
    $messageEmbeddedPath = if ($Message.PSObject.Properties['EmbeddedPath']) { ($Message.EmbeddedPath + '') } else { '' }
    $messageMatchMethod = if ($Message.PSObject.Properties['MatchMethod']) { ($Message.MatchMethod + '') } else { '' }
    $messageInsertedBy = if ($Message.PSObject.Properties['InsertedBy']) { ($Message.InsertedBy + '') } else { '' }
    $row = $AppState.Rows[$index]
    $row.SourcePath = ($Message.SourcePath + '')
    $row.SourceDisplay = if ($Message.SourcePath) { $Message.SourcePath } else { '未解決' }
    $row.Backend = ($Message.Backend + '')
    $row.BackendDisplay = Get-BackendDisplayLabel -Backend ($Message.Backend + '')
    $row.SourceExists = [bool]$Message.SourceExists
    $row.EmbeddedPath = $messageEmbeddedPath
    $row.ExternalPath = $messageExternalPath
    if ($Message.PSObject.Properties['InsertedBy']) {
        $row.InsertedBy = $messageInsertedBy
    } else {
        $row.InsertedBy = $localIdentity
    }
    $row.LastVerifiedAt = $verifiedAt
    $row.IsForeign = [bool](($row.InsertedBy + '') -and (($row.InsertedBy + '') -ne $localIdentity))
    if ($Message.Backend -eq 'external_link') {
        $row.MatchMethod = if ($messageMatchMethod) { $messageMatchMethod } else { 'EXTERNAL' }
        if ($Message.SourceExists) { $row.StatusDisplay = '→'; $row.StatusKind = 'external' } else { $row.StatusDisplay = '✗→'; $row.StatusKind = 'external_missing' }
    } elseif ($Message.SourcePath) {
        $row.StatusDisplay = if ($Message.SourceExists) { '✓' } else { '✓?' }
        $row.StatusKind = if ($Message.SourceExists) { 'matched' } else { 'missing' }
        $row.PreviewPath = $Message.SourcePath
        $row.MatchMethod = if ($messageMatchMethod) { $messageMatchMethod } else { 'RETRO_SCAN' }
    } else {
        $row.StatusDisplay = '✗'
        $row.StatusKind = 'unresolved'
        if (-not $row.PreviewPath) { $row.PreviewPath = $row.EmbeddedPath }
        $row.MatchMethod = if ($messageMatchMethod) { $messageMatchMethod } else { 'RETRO_UNRESOLVED' }
    }
    if ($row.PSObject.Properties['NeedsResolve']) {
        $row.NeedsResolve = $false
    }
    $nextResolveIndex = Get-NextResolvableRowIndex -Rows @($AppState.Rows) -StartIndex ($index + 1)
    if ($nextResolveIndex -ge 0) {
        $AppState.Rows[$nextResolveIndex].StatusKind = 'running'
        $AppState.Rows[$nextResolveIndex].StatusDisplay = 'Running'
    }
    $WindowRefs.ProgressBar.IsIndeterminate = $false
    $WindowRefs.ProgressBar.Maximum = [int]$Message.Total
    $WindowRefs.ProgressBar.Value = [int]$Message.Index
    $WindowRefs.ProgressLabel.Text = ('{0} / {1}' -f $Message.Index, $Message.Total)
    $WindowRefs.StageLabel.Text = ('Scanning {0} / {1}' -f $Message.Index, $Message.Total)
    Refresh-ResultsListPreservingState -WindowRefs $WindowRefs
    $mediaName = if ($row.MediaFile) { $row.MediaFile } else { '(external)' }
    $logText = if ($row.SourcePath) {
        '[{0}/{1}] {2} -> {3}' -f $Message.Index, $Message.Total, $mediaName, [System.IO.Path]::GetFileName(($row.SourcePath + ''))
    } else {
        '[{0}/{1}] {2} -> unresolved' -f $Message.Index, $Message.Total, $mediaName
    }
    Add-LogLine -WindowRefs $WindowRefs -Text $logText
}

$windowRefs.ResultsList.Add_SelectionChanged({
    try {
        Ensure-RowPreviewReady -AppState $appState -Row $windowRefs.ResultsList.SelectedItem
        Set-PreviewFromRow -WindowRefs $windowRefs -Row $windowRefs.ResultsList.SelectedItem
        $windowRefs.ManualButton.IsEnabled = ($windowRefs.ResultsList.SelectedItem -ne $null)
    } catch {
        Write-TraceLog -Logger $appState.Logger -Message ('selection changed error: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_)) -Error
        throw
    }
})
$windowRefs.ResultsList.Add_PreviewMouseRightButtonDown({
    param($sender, $eventArgs)
    try {
        $listViewItem = Find-VisualParentOfType -Child $eventArgs.OriginalSource -TargetType ([System.Windows.Controls.ListViewItem])
        if ($listViewItem) {
            $listViewItem.IsSelected = $true
            $listViewItem.Focus() | Out-Null
        }
    } catch {
        Write-TraceLog -Logger $appState.Logger -Message ('right click selection sync error: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_)) -Error
    }
})
$windowRefs.CloseButton.Add_Click({ $window.Close() })
$windowRefs.HelpMenuItem.Add_Click({
    [System.Windows.MessageBox]::Show(
        "ステータス列:`n  ✓   一致`n  ✓?  パスは解決済みだがファイルが見つからない`n  →   外部リンク`n  ✗→ リンク切れの外部リンク`n  ✗   未解決`n`nバックエンド:`n  Tag       PowerPoint の既存タグ`n  Manifest  補助 JSON (sources_list.json)`n  External  現在の外部リンク先`n`nMatchMethod（判定方法）:`n  PASTE            貼り付け時に記録`n  RETRO_SCAN       Re-scan で解決`n  RETRO_MANUAL     Manual Pick で指定`n  RETRO_UNRESOLVED Re-scan 後も未解決`n  EXTERNAL         外部リンク`n`nExportStatus（書き出し状態）:`n  none        未書き出し`n  copied      sources フォルダへコピー済み`n  manual      Manual Pick 由来`n  unresolved  未解決として書き出し`n`nForeign（外部更新行）:`n  InsertedBy が現在の user@PC と異なる row`n`nショートカット:`n  Ctrl+Alt+E  ソースマネージャーを開く`n  Ctrl+Alt+Q  現在のタグ情報を表示`n  Ctrl+Alt+F1 このヘルプを開く",
        'Source Manager Help',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information
    ) | Out-Null
})
$windowRefs.ExportButton.Add_Click({
    if (Confirm-PresentationSavedForAction -PptPath $appState.PptPath -ActionLabel 'Export Sources' -Logger $appState.Logger) {
        try {
            $exportOk = Export-RowsToSources -AppState $appState -WindowRefs $windowRefs
            if ($exportOk) {
                $appState.HasUnsavedChanges = $false
                $appState.IsStale = $false
                $appState.LastCommittedRows = Copy-ManagerRows -Rows @($appState.Rows)
                Update-IdleSummary -AppState $appState -WindowRefs $windowRefs
            }
        } catch {
            $detail = Format-ExceptionDetail -ExceptionRecord $_
            Write-TraceLog -Logger $appState.Logger -Message ('export button error: {0}' -f $detail) -Error
            Add-LogLine -WindowRefs $windowRefs -Text ('ERROR: Export Sources failed: {0}' -f $detail)
            Reset-ProgressIndicators -WindowRefs $windowRefs -Stage 'Error'
            [System.Windows.MessageBox]::Show(
                ("Export Sources の実行中にエラーが発生しました。`n`n{0}" -f $detail),
                'Source Manager Error',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            ) | Out-Null
        }
    }
})
$windowRefs.ManualButton.Add_Click({
    if (Confirm-PresentationSavedForAction -PptPath $appState.PptPath -ActionLabel 'Manual Pick' -Logger $appState.Logger) {
        Set-SelectedRowManualPath -AppState $appState -WindowRefs $windowRefs
        $appState.HasUnsavedChanges = $false
        $appState.IsStale = $false
        $appState.LastCommittedRows = Copy-ManagerRows -Rows @($appState.Rows)
        Update-IdleSummary -AppState $appState -WindowRefs $windowRefs
    }
})
$windowRefs.RescanButton.Add_Click({
    $actionLabel = if (($windowRefs.RescanButton.Content + '') -eq 'Scan') { 'Scan' } else { 'Re-scan' }
    if (Confirm-PresentationSavedForAction -PptPath $appState.PptPath -ActionLabel $actionLabel -Logger $appState.Logger) {
        Start-ScanWorker -AppState $appState -WindowRefs $windowRefs
    }
})
$windowRefs.CancelButton.Add_Click({
    if (($windowRefs.CancelButton.Content + '') -eq 'Force Stop') {
        Force-StopScanWorker -AppState $appState
        Replace-ManagerRows -AppState $appState -WindowRefs $windowRefs -Rows (Copy-ManagerRows -Rows @($appState.LastCommittedRows))
        $windowRefs.CancelButton.Visibility = 'Collapsed'
        $windowRefs.CancelButton.IsEnabled = $true
        $windowRefs.CancelButton.Content = 'Cancel'
        $windowRefs.StageLabel.Text = 'Cancelled'
        Update-IdleSummary -AppState $appState -WindowRefs $windowRefs
        $windowRefs.SummaryLabel.Text = "Force Stop を実行しました。前回の結果を保持しました。`n" + $windowRefs.SummaryLabel.Text
        Add-LogLine -WindowRefs $windowRefs -Text 'Force stop requested from manager UI.'
    } else {
        Stop-ScanWorker -AppState $appState
        $windowRefs.CancelButton.IsEnabled = $true
        $windowRefs.CancelButton.Content = 'Force Stop'
        $windowRefs.SummaryLabel.Text = 'Stopping... もう一度押すと Force Stop します。'
    }
})

$contextMenu = New-Object System.Windows.Controls.ContextMenu
foreach ($definition in @(
        @{ Header = 'Manual Pick'; Action = { Set-SelectedRowManualPath -AppState $appState -WindowRefs $windowRefs } },
        @{ Header = 'Details'; Action = { if ($windowRefs.ResultsList.SelectedItem) { Show-RowDetailsDialog -Owner $window -Row $windowRefs.ResultsList.SelectedItem } } },
        @{ Header = 'Copy source path'; Action = { if ($windowRefs.ResultsList.SelectedItem -and $windowRefs.ResultsList.SelectedItem.SourcePath) { [System.Windows.Clipboard]::SetText($windowRefs.ResultsList.SelectedItem.SourcePath) } } },
        @{ Header = 'Copy media name'; Action = { if ($windowRefs.ResultsList.SelectedItem -and $windowRefs.ResultsList.SelectedItem.MediaFullName) { [System.Windows.Clipboard]::SetText($windowRefs.ResultsList.SelectedItem.MediaFullName) } } },
        @{ Header = 'Open source folder'; Action = { if ($windowRefs.ResultsList.SelectedItem -and $windowRefs.ResultsList.SelectedItem.SourcePath -and (Test-Path -LiteralPath $windowRefs.ResultsList.SelectedItem.SourcePath)) { Start-Process -FilePath ([System.IO.Path]::GetDirectoryName($windowRefs.ResultsList.SelectedItem.SourcePath)) } } }
    )) {
    $item = New-Object System.Windows.Controls.MenuItem
    $item.Header = $definition.Header
    $item.Add_Click($definition.Action)
    $contextMenu.Items.Add($item) | Out-Null
}
$windowRefs.ResultsList.ContextMenu = $contextMenu

$queueTimer = New-Object System.Windows.Threading.DispatcherTimer
$queueTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$queueTimer.Add_Tick({
    try {
        $item = $null
        while ($appState.Queue.TryDequeue([ref]$item)) {
            $itemType = if ($item -and $item.PSObject.Properties['Type']) { ($item.Type + '') } else { '' }
            $itemMediaId = if ($item -and $item.PSObject.Properties['MediaId']) { ($item.MediaId + '') } else { '' }
            $itemRowCount = if ($item -and $item.PSObject.Properties['Rows'] -and $item.Rows) { @($item.Rows).Count } else { 0 }
            Write-TraceLog -Logger $appState.Logger -Message ('queue event begin: type={0} media_id={1} rows={2} ui_rows={3}' -f $itemType, $itemMediaId, $itemRowCount, $appState.Rows.Count)
            switch ($item.Type) {
                'map_built' {
                    $localIdentity = Get-LocalIdentityTag
                    foreach ($rawRow in $item.Rows) {
                        $rawExternalPath = if ($rawRow.PSObject.Properties['ExternalPath']) { ($rawRow.ExternalPath + '') } else { '' }
                        $rawMediaFile = ($rawRow.MediaFile + '')
                        $rawMediaFullName = if ($rawMediaFile) { $rawMediaFile } else { '(external)' }
                        $rawSourcePath = if ($rawRow.PSObject.Properties['SourcePath']) { ($rawRow.SourcePath + '') } else { '' }
                        $rawBackend = if ($rawRow.PSObject.Properties['Backend']) { ($rawRow.Backend + '') } else { '' }
                        $rawStatusKind = if ($rawRow.PSObject.Properties['StatusKind']) { ($rawRow.StatusKind + '') } else { '' }
                        $rawStatusDisplay = if ($rawRow.PSObject.Properties['StatusDisplay']) { ($rawRow.StatusDisplay + '') } else { '' }
                        $rawPreviewPath = if ($rawRow.PSObject.Properties['PreviewPath']) { ($rawRow.PreviewPath + '') } else { '' }
                        $rawMatchMethod = if ($rawRow.PSObject.Properties['MatchMethod']) { ($rawRow.MatchMethod + '') } else { '' }
                        $rawInsertedBy = if ($rawRow.PSObject.Properties['InsertedBy']) { ($rawRow.InsertedBy + '') } else { '' }
                        $rawLastVerifiedAt = if ($rawRow.PSObject.Properties['LastVerifiedAt']) { ($rawRow.LastVerifiedAt + '') } else { '' }
                        $rawNeedsResolve = if ($rawRow.PSObject.Properties['NeedsResolve']) { [bool]$rawRow.NeedsResolve } else { $true }
                        $rawSourceExists = if ($rawRow.PSObject.Properties['SourceExists']) { [bool]$rawRow.SourceExists } else { $false }
                        $statusKind = if ($rawStatusKind) { $rawStatusKind } else { 'pending' }
                        $statusDisplay = if ($rawStatusDisplay) { $rawStatusDisplay } else { Get-StatusDisplayForKind -Kind $statusKind }
                        $appState.Rows.Add([pscustomobject]@{
                                MediaId = ($rawRow.MediaId + ''); Slide = [int]$rawRow.Slide; MediaFile = $rawMediaFile
                                MediaDisplay = (Get-MediaDisplayLabel -MediaFile $rawMediaFile)
                                MediaFullName = $rawMediaFullName
                                SourcePath = $rawSourcePath
                                SourceDisplay = if ($rawSourcePath) { $rawSourcePath } else { '未解決' }
                                Backend = $rawBackend
                                BackendDisplay = (Get-BackendDisplayLabel -Backend $rawBackend)
                                StatusDisplay = $statusDisplay
                                StatusKind = $statusKind
                                SourceExists = $rawSourceExists
                                PreviewPath = if ($rawPreviewPath) { $rawPreviewPath } elseif ($rawSourceExists) { $rawSourcePath } else { '' }
                                EmbeddedPath = ($rawRow.EmbeddedPath + ''); ExternalPath = $rawExternalPath; ExportStatus = ''
                                Shapes = @($rawRow.Shapes); DestinationPath = ''
                                MatchMethod = $rawMatchMethod
                                InsertedBy = $rawInsertedBy
                                LastVerifiedAt = $rawLastVerifiedAt
                                IsForeign = [bool]($rawInsertedBy -and $rawInsertedBy -ne $localIdentity)
                                NeedsResolve = $rawNeedsResolve
                            })
                    }
                    $runningIndex = Get-NextResolvableRowIndex -Rows @($appState.Rows) -StartIndex 0
                    if ($runningIndex -ge 0) {
                        $appState.Rows[$runningIndex].StatusKind = 'running'
                        $appState.Rows[$runningIndex].StatusDisplay = 'Running'
                    }
                    $windowRefs.ResultsList.Items.Refresh()
                    Add-LogLine -WindowRefs $windowRefs -Text ('Media map: {0} items' -f $appState.Rows.Count)
                }
                'resolved' { Apply-ResolvedUiRow -AppState $appState -WindowRefs $windowRefs -Message $item }
                'done' {
                    Complete-Worker -AppState $appState
                    $windowRefs.CancelButton.Visibility = 'Collapsed'
                    $windowRefs.CancelButton.IsEnabled = $true
                    $windowRefs.CancelButton.Content = 'Cancel'
                    $windowRefs.ExportButton.IsEnabled = $true
                    $windowRefs.RescanButton.IsEnabled = $true
                    $windowRefs.StageLabel.Text = 'Applying'
                    $windowRefs.SummaryLabel.Text = 'PowerPoint へタグ適用中...'
                    Add-LogLine -WindowRefs $windowRefs -Text 'Scan complete. Waiting for PowerPoint tag sync.'
                }
                'cancelled' {
                    Complete-Worker -AppState $appState
                    Replace-ManagerRows -AppState $appState -WindowRefs $windowRefs -Rows (Copy-ManagerRows -Rows @($appState.LastCommittedRows))
                    $windowRefs.StageLabel.Text = 'Cancelled'
                    $windowRefs.CancelButton.Visibility = 'Collapsed'
                    $windowRefs.CancelButton.IsEnabled = $true
                    $windowRefs.CancelButton.Content = 'Cancel'
                    $windowRefs.RescanButton.IsEnabled = $true
                    Update-IdleSummary -AppState $appState -WindowRefs $windowRefs
                    $windowRefs.SummaryLabel.Text = "Scan cancelled. 前回の結果を保持しました。`n" + $windowRefs.SummaryLabel.Text
                }
                'error' {
                    Complete-Worker -AppState $appState
                    Replace-ManagerRows -AppState $appState -WindowRefs $windowRefs -Rows (Copy-ManagerRows -Rows @($appState.LastCommittedRows))
                    $windowRefs.StageLabel.Text = 'Error'
                    $windowRefs.CancelButton.Visibility = 'Collapsed'
                    $windowRefs.CancelButton.IsEnabled = $true
                    $windowRefs.CancelButton.Content = 'Cancel'
                    $windowRefs.RescanButton.IsEnabled = $true
                    Update-IdleSummary -AppState $appState -WindowRefs $windowRefs
                    $windowRefs.SummaryLabel.Text = ('Scan error: {0}`n{1}' -f $item.Error, $windowRefs.SummaryLabel.Text)
                    Add-LogLine -WindowRefs $windowRefs -Text ('ERROR: {0}' -f $item.Error)
                }
            }
            Write-TraceLog -Logger $appState.Logger -Message ('queue event end: type={0} media_id={1} ui_rows={2}' -f $itemType, $itemMediaId, $appState.Rows.Count)
        }
    } catch {
        $itemType = if ($item -and $item.PSObject.Properties['Type']) { ($item.Type + '') } else { '' }
        $itemMediaId = if ($item -and $item.PSObject.Properties['MediaId']) { ($item.MediaId + '') } else { '' }
        $itemRowCount = if ($item -and $item.PSObject.Properties['Rows'] -and $item.Rows) { @($item.Rows).Count } else { 0 }
        $workerActive = [bool]($appState.Worker -and $appState.WorkerHandle -and -not $appState.WorkerHandle.IsCompleted)
        Write-TraceLog -Logger $appState.Logger -Message ('queue timer error: {0} | item_type={1} media_id={2} payload_rows={3} ui_rows={4} worker_active={5}' -f (Format-ExceptionDetail -ExceptionRecord $_), $itemType, $itemMediaId, $itemRowCount, $appState.Rows.Count, $workerActive) -Error
        throw
    }
})
$queueTimer.Start()

$statusTimer = New-Object System.Windows.Threading.DispatcherTimer
$statusTimer.Interval = [TimeSpan]::FromMilliseconds(300)
$statusTimer.Add_Tick({
    try {
        if (Test-Path -LiteralPath $appState.StatusPath) {
            $text = Get-FileTextUtf8 -Path $appState.StatusPath
            if ($text) {
                $status = @{}
                foreach ($line in ($text -split "`r?`n")) {
                    if (-not $line) { continue }
                    $sep = $line.IndexOf('=')
                    if ($sep -le 0) { continue }
                    $status[$line.Substring(0, $sep)] = $line.Substring($sep + 1)
                }
                $appState.Status = $status
                Update-ProgressLabels -WindowRefs $windowRefs -Status $status
            }
        }
        if ($appState.RescanPath -and (Test-Path -LiteralPath $appState.RescanPath) -and -not ($appState.Worker -and $appState.WorkerHandle -and -not $appState.WorkerHandle.IsCompleted)) {
            Remove-Item -LiteralPath $appState.RescanPath -Force -ErrorAction SilentlyContinue
            Write-TraceLog -Logger $appState.Logger -Message 'rescan request consumed from AHK'
            Start-ScanWorker -AppState $appState -WindowRefs $windowRefs
        }
        if ($appState.SyncPath -and (Test-Path -LiteralPath $appState.SyncPath) -and -not ($appState.Worker -and $appState.WorkerHandle -and -not $appState.WorkerHandle.IsCompleted)) {
            $syncText = Get-FileTextUtf8 -Path $appState.SyncPath
            Remove-Item -LiteralPath $appState.SyncPath -Force -ErrorAction SilentlyContinue
            $parts = @(($syncText + '') -split '\|', 2)
            $syncCode = if ($parts.Count -gt 0) { $parts[0] } else { '' }
            $syncDetail = if ($parts.Count -gt 1) { $parts[1] } else { '' }
            switch ($syncCode) {
                'apply_ok' {
                    try {
                        $layout = Get-SourcesLayout -PptPath $appState.PptPath
                        Write-ManifestFile -ManifestPath $layout.ManifestPath -PptPath $appState.PptPath -Rows @($appState.Rows)
                        $appState.ManifestPath = $layout.ManifestPath
                        $appState.ManifestMeta = Get-ManifestMetadata -ManifestPath $layout.ManifestPath
                        $appState.HasUnsavedChanges = $false
                        $appState.IsStale = $false
                        $appState.LastCommittedRows = Copy-ManagerRows -Rows @($appState.Rows)
                        $windowRefs.StageLabel.Text = 'Ready'
                        Update-IdleSummary -AppState $appState -WindowRefs $windowRefs
                        Add-LogLine -WindowRefs $windowRefs -Text 'PowerPoint tag sync committed.'
                    } catch {
                        $appState.HasUnsavedChanges = $false
                        $appState.LastCommittedRows = Copy-ManagerRows -Rows @($appState.Rows)
                        $appState.IsStale = $true
                        $windowRefs.StageLabel.Text = 'Warning'
                        Update-IdleSummary -AppState $appState -WindowRefs $windowRefs
                        $windowRefs.SummaryLabel.Text = ('manifest sync failed after tag apply: {0}`n{1}' -f (Format-ExceptionDetail -ExceptionRecord $_), $windowRefs.SummaryLabel.Text)
                        Add-LogLine -WindowRefs $windowRefs -Text ('WARN: manifest sync failed after tag apply: {0}' -f (Format-ExceptionDetail -ExceptionRecord $_))
                    }
                }
                'apply_skipped' {
                    Replace-ManagerRows -AppState $appState -WindowRefs $windowRefs -Rows (Copy-ManagerRows -Rows @($appState.LastCommittedRows))
                    $appState.IsStale = $true
                    $windowRefs.StageLabel.Text = 'Ready'
                    Update-IdleSummary -AppState $appState -WindowRefs $windowRefs
                    $windowRefs.SummaryLabel.Text = ('PowerPoint tag apply was skipped: {0}`n{1}' -f $syncDetail, $windowRefs.SummaryLabel.Text)
                    Add-LogLine -WindowRefs $windowRefs -Text ('WARN: PowerPoint tag apply skipped: {0}' -f $syncDetail)
                }
                'apply_failed' {
                    Replace-ManagerRows -AppState $appState -WindowRefs $windowRefs -Rows (Copy-ManagerRows -Rows @($appState.LastCommittedRows))
                    $appState.IsStale = $true
                    $windowRefs.StageLabel.Text = 'Error'
                    Update-IdleSummary -AppState $appState -WindowRefs $windowRefs
                    $windowRefs.SummaryLabel.Text = ('PowerPoint tag apply failed: {0}`n{1}' -f $syncDetail, $windowRefs.SummaryLabel.Text)
                    Add-LogLine -WindowRefs $windowRefs -Text ('ERROR: PowerPoint tag apply failed: {0}' -f $syncDetail)
                }
            }
        }
        $windowRefs.ElapsedLabel.Text = ('{0:n1}s' -f ((Get-Date) - $appState.StartTime).TotalSeconds)
    } catch {
        $statusStage = if ($appState.Status -and $appState.Status.ContainsKey('stage')) { ($appState.Status['stage'] + '') } else { '' }
        $syncExists = [bool]($appState.SyncPath -and (Test-Path -LiteralPath $appState.SyncPath))
        $rescanExists = [bool]($appState.RescanPath -and (Test-Path -LiteralPath $appState.RescanPath))
        $workerActive = [bool]($appState.Worker -and $appState.WorkerHandle -and -not $appState.WorkerHandle.IsCompleted)
        Write-TraceLog -Logger $appState.Logger -Message ('status timer error: {0} | stage={1} sync_exists={2} rescan_exists={3} worker_active={4}' -f (Format-ExceptionDetail -ExceptionRecord $_), $statusStage, $syncExists, $rescanExists, $workerActive) -Error
        return
    }
})
$statusTimer.Start()

$window.Add_Closing({
    $queueTimer.Stop()
    $statusTimer.Stop()
    if ($appState.Worker -and $appState.WorkerHandle -and -not $appState.WorkerHandle.IsCompleted) {
        Stop-ScanWorker -AppState $appState
        $deadline = (Get-Date).AddSeconds(2)
        while ($appState.WorkerHandle -and -not $appState.WorkerHandle.IsCompleted -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 100
        }
        if ($appState.WorkerHandle -and -not $appState.WorkerHandle.IsCompleted) {
            Force-StopScanWorker -AppState $appState
        }
    }
    Complete-Worker -AppState $appState
    Remove-DirectorySafe -Path $appState.ScanTempDir
})

$windowRefs.ExportButton.IsEnabled = $false
$windowRefs.ManualButton.IsEnabled = $false
$windowRefs.RescanButton.IsEnabled = $true
$windowRefs.CancelButton.Visibility = 'Collapsed'
$windowRefs.SummaryLabel.Text = ''
try { Update-ResultsListLayout -WindowRefs $windowRefs } catch {}
if ($Mode -eq 'scan') {
    $windowRefs.StageLabel.Text = 'Preparing'
    $windowRefs.ProgressBar.IsIndeterminate = $true
    $windowRefs.ProgressBar.Value = 0
    $windowRefs.ProgressLabel.Text = ''
    $windowRefs.SummaryLabel.Text = 'スキャン開始中...'
} else {
    $windowRefs.StageLabel.Text = 'Opening'
    $windowRefs.ProgressBar.IsIndeterminate = $true
    $windowRefs.ProgressBar.Value = 0
    $windowRefs.ProgressLabel.Text = ''
    $windowRefs.SummaryLabel.Text = '起動時検証中...'
}

$window.Add_ContentRendered({
    try {
        Update-ResultsListLayout -WindowRefs $windowRefs
    } catch {
    }
    if ($appState.StartupInitialized) {
        return
    }
    $appState.StartupInitialized = $true

    if ($Mode -eq 'scan') {
        Start-ScanWorker -AppState $appState -WindowRefs $windowRefs
        return
    }

    try {
        Set-StaticProgressState -WindowRefs $windowRefs -Stage 'Opening' -Message 'マニフェストを確認しています...'
        $appState.ManifestMeta = Get-ManifestMetadata -ManifestPath $appState.ManifestPath
        Set-StaticProgressState -WindowRefs $windowRefs -Stage 'Opening' -Message 'PowerPoint の保存状態を確認しています...'
        $appState.HasUnsavedChanges = Get-PresentationDirtyState -PptPath $appState.PptPath -Logger $appState.Logger
        Set-StaticProgressState -WindowRefs $windowRefs -Stage 'Opening' -Message '既存の source row を復元しています...'
        foreach ($row in (New-StartupRows -PptPath $appState.PptPath -ManifestPath $appState.ManifestPath -Logger $appState.Logger)) {
            $appState.Rows.Add($row)
        }
        $appState.IsStale = Test-StartupStale -PptPath $appState.PptPath -ManifestMeta $appState.ManifestMeta -HasUnsavedChanges $appState.HasUnsavedChanges -Rows @($appState.Rows)
        Verify-StartupRows -AppState $appState -WindowRefs $windowRefs
        $appState.LastCommittedRows = Copy-ManagerRows -Rows @($appState.Rows)
        Initialize-StartupPreviewSelection -AppState $appState -WindowRefs $windowRefs
        if ($appState.Rows.Count -gt 0) {
            Add-LogLine -WindowRefs $windowRefs -Text ('Startup rows loaded: {0}' -f $appState.Rows.Count)
        } else {
            Add-LogLine -WindowRefs $windowRefs -Text 'No previous source rows were restored.'
        }
    } catch {
        $detail = Format-ExceptionDetail -ExceptionRecord $_
        Write-TraceLog -Logger $appState.Logger -Message ('startup initialization error: {0}' -f $detail) -Error
        [System.Windows.MessageBox]::Show(
            ("Source manager の起動中にエラーが発生しました。`n`n{0}`n`n詳細ログ: {1}" -f $detail, $StderrPath),
            'Source Manager Error',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
        $window.Close()
    }
})

[void]$window.ShowDialog()
