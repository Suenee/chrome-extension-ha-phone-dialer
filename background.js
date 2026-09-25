// HA Phone Dialer
// Version 1.18
// - Configuration is stored in chrome.storage.local and edited through options.html.
// - Legacy config.local.js is imported once as a migration fallback.
// - Runtime logging modes: off / phone / single / all.

try { importScripts("config.local.js"); } catch {}

const MENU_ID = "ha-phone-dialer";
const WS_TIMEOUT_MS = 10000;
const CONFIG_KEY = "hapd_config";
const RUNTIME_LOG_KEY = "runtime_log";
const VALID_LOG_MODES = new Set(["off", "phone", "single", "all"]);
const INSTANCE_ID = `${new Date().toISOString()}-${Math.random().toString(36).slice(2, 8)}`;
let logWriteChain = Promise.resolve();
let configCache = null;

function normalizeConfig(config = {}) {
  const logMode = String(config.log_mode || "off").toLowerCase();
  return {
    ha_ip: String(config.ha_ip || "").trim(),
    ha_port: Number(config.ha_port || 8123),
    mobile_notify_service: String(config.mobile_notify_service || "").trim(),
    token: String(config.token || "").trim(),
    log_mode: VALID_LOG_MODES.has(logMode) ? logMode : "off"
  };
}

async function loadConfig() {
  if (configCache) return configCache;
  const stored = await chrome.storage.local.get(CONFIG_KEY);
  if (stored[CONFIG_KEY]) {
    configCache = normalizeConfig(stored[CONFIG_KEY]);
    return configCache;
  }

  const legacy = globalThis.HA_PHONE_DIALER_CONFIG;
  if (legacy && typeof legacy === "object") {
    configCache = normalizeConfig(legacy);
    await chrome.storage.local.set({ [CONFIG_KEY]: configCache });
    return configCache;
  }

  configCache = normalizeConfig();
  return configCache;
}

chrome.storage.onChanged.addListener((changes, area) => {
  if (area === "local" && changes[CONFIG_KEY]) configCache = normalizeConfig(changes[CONFIG_KEY].newValue || {});
});

function validateConfig(config) {
  if (!config.ha_ip || !config.ha_port || !config.mobile_notify_service || !config.token) {
    throw new Error("Konfigurace Home Assistantu není kompletní. Otevři nastavení HA Phone Dialer.");
  }
}

function formatLogData(data) {
  if (data === undefined || data === null || data === "") return "";
  if (typeof data === "string") return ` | ${data}`;
  try { return ` | ${JSON.stringify(data)}`; } catch { return ` | ${String(data)}`; }
}

function queueStorageWrite(operation) {
  logWriteChain = logWriteChain.then(operation).catch(error => console.error("HA Phone Dialer: runtime log write failed:", error));
  return logWriteChain;
}

async function currentLogMode() {
  return (await loadConfig()).log_mode;
}

function clearRuntimeLog() {
  return queueStorageWrite(() => chrome.storage.local.set({ [RUNTIME_LOG_KEY]: "" }));
}

async function appendRuntimeLog(scope, message, data = null) {
  const mode = await currentLogMode();
  if (mode === "off") return;
  const line = `${new Date().toISOString()} [${INSTANCE_ID}] [${scope}] ${message}${formatLogData(data)}`;
  console.log(`HA Phone Dialer LOG: ${line}`);
  return queueStorageWrite(async () => {
    const stored = await chrome.storage.local.get(RUNTIME_LOG_KEY);
    const previous = stored[RUNTIME_LOG_KEY] || "";
    await chrome.storage.local.set({ [RUNTIME_LOG_KEY]: previous ? `${previous}\n${line}` : line });
  });
}

async function initializeRuntimeLog() {
  const mode = await currentLogMode();
  if (mode === "single") await clearRuntimeLog();
  if (mode === "single" || mode === "all") await appendRuntimeLog("INSTANCE", "Service worker instance started", { mode });
}
initializeRuntimeLog();

async function beginPhoneLog(phone, source) {
  if (await currentLogMode() === "phone") await clearRuntimeLog();
  await appendRuntimeLog("PHONE", "Phone request started", { source, phone });
}

async function ensureOffscreenDocument() {
  const offscreenUrl = chrome.runtime.getURL("offscreen.html");
  const contexts = await chrome.runtime.getContexts({ contextTypes: ["OFFSCREEN_DOCUMENT"], documentUrls: [offscreenUrl] });
  if (contexts.length === 0) {
    await chrome.offscreen.createDocument({
      url: "offscreen.html",
      reasons: ["AUDIO_PLAYBACK"],
      justification: "Přehrání krátkého potvrzovacího zvuku po úspěšném odeslání čísla."
    });
  }
}

function showSuccess() {
  appendRuntimeLog("AUDIO", "Playing success sound");
  ensureOffscreenDocument()
    .then(() => chrome.runtime.sendMessage({ type: "play-success-sound" }))
    .catch(error => console.error("HA Phone Dialer: potvrzovací zvuk:", error));
}

function reportError(message, error = null) {
  appendRuntimeLog("ERROR", message, error ? { error: String(error) } : null);
  console.error(`HA Phone Dialer: ${message}`, error || "");
}

function createContextMenu() {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({ id: MENU_ID, title: "Poslat číslo do telefonu", contexts: ["selection", "link"] });
  });
}
chrome.runtime.onInstalled.addListener(createContextMenu);
chrome.runtime.onStartup.addListener(createContextMenu);

function normalizePhone(raw) {
  if (!raw) return null;
  let value = raw.trim().replace(/^tel:/i, "").replace(/^callto:/i, "").replace(/^phone:/i, "").trim();
  if (!/^[+()\d\s.\/\-–—]+$/u.test(value)) return null;
  value = value.replace(/[\s().\/\-–—]/gu, "");
  if (!/^\+?\d+$/.test(value)) return null;
  const digits = value.replace(/\D/g, "");
  return digits.length >= 5 && digits.length <= 15 ? value : null;
}

function parseNotifyService(value) {
  if (!value || !value.startsWith("notify.")) throw new Error("Mobile notify service musí začínat 'notify.'.");
  return value.slice(7);
}

function callHomeAssistantWebSocket(config, service, phone) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(`ws://${config.ha_ip}:${config.ha_port}/api/websocket`);
    let authenticated = false, serviceSent = false, finished = false;
    appendRuntimeLog("WS", "Connecting to Home Assistant", { host: config.ha_ip, port: config.ha_port });

    const timeout = setTimeout(() => finishError("Home Assistant WebSocket timeout."), WS_TIMEOUT_MS);
    function finishOk() {
      if (finished) return; finished = true; clearTimeout(timeout); try { socket.close(); } catch {}
      appendRuntimeLog("WS", "Request completed successfully"); resolve(true);
    }
    function finishError(message) {
      if (finished) return; finished = true; clearTimeout(timeout); try { socket.close(); } catch {}
      appendRuntimeLog("WS", "Request failed", { message }); reject(new Error(message));
    }
    socket.onerror = () => finishError(`Nelze navázat WebSocket spojení s Home Assistantem ${config.ha_ip}:${config.ha_port}.`);
    socket.onmessage = event => {
      let message;
      try { message = JSON.parse(event.data); } catch { finishError("Home Assistant poslal neplatnou WebSocket odpověď."); return; }
      if (message.type === "auth_required") {
        socket.send(JSON.stringify({ type: "auth", access_token: config.token })); return;
      }
      if (message.type === "auth_invalid") { finishError(`Home Assistant odmítl token: ${message.message || "auth_invalid"}`); return; }
      if (message.type === "auth_ok") {
        authenticated = true;
        socket.send(JSON.stringify({
          id: 1, type: "call_service", domain: "notify", service,
          service_data: { message: "command_activity", data: { intent_action: "android.intent.action.DIAL", intent_uri: `tel:${phone}` } }
        }));
        serviceSent = true;
        appendRuntimeLog("SERVICE", "notify service sent", { service: `notify.${service}`, phone });
        return;
      }
      if (message.type === "result" && message.id === 1) {
        if (!authenticated || !serviceSent) { finishError("Home Assistant vrátil výsledek v neočekávaném stavu."); return; }
        if (message.success) finishOk();
        else finishError(`Home Assistant call_service selhal: ${message.error?.message || message.error?.code || "unknown error"}`);
      }
    };
  });
}

async function sendToPhone(phone, source) {
  await beginPhoneLog(phone, source);
  const config = await loadConfig();
  validateConfig(config);
  const service = parseNotifyService(config.mobile_notify_service);
  await appendRuntimeLog("CONFIG", "Configuration loaded", { host: config.ha_ip, port: config.ha_port, service: config.mobile_notify_service, log_mode: config.log_mode });
  return callHomeAssistantWebSocket(config, service, phone);
}

chrome.contextMenus.onClicked.addListener(async info => {
  if (info.menuItemId !== MENU_ID) return;
  const phone = normalizePhone(info.selectionText || info.linkUrl || "");
  if (!phone) { reportError("Vybraný text není platné telefonní číslo."); return; }
  try { await sendToPhone(phone, "context-menu"); showSuccess(); }
  catch (error) { reportError("Číslo se nepodařilo odeslat.", error); }
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message) return;
  if (message.type === "config-changed") {
    configCache = null;
    sendResponse({ ok: true });
    return;
  }
  if (message.type !== "dial-phone") return;
  const phone = normalizePhone(message.raw || "");
  if (!phone) { sendResponse({ ok: false, error: "invalid_phone" }); return; }
  sendToPhone(phone, "tel-callto")
    .then(() => { showSuccess(); sendResponse({ ok: true }); })
    .catch(error => { reportError("Číslo se nepodařilo odeslat.", error); sendResponse({ ok: false, error: String(error) }); });
  return true;
});
