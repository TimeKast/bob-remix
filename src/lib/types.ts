// Types for Antigravity Monitor

export type InstanceStatus = 'idle' | 'working' | 'error' | 'complete' | 'disabled' | 'blocked';

export interface Instance {
    id: string;
    windowTitle: string;
    windowHandle: number;
    projectPath: string;
    projectName: string;
    enabled: boolean;
    customPrompt?: string;
    currentIssue: number;
    totalIssues: number;
    retryCount: number;
    maxRetries: number;
    status: InstanceStatus;
    lastActivity: number;
    stepCount: number;
    // New fields for auto-implementation
    lastResponse?: string;
    isBlocked?: boolean;
    blockReason?: string;
    issuesCompleted?: number;
    lastPromptSent?: number;  // Timestamp of last prompt sent (for inactivity timeout)
}

export interface Settings {
    defaultPrompt: string;
    inactivitySeconds: number;
    maxRetries: number;
    discordWebhook: string;
    notifyOnComplete: boolean;
    notifyOnError: boolean;
    minimizeToTray: boolean;
    // New fields for auto-implementation
    autoPrompt: string;
    pollIntervalSeconds: number;
    stopConditions: string[];
    inactivityTimeoutMinutes: number;  // Minutes before stopping inactive project (default 20)
    // Logging settings
    loggingEnabled: boolean;
    logFilePath: string;  // Path to log file (e.g., "C:/logs/antigravity.log")
}

export interface ScanResult {
    windowTitle: string;
    windowHandle: number;
    processId: number;
}

// Stop condition detection result
export interface StopCondition {
    detected: boolean;
    condition: string;
    message: string;
}
