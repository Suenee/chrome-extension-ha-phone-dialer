// HA Phone Dialer
// Version 1.12
// - Uses the verified Home Assistant Companion command_activity flow.
// - Opens Android dialer via android.intent.action.DIAL.
// - Handles selected phone numbers and tel:/callto: links.
// - Uses chrome.contextMenus.onShown for reliable context-menu visibility.
// - Accepts common international phone-number notation and separators.
// - Plays success.wav after successful sending.
// - Shows an error notification on failure.

const MENU_ID = "ha-phone-dialer";
const NOTIFICATION_ICON = "icon128.png";

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
      justification: "Play a short confirmation sound after successfully sending a phone number."
    });
  }
}

function showSuccess() {
  ensureOffscreenDocument()
    .then(() => chrome.runtime.sendMessage({ type: "play-success-sound" }))
    .catch((error) => console.error("HA Phone Dialer: confirmation sound failed:", error));
}

function showError(message) {
  chrome.notifications.create({
    type: "basic",
    iconUrl: NOTIFICATION_ICON,
    title: "HA Phone Dialer - error",
    message,
    priority: 2
  });
}

function createContextMenu() {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: MENU_ID,
      title: "Poslat číslo do telefonu",
      contexts: ["selection", "link"],
      visible: false
    });
  });
}

chrome.runtime.onInstalled.addListener(createContextMenu);
chrome.runtime.onStartup.addListener(createContextMenu);

async function loadConfig() {
  const response = await fetch(chrome.runtime.getURL("config.json"));
  if (!response.ok) throw new Error(`Cannot load config.json: HTTP ${response.status}`);

  const config = await response.json();
  if (!config.ha_ip || !config.ha_port || !config.mobile_notify_service || !config.token) {
    throw new Error("config.json is incomplete. Copy config.example.json to config.json and fill in local values.");
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

  // Obecná telefonní notace: číslice, +, mezery, závorky, tečky,
  // lomítka a běžné varianty pomlček. Písmena ani jiné znaky nepovolujeme.
  if (!/^[+()\d\s.\/\-–—]+$/u.test(value)) return null;

  // Formátovací znaky odstraníme; v Android dialeru zůstane čisté číslo.
  value = value.replace(/[\s().\/\-–—]/gu, "");

  // Plus smí být jen jednou a pouze na začátku.
  if (!/^\+?\d+$/.test(value)) return null;

  const digits = value.replace(/\D/g, "");

  // E.164 dovoluje nejvýše 15 číslic. Spodní hranice 5 omezuje náhodné
  // roky, pořadová čísla a podobné krátké výběry; lokální čísla ponecháváme.
  if (digits.length < 5 || digits.length > 15) return null;

  return value;
}

function parseNotifyService(value) {
  const prefix = "notify.";
  if (!value || !value.startsWith(prefix)) throw new Error("mobile_notify_service must start with 'notify.'");
  return value.slice(prefix.length);
}

async function sendToPhone(phone) {
  const config = await loadConfig();
  const service = parseNotifyService(config.mobile_notify_service);
  const url = `http://${config.ha_ip}:${config.ha_port}/api/services/notify/${service}`;
  const payload = {
    message: "command_activity",
    data: {
      intent_action: "android.intent.action.DIAL",
      intent_uri: `tel:${phone}`
    }
  };

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${config.token}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Home Assistant HTTP ${response.status}: ${body}`);
  }
}

// Chrome nám při otevírání kontextové nabídky předá přímo vybraný text.
// To je spolehlivější než pokoušet se menu skrývat z content scriptu těsně
// před pravým kliknutím.
chrome.contextMenus.onShown.addListener((info) => {
  const raw = info.selectionText || info.linkUrl || "";
  const visible = Boolean(normalizePhone(raw));

  chrome.contextMenus.update(MENU_ID, { visible }, () => {
    void chrome.runtime.lastError;
    chrome.contextMenus.refresh();
  });
});

chrome.contextMenus.onHidden.addListener(() => {
  chrome.contextMenus.update(MENU_ID, { visible: false }, () => {
    void chrome.runtime.lastError;
  });
});

chrome.contextMenus.onClicked.addListener(async (info) => {
  if (info.menuItemId !== MENU_ID) return;

  const raw = info.selectionText || info.linkUrl || "";
  const phone = normalizePhone(raw);
  if (!phone) return;

  try {
    await sendToPhone(phone);
    showSuccess();
  } catch (error) {
    console.error("HA Phone Dialer:", error);
    showError(`Číslo se nepodařilo odeslat. ${String(error)}`);
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
      showSuccess();
      sendResponse({ ok: true });
    })
    .catch((error) => {
      console.error("HA Phone Dialer:", error);
      showError(`Číslo se nepodařilo odeslat. ${String(error)}`);
      sendResponse({ ok: false, error: String(error) });
    });

  return true;
});
