// HA Phone Dialer
// Version 1.11
// Přehrává původní potvrzovací zvuk success.wav.

chrome.runtime.onMessage.addListener((message) => {
  if (!message || message.type !== "play-success-sound") {
    return;
  }

  const audio = new Audio(chrome.runtime.getURL("success.wav"));
  audio.volume = 0.8;
  audio.play().catch((error) => {
    console.error("HA Phone Dialer: nepodařilo se přehrát zvuk:", error);
  });
});
