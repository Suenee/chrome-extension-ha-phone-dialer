// HA Phone Dialer
// Version 1.10
// - Uses the verified Home Assistant Companion command_activity flow.
// - Opens Android dialer via android.intent.action.DIAL.
// - Handles selected phone numbers and tel:/callto: links.
// - Plays a short confirmation tone after successful sending.
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
      justification: "Play a short confirmation tone after successfully sending a phone number."
    });
  }
}

function showSuccess() {
  ensureOffscreenDocument()
    .then(() => chrome.runtime.sendMessage({ type: "play-success-sound" }))
    .catch((error) => {
      console.error("HA Phone Dialer: confirmation sound failed:", error);
    });
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

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: MENU_ID,
      title: "Send number to phone",
      contexts: ["selection", "link"]
    });
  });
});

async function loadConfig() {
  const response = await fetch(chrome.runtime.getURL("config.json"));
  if (!response.ok) {
    throw new Error(`Cannot load config.json: HTTP ${response.status}`);
  }

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

  if (!/^[+()\d\s.\-/]+$/.test(value)) {
    return null;
  }

  value = value.replace(/[\s().\-/]/g, "");

  if (!/^\+?\d+$/.test(value)) {
    return null;
  }

  const digits = value.replace(/\D/g, "");

  if (digits.length < 5 || digits.length > 15) {
    return null;
  }

  return value;
}

function parseNotifyService(value) {
  const prefix = "notify.";

  if (!value || !value.startsWith(prefix)) {
    throw new Error("mobile_notify_service must start with 'notify.'");
  }

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

chrome.contextMenus.onClicked.addListener(async (info) => {
  if (info.menuItemId !== MENU_ID) return;

  const raw = info.selectionText || info.linkUrl || "";
  const phone = normalizePhone(raw);

  if (!phone) {
    showError("Selected text is not a valid phone number.");
    return;
  }

  try {
    await sendToPhone(phone);
    showSuccess();
  } catch (error) {
    console.error("HA Phone Dialer:", error);
    showError(`Number could not be sent. ${String(error)}`);
  }
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || message.type !== "dial-phone") return;

  const phone = normalizePhone(message.raw || "");

  if (!phone) {
    showError("Link does not contain a valid phone number.");
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
      showError(`Number could not be sent. ${String(error)}`);
      sendResponse({ ok: false, error: String(error) });
    });

  return true;
});
