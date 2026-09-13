// HA Phone Dialer - local/private configuration template
// Copy to config.local.js and fill in local values.
// NEVER commit config.local.js because it contains the Home Assistant token.

globalThis.HA_PHONE_DIALER_CONFIG = {
  ha_ip: "192.168.x.x",
  ha_port: 8123,
  mobile_notify_service: "notify.mobile_app_your_device",
  token: "YOUR_LOCAL_LONG_LIVED_ACCESS_TOKEN"
};
