/**
 * UI Automation Module - Wrapper for PowerShell UI automation scripts
 * Provides high-level API for detecting and interacting with Antigravity UI
 */

const { spawn } = require('child_process');
const path = require('path');

const SCRIPTS_DIR = path.join(__dirname, 'scripts');

/**
 * Execute a PowerShell script and return parsed JSON result
 */
function runPowerShell(scriptName, args = {}) {
    return new Promise((resolve, reject) => {
        const scriptPath = path.join(SCRIPTS_DIR, scriptName);

        // Build argument string
        const argPairs = Object.entries(args)
            .map(([key, value]) => `-${key} "${value}"`)
            .join(' ');

        const command = `powershell -ExecutionPolicy Bypass -File "${scriptPath}" ${argPairs}`;

        const proc = spawn('powershell', [
            '-ExecutionPolicy', 'Bypass',
            '-File', scriptPath,
            ...Object.entries(args).flatMap(([key, value]) => [`-${key}`, value.toString()])
        ], {
            stdio: ['ignore', 'pipe', 'pipe']
        });

        let stdout = '';
        let stderr = '';

        proc.stdout.on('data', (data) => {
            stdout += data.toString();
        });

        proc.stderr.on('data', (data) => {
            stderr += data.toString();
        });

        proc.on('close', (code) => {
            if (code !== 0 && !stdout) {
                reject(new Error(`Script failed with code ${code}: ${stderr}`));
                return;
            }

            try {
                // Extract JSON from output (may have other text)
                const jsonMatch = stdout.match(/\{.*\}/s);
                if (jsonMatch) {
                    resolve(JSON.parse(jsonMatch[0]));
                } else {
                    resolve({ success: true, output: stdout.trim() });
                }
            } catch (e) {
                resolve({ success: true, output: stdout.trim() });
            }
        });

        proc.on('error', (err) => {
            reject(err);
        });
    });
}

/**
 * UI state for an Antigravity instance
 */
const UIState = {
    IDLE: 'idle',           // Ready for input
    WORKING: 'working',     // Antigravity is processing
    WAITING: 'waiting',     // Has Accept/Enter button
    ERROR: 'error',         // Has Retry button
    UNKNOWN: 'unknown'
};

class UIAutomation {
    /**
     * Find all VS Code instances that could be running Antigravity
     */
    static async findInstances() {
        try {
            const result = await runPowerShell('find-instances.ps1');
            if (result.success && result.instances) {
                return result.instances.map(inst => ({
                    handle: inst.handle,
                    title: inst.title,
                    projectName: inst.projectName,
                    processId: inst.processId
                }));
            }
            return [];
        } catch (error) {
            console.error('Error finding instances:', error);
            return [];
        }
    }

    /**
     * Detect UI state of a specific window
     */
    static async detectUIState(windowHandle) {
        try {
            const result = await runPowerShell('detect-ui-state.ps1', {
                WindowHandle: windowHandle
            });

            if (result.error) {
                return {
                    state: UIState.UNKNOWN,
                    error: result.error,
                    buttons: null
                };
            }

            let state = UIState.IDLE;

            if (result.hasRetryButton) {
                state = UIState.ERROR;
            } else if (result.hasAcceptButton || result.hasEnterButton) {
                state = UIState.WAITING;
            }

            return {
                state,
                buttons: {
                    accept: result.hasAcceptButton ? { x: result.acceptButtonX, y: result.acceptButtonY } : null,
                    enter: result.hasEnterButton ? { x: result.enterButtonX, y: result.enterButtonY } : null,
                    retry: result.hasRetryButton ? { x: result.retryButtonX, y: result.retryButtonY } : null
                }
            };
        } catch (error) {
            console.error('Error detecting UI state:', error);
            return {
                state: UIState.UNKNOWN,
                error: error.message,
                buttons: null
            };
        }
    }

    /**
     * Click the Accept/Approve button
     */
    static async clickAccept(windowHandle, buttonX, buttonY) {
        try {
            const result = await runPowerShell('click-button.ps1', {
                WindowHandle: windowHandle,
                ScreenX: buttonX,
                ScreenY: buttonY
            });
            return result.success;
        } catch (error) {
            console.error('Error clicking accept:', error);
            return false;
        }
    }

    /**
     * Click the Enter button (to start next task)
     */
    static async clickEnter(windowHandle, buttonX, buttonY) {
        return this.clickAccept(windowHandle, buttonX, buttonY);
    }

    /**
     * Click the Retry button (after error)
     */
    static async clickRetry(windowHandle, buttonX, buttonY) {
        return this.clickAccept(windowHandle, buttonX, buttonY);
    }

    /**
     * Write a prompt to the chat and submit
     */
    static async sendPrompt(windowHandle, prompt) {
        try {
            const result = await runPowerShell('write-to-chat.ps1', {
                WindowHandle: windowHandle,
                Prompt: prompt
            });
            return result.success;
        } catch (error) {
            console.error('Error sending prompt:', error);
            return false;
        }
    }
}

module.exports = {
    UIAutomation,
    UIState
};
