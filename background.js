// HA Phone Dialer
// Version 1.10
// - Opraven cílový notify service na notify.mobile_app_souhvezdi_liry.
// - Používá ověřený Home Assistant Companion příkaz command_activity.
// - Android otevře číselník přes android.intent.action.DIAL.
// - Kontextové menu funguje pro označený text i tel:/callto: odkazy.
// - Přidána zelená ikona otočného telefonu do rozšíření a kontextového menu.
// - Přímý klik na tel:/callto: odkaz je zachycen a poslán do telefonu.

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
      justification: "Přehrání krátkého potvrzovacího zvuku po úspěšném odeslání čísla."
    });
  }
}

function showSuccess(phone) {
  ensureOffscreenDocument()
    .then(() => chrome.runtime.sendMessage({ type: "play-success-sound" }))
    .catch((error) => {
      console.error("HA Phone Dialer: potvrzovací zvuk:", error);
    });
}

function showError(message) {
  chrome.notifications.create({
    type: "basic",
    iconUrl: NOTIFICATION_ICON,
    title: "HA Phone Dialer – chyba",
    message: message,
    priority: 2
  });
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: MENU_ID,
      title: "Poslat číslo do telefonu",
      contexts: ["selection", "link"]
    });
  });
});

async function loadConfig() {
  const response = await fetch(chrome.runtime.getURL("config.json"));
  if (!response.ok) {
    throw new Error(`Nelze načíst config.json: HTTP ${response.status}`);
  }

  return await response.json();
}

function normalizePhone(raw) {
  if (!raw) return null;

  let value = raw.trim()
    .replace(/^tel:/i, "")
    .replace(/^callto:/i, "")
    .replace(/^phone:/i, "")
    .trim();

  // Povolíme běžné formáty telefonních čísel.
  if (!/^[+()\d\s.\-/]+$/.test(value)) {
    return null;
  }

  // Odstraníme mezery a běžné oddělovače.
  value = value.replace(/[\s().\-/]/g, "");

  // Plus může být pouze na začátku.
  if (!/^\+?\d+$/.test(value)) {
    return null;
  }

  const digits = value.replace(/\D/g, "");

  // Praktický rozsah délky telefonního čísla.
  if (digits.length < 5 || digits.length > 15) {
    return null;
  }

  return value;
}

function parseNotifyService(value) {
  const prefix = "notify.";

  if (!value || !value.startsWith(prefix)) {
    throw new Error("mobile_notify_service musí začínat 'notify.'");
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

  return true;
}

chrome.contextMenus.onClicked.addListener(async (info) => {
  if (info.menuItemId !== MENU_ID) return;

  const raw = info.selectionText || info.linkUrl || "";
  const phone = normalizePhone(raw);

  if (!phone) {
    console.error("HA Phone Dialer: text není platné telefonní číslo:", raw);
    showError("Vybraný text není platné telefonní číslo.");
    return;
  }

  try {
    await sendToPhone(phone);
    console.log("HA Phone Dialer: dialer požadavek odeslán:", phone);
    showSuccess(phone);
  } catch (error) {
    console.error("HA Phone Dialer:", error);
    showError(`Číslo se nepodařilo odeslat. ${String(error)}`);
  }
});


// Přijímá telefonní číslo zachycené content scriptem při kliknutí na tel:/callto:.
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || message.type !== "dial-phone") return;

  const phone = normalizePhone(message.raw || "");

  if (!phone) {
    console.error("HA Phone Dialer: odkaz neobsahuje platné telefonní číslo:", message.raw);
    showError("Odkaz neobsahuje platné telefonní číslo.");
    sendResponse({ ok: false, error: "invalid_phone" });
    return;
  }

  sendToPhone(phone)
    .then(() => {
      console.log("HA Phone Dialer: tel:/callto: odkaz odeslán:", phone);
      showSuccess(phone);
      sendResponse({ ok: true });
    })
    .catch((error) => {
      console.error("HA Phone Dialer:", error);
      showError(`Číslo se nepodařilo odeslat. ${String(error)}`);
      sendResponse({ ok: false, error: String(error) });
    });

  return true;
});
