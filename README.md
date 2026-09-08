# HA Phone Dialer

Chrome extension that sends `tel:`, `callto:` and selected phone numbers from web pages to an Android dialer through Home Assistant.

## Features

- Intercepts `tel:` and `callto:` links directly in Chrome.
- Sends selected phone numbers from the context menu.
- Uses Home Assistant REST API and the Android Home Assistant Companion app.
- Opens the Android dialer with the phone number prefilled.
- Plays a short confirmation sound after a successful send.
- Shows an error notification if the request fails.
- Works with Manifest V3.

## Requirements

- Google Chrome or Chromium-based browser with Manifest V3 support.
- Home Assistant reachable from the computer running Chrome.
- Home Assistant Companion installed on the Android phone.
- A working legacy mobile notify service, for example:

```text
notify.mobile_app_your_device
```

- Companion permission for `command_activity` / Display over other apps.

## Home Assistant command

The extension sends a Home Assistant notification command equivalent to:

```yaml
action: notify.mobile_app_your_device
data:
  message: command_activity
  data:
    intent_action: android.intent.action.DIAL
    intent_uri: "tel:+420777123456"
```

This opens the Android dialer with the number filled in. The call itself is not placed automatically.

## Installation

This project is intended to be used as an unpacked Chrome extension.

1. Clone or update the repository locally.
2. Open:

```text
chrome://extensions
```

3. Enable **Developer mode**.
4. Click **Load unpacked**.
5. Select the local repository folder.

For the preferred update workflow, use `upgrade.cmd`.

## Local path convention

The expected local repository path is:

```text
D:\WORK\GitHub\chromeextension-HA-PhoneDialer
```

or:

```text
N:\WORK\GitHub\chromeextension-HA-PhoneDialer
```

The update script detects the active drive automatically.

## Configuration and secrets

Home Assistant credentials, Long-Lived Access Tokens and other private configuration must never be committed to this repository.

Use a local-only configuration file that is excluded by `.gitignore`.

Example:

```json
{
  "ha_ip": "192.168.x.x",
  "ha_port": 8123,
  "mobile_notify_service": "notify.mobile_app_your_device",
  "token": "YOUR_LOCAL_TOKEN"
}
```

## Updating

Run:

```bat
upgrade.cmd
```

The script updates the repository from GitHub while preserving local-only configuration files.

After an update, open `chrome://extensions` and click **Reload** for the extension if Chrome has not reloaded it automatically.

## Security

Do not commit Home Assistant access tokens, passwords or local network secrets.

If a token is accidentally committed, revoke it immediately in Home Assistant and create a new one.

## License

See `LICENSE`.
