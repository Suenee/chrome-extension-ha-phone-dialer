// HA Phone Dialer
// Version 1.14
// - Intercepts tel:, callto: and phone: links, including links inside iframes.
// - Guards against stale content scripts after an extension reload.

function findPhoneLink(event) {
  const path = typeof event.composedPath === "function" ? event.composedPath() : [];

  for (const node of path) {
    if (node && node.tagName === "A") {
      const href = node.getAttribute("href") || "";
      if (/^(tel|callto|phone):/i.test(href.trim())) {
        return href.trim();
      }
    }
  }

  const target = event.target;
  if (target && target.closest) {
    const link = target.closest("a[href]");
    if (link) {
      const href = link.getAttribute("href") || "";
      if (/^(tel|callto|phone):/i.test(href.trim())) {
        return href.trim();
      }
    }
  }

  return null;
}

function runtimeAvailable() {
  try {
    return Boolean(chrome && chrome.runtime && chrome.runtime.id && chrome.runtime.sendMessage);
  } catch {
    return false;
  }
}

function interceptPhoneLink(event) {
  if (event.type === "click" && event.button !== 0) return;
  if (event.ctrlKey || event.shiftKey || event.altKey || event.metaKey) return;

  const href = findPhoneLink(event);
  if (!href) return;

  // Po reloadu extension může na už otevřené stránce krátce zůstat starý
  // content script bez platného chrome.runtime. V takovém případě odkaz
  // necháme zpracovat prohlížečem a nevytváříme chybu v konzoli.
  if (!runtimeAvailable()) return;

  event.preventDefault();
  event.stopPropagation();
  event.stopImmediatePropagation();

  try {
    const result = chrome.runtime.sendMessage({
      type: "dial-phone",
      raw: href
    });

    if (result && typeof result.catch === "function") {
      result.catch((error) => {
        console.error("HA Phone Dialer: failed to pass number to extension:", error);
      });
    }
  } catch (error) {
    console.error("HA Phone Dialer: runtime unavailable:", error);
  }
}

document.addEventListener("click", interceptPhoneLink, true);
