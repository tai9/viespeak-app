# VieSpeak

AI voice companion app that helps Vietnamese university students practice English speaking through natural conversations with AI personas.

## Tech Stack

- **Mobile:** Flutter (iOS + Android)
- **Backend:** NestJS (separate repo)
- **Voice:** OpenAI Realtime API (Speech-to-Speech)

## Setup

1. Clone the repo
2. Copy `.env.example` to `.env` and fill in values
3. Run `flutter pub get`
4. Run `flutter run`

### Environment Variables

```
API_BASE_URL=          # NestJS backend REST API
SUPABASE_URL=          # Supabase project URL
SUPABASE_ANON_KEY=     # Supabase anonymous key
DEV_MODE=false         # true = mock services, no backend needed
```

## Release Builds

Use `scripts/release.sh` to auto-increment the build number in `pubspec.yaml` and build a release artifact:

```bash
./scripts/release.sh              # default: appbundle (Android Play Store)
./scripts/release.sh apk          # Android APK
./scripts/release.sh ipa          # iOS IPA
./scripts/release.sh ios          # iOS build only
./scripts/release.sh all          # appbundle + ipa
```

The script:
1. Bumps only the build number (`+N` in `1.0.0+N`); the version name is left untouched.
2. Temporarily replaces `.env` with `.env.production` during the build so the release bundle ships with prod config. The original `.env` is restored on exit, even if the build fails.

Requires `.env.production` to exist at the repo root before running.

## Architecture

The app connects directly to OpenAI Realtime API via ephemeral tokens. The backend handles auth, quota, memory, and token generation — it does not proxy audio.

```
Flutter App
  → GET /session/init        → Backend (returns ephemeral token)
  → WebSocket (voice)        → OpenAI Realtime API (direct)
  → POST /session/end        → Backend (stores memory, deducts quota)
```
