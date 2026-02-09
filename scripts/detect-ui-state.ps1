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
    # Blue button: low R, medium G, high B
    $isBlueButton = ($R -lt 100 -and $G -ge 100 -and $G -le 200 -and $B -ge 180)
    
    # GREEN/TEAL Accept all button (file changes panel)
    # Green button: low R, high G, medium-high B
    $isGreenButton = ($R -lt 80 -and $G -ge 160 -and $B -ge 100 -and $B -le 200)
    
    # Teal/Cyan button (some themes)
    $isTeal = ($R -lt 80 -and $G -ge 150 -and $B -ge 150)
    
    return $isBlueButton -or $isGreenButton -or $isTeal
}

function Test-IsRedButton {
    param([int]$R, [int]$G, [int]$B)
    # Only match solid bright red buttons (error/retry), not text
    return ($R -ge 200 -and $G -lt 80 -and $B -lt 80)
}

function Test-IsGrayArrowButton {
    param([int]$R, [int]$G, [int]$B)
    # Gray arrow button indicates chat is ready for input
    # Gray is when R, G, B are similar and medium brightness (80-180)
    $isGray = ($R -ge 80 -and $R -le 180 -and $G -ge 80 -and $G -le 180 -and $B -ge 80 -and $B -le 180)
    $isSimilar = ([Math]::Abs($R - $G) -lt 30 -and [Math]::Abs($G - $B) -lt 30 -and [Math]::Abs($R - $B) -lt 30)
    return $isGray -and $isSimilar
}

try {
    $hwnd = [IntPtr]$WindowHandle
    
    $result = @{
        hasAcceptButton = $false
        hasRetryButton  = $false
        chatButtonColor = "none"  # "gray" = ready for input, "red" = agent working, "none" = not found
        acceptButtonX   = 0
        acceptButtonY   = 0
        retryButtonX    = 0
        retryButtonY    = 0
        windowMinimized = $false
        isBottomButton  = $false  # True if Accept all (needs click), False if dialog (use Alt+Enter)
        # Keeping these for compatibility
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
    
    # Get window rect without bringing to foreground first
    $rect = New-Object FastDetector+RECT
    [FastDetector]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    
    # Briefly focus to read pixels
    [FastDetector]::ShowWindow($hwnd, [FastDetector]::SW_RESTORE) | Out-Null
    [FastDetector]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 100
    
    # Scroll to bottom using mouse wheel in chat area (right side of window, center height)
    # Chat panel is typically on the right side of VS Code
    $chatX = $rect.Left + [int]($width * 0.75)  # 75% from left = in chat area
    $chatY = $rect.Top + [int]($height * 0.5)   # Center height
    [FastDetector]::ScrollToBottom($chatX, $chatY)
    Start-Sleep -Milliseconds 150
    
    $hdc = [FastDetector]::GetDC([IntPtr]::Zero)
    
    # FASTER: Larger step sizes for quicker scanning
    $stepX = 25
    $stepY = 20
    
    # Common X range: right side of screen
    $startX = [int]($width * 0.5)
    $endX = [int]($width * 0.98)
    
    # ========== FIRST: Check for Accept all button (priority - most common) ==========
    # Accept all is always in bottom-right, can move up as files increase
    # Scan from BOTTOM UP for faster detection, smaller area (last 30% of width)
    $acceptAllStartX = [int]($width * 0.70)  # Only right 30%
    $bottomStartY = [int]($height * 0.65)    # Starts lower, can move up
    $bottomEndY = [int]($height * 0.98)
    
    # Scan from bottom to top (more likely to find it at bottom first)
    for ($y = $bottomEndY; $y -gt $bottomStartY -and -not $result.hasAcceptButton; $y -= $stepY) {
        for ($x = $acceptAllStartX; $x -lt $endX; $x += $stepX) {
            $screenX = $rect.Left + $x
            $screenY = $rect.Top + $y
            
            $pixel = [FastDetector]::GetPixel($hdc, $screenX, $screenY)
            $r = $pixel -band 0xFF
            $g = ($pixel -shr 8) -band 0xFF
            $b = ($pixel -shr 16) -band 0xFF
            
            if (Test-IsGreenAcceptButton -R $r -G $g -B $b) {
                # FAST: Check only 2 neighbors for Accept all button
                $px1 = [FastDetector]::GetPixel($hdc, $screenX + 20, $screenY)
                $r1 = $px1 -band 0xFF; $g1 = ($px1 -shr 8) -band 0xFF; $b1 = ($px1 -shr 16) -band 0xFF
                
                $px2 = [FastDetector]::GetPixel($hdc, $screenX + 40, $screenY)
                $r2 = $px2 -band 0xFF; $g2 = ($px2 -shr 8) -band 0xFF; $b2 = ($px2 -shr 16) -band 0xFF
                
                if ((Test-IsGreenAcceptButton -R $r1 -G $g1 -B $b1) -and (Test-IsGreenAcceptButton -R $r2 -G $g2 -B $b2)) {
                    $result.hasAcceptButton = $true
                    $result.isBottomButton = $true  # This is Accept all, needs click
                    $result.acceptButtonX = $screenX + 30
                    $result.acceptButtonY = $screenY
                    break
                }
            }
        }
    }
    
    # ========== SECOND: Check for dialog Accept button (Run command? etc) ==========
    # Only if Accept all was NOT found - expanded area to catch lower buttons
    if (-not $result.hasAcceptButton) {
        $dialogStartY = [int]($height * 0.30)  # Start higher
        $dialogEndY = [int]($height * 0.78)    # End lower to catch all positions
        
        for ($y = $dialogStartY; $y -lt $dialogEndY -and -not $result.hasAcceptButton; $y += $stepY) {
            for ($x = $startX; $x -lt $endX; $x += $stepX) {
                $screenX = $rect.Left + $x
                $screenY = $rect.Top + $y
                
                $pixel = [FastDetector]::GetPixel($hdc, $screenX, $screenY)
                $r = $pixel -band 0xFF
                $g = ($pixel -shr 8) -band 0xFF
                $b = ($pixel -shr 16) -band 0xFF
                
                if (Test-IsGreenAcceptButton -R $r -G $g -B $b) {
                    # FAST: Check only 2 neighbors
                    $px1 = [FastDetector]::GetPixel($hdc, $screenX + 20, $screenY)
                    $r1 = $px1 -band 0xFF; $g1 = ($px1 -shr 8) -band 0xFF; $b1 = ($px1 -shr 16) -band 0xFF
                    
                    $px2 = [FastDetector]::GetPixel($hdc, $screenX + 40, $screenY)
                    $r2 = $px2 -band 0xFF; $g2 = ($px2 -shr 8) -band 0xFF; $b2 = ($px2 -shr 16) -band 0xFF
                    
                    if ((Test-IsGreenAcceptButton -R $r1 -G $g1 -B $b1) -and (Test-IsGreenAcceptButton -R $r2 -G $g2 -B $b2)) {
                        $result.hasAcceptButton = $true
                        # isBottomButton stays false - this is dialog, use Alt+Enter
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
    
    # ========== THIRD: Check for PAUSE button (red square in bottom-right corner) ==========
    # If pause button is visible, agent is working - do NOT send prompt
    $hdc2 = [FastDetector]::GetDC([IntPtr]::Zero)
    
    # Pause button is in the very bottom-right corner of the chat area
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
            
            # Red pause/stop button
            if ($r -ge 180 -and $g -lt 100 -and $b -lt 100) {
                # Verify it's a solid button (check 2 neighbors)
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
    
    # ========== STEP 2: Check chat button color (if no Accept all found) ==========
    # Only run if Accept all was NOT found
    if (-not $result.hasAcceptButton) {
        $hdc3 = [FastDetector]::GetDC([IntPtr]::Zero)
        
        # Chat button is in the extreme bottom-right corner - sample multiple points
        # Use ABSOLUTE offsets from edges instead of percentages for consistency across window sizes
        # The send button is typically 20-60 pixels from right edge and 30-70 pixels from bottom
        $foundGray = $false
        $foundRed = $false
        $foundBlue = $false  # Blue/cyan send button
        
        # Search area: right edge -5px to -50px, bottom edge -20px to -100px
        # Expanded range for different resolutions and DPI scaling (100%-200%)
        foreach ($xOffset in @(10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100)) {
            foreach ($yOffset in @(25, 30, 35, 40, 50, 60, 70, 80, 90, 100, 110, 120)) {
                if ($foundGray -or $foundRed -or $foundBlue) { break }
                
                $screenX = $rect.Right - $xOffset
                $screenY = $rect.Bottom - $yOffset
                
                $pixel = [FastDetector]::GetPixel($hdc3, $screenX, $screenY)
                $r = $pixel -band 0xFF
                $g = ($pixel -shr 8) -band 0xFF
                $b = ($pixel -shr 16) -band 0xFF
                
                # Check if GRAY (R, G, B are similar and medium brightness 80-180)
                $isGray = ($r -ge 100 -and $r -le 180 -and $g -ge 100 -and $g -le 180 -and $b -ge 100 -and $b -le 180)
                $isSimilar = ([Math]::Abs($r - $g) -lt 20 -and [Math]::Abs($g - $b) -lt 20)
                
                # Check if RED (high R, low G and B) - agent is working
                $isRed = ($r -ge 150 -and $g -lt 100 -and $b -lt 100)
                
                # Check if BLUE/CYAN (high B, medium-high G, low R) - ready to send
                # This catches blue send arrows
                $isBlue = ($r -lt 100 -and $g -ge 100 -and $b -ge 150)
                
                if ($isGray -and $isSimilar) {
                    $foundGray = $true
                }
                if ($isRed) {
                    $foundRed = $true
                }
                if ($isBlue) {
                    $foundBlue = $true
                }
            }
        }
        
        # DETECTION STRATEGY:
        # - If RED button found -> Agent is working
        # - If NO RED found -> Chat is ready for input (works for light and dark themes)
        # We prioritize detecting red because it's the clearest indicator of "busy"
        
        if ($foundRed) {
            # ========== RED BUTTON: Agent is working ==========
            $result.chatButtonColor = "red"
            $result.isPaused = $true
            
            # Search for Accept dialog while agent is working
            $dialogStartY = [int]($height * 0.30)
            $dialogEndY = [int]($height * 0.78)
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
                        # Verify neighbor
                        $px1 = [FastDetector]::GetPixel($hdc3, $px + 20, $py)
                        $r1 = $px1 -band 0xFF; $g1 = ($px1 -shr 8) -band 0xFF; $b1 = ($px1 -shr 16) -band 0xFF
                        
                        if (Test-IsGreenAcceptButton -R $r1 -G $g1 -B $b1) {
                            $result.hasAcceptButton = $true
                            $result.isBottomButton = $false  # Dialog Accept, use Alt+Enter
                            $result.acceptButtonX = $px + 30
                            $result.acceptButtonY = $py
                            break
                        }
                    }
                }
            }
        }
        else {
            # ========== NO RED: Chat is ready for input ==========
            $result.chatButtonColor = "gray"  # Use "gray" to indicate ready
            
            # Search for Retry button in the dialog area
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
                    
                    # Blue Retry button
                    $isBlueRetry = ($pr -lt 100 -and $pg -ge 100 -and $pg -le 200 -and $pb -ge 180)
                    
                    if ($isBlueRetry) {
                        # Cluster check for real button
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
