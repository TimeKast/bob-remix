<#
.SYNOPSIS
    Detects active VS Code / Antigravity windows

.DESCRIPTION
    Scans for windows matching VS Code or Antigravity patterns
    Returns JSON array with window info

.EXAMPLE
    .\detect-windows.ps1
#>

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class WindowScanner {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    
    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    
    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
}
"@

function Get-VSCodeWindows {
    $windows = [System.Collections.ArrayList]::new()
    
    $callback = [WindowScanner+EnumWindowsProc] {
        param([IntPtr]$hWnd, [IntPtr]$lParam)
        
        if ([WindowScanner]::IsWindowVisible($hWnd)) {
            $length = [WindowScanner]::GetWindowTextLength($hWnd)
            if ($length -gt 0) {
                $sb = New-Object System.Text.StringBuilder($length + 1)
                [WindowScanner]::GetWindowText($hWnd, $sb, $sb.Capacity) | Out-Null
                $title = $sb.ToString()
                
                # Match Antigravity project windows: contains " - Antigravity" (case insensitive)
                $isAntigravity = $title -match " - Antigravity"
                
                # Exclusions (case insensitive)
                $isMonitor = $title -match "BOB Monitor|Antigravity Monitor|antigravity-monitor"
                $isPlugin = $title -match "@tauri-apps|plugin-"
                $isShortcut = $title -match "shortcut for"
                $isSearch = $title -match "^Buscar con Google|^Search with Google"
                
                if ($isAntigravity -and 
                    -not $isMonitor -and 
                    -not $isPlugin -and 
                    -not $isShortcut -and
                    -not $isSearch) {
                    $processId = 0
                    [WindowScanner]::GetWindowThreadProcessId($hWnd, [ref]$processId) | Out-Null
                    
                    $windows.Add(@{
                            windowTitle  = $title
                            windowHandle = $hWnd.ToInt64()
                            processId    = $processId
                        }) | Out-Null
                }
            }
        }
        return $true
    }
    
    [WindowScanner]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
    
    return $windows
}

# Get windows and output as JSON
$windows = Get-VSCodeWindows
$windows | ConvertTo-Json -Compress
