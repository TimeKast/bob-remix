<#
.SYNOPSIS
    Detects UI state of Antigravity in VS Code window (Optimized)

.PARAMETER WindowHandle
    Handle of the VS Code window to scan
#>

param(
    [Parameter(Mandatory = $true)]
    [int64]$WindowHandle
)

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class FastDetector {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
    
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    
    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern IntPtr GetDC(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    
    [DllImport("gdi32.dll")]
    public static extern uint GetPixel(IntPtr hdc, int nXPos, int nYPos);
    
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
    
    public const int SW_RESTORE = 9;
    
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);
    
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, int dwData, UIntPtr dwExtraInfo);
    
    public const uint MOUSEEVENTF_WHEEL = 0x0800;
    public const int WHEEL_DELTA = 120;
    
    // Faster scroll - fewer iterations, bigger deltas
    public static void ScrollToBottom(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(30);
        for (int i = 0; i < 5; i++) {
            mouse_event(MOUSEEVENTF_WHEEL, 0, 0, -WHEEL_DELTA * 10, UIntPtr.Zero);
            System.Threading.Thread.Sleep(15);
        }
    }
}
"@

try {
    [FastDetector]::SetProcessDPIAware() | Out-Null
    
    $hwnd = [IntPtr]$WindowHandle
    
    $result = @{
        hasAcceptButton = $false
        hasRetryButton  = $false
        chatButtonColor = "none"
        acceptButtonX   = 0
        acceptButtonY   = 0
        retryButtonX    = 0
        retryButtonY    = 0
        windowMinimized = $false
        isBottomButton  = $false
        hasEnterButton  = $false
        isPaused        = $false
        enterButtonX    = 0
        enterButtonY    = 0
    }
    
    if ([FastDetector]::IsIconic($hwnd)) {
        $result.windowMinimized = $true
        $result | ConvertTo-Json -Compress
        exit
    }
    
    $rect = New-Object FastDetector+RECT
    [FastDetector]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    
    # Only restore if minimized
    if ([FastDetector]::IsIconic($hwnd)) {
        [FastDetector]::ShowWindow($hwnd, [FastDetector]::SW_RESTORE) | Out-Null
        Start-Sleep -Milliseconds 50
    }
    [FastDetector]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 50
    
    # Quick scroll to bottom
    $chatX = $rect.Left + [int]($width * 0.88)
    $chatY = $rect.Top + [int]($height * 0.5)
    [FastDetector]::ScrollToBottom($chatX, $chatY)
    Start-Sleep -Milliseconds 80
    
    # ===== SINGLE DC for ALL scanning =====
    $hdc = [FastDetector]::GetDC([IntPtr]::Zero)
    
    $stepX = 30
    $stepY = 25
    
    # ========== PASS 1: Scan right side for Accept buttons + blue buttons ==========
    # This covers Accept all (bottom), dialog Accept/Run (middle), in ONE pass from top to bottom
    $scanStartX = [int]($width * 0.50)
    $scanEndX = [int]($width * 0.98)
    $scanStartY = [int]($height * 0.15)
    $scanEndY = [int]($height * 0.98)
    
    for ($y = $scanEndY; $y -gt $scanStartY -and -not $result.hasAcceptButton; $y -= $stepY) {
        for ($x = $scanStartX; $x -lt $scanEndX; $x += $stepX) {
            $screenX = $rect.Left + $x
            $screenY = $rect.Top + $y
            
            $pixel = [FastDetector]::GetPixel($hdc, $screenX, $screenY)
            $r = $pixel -band 0xFF
            $g = ($pixel -shr 8) -band 0xFF
            $b = ($pixel -shr 16) -band 0xFF
            
            # Blue/Green/Teal button detection (Accept, Run, Accept all)
            $isButton = ($r -lt 100 -and $g -ge 100 -and $b -ge 150)
            
            if ($isButton) {
                # Quick neighbor check (1 pixel only for speed)
                $px1 = [FastDetector]::GetPixel($hdc, $screenX + 25, $screenY)
                $r1 = $px1 -band 0xFF; $g1 = ($px1 -shr 8) -band 0xFF; $b1 = ($px1 -shr 16) -band 0xFF
                $isButton1 = ($r1 -lt 100 -and $g1 -ge 100 -and $b1 -ge 150)
                
                if ($isButton1) {
                    $result.hasAcceptButton = $true
                    $result.acceptButtonX = $screenX + 15
                    $result.acceptButtonY = $screenY
                    # Bottom 35% = Accept all (click), otherwise dialog (Alt+Enter)
                    $result.isBottomButton = ($y -gt ($height * 0.65))
                    break
                }
            }
        }
    }
    
    # ========== PASS 2: Check for stop/pause (red square, bottom-right of chat) ==========
    # Only check if no Accept button was found
    if (-not $result.hasAcceptButton) {
        $pauseStartX = [int]($width * 0.80)
        $pauseEndX = [int]($width * 0.97)
        $pauseStartY = [int]($height * 0.82)
        $pauseEndY = [int]($height * 0.97)
        
        for ($y = $pauseStartY; $y -lt $pauseEndY -and -not $result.isPaused; $y += 12) {
            for ($x = $pauseStartX; $x -lt $pauseEndX; $x += 12) {
                $screenX = $rect.Left + $x
                $screenY = $rect.Top + $y
                
                $pixel = [FastDetector]::GetPixel($hdc, $screenX, $screenY)
                $r = $pixel -band 0xFF
                $g = ($pixel -shr 8) -band 0xFF
                $b = ($pixel -shr 16) -band 0xFF
                
                if ($r -ge 180 -and $g -lt 100 -and $b -lt 100) {
                    # Quick neighbor verify
                    $px1 = [FastDetector]::GetPixel($hdc, $screenX + 5, $screenY)
                    $r1 = $px1 -band 0xFF
                    if ($r1 -ge 180) {
                        $result.isPaused = $true
                        $result.chatButtonColor = "red"
                        break
                    }
                }
            }
        }
    }
    
    # ========== PASS 3: Determine chat state (only if no Accept and no pause) ==========
    if (-not $result.hasAcceptButton -and -not $result.isPaused) {
        # Corner scan for send button color
        $foundRed = $false
        
        foreach ($xOffset in @(30, 50, 80, 120, 160, 200, 250)) {
            foreach ($yOffset in @(30, 50, 70, 100, 130, 160)) {
                if ($foundRed) { break }
                
                $screenX = $rect.Right - $xOffset
                $screenY = $rect.Bottom - $yOffset
                
                $pixel = [FastDetector]::GetPixel($hdc, $screenX, $screenY)
                $r = $pixel -band 0xFF
                $g = ($pixel -shr 8) -band 0xFF
                $b = ($pixel -shr 16) -band 0xFF
                
                if ($r -ge 150 -and $g -lt 100 -and $b -lt 100) {
                    $foundRed = $true
                }
            }
        }
        
        if ($foundRed) {
            $result.chatButtonColor = "red"
            $result.isPaused = $true
        }
        else {
            # No red found = chat is ready for input
            $result.chatButtonColor = "gray"
            
            # Check for Retry button with cluster verification (bottom half, right side)
            $retryStartY = [int]($height * 0.55)
            $retryEndY = [int]($height * 0.95)
            $retryStartX = [int]($width * 0.55)
            $retryEndX = [int]($width * 0.95)
            
            for ($y = $retryEndY; $y -gt $retryStartY -and -not $result.hasRetryButton; $y -= 20) {
                for ($x = $retryStartX; $x -lt $retryEndX; $x += 25) {
                    $px = $rect.Left + $x
                    $py = $rect.Top + $y
                    
                    $pxl = [FastDetector]::GetPixel($hdc, $px, $py)
                    $pr = $pxl -band 0xFF
                    $pg = ($pxl -shr 8) -band 0xFF
                    $pb = ($pxl -shr 16) -band 0xFF
                    
                    # Blue Retry button (R<100, G:100-200, B>=180)
                    if ($pr -lt 100 -and $pg -ge 100 -and $pg -le 200 -and $pb -ge 180) {
                        # Cluster check - need 3+ adjacent blue pixels
                        $blueCount = 1
                        for ($checkX = 10; $checkX -le 40; $checkX += 10) {
                            $cpx = [FastDetector]::GetPixel($hdc, $px + $checkX, $py)
                            $cr = $cpx -band 0xFF; $cg = ($cpx -shr 8) -band 0xFF; $cb = ($cpx -shr 16) -band 0xFF
                            if ($cr -lt 100 -and $cg -ge 100 -and $cb -ge 180) { $blueCount++ }
                        }
                        
                        if ($blueCount -ge 3) {
                            $result.hasRetryButton = $true
                            $result.retryButtonX = $px + 20
                            $result.retryButtonY = $py
                            break
                        }
                    }
                }
            }
            
            # If no Retry, chat is ready
            if (-not $result.hasRetryButton) {
                $result.hasEnterButton = $true
                $result.enterButtonX = $rect.Right - 60
                $result.enterButtonY = $rect.Bottom - 50
            }
        }
    }
    
    [FastDetector]::ReleaseDC([IntPtr]::Zero, $hdc) | Out-Null
    
    $result | ConvertTo-Json -Compress
}
catch {
    @{
        error           = $_.Exception.Message
        hasAcceptButton = $false
        hasEnterButton  = $false
        hasRetryButton  = $false
        isPaused        = $false
        chatButtonColor = "none"
    } | ConvertTo-Json -Compress
}
