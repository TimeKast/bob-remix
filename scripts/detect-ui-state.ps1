<#
.SYNOPSIS
    Detects UI state of Antigravity in VS Code window (Fast version)

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
    
    // Mouse scroll for chat panel
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);
    
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, int dwData, UIntPtr dwExtraInfo);
    
    public const uint MOUSEEVENTF_WHEEL = 0x0800;
    public const int WHEEL_DELTA = 120;
    
    public static void ScrollToBottom(int x, int y) {
        // Move cursor to chat area
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(50);
        
        // Scroll down aggressively (negative = down)
        for (int i = 0; i < 10; i++) {
            mouse_event(MOUSEEVENTF_WHEEL, 0, 0, -WHEEL_DELTA * 5, UIntPtr.Zero);
            System.Threading.Thread.Sleep(30);
        }
    }
}
"@

function Test-IsGreenAcceptButton {
    param([int]$R, [int]$G, [int]$B)
    # Detect BOTH blue Accept buttons AND green/teal Accept all buttons
    
    # BLUE Accept button (VS Code dark theme dialog buttons)
    $isBlueButton = ($R -lt 100 -and $G -ge 100 -and $G -le 200 -and $B -ge 180)
    
    # GREEN/TEAL Accept all button (file changes panel)
    $isGreenButton = ($R -lt 80 -and $G -ge 160 -and $B -ge 100 -and $B -le 200)
    
    # Teal/Cyan button (some themes)
    $isTeal = ($R -lt 80 -and $G -ge 150 -and $B -ge 150)
    
    return $isBlueButton -or $isGreenButton -or $isTeal
}

function Test-IsRedButton {
    param([int]$R, [int]$G, [int]$B)
    return ($R -ge 200 -and $G -lt 80 -and $B -lt 80)
}

function Test-IsGrayArrowButton {
    param([int]$R, [int]$G, [int]$B)
    $isGray = ($R -ge 80 -and $R -le 180 -and $G -ge 80 -and $G -le 180 -and $B -ge 80 -and $B -le 180)
    $isSimilar = ([Math]::Abs($R - $G) -lt 30 -and [Math]::Abs($G - $B) -lt 30 -and [Math]::Abs($R - $B) -lt 30)
    return $isGray -and $isSimilar
}

try {
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
    
    # Check minimized
    if ([FastDetector]::IsIconic($hwnd)) {
        $result.windowMinimized = $true
        $result | ConvertTo-Json -Compress
        exit
    }
    
    # Get window rect
    $rect = New-Object FastDetector+RECT
    [FastDetector]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    
    # Only restore if minimized - avoid un-snapping windows from split layouts
    if ([FastDetector]::IsIconic($hwnd)) {
        [FastDetector]::ShowWindow($hwnd, [FastDetector]::SW_RESTORE) | Out-Null
        Start-Sleep -Milliseconds 100
    }
    [FastDetector]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 100
    
    # Scroll to bottom in chat area (far right side)
    $chatX = $rect.Left + [int]($width * 0.88)
    $chatY = $rect.Top + [int]($height * 0.5)
    [FastDetector]::ScrollToBottom($chatX, $chatY)
    Start-Sleep -Milliseconds 150
    
    $hdc = [FastDetector]::GetDC([IntPtr]::Zero)
    
    $stepX = 25
    $stepY = 20
    $startX = [int]($width * 0.5)
    $endX = [int]($width * 0.98)
    
    # ========== FIRST: Check for Accept all button (bottom-right, green/teal) ==========
    $acceptAllStartX = [int]($width * 0.70)
    $bottomStartY = [int]($height * 0.65)
    $bottomEndY = [int]($height * 0.98)
    
    for ($y = $bottomEndY; $y -gt $bottomStartY -and -not $result.hasAcceptButton; $y -= $stepY) {
        for ($x = $acceptAllStartX; $x -lt $endX; $x += $stepX) {
            $screenX = $rect.Left + $x
            $screenY = $rect.Top + $y
            
            $pixel = [FastDetector]::GetPixel($hdc, $screenX, $screenY)
            $r = $pixel -band 0xFF
            $g = ($pixel -shr 8) -band 0xFF
            $b = ($pixel -shr 16) -band 0xFF
            
            if (Test-IsGreenAcceptButton -R $r -G $g -B $b) {
                $px1 = [FastDetector]::GetPixel($hdc, $screenX + 20, $screenY)
                $r1 = $px1 -band 0xFF; $g1 = ($px1 -shr 8) -band 0xFF; $b1 = ($px1 -shr 16) -band 0xFF
                
                $px2 = [FastDetector]::GetPixel($hdc, $screenX + 40, $screenY)
                $r2 = $px2 -band 0xFF; $g2 = ($px2 -shr 8) -band 0xFF; $b2 = ($px2 -shr 16) -band 0xFF
                
                if ((Test-IsGreenAcceptButton -R $r1 -G $g1 -B $b1) -and (Test-IsGreenAcceptButton -R $r2 -G $g2 -B $b2)) {
                    $result.hasAcceptButton = $true
                    $result.isBottomButton = $true
                    $result.acceptButtonX = $screenX + 30
                    $result.acceptButtonY = $screenY
                    break
                }
            }
        }
    }
    
    # ========== SECOND: Check for dialog Accept/Run button (wider area) ==========
    if (-not $result.hasAcceptButton) {
        $dialogStartY = [int]($height * 0.15)
        $dialogEndY = [int]($height * 0.90)
        
        for ($y = $dialogStartY; $y -lt $dialogEndY -and -not $result.hasAcceptButton; $y += $stepY) {
            for ($x = $startX; $x -lt $endX; $x += $stepX) {
                $screenX = $rect.Left + $x
                $screenY = $rect.Top + $y
                
                $pixel = [FastDetector]::GetPixel($hdc, $screenX, $screenY)
                $r = $pixel -band 0xFF
                $g = ($pixel -shr 8) -band 0xFF
                $b = ($pixel -shr 16) -band 0xFF
                
                if (Test-IsGreenAcceptButton -R $r -G $g -B $b) {
                    $px1 = [FastDetector]::GetPixel($hdc, $screenX + 20, $screenY)
                    $r1 = $px1 -band 0xFF; $g1 = ($px1 -shr 8) -band 0xFF; $b1 = ($px1 -shr 16) -band 0xFF
                    
                    $px2 = [FastDetector]::GetPixel($hdc, $screenX + 40, $screenY)
                    $r2 = $px2 -band 0xFF; $g2 = ($px2 -shr 8) -band 0xFF; $b2 = ($px2 -shr 16) -band 0xFF
                    
                    if ((Test-IsGreenAcceptButton -R $r1 -G $g1 -B $b1) -and (Test-IsGreenAcceptButton -R $r2 -G $g2 -B $b2)) {
                        $result.hasAcceptButton = $true
                        $result.acceptButtonX = $screenX + 30
                        $result.acceptButtonY = $screenY
                        break
                    }
                }
                
                if ((Test-IsRedButton -R $r -G $g -B $b) -and -not $result.hasRetryButton) {
                    $result.hasRetryButton = $true
                    $result.retryButtonX = $screenX
                    $result.retryButtonY = $screenY
                }
            }
        }
    }
    
    [FastDetector]::ReleaseDC([IntPtr]::Zero, $hdc) | Out-Null
    
    # ========== THIRD: Check for PAUSE button (red square in bottom-right) ==========
    $hdc2 = [FastDetector]::GetDC([IntPtr]::Zero)
    
    $pauseStartX = [int]($width * 0.93)
    $pauseEndX = [int]($width * 0.99)
    $pauseStartY = [int]($height * 0.90)
    $pauseEndY = [int]($height * 0.98)
    
    for ($y = $pauseStartY; $y -lt $pauseEndY -and -not $result.isPaused; $y += 10) {
        for ($x = $pauseStartX; $x -lt $pauseEndX; $x += 10) {
            $screenX = $rect.Left + $x
            $screenY = $rect.Top + $y
            
            $pixel = [FastDetector]::GetPixel($hdc2, $screenX, $screenY)
            $r = $pixel -band 0xFF
            $g = ($pixel -shr 8) -band 0xFF
            $b = ($pixel -shr 16) -band 0xFF
            
            if ($r -ge 180 -and $g -lt 100 -and $b -lt 100) {
                $px1 = [FastDetector]::GetPixel($hdc2, $screenX + 5, $screenY)
                $r1 = $px1 -band 0xFF; $g1 = ($px1 -shr 8) -band 0xFF; $b1 = ($px1 -shr 16) -band 0xFF
                
                $px2 = [FastDetector]::GetPixel($hdc2, $screenX, $screenY + 5)
                $r2 = $px2 -band 0xFF; $g2 = ($px2 -shr 8) -band 0xFF; $b2 = ($px2 -shr 16) -band 0xFF
                
                if (($r1 -ge 180 -and $g1 -lt 100 -and $b1 -lt 100) -and ($r2 -ge 180 -and $g2 -lt 100 -and $b2 -lt 100)) {
                    $result.isPaused = $true
                    break
                }
            }
        }
    }
    
    [FastDetector]::ReleaseDC([IntPtr]::Zero, $hdc2) | Out-Null
    
    # ========== STEP 2: Check chat button color ==========
    # SAFETY FIRST: If isPaused was already detected, force "red" and skip corner scan
    if (-not $result.hasAcceptButton) {
        if ($result.isPaused) {
            # Agent is working (red square found) - force red, don't risk false "gray"
            $result.chatButtonColor = "red"
        }
        else {
            # Normal corner scan for chat button color
            $hdc3 = [FastDetector]::GetDC([IntPtr]::Zero)
            
            $foundGray = $false
            $foundRed = $false
            $foundBlue = $false
            
            foreach ($xOffset in @(10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100)) {
                foreach ($yOffset in @(25, 30, 35, 40, 50, 60, 70, 80, 90, 100, 110, 120)) {
                    if ($foundGray -or $foundRed -or $foundBlue) { break }
                    
                    $screenX = $rect.Right - $xOffset
                    $screenY = $rect.Bottom - $yOffset
                    
                    $pixel = [FastDetector]::GetPixel($hdc3, $screenX, $screenY)
                    $r = $pixel -band 0xFF
                    $g = ($pixel -shr 8) -band 0xFF
                    $b = ($pixel -shr 16) -band 0xFF
                    
                    $isGray = ($r -ge 100 -and $r -le 180 -and $g -ge 100 -and $g -le 180 -and $b -ge 100 -and $b -le 180)
                    $isSimilar = ([Math]::Abs($r - $g) -lt 20 -and [Math]::Abs($g - $b) -lt 20)
                    $isRed = ($r -ge 150 -and $g -lt 100 -and $b -lt 100)
                    $isBlue = ($r -lt 100 -and $g -ge 100 -and $b -ge 150)
                    
                    if ($isGray -and $isSimilar) { $foundGray = $true }
                    if ($isRed) { $foundRed = $true }
                    if ($isBlue) { $foundBlue = $true }
                }
            }
            
            if ($foundRed) {
                $result.chatButtonColor = "red"
                $result.isPaused = $true
                
                # Search for Accept dialog while agent is working
                $dialogStartY = [int]($height * 0.15)
                $dialogEndY = [int]($height * 0.90)
                $dialogStartX = [int]($width * 0.50)
                $dialogEndX = [int]($width * 0.98)
                
                for ($y = $dialogStartY; $y -lt $dialogEndY -and -not $result.hasAcceptButton; $y += 20) {
                    for ($x = $dialogStartX; $x -lt $dialogEndX; $x += 25) {
                        $px = $rect.Left + $x
                        $py = $rect.Top + $y
                        
                        $pxl = [FastDetector]::GetPixel($hdc3, $px, $py)
                        $pr = $pxl -band 0xFF
                        $pg = ($pxl -shr 8) -band 0xFF
                        $pb = ($pxl -shr 16) -band 0xFF
                        
                        if (Test-IsGreenAcceptButton -R $pr -G $pg -B $pb) {
                            $px1 = [FastDetector]::GetPixel($hdc3, $px + 20, $py)
                            $r1 = $px1 -band 0xFF; $g1 = ($px1 -shr 8) -band 0xFF; $b1 = ($px1 -shr 16) -band 0xFF
                            
                            if (Test-IsGreenAcceptButton -R $r1 -G $g1 -B $b1) {
                                $result.hasAcceptButton = $true
                                $result.isBottomButton = $false
                                $result.acceptButtonX = $px + 30
                                $result.acceptButtonY = $py
                                break
                            }
                        }
                    }
                }
            }
            else {
                $result.chatButtonColor = "gray"
                
                # Search for Retry button
                $retryStartY = [int]($height * 0.50)
                $retryEndY = [int]($height * 0.95)
                $retryStartX = [int]($width * 0.50)
                $retryEndX = [int]($width * 0.98)
                
                for ($y = $retryEndY; $y -gt $retryStartY -and -not $result.hasRetryButton; $y -= 15) {
                    for ($x = $retryStartX; $x -lt $retryEndX; $x += 20) {
                        $px = $rect.Left + $x
                        $py = $rect.Top + $y
                        
                        $pxl = [FastDetector]::GetPixel($hdc3, $px, $py)
                        $pr = $pxl -band 0xFF
                        $pg = ($pxl -shr 8) -band 0xFF
                        $pb = ($pxl -shr 16) -band 0xFF
                        
                        $isBlueRetry = ($pr -lt 100 -and $pg -ge 100 -and $pg -le 200 -and $pb -ge 180)
                        
                        if ($isBlueRetry) {
                            $blueCount = 1
                            for ($checkX = 1; $checkX -le 40; $checkX += 10) {
                                $checkPxl = [FastDetector]::GetPixel($hdc3, $px + $checkX, $py)
                                $checkR = $checkPxl -band 0xFF
                                $checkG = ($checkPxl -shr 8) -band 0xFF
                                $checkB = ($checkPxl -shr 16) -band 0xFF
                                if ($checkR -lt 100 -and $checkG -ge 100 -and $checkG -le 200 -and $checkB -ge 180) {
                                    $blueCount++
                                }
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
                
                # If no Retry found, chat is ready for input
                if (-not $result.hasRetryButton) {
                    $result.hasEnterButton = $true
                    $result.enterButtonX = $rect.Right - 30
                    $result.enterButtonY = $rect.Bottom - 40
                }
            }
            
            [FastDetector]::ReleaseDC([IntPtr]::Zero, $hdc3) | Out-Null
        }
    }
    
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
