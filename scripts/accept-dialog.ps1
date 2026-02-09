<#
.SYNOPSIS
    Sends Alt+Enter keyboard shortcut to accept dialog

.DESCRIPTION
    Brings window to foreground and sends Alt+Enter to trigger Accept

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

public class KeyboardHelper {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    
    public const int SW_RESTORE = 9;
    public const byte VK_MENU = 0x12;    // Alt key
    public const byte VK_RETURN = 0x0D;  // Enter key
    public const uint KEYEVENTF_KEYUP = 0x0002;
    
    public static void SendAltEnter() {
        // Press Alt+Enter
        keybd_event(VK_MENU, 0, 0, UIntPtr.Zero);     // Alt down
        System.Threading.Thread.Sleep(30);
        keybd_event(VK_RETURN, 0, 0, UIntPtr.Zero);   // Enter down
        System.Threading.Thread.Sleep(50);
        keybd_event(VK_RETURN, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);  // Enter up
        System.Threading.Thread.Sleep(30);
        keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);    // Alt up
    }
}
"@

try {
    $hwnd = [IntPtr]$WindowHandle
    
    # Bring window to foreground - try multiple times for reliability when called from another app
    [KeyboardHelper]::ShowWindow($hwnd, [KeyboardHelper]::SW_RESTORE) | Out-Null
    Start-Sleep -Milliseconds 150
    [KeyboardHelper]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 300
    # Second attempt to ensure focus
    [KeyboardHelper]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 200
    
    # Send Alt+Enter
    [KeyboardHelper]::SendAltEnter()
    Start-Sleep -Milliseconds 150
    
    @{
        success = $true
        method  = "Alt+Enter"
    } | ConvertTo-Json -Compress
}
catch {
    @{
        success = $false
        error   = $_.Exception.Message
    } | ConvertTo-Json -Compress
}
