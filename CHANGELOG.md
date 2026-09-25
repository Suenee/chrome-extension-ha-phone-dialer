# Changelog

All notable changes to this project will be documented in this file.

## 1.20

- The configuration connection test now keeps the authenticated WebSocket open.
- The Connect button changes to Disconnect after successful authentication and returns to Connect after disconnect or connection loss.

## 1.19

- Added an extension toolbar action; clicking the HA Phone Dialer icon opens the configuration page directly.
- Kept the standard Chrome Options page entry as a secondary path.

## 1.18

- Added a Chrome configuration page for Home Assistant connection parameters.
- Configuration now auto-saves to `chrome.storage.local` only when valid; invalid edits keep the last valid configuration active.
- Added Connect/Disconnect-style connection test, Reset and Close controls.
- Added token show/hide control and runtime log-mode selector.
- Added one-time migration from legacy private `config.local.js` into Chrome local storage.
- Preserved direct `tel:` and `callto:` interception and context-menu dialing.

## 1.17

- Added runtime logging modes `off`, `phone`, `single` and `all`.

## 1.10

- Based on the verified working 1.08 build.
- Added a short local confirmation sound after a successful send.
- Preserved direct interception of `tel:` and `callto:` links.
- Preserved context-menu sending for selected phone numbers.

## 1.08

- Added success and error feedback.

## 1.07

- Improved interception of `tel:` and `callto:` links, including iframes and nested elements.

## 1.00

- Initial working prototype.
