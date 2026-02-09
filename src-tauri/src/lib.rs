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

/// Detect UI state (buttons) for a window using PowerShell
#[tauri::command]
fn detect_ui_state(window_handle: i64) -> Result<UIStateResult, String> {
    let script_path = get_script_path("detect-ui-state.ps1");

    println!("[detect_ui_state] Script path: {:?}", script_path);
    println!("[detect_ui_state] Script exists: {}", script_path.exists());
    println!("[detect_ui_state] Window handle: {}", window_handle);

    let output = Command::new("powershell")
        .args([
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            script_path
                .to_str()
                .unwrap_or("scripts/detect-ui-state.ps1"),
            "-WindowHandle",
            &window_handle.to_string(),
        ])
        .output()
        .map_err(|e| format!("Failed to execute PowerShell: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);

    println!("[detect_ui_state] stdout: {}", stdout);
    println!("[detect_ui_state] stderr: {}", stderr);
    println!("[detect_ui_state] exit code: {:?}", output.status.code());

    // Try to parse JSON from output
    if let Some(json_match) = stdout.find('{') {
        let json_str = &stdout[json_match..];
        if let Some(end) = json_str.rfind('}') {
            let json = &json_str[..=end];
            return serde_json::from_str(json)
                .map_err(|e| format!("Failed to parse JSON: {} - Output: {}", e, json));
        }
    }

    // Return default state if parsing failed
    Ok(UIStateResult {
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
        error: Some(format!("No valid JSON found in output: {}", stdout)),
    })
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

/// Read backlog from project path
#[tauri::command]
fn read_backlog(project_path: String) -> Result<BacklogResult, String> {
    let script_path = if cfg!(debug_assertions) {
        std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .map(|p| p.join("scripts").join("read-backlog.ps1"))
            .unwrap_or_else(|| std::path::PathBuf::from("scripts/read-backlog.ps1"))
    } else {
        std::env::current_exe()
            .ok()
            .and_then(|p| {
                p.parent()
                    .map(|p| p.join("scripts").join("read-backlog.ps1"))
            })
            .unwrap_or_else(|| std::path::PathBuf::from("scripts/read-backlog.ps1"))
    };

    let output = std::process::Command::new("powershell")
        .args([
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            script_path.to_str().unwrap_or("scripts/read-backlog.ps1"),
            "-ProjectPath",
            &project_path,
        ])
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
