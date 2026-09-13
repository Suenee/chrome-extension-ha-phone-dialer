// HA Phone Dialer
// Version 1.17
// - Přidán běhový log s režimy off / phone / single / all.
// - Log se ukládá do chrome.storage.local a současně se vypisuje do konzole.
// - Režim phone uchovává průběh posledního zadaného čísla.
// - Režim single uchovává průběh od spuštění aktuální instance service workeru.
// - Režim all přidává vše bez aplikačního omezení velikosti.
// - Konfigurace se načítá přímo z lokálního config.local.js bez fetch().

try {
  importScripts("config.local.js");
} catch (error) {
  console.error("HA Phone Dialer: config.local.js nelze načíst:", error);
}

const MENU_ID = "ha-phone-dialer";
const WS_TIMEOUT_MS = 10000;
const RUNTIME_LOG_KEY = "runtime_log";
const VALID_LOG_MODES = new Set(["off", "phone", "single", "all"]);
const INSTANCE_ID = `${new Date().toISOString()}-${Math.random().toString(36).slice(2, 8)}`;
let logWriteChain = Promise.resolve();

function loadConfig() {
  const config = globalThis.HA_PHONE_DIALER_CONFIG;

  if (!config || typeof config !== "object") {
    throw new Error("Chybí config.local.js nebo HA_PHONE_DIALER_CONFIG.");
  }

  if (!config.ha_ip || !config.ha_port || !config.mobile_notify_service || !config.token) {
    throw new Error("config.local.js je neúplný.");
  }

  const logMode = String(config.log_mode || "off").toLowerCase();
  config.log_mode = VALID_LOG_MODES.has(logMode) ? logMode : "off";
  return config;
}

function currentLogMode() {
  try {
    return loadConfig().log_mode;
  } catch {
    return "off";
  }
}

function formatLogData(data) {
  if (data === undefined || data === null || data === "") return "";
  if (typeof data === "string") return ` | ${data}`;
  try {
    return ` | ${JSON.stringify(data)}`;
  } catch {
    return ` | ${String(data)}`;
  }
}

function queueStorageWrite(operation) {
  logWriteChain = logWriteChain.then(operation).catch((error) => {
    console.error("HA Phone Dialer: runtime log write failed:", error);
  });
  return logWriteChain;
}

function clearRuntimeLog() {
  return queueStorageWrite(() => chrome.storage.local.set({ [RUNTIME_LOG_KEY]: "" }));
}

function appendRuntimeLog(scope, message, data = null) {
  const mode = currentLogMode();
  if (mode === "off") return Promise.resolve();

  const line = `${new Date().toISOString()} [${INSTANCE_ID}] [${scope}] ${message}${formatLogData(data)}`;
  console.log(`HA Phone Dialer LOG: ${line}`);

  return queueStorageWrite(async () => {
    const stored = await chrome.storage.local.get(RUNTIME_LOG_KEY);
    const previous = stored[RUNTIME_LOG_KEY] || "";
    const next = previous ? `${previous}\n${line}` : line;
    await chrome.storage.local.set({ [RUNTIME_LOG_KEY]: next });
  });
}

async function initializeRuntimeLog() {
  const mode = currentLogMode();
  if (mode === "single") {
    await clearRuntimeLog();
    await appendRuntimeLog("INSTANCE", "Service worker instance started", { mode });
  } else if (mode === "all") {
    await appendRuntimeLog("INSTANCE", "Service worker instance started", { mode });
  }
}

async function beginPhoneLog(phone, source) {
  const mode = currentLogMode();
  if (mode === "phone") {
    await clearRuntimeLog();
  }
  await appendRuntimeLog("PHONE", "Phone request started", { source, phone });
}

initializeRuntimeLog();

async function ensureOffscreenDocument() {
  const offscreenUrl = chrome.runtime.getURL("offscreen.html");
  const contexts = await chrome.runtime.getContexts({
    contextTypes: ["OFFSCREEN_DOCUMENT"],
    documentUrls: [offscreenUrl]
  });

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
    .catch((error) => {
      appendRuntimeLog("AUDIO", "Success sound failed", { error: String(error) });
      console.error("HA Phone Dialer: potvrzovací zvuk:", error);
    });
}

function reportError(message, error = null) {
  appendRuntimeLog("ERROR", message, error ? { error: String(error) } : null);
  if (error) {
    console.error(`HA Phone Dialer: ${message}`, error);
  } else {
    console.error(`HA Phone Dialer: ${message}`);
  }
}

function createContextMenu() {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: MENU_ID,
      title: "Poslat číslo do telefonu",
      contexts: ["selection", "link"]
    });
  });
}

chrome.runtime.onInstalled.addListener(createContextMenu);
chrome.runtime.onStartup.addListener(createContextMenu);

function normalizePhone(raw) {
  if (!raw) return null;

  let value = raw.trim()
    .replace(/^tel:/i, "")
    .replace(/^callto:/i, "")
    .replace(/^phone:/i, "")
    .trim();

  if (!/^[+()\d\s.\/\-–—]+$/u.test(value)) return null;

  value = value.replace(/[\s().\/\-–—]/gu, "");
  if (!/^\+?\d+$/.test(value)) return null;

  const digits = value.replace(/\D/g, "");
  if (digits.length < 5 || digits.length > 15) return null;

  return value;
}

function parseNotifyService(value) {
  const prefix = "notify.";

  if (!value || !value.startsWith(prefix)) {
    throw new Error("mobile_notify_service musí začínat 'notify.'.");
  }

  return value.slice(prefix.length);
}

function callHomeAssistantWebSocket(config, service, phone) {
  return new Promise((resolve, reject) => {
    const url = `ws://${config.ha_ip}:${config.ha_port}/api/websocket`;
    const socket = new WebSocket(url);
    let authenticated = false;
    let serviceSent = false;
    let finished = false;

    appendRuntimeLog("WS", "Connecting to Home Assistant", { host: config.ha_ip, port: config.ha_port });

    const timeout = setTimeout(() => {
      if (finished) return;
      finished = true;
      try { socket.close(); } catch {}
      appendRuntimeLog("WS", "Timeout");
      reject(new Error("Home Assistant WebSocket timeout."));
    }, WS_TIMEOUT_MS);

    function finishOk() {
      if (finished) return;
      finished = true;
      clearTimeout(timeout);
      try { socket.close(); } catch {}
      appendRuntimeLog("WS", "Request completed successfully");
      resolve(true);
    }

    function finishError(message) {
      if (finished) return;
      finished = true;
      clearTimeout(timeout);
      try { socket.close(); } catch {}
      appendRuntimeLog("WS", "Request failed", { message });
      reject(new Error(message));
    }

    socket.onopen = () => {
      appendRuntimeLog("WS", "Socket opened");
    };

    socket.onerror = () => {
      finishError(`Nelze navázat WebSocket spojení s Home Assistantem ${config.ha_ip}:${config.ha_port}.`);
    };

    socket.onclose = (event) => {
      appendRuntimeLog("WS", "Socket closed", { code: event.code, reason: event.reason || "" });
      if (!finished) finishError("Home Assistant WebSocket byl ukončen před dokončením požadavku.");
    };

    socket.onmessage = (event) => {
      let message;
      try {
        message = JSON.parse(event.data);
      } catch {
        finishError("Home Assistant poslal neplatnou WebSocket odpověď.");
        return;
      }

      appendRuntimeLog("WS", "Message received", { type: message.type, id: message.id ?? null, success: message.success ?? null });

      if (message.type === "auth_required") {
        appendRuntimeLog("AUTH", "Authentication requested");
        socket.send(JSON.stringify({
          type: "auth",
          access_token: config.token
        }));
        return;
      }

      if (message.type === "auth_invalid") {
        finishError(`Home Assistant odmítl token: ${message.message || "auth_invalid"}`);
        return;
      }

      if (message.type === "auth_ok") {
        authenticated = true;
        appendRuntimeLog("AUTH", "Authentication successful");
        socket.send(JSON.stringify({
          id: 1,
          type: "call_service",
          domain: "notify",
          service,
          service_data: {
            message: "command_activity",
            data: {
              intent_action: "android.intent.action.DIAL",
              intent_uri: `tel:${phone}`
            }
          }
        }));
        serviceSent = true;
        appendRuntimeLog("SERVICE", "notify service sent", { service: `notify.${service}`, phone });
        return;
      }

      if (message.type === "result" && message.id === 1) {
        if (!authenticated || !serviceSent) {
          finishError("Home Assistant vrátil výsledek v neočekávaném stavu.");
          return;
        }

        if (message.success) {
          appendRuntimeLog("SERVICE", "Home Assistant accepted call_service");
          finishOk();
        } else {
          const details = message.error?.message || message.error?.code || "unknown error";
          finishError(`Home Assistant call_service selhal: ${details}`);
        }
      }
    };
  });
}

async function sendToPhone(phone, source) {
  await beginPhoneLog(phone, source);
  const config = loadConfig();
  const service = parseNotifyService(config.mobile_notify_service);
  appendRuntimeLog("CONFIG", "Configuration loaded", {
    host: config.ha_ip,
    port: config.ha_port,
    service: config.mobile_notify_service,
    log_mode: config.log_mode
  });
  return callHomeAssistantWebSocket(config, service, phone);
}

chrome.contextMenus.onClicked.addListener(async (info) => {
  if (info.menuItemId !== MENU_ID) return;

  const raw = info.selectionText || info.linkUrl || "";
  const phone = normalizePhone(raw);

  if (!phone) {
    reportError("Vybraný text není platné telefonní číslo.");
    return;
  }

  try {
    await sendToPhone(phone, "context-menu");
    appendRuntimeLog("PHONE", "Phone request finished successfully", { phone });
    console.log("HA Phone Dialer: dialer požadavek odeslán:", phone);
    showSuccess();
  } catch (error) {
    reportError("Číslo se nepodařilo odeslat.", error);
  }
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || message.type !== "dial-phone") return;

  const phone = normalizePhone(message.raw || "");
  if (!phone) {
    sendResponse({ ok: false, error: "invalid_phone" });
    return;
  }

  sendToPhone(phone, "tel-callto")
    .then(() => {
      appendRuntimeLog("PHONE", "Phone request finished successfully", { phone });
      console.log("HA Phone Dialer: tel:/callto: odkaz odeslán:", phone);
      showSuccess();
      sendResponse({ ok: true });
    })
    .catch((error) => {
      reportError("Číslo se nepodařilo odeslat.", error);
      sendResponse({ ok: false, error: String(error) });
    });

  return true;
});
