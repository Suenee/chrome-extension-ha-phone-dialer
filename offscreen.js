chrome.runtime.onMessage.addListener((message) => {
  if (!message || message.type !== "play-success-sound") {
    return;
  }

  const AudioContextClass = window.AudioContext || window.webkitAudioContext;
  const context = new AudioContextClass();
  const oscillator = context.createOscillator();
  const gain = context.createGain();

  oscillator.type = "sine";
  oscillator.frequency.setValueAtTime(1046.5, context.currentTime);
  oscillator.frequency.exponentialRampToValueAtTime(1318.5, context.currentTime + 0.12);

  gain.gain.setValueAtTime(0.18, context.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.001, context.currentTime + 0.14);

  oscillator.connect(gain);
  gain.connect(context.destination);
  oscillator.start();
  oscillator.stop(context.currentTime + 0.14);

  oscillator.addEventListener("ended", () => {
    context.close().catch(() => {});
  });
});
