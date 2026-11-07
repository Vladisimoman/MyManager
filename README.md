# MyManager

A personal finance, to-do and time-tracking app built with **Flutter** for Android and the web.
Data is stored locally (SQLite via drift) and synced between devices through the user's own Google Drive, so the app needs no backend database and costs nothing to run.

Built incrementally over 26 stages; current version **1.28**, covered by **~230 automated tests**.

## Features

**Finance**
- Income and expense records with categories, multi-currency wallets and transfers with exchange
- Exchange rates from the ECB (Frankfurter) and the National Bank of Ukraine, with the rate stored for each record's date
- Crypto and stock holdings (buy, sell, transfer), plus owned items as assets
- Monthly budgets per category with warnings, savings goals with progress and a "per month" target
- Recurring payments and one-tap templates
- Statistics with charts (fl_chart) and period / currency filters

**To-Do**
- Tasks for today, a date, or undated; overdue and completed lists
- Flexible repeats (daily, weekly on chosen days, every N days / weeks / months / years) and key dates such as birthdays
- Month calendar, priorities, missed repeats recorded automatically
- Notifications with "Done" and "Snooze" actions and a morning summary

**Activity**
- Time tracking with a timer, a day timeline with gaps, productivity tags
- Statistics by day, week, month or a custom period

**Sync and security**
- Two-way sync through a hidden Google Drive app folder, "latest change wins" merge
- PIN and fingerprint lock, PIN reset through Google
- Backup to a file

## Tech stack

| Area | Tools |
| --- | --- |
| App | Flutter, Dart, Riverpod |
| Storage | drift (SQLite), IndexedDB on the web |
| Charts | fl_chart |
| Sync | Google Sign-In, Google Drive REST API (`drive.appdata`) |
| Web auth | Cloudflare Worker that keeps the Google refresh token in an HttpOnly cookie |
| Device | local_auth, flutter_local_notifications |

## Architecture

```
lib/
  core/            theme, money formatting and parsing, config, version
  data/            drift database, default categories, exchange-rate services
  features/
    finance/       balances, ledger, budgets, goals, recurring payments, statistics
    wallets/       wallets, transfers and exchange
    assets/        crypto, stocks and owned items
    todo/          tasks, repeats, calendar, missed-repeat recorder
    activity/      time tracking and statistics
    notifications/ notification planning and actions
    security/      PIN and fingerprint lock
    settings/      categories, sync, backup, data deletion
  sync/            JSON snapshot and merge, Google Drive store, sign-in on phone and web
cloudflare/        Worker for web sign-in (token exchange, refresh, sign-out) and its tests
test/              unit and widget tests, with fake network and in-memory Drive helpers
```

Business logic (ledger, budgets, repeats, statistics, notification planning) lives in plain Dart files separate from the screens, which keeps it testable without a device.

## Running locally

Requires Flutter 3.47+ and the Android SDK.

```bash
flutter pub get
dart run build_runner build   # only after changing tables in lib/data/database.dart
flutter test
flutter run
```

Google sign-in needs your own OAuth clients in Google Cloud (Android and Web) and your Web Client ID in `lib/core/config.dart`. Release builds read the signing key from `android/key.properties`, which is not part of this repository.

Worker tests: `cd cloudflare && node --test test/worker.test.mjs`.
