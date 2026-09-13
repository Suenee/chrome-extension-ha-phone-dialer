// HA Phone Dialer
// Version 1.16
// - Konfigurace se načítá přímo z lokálního config.local.js bez fetch().
// - Komunikace s Home Assistantem zůstává přes WebSocket API.
// - Odstraněny systémové Chrome notifikace, které způsobovaly chybu ikon.
// - Kontextové menu zůstává dostupné pro výběr textu a odkazy.

try {
  importScripts("config.local.js");
} catch (error) {
  console.error("HA Phone Dialer: config.local.js nelze načíst:", error);
}

const MENU_ID = "ha-phone-dialer";
const WS_TIMEOUT_MS = 10000;

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
  ensureOffscreenDocument()
    .then(() => chrome.runtime.sendMessage({ type: "play-success-sound" }))
    .catch((error) => console.error("HA Phone Dialer: potvrzovací zvuk:", error));
}

function reportError(message, error = null) {
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

function loadConfig() {
  const config = globalThis.HA_PHONE_DIALER_CONFIG;

  if (!config || typeof config !== "object") {
    throw new Error("Chybí config.local.js nebo HA_PHONE_DIALER_CONFIG.");
  }

  if (!config.ha_ip || !config.ha_port || !config.mobile_notify_service || !config.token) {
    throw new Error("config.local.js je neúplný.");
  }

  return config;
}

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

    const timeout = setTimeout(() => {
      if (finished) return;
      finished = true;
      try { socket.close(); } catch {}
      reject(new Error("Home Assistant WebSocket timeout."));
    }, WS_TIMEOUT_MS);

    function finishOk() {
      if (finished) return;
      finished = true;
      clearTimeout(timeout);
      try { socket.close(); } catch {}
      resolve(true);
    }

    function finishError(message) {
      if (finished) return;
      finished = true;
      clearTimeout(timeout);
      try { socket.close(); } catch {}
      reject(new Error(message));
    }

    socket.onerror = () => {
      finishError(`Nelze navázat WebSocket spojení s Home Assistantem ${config.ha_ip}:${config.ha_port}.`);
    };

    socket.onclose = () => {
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

      if (message.type === "auth_required") {
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
        return;
      }

      if (message.type === "result" && message.id === 1) {
        if (!authenticated || !serviceSent) {
          finishError("Home Assistant vrátil výsledek v neočekávaném stavu.");
          return;
        }

        if (message.success) {
          finishOk();
        } else {
          const details = message.error?.message || message.error?.code || "unknown error";
          finishError(`Home Assistant call_service selhal: ${details}`);
        }
      }
    };
  });
}

async function sendToPhone(phone) {
  const config = loadConfig();
  const service = parseNotifyService(config.mobile_notify_service);
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
    await sendToPhone(phone);
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

  sendToPhone(phone)
    .then(() => {
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
