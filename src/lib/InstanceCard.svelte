<script lang="ts">
  import type { Instance, BacklogMode } from "./types";
  import {
    testInstance,
    detectUIState,
    clickAcceptButton,
    acceptDialog,
    writeToChat,
    settings,
    updateInstanceBacklogConfig,
  } from "./store";

  interface Props {
    instance: Instance;
    onToggle: () => void;
  }

  let { instance, onToggle }: Props = $props();
  let testResult = $state<string>("");
  let testing = $state(false);
  let showBacklogConfig = $state(false);
  let backlogPath = $state(instance.backlogConfig?.path || "");
  let backlogMode = $state<BacklogMode>(instance.backlogConfig?.mode || "auto");

  const statusColors: Record<string, string> = {
    idle: "#ffb800",
    working: "#00ff88",
    error: "#ff4757",
    complete: "#00d9ff",
    disabled: "#666",
    blocked: "#ff6b35",
  };

  const statusIcons: Record<string, string> = {
    idle: "🟡",
    working: "🟢",
    error: "🔴",
    complete: "✅",
    disabled: "⚪",
    blocked: "🚫",
  };

  function formatTime(timestamp: number): string {
    const diff = Date.now() - timestamp;
    const seconds = Math.floor(diff / 1000);
    if (seconds < 60) return `${seconds}s ago`;
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) return `${minutes}m ago`;
    return `${Math.floor(minutes / 60)}h ago`;
  }

  async function handleDetectUI() {
    testing = true;
    testResult = "Detecting...";
    const result = await detectUIState(instance.windowHandle);
    if (result) {
      if (result.error) {
        testResult = `Error: ${result.error}`;
      } else {
        const states = [];
        // Show chat button color first
        if (result.chatButtonColor === "gray") states.push("🟢 Ready");
        else if (result.chatButtonColor === "red") states.push("🔴 Working");
        else if (!result.hasAcceptButton) states.push("⚪ Unknown");

        // Then show detected buttons
        if (result.hasAcceptButton) {
          states.push(result.isBottomButton ? "Accept all" : "Accept (dialog)");
        }
        if (result.hasRetryButton) states.push("❌ Retry");
        if (result.hasEnterButton) states.push("➡️ Enter");

        testResult =
          states.length > 0
            ? `Found: ${states.join(", ")}`
            : "No buttons found";
      }
    } else {
      testResult = "Detection failed";
    }
    testing = false;
  }

  async function handleDetectAndAct() {
    testing = true;
    testResult = "Detecting...";

    try {
      const result = await detectUIState(instance.windowHandle);

      if (result) {
        // STEP 1: Accept all (priority)
        if (result.hasAcceptButton && result.isBottomButton) {
          testResult = "Clicking Accept all...";
          const acceptResult = await clickAcceptButton(
            instance.windowHandle,
            result.acceptButtonX,
            result.acceptButtonY,
          );
          testResult = acceptResult
            ? "✅ Clicked Accept all"
            : "❌ Click failed";
        }
        // STEP 2: Gray button = chat ready
        else if (result.chatButtonColor === "gray") {
          if (result.hasRetryButton) {
            testResult = "❌ Found Retry - click manually";
          } else if (result.hasEnterButton) {
            testResult = "Sending prompt...";
            const prompt = instance.customPrompt || $settings.autoPrompt;
            const sendResult = await writeToChat(instance.windowHandle, prompt);
            testResult = sendResult ? "✅ Sent prompt" : "❌ Send failed";
          } else {
            testResult = "🟢 Ready but no action";
          }
        }
        // STEP 3: Red button = agent working
        else if (result.chatButtonColor === "red") {
          if (result.hasAcceptButton && !result.isBottomButton) {
            testResult = "Sending Alt+Enter...";
            const acceptResult = await acceptDialog(instance.windowHandle);
            testResult = acceptResult
              ? "✅ Accepted dialog"
              : "❌ Accept failed";
          } else {
            testResult = "🔴 Agent working...";
          }
        }
        // Unknown state
        else {
          testResult = `⚪ Unknown (${result.chatButtonColor})`;
        }
      } else {
        testResult = "Detection failed";
      }
    } catch (error) {
      testResult = `❌ Error: ${error}`;
      console.error("Detect & Act error:", error);
    } finally {
      testing = false;
    }
  }

  function saveBacklogConfig() {
    updateInstanceBacklogConfig(instance.id, {
      path: backlogPath,
      mode: backlogMode,
    });
    showBacklogConfig = false;
  }
</script>

<div
  class="card"
  class:disabled={!instance.enabled}
  class:error={instance.status === "error"}
>
  <div class="header">
    <div class="title">
      <span class="status-icon">{statusIcons[instance.status]}</span>
      <span class="name">{instance.projectName}</span>
    </div>
    <label class="toggle">
      <input type="checkbox" checked={instance.enabled} onchange={onToggle} />
      <span class="slider"></span>
    </label>
  </div>

  <div class="content">
    <div class="progress-bar">
      <div
        class="progress-fill"
        style="width: {instance.totalIssues > 0
          ? (instance.currentIssue / instance.totalIssues) * 100
          : 0}%; background: {statusColors[instance.status]}"
      ></div>
    </div>

    <div class="stats">
      <span class="stat">
        📋 {instance.currentIssue}/{instance.totalIssues} issues
      </span>
      <span class="stat">
        🔄 {instance.stepCount} steps
      </span>
      {#if instance.retryCount > 0}
        <span class="stat retry">
          ⚠️ Retry {instance.retryCount}/{$settings.maxRetries}
        </span>
      {:else}
        <span class="stat">
          🔄 Retries: 0/{$settings.maxRetries}
        </span>
      {/if}
    </div>

    <div class="meta">
      <span class="path" title={instance.projectPath}>
        📁 {instance.projectPath.split(/[/\\]/).pop()}
      </span>
      <span class="time">
        ⏱️ {formatTime(instance.lastActivity)}
      </span>
    </div>

    {#if instance.customPrompt}
      <div class="custom-prompt">
        💬 {instance.customPrompt}
      </div>
    {/if}

    {#if instance.isBlocked}
      <div class="blocked-indicator">
        🚫 Bloqueado: {instance.blockReason || "Requiere atención manual"}
      </div>
    {/if}

    <!-- Backlog Config -->
    <div class="backlog-config-row">
      <button
        class="btn-config"
        class:active={showBacklogConfig}
        onclick={() => (showBacklogConfig = !showBacklogConfig)}
        title="Configure backlog path"
      >
        📂 Backlog
      </button>
      {#if instance.backlogConfig?.path}
        <span class="config-indicator" title={instance.backlogConfig.path}>
          ✓ {instance.backlogConfig.mode}
        </span>
      {/if}
    </div>

    {#if showBacklogConfig}
      <div class="backlog-config">
        <div class="config-field">
          <label for="backlogPath-{instance.id}">Path</label>
          <input
            type="text"
            id="backlogPath-{instance.id}"
            bind:value={backlogPath}
            placeholder="e.g. backlog.md, docs/issues, plan/"
          />
          <span class="config-hint"
            >Relative to project root, or absolute path</span
          >
        </div>
        <div class="config-field">
          <label for="backlogMode-{instance.id}">Mode</label>
          <select id="backlogMode-{instance.id}" bind:value={backlogMode}>
            <option value="auto">🔍 Auto (smart detection)</option>
            <option value="file">📄 Single File (checkboxes)</option>
            <option value="folder">📁 Folder (each .md = 1 issue)</option>
          </select>
        </div>
        <div class="config-actions">
          <button class="btn-config-save" onclick={saveBacklogConfig}
            >💾 Save</button
          >
          <button
            class="btn-config-cancel"
            onclick={() => (showBacklogConfig = false)}>✕</button
          >
        </div>
      </div>
    {/if}

    <!-- Test Controls -->
    <div class="test-controls">
      <button class="btn-test" onclick={handleDetectUI} disabled={testing}>
        🔍 Detect UI
      </button>
      <button
        class="btn-test btn-send"
        onclick={handleDetectAndAct}
        disabled={testing}
      >
        ⚡ Detect & Act
      </button>
    </div>
    {#if testResult}
      <div class="test-result">
        {testResult}
      </div>
    {/if}
  </div>
</div>

<style>
  .card {
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 12px;
    padding: 1rem;
    transition: all 0.3s ease;
  }

  .card:hover {
    background: rgba(255, 255, 255, 0.08);
    transform: translateX(4px);
  }

  .card.disabled {
    opacity: 0.5;
  }

  .card.error {
    border-color: #ff4757;
    animation: pulse 2s infinite;
  }

  @keyframes pulse {
    0%,
    100% {
      box-shadow: 0 0 0 0 rgba(255, 71, 87, 0.4);
    }
    50% {
      box-shadow: 0 0 0 8px rgba(255, 71, 87, 0);
    }
  }

  .header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.75rem;
  }

  .title {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .status-icon {
    font-size: 0.9rem;
  }

  .name {
    font-weight: 600;
    font-size: 1rem;
  }

  /* Toggle switch */
  .toggle {
    position: relative;
    width: 44px;
    height: 24px;
  }

  .toggle input {
    opacity: 0;
    width: 0;
    height: 0;
  }

  .slider {
    position: absolute;
    cursor: pointer;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background-color: #444;
    transition: 0.3s;
    border-radius: 24px;
  }

  .slider:before {
    position: absolute;
    content: "";
    height: 18px;
    width: 18px;
    left: 3px;
    bottom: 3px;
    background-color: white;
    transition: 0.3s;
    border-radius: 50%;
  }

  input:checked + .slider {
    background: linear-gradient(90deg, #00d9ff, #00ff88);
  }

  input:checked + .slider:before {
    transform: translateX(20px);
  }

  .content {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .progress-bar {
    height: 4px;
    background: rgba(255, 255, 255, 0.1);
    border-radius: 2px;
    overflow: hidden;
  }

  .progress-fill {
    height: 100%;
    transition: width 0.5s ease;
  }

  .stats {
    display: flex;
    gap: 1rem;
    font-size: 0.8rem;
    opacity: 0.8;
  }

  .stat.retry {
    color: #ffb800;
  }

  .meta {
    display: flex;
    justify-content: space-between;
    font-size: 0.75rem;
    opacity: 0.6;
  }

  .path {
    max-width: 200px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .custom-prompt {
    font-size: 0.75rem;
    padding: 0.5rem;
    background: rgba(0, 217, 255, 0.1);
    border-radius: 6px;
    border-left: 2px solid #00d9ff;
    margin-top: 0.25rem;
  }

  .test-controls {
    display: flex;
    gap: 0.5rem;
    margin-top: 0.5rem;
  }

  .btn-test {
    flex: 1;
    padding: 0.4rem 0.6rem;
    font-size: 0.75rem;
    background: rgba(255, 255, 255, 0.1);
    border: 1px solid rgba(255, 255, 255, 0.2);
    border-radius: 6px;
    color: #eee;
    cursor: pointer;
    transition: all 0.2s;
  }

  .btn-test:hover:not(:disabled) {
    background: rgba(255, 255, 255, 0.2);
  }

  .btn-test:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .btn-send {
    background: rgba(0, 217, 255, 0.2);
    border-color: rgba(0, 217, 255, 0.4);
  }

  .btn-send:hover:not(:disabled) {
    background: rgba(0, 217, 255, 0.3);
  }

  .test-result {
    font-size: 0.7rem;
    padding: 0.4rem;
    background: rgba(0, 0, 0, 0.3);
    border-radius: 4px;
    color: #aaa;
    margin-top: 0.25rem;
  }

  .blocked-indicator {
    background: rgba(255, 107, 53, 0.2);
    border: 1px solid rgba(255, 107, 53, 0.4);
    border-radius: 6px;
    padding: 0.5rem;
    font-size: 0.8rem;
    color: #ff6b35;
    margin-top: 0.5rem;
  }

  .backlog-config-row {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    margin-top: 0.25rem;
  }

  .btn-config {
    padding: 0.3rem 0.6rem;
    font-size: 0.7rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 255, 255, 0.15);
    border-radius: 6px;
    color: #aaa;
    cursor: pointer;
    transition: all 0.2s;
  }

  .btn-config:hover,
  .btn-config.active {
    background: rgba(0, 217, 255, 0.15);
    border-color: rgba(0, 217, 255, 0.4);
    color: #00d9ff;
  }

  .config-indicator {
    font-size: 0.65rem;
    color: #00ff88;
    opacity: 0.8;
  }

  .backlog-config {
    background: rgba(0, 0, 0, 0.3);
    border: 1px solid rgba(0, 217, 255, 0.2);
    border-radius: 8px;
    padding: 0.75rem;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    margin-top: 0.25rem;
  }

  .config-field {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
  }

  .config-field label {
    font-size: 0.7rem;
    opacity: 0.7;
  }

  .config-field input,
  .config-field select {
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 4px;
    padding: 0.4rem 0.5rem;
    color: #fff;
    font-size: 0.75rem;
    font-family: inherit;
  }

  .config-field input:focus,
  .config-field select:focus {
    outline: none;
    border-color: #00d9ff;
  }

  .config-hint {
    font-size: 0.6rem;
    opacity: 0.4;
    font-style: italic;
  }

  .config-actions {
    display: flex;
    gap: 0.5rem;
    justify-content: flex-end;
  }

  .btn-config-save {
    padding: 0.3rem 0.8rem;
    font-size: 0.7rem;
    background: linear-gradient(90deg, #00d9ff, #00ff88);
    border: none;
    border-radius: 4px;
    color: #000;
    cursor: pointer;
    font-weight: 600;
  }

  .btn-config-save:hover {
    transform: translateY(-1px);
  }

  .btn-config-cancel {
    padding: 0.3rem 0.5rem;
    font-size: 0.7rem;
    background: transparent;
    border: 1px solid rgba(255, 255, 255, 0.2);
    border-radius: 4px;
    color: #888;
    cursor: pointer;
  }

  .btn-config-cancel:hover {
    color: #fff;
  }
</style>
