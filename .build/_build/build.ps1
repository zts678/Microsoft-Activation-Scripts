# Build MAS_AIO.exe - standalone wrapper for MAS_AIO.cmd
# Usage: powershell -ExecutionPolicy Bypass -File build.ps1
$ErrorActionPreference = 'Stop'

$buildDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir  = Split-Path -Parent $buildDir
$srcCmd   = Join-Path $rootDir 'MAS_AIO.cmd'
$outExe   = Join-Path $rootDir 'MAS_AIO.exe'
$csTpl    = Join-Path $buildDir 'Launcher.cs'
$manifest = Join-Path $buildDir 'app.manifest'
$genCs    = Join-Path $buildDir 'Launcher.gen.cs'

if (-not (Test-Path $srcCmd))   { throw "Source script not found: $srcCmd" }
if (-not (Test-Path $csTpl))    { throw "Launcher template not found: $csTpl" }
if (-not (Test-Path $manifest)) { throw "Manifest not found: $manifest" }

# 1. Read original script bytes (must stay byte-for-byte identical: CRLF, no BOM)
Write-Host "[1/5] Reading $srcCmd"
$bytes = [System.IO.File]::ReadAllBytes($srcCmd)
Write-Host "      Payload size: $($bytes.Length) bytes"

# 2. GZip compress + Base64 encode
Write-Host "[2/5] Compressing payload (GZip + Base64)"
$ms = New-Object System.IO.MemoryStream
$gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Compress, $true)
$gz.Write($bytes, 0, $bytes.Length)
$gz.Close()
$gzBytes = $ms.ToArray()
$ms.Close()
$b64 = [Convert]::ToBase64String($gzBytes)
Write-Host "      Compressed: $($gzBytes.Length) bytes / Base64: $($b64.Length) chars"

# 3. Inject payload into C# source (UTF-8 without BOM)
Write-Host "[3/5] Generating Launcher source"
$tpl = [System.IO.File]::ReadAllText($csTpl, [System.Text.Encoding]::UTF8)
if (-not $tpl.Contains('__PAYLOAD_BASE64__')) { throw 'Payload placeholder not found in Launcher.cs' }
$gen = $tpl.Replace('__PAYLOAD_BASE64__', $b64)
[System.IO.File]::WriteAllText($genCs, $gen, (New-Object System.Text.UTF8Encoding($false)))

# 4. Optional: build a proper multi-resolution .ico from ..\logo.png
#    Every entry is PNG-encoded (lossless, full 32-bit alpha). The 256x256 entry
#    embeds the original PNG bytes directly; smaller sizes are downscaled with
#    HighQualityBicubic. This avoids GDI GetHicon()/Icon.Save() which mangles
#    colors and transparency.
$iconArg = @()
$logoPng = Join-Path $rootDir 'logo.png'
$logoIco = Join-Path $buildDir 'logo.ico'
if (Test-Path $logoPng) {
    Write-Host "[4/5] Building multi-resolution logo.ico"
    Add-Type -AssemblyName System.Drawing
    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $pngOrig = [System.IO.File]::ReadAllBytes($logoPng)
    $srcImg = [System.Drawing.Image]::FromFile($logoPng)
    $entries = New-Object 'System.Collections.Generic.List[byte[]]'
    foreach ($sz in $sizes) {
        if ($sz -eq 256 -and $srcImg.Width -eq 256 -and $srcImg.Height -eq 256) {
            $entries.Add($pngOrig)  # pixel-perfect original
            continue
        }
        $bmp = New-Object System.Drawing.Bitmap $sz, $sz, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.Clear([System.Drawing.Color]::Transparent)
        $g.DrawImage($srcImg, 0, 0, $sz, $sz)
        $g.Dispose()
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        $entries.Add($ms.ToArray())
        $ms.Close()
    }
    $srcImg.Dispose()

    # Assemble ICO file: 6-byte header + 16-byte directory per entry + image data
    $out = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter $out
    $bw.Write([UInt16]0)                       # reserved
    $bw.Write([UInt16]1)                       # type = icon
    $bw.Write([UInt16]$entries.Count)          # number of images
    $offset = 6 + 16 * $entries.Count
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $sz = $sizes[$i]
        $d = $entries[$i]
        $dim = if ($sz -ge 256) { [Byte]0 } else { [Byte]$sz }   # 0 means 256
        $bw.Write($dim)                        # width
        $bw.Write($dim)                        # height
        $bw.Write([Byte]0)                     # palette color count
        $bw.Write([Byte]0)                     # reserved
        $bw.Write([UInt16]1)                   # color planes
        $bw.Write([UInt16]32)                  # bits per pixel
        $bw.Write([UInt32]$d.Length)           # image data size
        $bw.Write([UInt32]$offset)             # image data offset
        $offset += $d.Length
    }
    foreach ($d in $entries) { $bw.Write($d) }
    [System.IO.File]::WriteAllBytes($logoIco, $out.ToArray())
    $bw.Close(); $out.Close()
    $iconArg = @('/win32icon:' + $logoIco)
    Write-Host ("      Icon embedded ({0} sizes: {1})" -f $entries.Count, ($sizes -join ', '))
}

# 5. Compile with in-box .NET Framework C# compiler (AnyCPU -> 64-bit on x64)
$csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw 'csc.exe (.NET Framework compiler) not found' }

Write-Host "[5/5] Compiling with csc.exe"
& $csc /nologo /target:exe /platform:anycpu /optimize+ /out:"$outExe" /win32manifest:"$manifest" @iconArg "$genCs"
if ($LASTEXITCODE -ne 0) { throw "csc.exe failed (exit $LASTEXITCODE)" }

Remove-Item $genCs -Force -ErrorAction SilentlyContinue

$fi = Get-Item $outExe
Write-Host ""
Write-Host ("BUILD OK: {0} ({1} bytes)" -f $fi.FullName, $fi.Length)
