# Turnstile verification

Last verified: 2026-07-20.

## Current paths

- Native Flutter (`turnstile_verification_widget_io.dart`) opens a WebView to
  the backend `/turnstile` page. Production uses the Zero Trust hostname;
  development uses the Alibaba debug server.
- Flutter web (`turnstile_verification_widget_web.dart`) renders Turnstile
  through JavaScript interop and returns the token to Dart.
- The separate React app under `webpage/web/` has its own Turnstile component.
- Alibaba `CDT-server/debug/middleware/turnstile.js` verifies tokens with
  Cloudflare during registration/password flows. Production has the equivalent
  middleware in its protected tree.

The repository's legacy Worker is not the source of truth for current Turnstile
enforcement. Keep the widget site key public, but keep the verification secret
server-side. Validate expected action, token lifetime, failure/cancellation,
network errors and WebView disposal. Never log complete verification tokens.
