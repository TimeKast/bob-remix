// BOB - Tauri Backend
// Commands for window scanning, monitoring, and system integration

use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::process::Command;

#[derive(Debug, Serialize, Deserialize)]
pub struct ScanResult {
    #[serde(rename = "windowTitle")]
    pub window_title: String,
    #[serde(rename = "windowHandle")]
    pub window_handle: i64,
    #[serde(rename = "processId")]
    pub process_id: u32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct InstanceStatus {
    pub status: String,
    #[serde(rename = "currentIssue")]
    pub current_issue: u32,
    #[serde(rename = "totalIssues")]
    pub total_issues: u32,
    #[serde(rename = "retryCount")]
    pub retry_count: u32,
    #[serde(rename = "lastActivity")]
    pub last_activity: u64,
    #[serde(rename = "stepCount")]
    pub step_count: u32,
}

/// Helper function to find script path in multiple locations
fn get_script_path(script_name: &str) -> PathBuf {
    if cfg!(debug_assertions) {
        // Development: use CARGO_MANIFEST_DIR (src-tauri) parent + scripts
        std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .map(|p| p.join("scripts").join(script_name))
            .unwrap_or_else(|| PathBuf::from(format!("scripts/{}", script_name)))
    } else {
        // Production: check exe directory for scripts
        let exe_dir = std::env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(|d| d.to_path_buf()));

        if let Some(ref dir) = exe_dir {
            // Try _up_/scripts/ (Tauri NSIS installer location)
            let up_scripts = dir.join("_up_").join("scripts").join(script_name);
            if up_scripts.exists() {
                return up_scripts;
            }

            // Try direct script file in exe dir
            let direct = dir.join(script_name);
            if direct.exists() {
                return direct;
            }

            // Try scripts subfolder
            let scripts = dir.join("scripts").join(script_name);
            if scripts.exists() {
                return scripts;
            }
        }

        // Fallback to _up_/scripts (most likely for NSIS)
        exe_dir
            .map(|d| d.join("_up_").join("scripts").join(script_name))
            .unwrap_or_else(|| PathBuf::from(script_name))
    }
}

/// Scan for VS Code / Antigravity windows using PowerShell
#[tauri::command]
fn scan_windows() -> Result<Vec<ScanResult>, String> {
    let script_path = get_script_path("detect-windows.ps1");

    let output = Command::new("powershell")
        .args([
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            script_path.to_str().unwrap_or("scripts/detect-windows.ps1"),
        ])
        .output()
        .map_err(|e| format!("Failed to execute PowerShell: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!(
            "PowerShell script failed: {} (path: {:?})",
            stderr, script_path
        ));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);

    // Handle empty output (no windows found)
    if stdout.trim().is_empty() {
        return Ok(vec![]);
    }

    // Handle single object vs array
    let results: Vec<ScanResult> = if stdout.trim().starts_with('[') {
        serde_json::from_str(&stdout)
            .map_err(|e| format!("Failed to parse JSON array: {} - Output: {}", e, stdout))?
    } else {
        // Single object, wrap in array
        let single: ScanResult = serde_json::from_str(&stdout)
            .map_err(|e| format!("Failed to parse JSON object: {} - Output: {}", e, stdout))?;
        vec![single]
    };

    Ok(results)
}

/// Get the current status of a monitored instance
#[tauri::command]
fn get_instance_status(_window_handle: i64) -> Result<InstanceStatus, String> {
    // TODO: Implement actual status checking
    Ok(InstanceStatus {
        status: "idle".to_string(),
        current_issue: 0,
        total_issues: 0,
        retry_count: 0,
        last_activity: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64,
        step_count: 0,
    })
}

/// Paste a prompt to a specific window
#[tauri::command]
fn paste_prompt(window_title: String, prompt: String, instance_id: String) -> Result<(), String> {
    let script_path = get_script_path("paste-prompt.ps1");

    let output = Command::new("powershell")
        .args([
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            script_path.to_str().unwrap_or("scripts/paste-prompt.ps1"),
            "-Prompt",
            &prompt,
            "-WindowTitle",
            &window_title,
            "-InstanceId",
            &instance_id,
        ])
        .output()
        .map_err(|e| format!("Failed to execute PowerShell: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Failed to paste prompt: {}", stderr));
    }

    Ok(())
}

// UI Automation types
#[derive(Debug, Serialize, Deserialize)]
pub struct UIStateResult {
    #[serde(rename = "hasAcceptButton")]
    pub has_accept_button: bool,
    #[serde(rename = "hasEnterButton")]
    pub has_enter_button: bool,
    #[serde(rename = "hasRetryButton")]
    pub has_retry_button: bool,
    #[serde(rename = "isPaused")]
    pub is_paused: bool,
    #[serde(rename = "chatButtonColor", default)]
    pub chat_button_color: String,
    #[serde(rename = "acceptButtonX")]
    pub accept_button_x: i32,
    #[serde(rename = "acceptButtonY")]
    pub accept_button_y: i32,
    #[serde(rename = "enterButtonX")]
    pub enter_button_x: i32,
    #[serde(rename = "enterButtonY")]
    pub enter_button_y: i32,
    #[serde(rename = "retryButtonX")]
    pub retry_button_x: i32,
    #[serde(rename = "retryButtonY")]
    pub retry_button_y: i32,
    #[serde(rename = "isBottomButton")]
    pub is_bottom_button: bool,
    pub error: Option<String>,
}

/// Detect UI state using native Win32 API (no PowerShell overhead)
#[tauri::command]
fn detect_ui_state(window_handle: i64) -> Result<UIStateResult, String> {
    use std::time::Instant;
    let start = Instant::now();

    #[cfg(target_os = "windows")]
    {
        use winapi::shared::windef::{HDC, HWND, RECT};
        use winapi::um::wingdi::GetPixel;
        use winapi::um::winuser::{
            GetDC, GetWindowRect, IsIconic, ReleaseDC, SendInput, SetCursorPos,
            SetForegroundWindow, SetProcessDPIAware, ShowWindow, INPUT, MOUSEEVENTF_WHEEL,
        };

        unsafe {
            SetProcessDPIAware();

            let hwnd = window_handle as HWND;

            let mut result = UIStateResult {
                has_accept_button: false,
                has_enter_button: false,
                has_retry_button: false,
                is_paused: false,
                chat_button_color: String::from("none"),
                accept_button_x: 0,
                accept_button_y: 0,
                enter_button_x: 0,
                enter_button_y: 0,
                retry_button_x: 0,
                retry_button_y: 0,
                is_bottom_button: false,
                error: None,
            };

            // Check if minimized
            if IsIconic(hwnd) != 0 {
                result.error = Some("Window is minimized".to_string());
                return Ok(result);
            }

            // Get window rect
            let mut rect: RECT = std::mem::zeroed();
            GetWindowRect(hwnd, &mut rect);
            let width = rect.right - rect.left;
            let height = rect.bottom - rect.top;

            if width <= 0 || height <= 0 {
                result.error = Some("Invalid window size".to_string());
                return Ok(result);
            }

            // Only restore if minimized
            if IsIconic(hwnd) != 0 {
                ShowWindow(hwnd, 9); // SW_RESTORE
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
            SetForegroundWindow(hwnd);
            std::thread::sleep(std::time::Duration::from_millis(50));

            // Scroll to bottom (mouse wheel in chat area)
            let chat_x = rect.left + (width as f64 * 0.88) as i32;
            let chat_y = rect.top + (height as f64 * 0.5) as i32;
            SetCursorPos(chat_x, chat_y);
            std::thread::sleep(std::time::Duration::from_millis(30));

            for _ in 0..5 {
                let mut input: INPUT = std::mem::zeroed();
                input.type_ = 0; // INPUT_MOUSE
                let mi = input.u.mi_mut();
                mi.dwFlags = MOUSEEVENTF_WHEEL;
                mi.mouseData = (-120 * 10) as u32; // Scroll down aggressively
                SendInput(1, &mut input, std::mem::size_of::<INPUT>() as i32);
                std::thread::sleep(std::time::Duration::from_millis(15));
            }
            std::thread::sleep(std::time::Duration::from_millis(80));

            // Single DC for all scanning
            let hdc: HDC = GetDC(std::ptr::null_mut());

            // ===== PIXEL RELIABILITY CHECK =====
            // On non-primary monitors (negative coords), GetPixel returns all-same values.
            // Sample 10 diverse points. If they're ALL identical, GetPixel is broken → bail out.
            let test_points: [(f64, f64); 10] = [
                (0.3, 0.3),
                (0.5, 0.5),
                (0.7, 0.3),
                (0.3, 0.7),
                (0.9, 0.9),
                (0.5, 0.8),
                (0.8, 0.5),
                (0.6, 0.6),
                (0.4, 0.9),
                (0.9, 0.4),
            ];
            let mut first_pixel: Option<u32> = None;
            let mut all_same = true;
            for &(xp, yp) in &test_points {
                let tx = rect.left + (width as f64 * xp) as i32;
                let ty = rect.top + (height as f64 * yp) as i32;
                let tp = GetPixel(hdc, tx, ty);
                if tp == 0xFFFFFFFF {
                    continue;
                } // CLR_INVALID, skip
                match first_pixel {
                    None => {
                        first_pixel = Some(tp);
                    }
                    Some(fp) => {
                        if tp != fp {
                            all_same = false;
                            break;
                        }
                    }
                }
            }

            if all_same && first_pixel.is_some() {
                // GetPixel is broken for this window position (all pixels identical)
                // Return "none" state - frontend should NOT send prompts
                println!("[detect_ui_state] PIXEL RELIABILITY FAILED: all 10 test pixels returned same value {:?}. Window at L={} T={} R={} B={}",
                    first_pixel, rect.left, rect.top, rect.right, rect.bottom);
                ReleaseDC(std::ptr::null_mut(), hdc);
                result.chat_button_color = "none".to_string();
                result.error = Some(format!(
                    "GetPixel unreliable at window position L={} T={}",
                    rect.left, rect.top
                ));
                return Ok(result);
            }

            let step_x = 30;
            let step_y = 25;

            // ===== PASS 1: Scan for Accept/Run buttons (blue/green/teal) =====
            let scan_start_x = (width as f64 * 0.50) as i32;
            let scan_end_x = (width as f64 * 0.98) as i32;
            let scan_start_y = (height as f64 * 0.15) as i32;
            let scan_end_y = (height as f64 * 0.98) as i32;

            let mut y = scan_end_y;
            while y > scan_start_y && !result.has_accept_button {
                let mut x = scan_start_x;
                while x < scan_end_x {
                    let sx = rect.left + x;
                    let sy = rect.top + y;

                    let pixel = GetPixel(hdc, sx, sy);
                    if pixel == 0xFFFFFFFF {
                        x += step_x;
                        continue;
                    } // CLR_INVALID

                    let r = pixel & 0xFF;
                    let g = (pixel >> 8) & 0xFF;
                    let b = (pixel >> 16) & 0xFF;

                    // Blue/Green/Teal button
                    if r < 100 && g >= 100 && b >= 150 {
                        // Verify neighbor
                        let px1 = GetPixel(hdc, sx + 25, sy);
                        let r1 = px1 & 0xFF;
                        let g1 = (px1 >> 8) & 0xFF;
                        let b1 = (px1 >> 16) & 0xFF;

                        if r1 < 100 && g1 >= 100 && b1 >= 150 {
                            result.has_accept_button = true;
                            result.accept_button_x = sx + 15;
                            result.accept_button_y = sy;
                            result.is_bottom_button = y > (height as f64 * 0.65) as i32;
                            break;
                        }
                    }

                    x += step_x;
                }
                y -= step_y;
            }

            // ===== PASS 2: Check for pause/stop (red square) =====
            if !result.has_accept_button {
                let pause_start_x = (width as f64 * 0.80) as i32;
                let pause_end_x = (width as f64 * 0.97) as i32;
                let pause_start_y = (height as f64 * 0.82) as i32;
                let pause_end_y = (height as f64 * 0.97) as i32;

                let mut y = pause_start_y;
                'pause_outer: while y < pause_end_y {
                    let mut x = pause_start_x;
                    while x < pause_end_x {
                        let sx = rect.left + x;
                        let sy = rect.top + y;

                        let pixel = GetPixel(hdc, sx, sy);
                        let r = pixel & 0xFF;
                        let g = (pixel >> 8) & 0xFF;
                        let b = (pixel >> 16) & 0xFF;

                        if r >= 180 && g < 100 && b < 100 {
                            // Quick neighbor verify
                            let px1 = GetPixel(hdc, sx + 5, sy);
                            if (px1 & 0xFF) >= 180 {
                                result.is_paused = true;
                                result.chat_button_color = "red".to_string();
                                break 'pause_outer;
                            }
                        }
                        x += 12;
                    }
                    y += 12;
                }
            }

            // ===== PASS 3: Determine chat state =====
            if !result.has_accept_button && !result.is_paused {
                let mut found_red = false;

                let x_offsets = [30, 50, 80, 120, 160, 200, 250];
                let y_offsets = [30, 50, 70, 100, 130, 160];

                for &xo in &x_offsets {
                    if found_red {
                        break;
                    }
                    for &yo in &y_offsets {
                        let sx = rect.right - xo;
                        let sy = rect.bottom - yo;

                        let pixel = GetPixel(hdc, sx, sy);
                        let r = pixel & 0xFF;
                        let g = (pixel >> 8) & 0xFF;
                        let b = (pixel >> 16) & 0xFF;

                        if r >= 150 && g < 100 && b < 100 {
                            found_red = true;
                            break;
                        }
                    }
                }

                if found_red {
                    result.chat_button_color = "red".to_string();
                    result.is_paused = true;
                } else {
                    result.chat_button_color = "gray".to_string();

                    // Check for Retry button with cluster verification
                    let retry_start_y = (height as f64 * 0.55) as i32;
                    let retry_end_y = (height as f64 * 0.95) as i32;
                    let retry_start_x = (width as f64 * 0.55) as i32;
                    let retry_end_x = (width as f64 * 0.95) as i32;

                    let mut ry = retry_end_y;
                    'retry_outer: while ry > retry_start_y {
                        let mut rx = retry_start_x;
                        while rx < retry_end_x {
                            let px = rect.left + rx;
                            let py = rect.top + ry;

                            let pxl = GetPixel(hdc, px, py);
                            let pr = pxl & 0xFF;
                            let pg = (pxl >> 8) & 0xFF;
                            let pb = (pxl >> 16) & 0xFF;

                            // Blue Retry button
                            if pr < 100 && pg >= 100 && pg <= 200 && pb >= 180 {
                                let mut blue_count = 1u32;
                                for check_x in (10..=40).step_by(10) {
                                    let cpx = GetPixel(hdc, px + check_x, py);
                                    let cr = cpx & 0xFF;
                                    let cg = (cpx >> 8) & 0xFF;
                                    let cb = (cpx >> 16) & 0xFF;
                                    if cr < 100 && cg >= 100 && cb >= 180 {
                                        blue_count += 1;
                                    }
                                }

                                if blue_count >= 3 {
                                    result.has_retry_button = true;
                                    result.retry_button_x = px + 20;
                                    result.retry_button_y = py;
                                    break 'retry_outer;
                                }
                            }
                            rx += 25;
                        }
                        ry -= 20;
                    }

                    // If no Retry, chat is ready
                    if !result.has_retry_button {
                        result.has_enter_button = true;
                        result.enter_button_x = rect.right - 60;
                        result.enter_button_y = rect.bottom - 50;
                    }
                }
            }

            ReleaseDC(std::ptr::null_mut(), hdc);

            let elapsed = start.elapsed().as_millis();
            println!(
                "[detect_ui_state] Native detection completed in {}ms",
                elapsed
            );

            return Ok(result);
        }
    }

    #[cfg(not(target_os = "windows"))]
    {
        Err("UI detection only supported on Windows".to_string())
    }
}

/// Click a button at screen coordinates
#[tauri::command]
fn click_button(window_handle: i64, screen_x: i32, screen_y: i32) -> Result<bool, String> {
    let script_path = if cfg!(debug_assertions) {
        std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .map(|p| p.join("scripts").join("click-button.ps1"))
            .unwrap_or_else(|| std::path::PathBuf::from("scripts/click-button.ps1"))
    } else {
        std::env::current_exe()
            .ok()
            .and_then(|p| {
                p.parent()
                    .map(|p| p.join("scripts").join("click-button.ps1"))
            })
            .unwrap_or_else(|| std::path::PathBuf::from("scripts/click-button.ps1"))
    };

    println!("[click_button] Script path: {:?}", script_path);
    println!("[click_button] Script exists: {}", script_path.exists());
    let output = Command::new("powershell")
        .args([
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            script_path.to_str().unwrap_or("scripts/click-button.ps1"),
            "-WindowHandle",
            &window_handle.to_string(),
            "-ScreenX",
            &screen_x.to_string(),
            "-ScreenY",
            &screen_y.to_string(),
        ])
        .output()
        .map_err(|e| format!("Failed to execute PowerShell: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);

    println!("[click_button] Clicked at ({}, {})", screen_x, screen_y);
    println!("[click_button] stdout: {}", stdout);
    if !stderr.is_empty() {
        println!("[click_button] stderr: {}", stderr);
    }

    // Check if success in output
    Ok(stdout.contains("\"success\":true") || stdout.contains("success\": true"))
}

/// Accept dialog using Alt+Enter keyboard shortcut
#[tauri::command]
fn accept_dialog(window_handle: i64) -> Result<bool, String> {
    let script_path = if cfg!(debug_assertions) {
        std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .map(|p| p.join("scripts").join("accept-dialog.ps1"))
            .unwrap_or_else(|| std::path::PathBuf::from("scripts/accept-dialog.ps1"))
    } else {
        std::env::current_exe()
            .ok()
            .and_then(|p| {
                p.parent()
                    .map(|p| p.join("scripts").join("accept-dialog.ps1"))
            })
            .unwrap_or_else(|| std::path::PathBuf::from("scripts/accept-dialog.ps1"))
    };

    println!("[accept_dialog] Script path: {:?}", script_path);
    println!("[accept_dialog] Window handle: {}", window_handle);

    let output = Command::new("powershell")
        .args([
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            script_path.to_str().unwrap_or("scripts/accept-dialog.ps1"),
            "-WindowHandle",
            &window_handle.to_string(),
        ])
        .output()
        .map_err(|e| format!("Failed to execute PowerShell: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    println!("[accept_dialog] stdout: {}", stdout);

    Ok(stdout.contains("\"success\":true") || stdout.contains("success\": true"))
}

/// Scroll chat to bottom using Ctrl+End
#[tauri::command]
fn scroll_to_bottom(window_handle: i64) -> Result<bool, String> {
    let script_path = if cfg!(debug_assertions) {
        std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .map(|p| p.join("scripts").join("scroll-to-bottom.ps1"))
            .unwrap_or_else(|| std::path::PathBuf::from("scripts/scroll-to-bottom.ps1"))
    } else {
        std::env::current_exe()
            .ok()
            .and_then(|p| {
                p.parent()
                    .map(|p| p.join("scripts").join("scroll-to-bottom.ps1"))
            })
            .unwrap_or_else(|| std::path::PathBuf::from("scripts/scroll-to-bottom.ps1"))
    };

    let output = std::process::Command::new("powershell")
        .args([
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            script_path
                .to_str()
                .unwrap_or("scripts/scroll-to-bottom.ps1"),
            "-WindowHandle",
            &window_handle.to_string(),
        ])
        .output()
        .map_err(|e| format!("Failed to execute PowerShell: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    Ok(stdout.contains("\"success\":true") || stdout.contains("success\": true"))
}

// Backlog reading result
#[derive(Debug, Serialize, Deserialize)]
pub struct BacklogResult {
    #[serde(rename = "totalIssues", default)]
    pub total_issues: i32,
    #[serde(rename = "completedIssues", default)]
    pub completed_issues: i32,
    #[serde(rename = "currentIssue", default)]
    pub current_issue: String,
    #[serde(rename = "backlogPath", default)]
    pub backlog_path: String,
    pub error: Option<String>,
}

/// Read backlog from project path (with optional custom path and mode)
#[tauri::command]
fn read_backlog(
    project_path: String,
    backlog_path: Option<String>,
    mode: Option<String>,
) -> Result<BacklogResult, String> {
    let script_path = get_script_path("read-backlog.ps1");

    let mut args = vec![
        "-ExecutionPolicy".to_string(),
        "Bypass".to_string(),
        "-File".to_string(),
        script_path
            .to_str()
            .unwrap_or("scripts/read-backlog.ps1")
            .to_string(),
        "-ProjectPath".to_string(),
        project_path,
    ];

    if let Some(ref bp) = backlog_path {
        if !bp.is_empty() {
            args.push("-BacklogPath".to_string());
            args.push(bp.clone());
        }
    }

    if let Some(ref m) = mode {
        if !m.is_empty() {
            args.push("-Mode".to_string());
            args.push(m.clone());
        }
    }

    let output = std::process::Command::new("powershell")
        .args(&args)
        .output()
        .map_err(|e| format!("Failed to execute PowerShell: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout);

    // Parse JSON output
    if let Ok(result) = serde_json::from_str::<BacklogResult>(&stdout) {
        return Ok(result);
    }

    Ok(BacklogResult {
        total_issues: 0,
        completed_issues: 0,
        current_issue: String::new(),
        backlog_path: String::new(),
        error: Some(format!("Failed to parse backlog: {}", stdout)),
    })
}

/// Write to chat and submit prompt
#[tauri::command]
fn write_to_chat(window_handle: i64, prompt: String) -> Result<bool, String> {
    let script_path = if cfg!(debug_assertions) {
        std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .map(|p| p.join("scripts").join("write-to-chat.ps1"))
            .unwrap_or_else(|| std::path::PathBuf::from("scripts/write-to-chat.ps1"))
    } else {
        std::env::current_exe()
            .ok()
            .and_then(|p| {
                p.parent()
                    .map(|p| p.join("scripts").join("write-to-chat.ps1"))
            })
            .unwrap_or_else(|| std::path::PathBuf::from("scripts/write-to-chat.ps1"))
    };

    println!("[write_to_chat] Script path: {:?}", script_path);
    println!(
        "[write_to_chat] Window handle: {}, Prompt: {}",
        window_handle, prompt
    );

    let output = Command::new("powershell")
        .args([
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            script_path.to_str().unwrap_or("scripts/write-to-chat.ps1"),
            "-WindowHandle",
            &window_handle.to_string(),
            "-Prompt",
            &prompt,
        ])
        .output()
        .map_err(|e| format!("Failed to execute PowerShell: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);

    println!("[write_to_chat] stdout: {}", stdout);
    println!("[write_to_chat] stderr: {}", stderr);
    println!("[write_to_chat] exit code: {:?}", output.status.code());

    // Check if success in output
    let success = stdout.contains("\"success\":true") || stdout.contains("success\": true");
    println!("[write_to_chat] success: {}", success);

    Ok(success)
}

/// Send a notification to Discord webhook
#[tauri::command]
async fn notify_discord(webhook_url: String, title: String, message: String) -> Result<(), String> {
    let client = reqwest::Client::new();

    let payload = serde_json::json!({
        "embeds": [{
            "title": title,
            "description": message,
            "color": 5814783, // Cyan color
            "footer": {
                "text": "BOB Monitor"
            },
            "timestamp": chrono::Utc::now().to_rfc3339()
        }]
    });

    client
        .post(&webhook_url)
        .json(&payload)
        .send()
        .await
        .map_err(|e| format!("Failed to send Discord notification: {}", e))?;

    Ok(())
}

/// Write a log entry to file
#[tauri::command]
fn write_log(log_path: String, level: String, message: String) -> Result<(), String> {
    use std::fs::{create_dir_all, OpenOptions};
    use std::io::Write;

    // Use provided path or default to exe directory
    let path = if log_path.is_empty() {
        std::env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(|d| d.join("bob.log")))
            .unwrap_or_else(|| PathBuf::from("bob.log"))
    } else {
        PathBuf::from(&log_path)
    };

    // Create parent directory if it doesn't exist
    if let Some(parent) = path.parent() {
        if !parent.exists() {
            create_dir_all(parent).map_err(|e| format!("Failed to create log directory: {}", e))?;
        }
    }

    // Get current timestamp
    let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S%.3f");

    // Format log entry
    let log_entry = format!("[{}] [{}] {}\n", timestamp, level.to_uppercase(), message);

    // Append to file
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .map_err(|e| format!("Failed to open log file: {}", e))?;

    file.write_all(log_entry.as_bytes())
        .map_err(|e| format!("Failed to write to log file: {}", e))?;

    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            scan_windows,
            get_instance_status,
            paste_prompt,
            notify_discord,
            detect_ui_state,
            click_button,
            accept_dialog,
            scroll_to_bottom,
            read_backlog,
            write_to_chat,
            write_log
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
