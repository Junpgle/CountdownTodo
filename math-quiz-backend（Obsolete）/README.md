# Cloudflare Worker compatibility backend

This Worker is retained for compatibility and migration support. New backend
features target the separate Alibaba `CDT-server/debug/` development tree.
User-facing Cloudflare server selection is disabled in current clients, although
Cloudflare Zero Trust and Turnstile are still used elsewhere.

## Capabilities in `src/index.js`

- Account registration/login/password and user status.
- Delta sync for todos, countdowns, groups, courses, settings, screen time,
  Pomodoro data and collaboration-related records.
- Leaderboard/score, teams and server-to-server migration endpoints.

The Worker is a single-file implementation and does not have feature parity with
every modular Alibaba route. In particular, do not assume Alibaba Turnstile,
conflict-history or newer team/share behavior is enforced here unless present in
`src/index.js`.

## Development

```bash
npm install
npm run dev
npm test
npm run deploy
```

Keep Worker secrets in Cloudflare configuration, never in the repository. Any
change must preserve existing clients or be paired with an explicit migration.
