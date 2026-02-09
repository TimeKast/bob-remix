<#
.SYNOPSIS
    Scrolls the chat to the bottom using Ctrl+End

.DESCRIPTION
    Brings window to foreground and sends Ctrl+End to scroll to bottom

.PARAMETER WindowHandle
    Window handle to target
#>

param(
    [Parameter(Mandatory = $true)]
    [int64]$WindowHandle
)

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class ScrollHelper {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    
    public const int SW_RESTORE = 9;
    public const byte VK_CONTROL = 0x11;  // Ctrl key
    public const byte VK_END = 0x23;      // End key
    public const uint KEYEVENTF_KEYUP = 0x0002;
    
    public static void SendCtrlEnd() {
        // Press Ctrl+End
        keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);  // Ctrl down
        System.Threading.Thread.Sleep(30);
        keybd_event(VK_END, 0, 0, UIntPtr.Zero);      // End down
        System.Threading.Thread.Sleep(50);
        keybd_event(VK_END, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);     // End up
        System.Threading.Thread.Sleep(30);
        keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, UIntPtr.Zero); // Ctrl up
    }
}
"@

try {
    $hwnd = [IntPtr]$WindowHandle
    
    # Bring window to foreground
    [ScrollHelper]::ShowWindow($hwnd, [ScrollHelper]::SW_RESTORE) | Out-Null
    Start-Sleep -Milliseconds 100
    [ScrollHelper]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 200
    
    # Send Ctrl+End to scroll to bottom
    [ScrollHelper]::SendCtrlEnd()
    Start-Sleep -Milliseconds 100
    
    @{ success = $true } | ConvertTo-Json -Compress
}
catch {
    @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
}
