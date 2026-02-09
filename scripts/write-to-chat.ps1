<#
.SYNOPSIS
    Writes text to Antigravity chat and submits it (Simplified version)

.PARAMETER Prompt
    The text to type into the chat

.PARAMETER WindowHandle
    Handle of the VS Code window
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Prompt,
    
    [Parameter(Mandatory = $true)]
    [int64]$WindowHandle
)

# Set timeout for the whole script - 10 seconds max
$timeout = 10
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class ChatWriter {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    
    [DllImport("user32.dll")]
    public static extern void SetCursorPos(int X, int Y);
    
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);
    
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
    
    public const int SW_RESTORE = 9;
    public const byte VK_CONTROL = 0x11;
    public const byte VK_V = 0x56;
    public const byte VK_RETURN = 0x0D;
    public const uint KEYEVENTF_KEYUP = 0x0002;
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
}
"@

try {
    $hwnd = [IntPtr]$WindowHandle
    
    # Quick focus
    [ChatWriter]::ShowWindow($hwnd, [ChatWriter]::SW_RESTORE) | Out-Null
    [ChatWriter]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 200
    
    # Get window position
    $rect = New-Object ChatWriter+RECT
    [ChatWriter]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    
    # Click on chat input - bottom right area
    # Use multiple attempts with different offsets for different DPI scaling
    $chatX = $rect.Left + [int]($width * 0.75)
    $chatY = $rect.Bottom - [int]([Math]::Max(80, $height * 0.08))
    
    [ChatWriter]::SetCursorPos($chatX, $chatY)
    Start-Sleep -Milliseconds 50
    [ChatWriter]::mouse_event([ChatWriter]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 30
    [ChatWriter]::mouse_event([ChatWriter]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 150
    
    # Use clipboard to paste text (more reliable)
    Set-Clipboard -Value $Prompt
    Start-Sleep -Milliseconds 100
    
    # Ctrl+V
    [ChatWriter]::keybd_event([ChatWriter]::VK_CONTROL, 0, 0, [UIntPtr]::Zero)
    [ChatWriter]::keybd_event([ChatWriter]::VK_V, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 50
    [ChatWriter]::keybd_event([ChatWriter]::VK_V, 0, [ChatWriter]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    [ChatWriter]::keybd_event([ChatWriter]::VK_CONTROL, 0, [ChatWriter]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 200
    
    # Press Enter
    [ChatWriter]::keybd_event([ChatWriter]::VK_RETURN, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 50
    [ChatWriter]::keybd_event([ChatWriter]::VK_RETURN, 0, [ChatWriter]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    
    @{
        success = $true
        prompt  = $Prompt.Substring(0, [Math]::Min(50, $Prompt.Length))
        clickX  = $chatX
        clickY  = $chatY
        elapsed = $stopwatch.ElapsedMilliseconds
    } | ConvertTo-Json -Compress
}
catch {
    @{
        success = $false
        error   = $_.Exception.Message
        elapsed = $stopwatch.ElapsedMilliseconds
    } | ConvertTo-Json -Compress
}
finally {
    $stopwatch.Stop()
}
