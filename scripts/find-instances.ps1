<#
.SYNOPSIS
    Finds all VS Code windows with Antigravity active

.DESCRIPTION
    Scans all open windows for VS Code instances and returns information
    about each one including window handle, title (project name), and state

.EXAMPLE
    .\find-instances.ps1
#>

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class WindowFinder {
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);
    
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    
    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    
    public static List<WindowInfo> Windows = new List<WindowInfo>();
    
    public static bool EnumCallback(IntPtr hWnd, IntPtr lParam) {
        if (!IsWindowVisible(hWnd)) return true;
        
        int length = GetWindowTextLength(hWnd);
        if (length == 0) return true;
        
        StringBuilder title = new StringBuilder(length + 1);
        GetWindowText(hWnd, title, title.Capacity);
        
        string titleStr = title.ToString();
        
        // Look for VS Code windows (they contain "Visual Studio Code" or project name patterns)
        if (titleStr.Contains("Visual Studio Code") || titleStr.Contains(" - ") && (titleStr.EndsWith("]") || titleStr.Contains("Code"))) {
            uint processId;
            GetWindowThreadProcessId(hWnd, out processId);
            
            Windows.Add(new WindowInfo {
                Handle = hWnd.ToInt64(),
                Title = titleStr,
                ProcessId = processId
            });
        }
        
        return true;
    }
}

public class WindowInfo {
    public long Handle { get; set; }
    public string Title { get; set; }
    public uint ProcessId { get; set; }
}
"@

try {
    [WindowFinder]::Windows.Clear()
    [WindowFinder]::EnumWindows([WindowFinder+EnumWindowsProc]::new([WindowFinder]::EnumCallback), [IntPtr]::Zero) | Out-Null
    
    $instances = @()
    
    foreach ($window in [WindowFinder]::Windows) {
        # Extract project name from title
        # VS Code titles are typically: "filename - projectname - Visual Studio Code"
        $parts = $window.Title -split " - "
        $projectName = if ($parts.Count -ge 2) { $parts[$parts.Count - 2] } else { $window.Title }
        
        $instances += @{
            handle      = $window.Handle
            title       = $window.Title
            projectName = $projectName
            processId   = $window.ProcessId
        }
    }
    
    @{
        success   = $true
        count     = $instances.Count
        instances = $instances
    } | ConvertTo-Json -Depth 3 -Compress
}
catch {
    @{
        success   = $false
        error     = $_.Exception.Message
        instances = @()
    } | ConvertTo-Json -Compress
}
