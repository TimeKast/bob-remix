<script lang="ts">
  import { settings } from "./store";

  interface Props {
    onClose: () => void;
  }

  let { onClose }: Props = $props();

  let localSettings = $state({ ...$settings });

  function save() {
    settings.set(localSettings);
    onClose();
  }
</script>

<div
  class="overlay"
  role="button"
  tabindex="-1"
  onclick={onClose}
  onkeydown={(e) => e.key === "Escape" && onClose()}
>
  <div
    class="modal"
    role="dialog"
    aria-modal="true"
    tabindex="0"
    onclick={(e) => e.stopPropagation()}
    onkeydown={(e) => e.stopPropagation()}
  >
    <header>
      <h2>⚙️ Settings</h2>
      <button class="close" onclick={onClose}>✕</button>
    </header>

    <div class="content">
      <div class="section-header">🤖 Auto-Implementation</div>

      <div class="field">
        <label for="autoPrompt">Auto Prompt (sent when chat is ready)</label>
        <textarea
          id="autoPrompt"
          bind:value={localSettings.autoPrompt}
          rows="4"
          placeholder="Continúa con el siguiente paso..."
        ></textarea>
        <span class="hint"
          >Este prompt se envía automáticamente cuando Antigravity está listo
          para recibir instrucciones.</span
        >
      </div>

      <div class="field">
        <label for="pollInterval">Poll Interval (segundos)</label>
        <input
          type="number"
          id="pollInterval"
          bind:value={localSettings.pollIntervalSeconds}
          min="5"
          max="300"
          step="5"
        />
        <span class="hint"
          >Cada cuántos segundos revisar el estado de UI (default: 20)</span
        >
      </div>

      <div class="section-header">⚙️ General</div>

      <div class="field">
        <label for="defaultPrompt">Manual Test Prompt</label>
        <textarea
          id="defaultPrompt"
          bind:value={localSettings.defaultPrompt}
          rows="2"
        ></textarea>
      </div>

      <div class="field">
        <label for="inactivity">Inactivity Timeout (seconds)</label>
        <input
          type="number"
          id="inactivity"
          bind:value={localSettings.inactivitySeconds}
          min="10"
          max="300"
        />
      </div>

      <div class="field">
        <label for="maxRetries">Max Retries on Error</label>
        <input
          type="number"
          id="maxRetries"
          bind:value={localSettings.maxRetries}
          min="1"
          max="10"
        />
      </div>

      <div class="section-header">🔔 Notifications</div>

      <div class="field">
        <label for="discord">Discord Webhook URL</label>
        <input
          type="url"
          id="discord"
          bind:value={localSettings.discordWebhook}
          placeholder="https://discord.com/api/webhooks/..."
        />
      </div>

      <div class="toggles">
        <label class="checkbox">
          <input
            type="checkbox"
            bind:checked={localSettings.notifyOnComplete}
          />
          <span>Notify when project completes</span>
        </label>

        <label class="checkbox">
          <input type="checkbox" bind:checked={localSettings.notifyOnError} />
          <span>Notify on persistent errors</span>
        </label>

        <label class="checkbox">
          <input type="checkbox" bind:checked={localSettings.minimizeToTray} />
          <span>Minimize to system tray</span>
        </label>
      </div>

      <div class="section-header">📝 Logging</div>

      <div class="toggles">
        <label class="checkbox">
          <input type="checkbox" bind:checked={localSettings.loggingEnabled} />
          <span>Enable file logging</span>
        </label>
      </div>

      <div class="field">
        <label for="logPath">Log File Path (leave empty for default)</label>
        <input
          type="text"
          id="logPath"
          bind:value={localSettings.logFilePath}
          placeholder="C:\logs\bob.log"
          disabled={!localSettings.loggingEnabled}
        />
        <span class="hint">Default: bob.log in app directory</span>
      </div>
    </div>

    <footer>
      <button class="btn-cancel" onclick={onClose}>Cancel</button>
      <button class="btn-save" onclick={save}>Save Settings</button>
    </footer>
  </div>
</div>

<style>
  .overlay {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: rgba(0, 0, 0, 0.7);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 100;
    backdrop-filter: blur(4px);
  }

  .modal {
    background: #1a1a2e;
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 16px;
    width: 90%;
    max-width: 400px;
    max-height: 90vh;
    overflow-y: auto;
  }

  header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 1rem;
    border-bottom: 1px solid rgba(255, 255, 255, 0.1);
  }

  h2 {
    font-size: 1.1rem;
    font-weight: 600;
  }

  .close {
    background: transparent;
    border: none;
    color: #888;
    font-size: 1.2rem;
    cursor: pointer;
    padding: 0.25rem;
  }

  .close:hover {
    color: #fff;
  }

  .content {
    padding: 1rem;
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  label {
    font-size: 0.85rem;
    opacity: 0.8;
  }

  input,
  textarea {
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 8px;
    padding: 0.75rem;
    color: #fff;
    font-size: 0.9rem;
    font-family: inherit;
  }

  input:focus,
  textarea:focus {
    outline: none;
    border-color: #00d9ff;
  }

  textarea {
    resize: vertical;
    min-height: 60px;
  }

  .section-header {
    font-size: 0.9rem;
    font-weight: 600;
    color: #00d9ff;
    margin-top: 0.5rem;
    padding-bottom: 0.25rem;
    border-bottom: 1px solid rgba(0, 217, 255, 0.2);
  }

  .hint {
    font-size: 0.75rem;
    opacity: 0.5;
    font-style: italic;
  }

  .toggles {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .checkbox {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    cursor: pointer;
  }

  .checkbox input {
    width: 18px;
    height: 18px;
    accent-color: #00d9ff;
  }

  .checkbox span {
    font-size: 0.9rem;
  }

  footer {
    display: flex;
    justify-content: flex-end;
    gap: 0.5rem;
    padding: 1rem;
    border-top: 1px solid rgba(255, 255, 255, 0.1);
  }

  footer button {
    padding: 0.5rem 1rem;
    border-radius: 8px;
    cursor: pointer;
    font-weight: 500;
    transition: all 0.2s;
  }

  .btn-cancel {
    background: transparent;
    border: 1px solid rgba(255, 255, 255, 0.2);
    color: #888;
  }

  .btn-cancel:hover {
    color: #fff;
    border-color: rgba(255, 255, 255, 0.4);
  }

  .btn-save {
    background: linear-gradient(90deg, #00d9ff, #00ff88);
    border: none;
    color: #000;
  }

  .btn-save:hover {
    transform: translateY(-1px);
    box-shadow: 0 4px 12px rgba(0, 217, 255, 0.3);
  }
</style>
