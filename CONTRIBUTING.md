# Contributing

Contributions are welcome.

## Development

This project is a Manifest V3 Chrome extension.

Recommended workflow:

1. Fork or clone the repository.
2. Make changes in a dedicated branch.
3. Keep Home Assistant credentials and access tokens out of Git.
4. Test the extension as an unpacked extension in Chrome.
5. Verify `tel:` links, `callto:` links and context-menu sending.
6. Verify error handling and successful audio feedback.
7. Submit a pull request with a concise description of the change.

## Security

Never include:

- Home Assistant Long-Lived Access Tokens
- passwords
- private IP-specific secrets
- personal device identifiers that are not required for the public example

Use placeholders in documentation and examples.

## Versioning

Update the extension version in `manifest.json` for each release and document user-visible changes in `CHANGELOG.md`.
