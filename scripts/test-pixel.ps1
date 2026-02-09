param([int64]$WindowHandle)

Add-Type @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;

public class CaptureHelper {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
    
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    
    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
    
    [DllImport("gdi32.dll")]
    public static extern IntPtr CreateCompatibleDC(IntPtr hdc);
    
    [DllImport("gdi32.dll")]
    public static extern IntPtr CreateCompatibleBitmap(IntPtr hdc, int nWidth, int nHeight);
    
    [DllImport("gdi32.dll")]
    public static extern IntPtr SelectObject(IntPtr hdc, IntPtr hgdiobj);
    
    [DllImport("gdi32.dll")]
    public static extern uint GetPixel(IntPtr hdc, int x, int y);
    
    [DllImport("gdi32.dll")]
    public static extern bool DeleteObject(IntPtr hObject);
    
    [DllImport("gdi32.dll")]
    public static extern bool DeleteDC(IntPtr hdc);
    
    [DllImport("user32.dll")]
    public static extern IntPtr GetDC(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    
    public const uint PW_RENDERFULLCONTENT = 0x00000002;
}
"@

[CaptureHelper]::SetProcessDPIAware() | Out-Null

$hwnd = [IntPtr]$WindowHandle

$wr = New-Object CaptureHelper+RECT
[CaptureHelper]::GetWindowRect($hwnd, [ref]$wr) | Out-Null
$w = $wr.Right - $wr.Left
$h = $wr.Bottom - $wr.Top

Write-Host "Window: L=$($wr.Left) T=$($wr.Top) R=$($wr.Right) B=$($wr.Bottom) Size=${w}x${h}"

# Capture window using PrintWindow
$screenDC = [CaptureHelper]::GetDC([IntPtr]::Zero)
$memDC = [CaptureHelper]::CreateCompatibleDC($screenDC)
$bitmap = [CaptureHelper]::CreateCompatibleBitmap($screenDC, $w, $h)
$oldBmp = [CaptureHelper]::SelectObject($memDC, $bitmap)
[CaptureHelper]::ReleaseDC([IntPtr]::Zero, $screenDC) | Out-Null

# PrintWindow with PW_RENDERFULLCONTENT for modern apps
$result = [CaptureHelper]::PrintWindow($hwnd, $memDC, [CaptureHelper]::PW_RENDERFULLCONTENT)
Write-Host "PrintWindow result: $result"

# Test pixels at various positions
Write-Host "`n=== PrintWindow capture (window-relative coords) ==="
foreach ($xp in @(0.3, 0.5, 0.7, 0.85, 0.9, 0.95)) {
    foreach ($yp in @(0.3, 0.5, 0.7, 0.85, 0.9, 0.95, 0.98)) {
        $x = [int]($w * $xp)
        $y = [int]($h * $yp)
        $px = [CaptureHelper]::GetPixel($memDC, $x, $y)
        $r = $px -band 0xFF; $g = ($px -shr 8) -band 0xFF; $b = ($px -shr 16) -band 0xFF
        $label = ""
        if ($r -ge 180 -and $g -lt 100 -and $b -lt 100) { $label = " <<RED>>" }
        if ($r -lt 100 -and $g -ge 100 -and $b -ge 180) { $label = " <<BLUE>>" }
        if ($r -ge 100 -and $r -le 180 -and $g -ge 100 -and $g -le 180 -and $b -ge 100 -and $b -le 180) {
            $sim = [Math]::Abs($r - $g) -lt 20 -and [Math]::Abs($g - $b) -lt 20
            if ($sim) { $label = " <<GRAY>>" }
        }
        Write-Host ("  ({0:P0},{1:P0}) pos=({2},{3}) = R{4} G{5} B{6}{7}" -f $xp, $yp, $x, $y, $r, $g, $b, $label)
    }
}

# Cleanup
[CaptureHelper]::SelectObject($memDC, $oldBmp) | Out-Null
[CaptureHelper]::DeleteObject($bitmap) | Out-Null
[CaptureHelper]::DeleteDC($memDC) | Out-Null
