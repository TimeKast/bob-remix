<#
.SYNOPSIS
    Pastes a prompt into the Antigravity/VS Code window

.DESCRIPTION
    This script finds the Antigravity window, brings it to the foreground,
    and pastes the specified prompt using clipboard + Ctrl+V + Enter

.PARAMETER Prompt
    The prompt text to paste

.PARAMETER WindowTitle
    Part of the window title to search for

.PARAMETER InstanceId
    Optional instance ID for logging

.EXAMPLE
    .\paste-prompt.ps1 -Prompt "Continúa con el siguiente paso" -WindowTitle "Antigravity"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Prompt,
    
    [Parameter(Mandatory = $false)]
    [string]$WindowTitle = "Antigravity",

    [Parameter(Mandatory = $false)]
    [string]$InstanceId = "default"
)

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class WindowHelper {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    
    public const int SW_RESTORE = 9;
    public const int SW_SHOW = 5;
}
"@

# Find window by title
function Find-Window {
    param([string]$Title)
    
    $processes = Get-Process | Where-Object { $_.MainWindowTitle -like "*$Title*" }
    
    if ($processes.Count -eq 0) {
        Write-Host "[$InstanceId] Window not found: $Title"
        return $null
    }
    
    # If multiple matches, prefer exact match or first one
    if ($processes.Count -gt 1) {
        $exactMatch = $processes | Where-Object { $_.MainWindowTitle -eq $Title }
        if ($exactMatch) {
            return $exactMatch
        }
    }
    
    return $processes[0]
}

# Main execution
Write-Host "[$InstanceId] Looking for window: $WindowTitle"

$process = Find-Window -Title $WindowTitle

if ($null -eq $process) {
    # Try alternative titles
    $process = Find-Window -Title "Visual Studio Code"
    if ($null -eq $process) {
        $process = Find-Window -Title "Code"
    }
}

if ($null -eq $process) {
    Write-Host "[$InstanceId] No matching window found!"
    exit 1
}

Write-Host "[$InstanceId] Found: $($process.MainWindowTitle)"

# Copy prompt to clipboard
Set-Clipboard -Value $Prompt
Write-Host "[$InstanceId] Prompt copied to clipboard"

# Bring window to foreground
$hwnd = $process.MainWindowHandle
[WindowHelper]::ShowWindow($hwnd, [WindowHelper]::SW_RESTORE) | Out-Null
Start-Sleep -Milliseconds 100
[WindowHelper]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 300

# Verify window is in foreground
$foreground = [WindowHelper]::GetForegroundWindow()
if ($foreground -ne $hwnd) {
    Write-Host "[$InstanceId] Warning: Window may not be in foreground"
}

# Load Windows Forms for SendKeys
Add-Type -AssemblyName System.Windows.Forms

# Paste (Ctrl+V)
[System.Windows.Forms.SendKeys]::SendWait("^v")
Start-Sleep -Milliseconds 200

# Send Enter to submit
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

Write-Host "[$InstanceId] Prompt pasted and submitted"
exit 0
