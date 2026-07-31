# Countdown Todo Xiaomi band companion

Quick App companion source lives under `src/`. Last reviewed: 2026-07-20.

## Current version

- `src/manifest.json`: version **1.0.6**, versionCode **7**.
- `package.json`: version **1.0.6**.
- `src/common/sync_service.js` still defaults to 1.0.5/code 6 and
  `package-lock.json` still identifies the root package as 1.0.5. These are
  known version-source drifts; use the manifest for packaging and align all
  four files during the next version bump.

## Pages and data

`src/pages/` contains `index`, `todo`, `countdown`, `course`, `settings`,
`pomodoro`, and `alert`. The communication layer exchanges todo, countdown,
course and Pomodoro data with the Android host and also handles band info,
version/update messages, notifications and user actions.

The band is a companion, not an independent cloud client. Keep message schemas
compatible with `BandCommunicationPlugin.kt` and the Flutter band sync screens.

## Development

```bash
npm install
npm run start
npm run build
npm run lint
```

Do not edit generated `build/` output or dependency files by hand. Validate on
the target device/runtime because simulator support and Xiaomi APIs may differ.
