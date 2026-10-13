# MrPlay — Claude guide

Flutter, iOS-only app (Riverpod, flutter_inappwebview, Hive, AdMob). Branch `v2-tabs`, main is `master`.

## Token-saving rules (read first)
- Do NOT read or list anything in `claudeignore.md` (build output, logs, lockfiles, generated files, images).
- Use Grep/Glob to locate code, then Read only the needed range (`offset`/`limit`). Never read whole large files.
- Don't open `PROJECT_MAP.md` (huge changelog). Grep it for a keyword only if needed.
- Don't re-read a file you just edited. Don't re-explain unchanged code.
- Keep answers short: no recap of the diff, no option surveys — give one recommendation.
- Make the smallest change that solves the task; no unrequested refactors, comments, or docs.
- Prefer one parallel batch of tool calls over many sequential ones.
- Use the Explore agent only for broad multi-file searches; do small lookups directly.
- Run `flutter analyze <file>` on touched files, not the whole project; run `flutter test <file>` for specific tests.

## Layout
- `lib/main.dart`, `lib/app.dart` — entry/app shell
- `lib/presentation/{pages,widgets}` — screens and UI
- `lib/widgets/` — full player, link resolver sheet
- `lib/providers/player_provider.dart` — player state (Riverpod)
- `lib/services/` — background audio, media controls, PiP/spotlight/siri, sleep timer, share links, stats
- `lib/data/`, `lib/models/` — repositories, models (Hive boxes)
- `lib/core/` — constants, theme, utils
- `lib/ad_config.dart` — AdMob IDs/config
- `ios/` — native Runner, HomeWidgetExtension, Info.plist
- `web/` — static privacy/support pages (not the app)
- `codemagic.yaml` — CI/TestFlight build

## Conventions
- State: Riverpod (not bloc). WebView: flutter_inappwebview.
- Injected JS lives in Dart strings (e.g. content blocker, YouTube cleanup) — edit carefully, escape quotes.
- Commits: `type: short message` (feat/fix/chore).
- Never commit secrets; AdMob app ID in Info.plist is a TEST id until release.
