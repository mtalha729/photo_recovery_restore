# Photo Recovery & Restore Development Rules

## Scope and workflow

- Work on one requested milestone at a time; stop when it is complete.
- Inspect and change only files needed for the current milestone.
- Prefer the smallest correct change. Do not refactor unrelated working code.
- Do not add features, dependencies, APK/AAB builds, or expensive commands unless requested.
- When applicable, validate once with `flutter pub get` (only after dependency changes), `flutter analyze`, and `flutter test`.
- Report only changed files, implementation, validation, and blockers or decisions needed.

## Recovery correctness and platform compliance

- Recovery accuracy is the priority. Never present an existing normal photo as deleted or recovered.
- The one-tap Recover Photos scan automatically starts all permitted providers after any required permission grant; no folder selection is required.
- Recover Photos is recovery-first: current gallery inventory is for internal matching, exclusion, deduplication, and analysis, not default results. Do not publish ordinary gallery originals as recovery candidates.
- Independently discovered, recovery-relevant surviving copies, caches, and thumbnails may appear without verified deletion evidence; label them accurately. Preserve distinct accessible copies on other storage volumes, and never claim an original was deleted without supported evidence.
- Use only legitimate, Play Store-compliant Android APIs. Do not bypass permissions, use root, access private app data, or use unsupported raw-storage techniques.
- Never claim guaranteed recovery or invent recovery percentages or confidence scores.

## Architecture and quality

- Use null-safe, strongly typed Dart and a feature-oriented, modular architecture.
- Separate domain, data/platform, application/state, and presentation responsibilities.
- Keep recovery classification logic centralized and independently testable.
- Isolate native Android/Kotlin integration behind explicit interfaces or platform services.
- Use structured errors/results rather than silent failures.
- Keep files and classes focused; avoid unnecessary dependencies and comments that restate obvious syntax.
- Repair the active production engine and results flow; do not replace them with duplicate pipelines or screens.
- Prioritize recovery logic, tests, reliability, and performance before production UI polish.

## Planned capabilities

The long-term architecture must support permitted recovery across Camera/Gallery, Screenshots/Downloads, messaging/shared media, and removable SD cards when accessible; existing-media exclusion; deletion verification; duplicate/best-copy resolution; restore; and Recovery Shield. Do not reintroduce selected-folder scanning unless explicitly requested.
