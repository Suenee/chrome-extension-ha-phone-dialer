// HA Phone Dialer
// Version 1.07
// - Zachytává tel: a callto: i uvnitř iframe.
// - Používá composedPath(), takže funguje i při kliknutí na ikonu/span uvnitř odkazu.
// - Zastaví původní systémový handler a číslo pošle do Home Assistantu.

function findPhoneLink(event) {
  const path = typeof event.composedPath === "function" ? event.composedPath() : [];

  for (const node of path) {
    if (node && node.tagName === "A") {
      const href = node.getAttribute("href") || "";
      if (/^(tel|callto):/i.test(href.trim())) {
        return href.trim();
      }
    }
  }

  const target = event.target;
  if (target && target.closest) {
    const link = target.closest("a[href]");
    if (link) {
      const href = link.getAttribute("href") || "";
      if (/^(tel|callto):/i.test(href.trim())) {
        return href.trim();
      }
    }
  }

  return null;
}

function interceptPhoneLink(event) {
  // Pouze běžný levý klik.
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
    console.error("HA Phone Dialer: nelze předat číslo extension:", error);
  });
}

// Capture fáze = odchytíme odkaz dřív než stránka nebo Chrome.
document.addEventListener("click", interceptPhoneLink, true);
