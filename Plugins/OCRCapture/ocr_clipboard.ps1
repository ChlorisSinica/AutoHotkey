$OutputPath = if ($args.Count -ge 1 -and $args[0]) { [string]$args[0] } else { '' }
if (-not $OutputPath) {
    Write-Error 'Usage: ocr_clipboard.ps1 <outputPath>'
    exit 2
}

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

# --- WPF assembly (clipboard access) ---
Add-Type -AssemblyName PresentationCore

# --- WinRT async helper ---
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object {
        $_.Name -eq 'AsTask' -and
        $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    })[0]

function Await($WinRtTask, $ResultType) {
    $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    $netTask.Result
}

# --- Load WinRT OCR types ---
[void][Windows.Media.Ocr.OcrEngine,           Windows.Foundation.UniversalApiContract, ContentType = WindowsRuntime]
[void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation.UniversalApiContract, ContentType = WindowsRuntime]
[void][Windows.Graphics.Imaging.SoftwareBitmap,Windows.Foundation.UniversalApiContract, ContentType = WindowsRuntime]

# --- Read clipboard image ---
$bitmapSource = [System.Windows.Clipboard]::GetImage()
if (-not $bitmapSource) {
    Write-Error 'No image in clipboard'
    exit 1
}

# --- Convert BitmapSource to stream ---
$encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
$encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmapSource))
$ms = New-Object System.IO.MemoryStream
$encoder.Save($ms)
$ms.Position = 0

# --- Decode as WinRT SoftwareBitmap ---
$ras = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($ms)
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($ras)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap  = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])

# --- Run OCR ---
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if (-not $engine) {
    Write-Error 'Failed to create OCR engine'
    $ms.Dispose()
    exit 2
}
$result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])

# --- Build text with CJK-aware word joining ---
# OcrResult.Text inserts spaces between every Word, which breaks CJK text.
# Join words without space when either adjacent character is CJK.
function Test-IsCJK([char]$c) {
    $code = [int]$c
    return ($code -ge 0x3000 -and $code -le 0x9FFF) -or
           ($code -ge 0xF900 -and $code -le 0xFAFF) -or
           ($code -ge 0xFF00 -and $code -le 0xFFEF) -or
           ($code -ge 0xAC00 -and $code -le 0xD7AF)
}

$lines = @()
foreach ($line in $result.Lines) {
    $lineText = ''
    $prevWord = $null
    foreach ($word in $line.Words) {
        if ($prevWord -and $prevWord.Text.Length -gt 0 -and $word.Text.Length -gt 0) {
            $lastChar = $prevWord.Text[$prevWord.Text.Length - 1]
            $firstChar = $word.Text[0]
            if (-not (Test-IsCJK $lastChar) -and -not (Test-IsCJK $firstChar)) {
                $lineText += ' '
            }
        }
        $lineText += $word.Text
        $prevWord = $word
    }
    $lines += $lineText
}
$text = $lines -join "`r`n"

# --- Write result ---
$parentDir = [System.IO.Path]::GetDirectoryName($OutputPath)
if ($parentDir -and -not (Test-Path -LiteralPath $parentDir -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $parentDir -Force)
}
[System.IO.File]::WriteAllText($OutputPath, $text, [System.Text.Encoding]::UTF8)

# --- Cleanup ---
$ms.Dispose()
exit 0
