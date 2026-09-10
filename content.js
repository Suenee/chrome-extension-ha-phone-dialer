// HA Phone Dialer
// Version 1.11
// Intercepts tel: and callto: links, including links inside iframes,
// and controls context-menu visibility based on the actual right-click target.

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

function getContextCandidate(event) {
  const selected = (window.getSelection?.().toString() || "").trim();
  if (selected) return selected;
  return findPhoneLink(event) || "";
}

function reportContextCandidate(event) {
  if (event.type === "mousedown" && event.button !== 2) return;

  chrome.runtime.sendMessage({
    type: "context-menu-candidate",
    raw: getContextCandidate(event)
  }).catch(() => {});
}

function interceptPhoneLink(event) {
  if (event.type === "click" && event.button !== 0) return;
  if (event.ctrlKey || event.shiftKey || event.altKey || event.metaKey) return;

  const href = findPhoneLink(event);
  if (!href) return;

  event.preventDefault();
  event.stopPropagation();
  event.stopImmediatePropagation();

  chrome.runtime.sendMessage({
    type: "dial-phone",
    raw: href
  }).catch((error) => {
    console.error("HA Phone Dialer: failed to pass number to extension:", error);
  });
}

document.addEventListener("mousedown", reportContextCandidate, true);
document.addEventListener("contextmenu", reportContextCandidate, true);
document.addEventListener("click", interceptPhoneLink, true);
