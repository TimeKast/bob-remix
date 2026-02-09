<#
.SYNOPSIS
    Clicks at specific coordinates on screen

.DESCRIPTION
    Brings window to foreground and performs a mouse click at the specified coordinates

.PARAMETER ScreenX
    X coordinate (screen coordinates)

.PARAMETER ScreenY
    Y coordinate (screen coordinates)

.PARAMETER WindowHandle
    Optional window handle to bring to foreground first

.EXAMPLE
    .\click-button.ps1 -ScreenX 500 -ScreenY 300
#>

param(
    [Parameter(Mandatory = $true)]
    [int]$ScreenX,
    
    [Parameter(Mandatory = $true)]
    [int]$ScreenY,
    
    [Parameter(Mandatory = $false)]
    [int64]$WindowHandle = 0
)

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class MouseHelper {
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);
    
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);
    
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const int SW_RESTORE = 9;
    
    public static void Click(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(50);
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(30);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
    }
}
"@

try {
    # Bring window to foreground if handle provided
    if ($WindowHandle -gt 0) {
        $hwnd = [IntPtr]$WindowHandle
        [MouseHelper]::ShowWindow($hwnd, [MouseHelper]::SW_RESTORE) | Out-Null
        Start-Sleep -Milliseconds 150
        [MouseHelper]::SetForegroundWindow($hwnd) | Out-Null
        Start-Sleep -Milliseconds 300
    }
    
    # Perform click
    [MouseHelper]::Click($ScreenX, $ScreenY)
    
    Write-Host "Clicked at ($ScreenX, $ScreenY)"
    
    @{
        success = $true
        x       = $ScreenX
        y       = $ScreenY
    } | ConvertTo-Json -Compress
}
catch {
    @{
        success = $false
        error   = $_.Exception.Message
    } | ConvertTo-Json -Compress
}
