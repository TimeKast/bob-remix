<#
.SYNOPSIS
    Debug script to check what colors are being detected in the chat button area
#>

param(
    [string]$WindowTitle = "Inversa"
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FastDetector {
    [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("gdi32.dll")] public static extern uint GetPixel(IntPtr hdc, int x, int y);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

$proc = Get-Process | Where-Object { $_.MainWindowTitle -like "*$WindowTitle*" } | Select-Object -First 1
if (-not $proc) { 
    Write-Host "Window with '$WindowTitle' not found"
    exit 
}

$hwnd = $proc.MainWindowHandle
$rect = New-Object FastDetector+RECT
[FastDetector]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
$hdc = [FastDetector]::GetDC([IntPtr]::Zero)

$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top

Write-Host "Window: $($proc.MainWindowTitle.Substring(0, [Math]::Min(40, $proc.MainWindowTitle.Length)))"
Write-Host "Size: ${width}x${height}"
Write-Host "Position: Left=$($rect.Left) Top=$($rect.Top) Right=$($rect.Right) Bottom=$($rect.Bottom)"
Write-Host ""
Write-Host "Sampling bottom-right corner (chat button area):"
Write-Host "Format: (X,Y) -> R=red G=green B=blue | Classification"
Write-Host ""

foreach ($xOffset in @(10, 15, 20, 25, 30, 40, 50)) {
    foreach ($yOffset in @(25, 30, 35, 40, 50, 60, 70)) {
        $x = $rect.Right - $xOffset
        $y = $rect.Bottom - $yOffset
        $pixel = [FastDetector]::GetPixel($hdc, $x, $y)
        $r = $pixel -band 0xFF
        $g = ($pixel -shr 8) -band 0xFF
        $b = ($pixel -shr 16) -band 0xFF
        
        # Classify the color
        $isGray = ($r -ge 100 -and $r -le 180 -and $g -ge 100 -and $g -le 180 -and $b -ge 100 -and $b -le 180)
        $isSimilar = ([Math]::Abs($r - $g) -lt 20 -and [Math]::Abs($g - $b) -lt 20)
        $isRed = ($r -ge 150 -and $g -lt 100 -and $b -lt 100)
        $isBlue = ($r -lt 100 -and $g -ge 100 -and $b -ge 150)
        
        $class = "OTHER"
        if ($isGray -and $isSimilar) { $class = "GRAY (ready)" }
        elseif ($isRed) { $class = "RED (working)" }
        elseif ($isBlue) { $class = "BLUE (ready)" }
        
        Write-Host "  Offset(-$xOffset,-$yOffset) -> R=$($r.ToString().PadLeft(3)) G=$($g.ToString().PadLeft(3)) B=$($b.ToString().PadLeft(3)) | $class"
    }
}
