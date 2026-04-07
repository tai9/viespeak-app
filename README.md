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

## Architecture

The app connects directly to OpenAI Realtime API via ephemeral tokens. The backend handles auth, quota, memory, and token generation — it does not proxy audio.

```
Flutter App
  → GET /session/init        → Backend (returns ephemeral token)
  → WebSocket (voice)        → OpenAI Realtime API (direct)
  → POST /session/end        → Backend (stores memory, deducts quota)
```
