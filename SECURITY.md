# Security Policy

## Reporting a vulnerability

Please report security issues privately to the repository owner rather than opening a public issue when the report contains sensitive details.

## Secrets

This extension communicates with Home Assistant and may use a Long-Lived Access Token in local configuration.

Never commit:

- Home Assistant access tokens
- passwords
- private credentials
- local-only configuration containing secrets

If a credential is accidentally committed, revoke it immediately in Home Assistant and replace it with a new one.

## Local configuration

Private configuration should be stored only in files excluded by `.gitignore` or in browser-local storage.
