# VieSpeak — CLAUDE.md

## Project Overview

VieSpeak is an AI voice companion app that helps Vietnamese IT and Economics university students practice English speaking. Users have real, natural conversations with Alex — an AI persona that speaks like a human (with hesitations, laughter, pauses) and remembers personal context across sessions.

**Core philosophy: Open app → tap one button → start talking. Nothing else.**

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile | Flutter (iOS + Android) |
| Backend API | Golang (separate repo) |
| Voice AI | OpenAI Realtime API (S2S — Speech-to-Speech) |

---

## Architecture

```
Flutter App
    → GET /session/init             → Golang Backend (returns ephemeral token)
    → WebSocket (realtime voice)    → OpenAI Realtime API (direct connection)
    → POST /session/end             → Golang Backend (stores memory, deducts quota)
    → REST (auth, profile, memory)  → Golang Backend
```

The Flutter app connects **directly** to OpenAI Realtime API using an ephemeral token.
The Golang backend does NOT proxy audio — it only handles auth, quota, memory, and token generation.

---

## Folder Structure

```
lib/
├── main.dart
├── app.dart
├── core/
│   ├── config/
│   │   └── env.dart                # API URLs, keys
│   ├── theme/
│   │   └── app_theme.dart          # Design system (ElevenLabs-inspired)
│   ├── services/
│   │   ├── auth_service.dart       # Auth via Supabase
│   │   ├── realtime_service.dart   # Direct WebSocket to OpenAI Realtime API
│   │   ├── session_service.dart    # REST: session init (token) + session end
│   │   ├── api_service.dart        # REST: profile, memory, quota
│   │   └── audio_service.dart      # Mic recording + speaker playback (PCM16)
│   └── router/
│       └── app_router.dart
├── features/
│   ├── onboarding/
│   │   └── major_selection_screen.dart  # Choose IT or Economics
│   ├── auth/
│   │   └── login_screen.dart            # Google Sign-in
│   ├── conversation/
│   │   ├── conversation_screen.dart     # Main screen — one tap to talk
│   │   └── transcript_widget.dart       # Realtime transcript display
│   └── profile/
│       └── profile_screen.dart          # User profile, quota, conversation history
└── shared/
    └── widgets/
        └── quota_bar_widget.dart         # Session time remaining indicator
```

---

## Environment Variables

```bash
# .env
API_BASE_URL=          # Golang backend REST API base URL
SUPABASE_URL=          # Supabase project URL
SUPABASE_ANON_KEY=     # Supabase anonymous key
DEV_MODE=false         # true = use mock services (no backend/OpenAI needed)
```

---

## AI Personas

### Alex — IT Persona
- **Role:** Senior Software Engineer, 28, fintech startup in Singapore
- **Personality:** Chill, mentors juniors, shares real stories, never judgmental
- **Speech style:** Natural fillers ("you know...", "hmm let me think..."), laughs, pauses, self-corrects
- **Topics:** System design, career advice, code reviews, interview prep, side projects

### Sarah — Economics Persona
- **Role:** Marketing Manager, 30, multinational FMCG in Singapore
- **Personality:** Energetic, practical, shares real work experiences, stays positive
- **Speech style:** Same human-like naturalness as Alex
- **Topics:** Market trends, campaign strategy, career growth, business English

---

## Core Features — MVP Scope

### Must Have
- [ ] Google Sign-in (via Supabase)
- [ ] Major selection screen (IT → Alex, Economics → Sarah)
- [ ] One tap to start voice conversation
- [ ] Realtime transcript display
- [ ] Session quota: time limit + daily session count
- [ ] Memory: fetch previous session context, display hint on session start
- [ ] Quota display on profile screen

### Must NOT Have (post-MVP)
- Progress tracking / dashboard
- Multiple personas per major
- Pronunciation scoring
- Gamification / streaks
- Settings screen

---

## Conversation Flow

```
App opens
  → "Hey [name], Alex is ready to chat."
  → One large button: "Start talking"
  → GET /session/init → receive ephemeral token + remaining_seconds
  → Connect directly to OpenAI Realtime API (wss://api.openai.com/v1/realtime)
  → Send session.update (PCM16 format, server VAD)
  → Voice streams both ways (Flutter ↔ OpenAI)
  → Transcript displays in realtime
  → On user interruption: stop playback + send response.cancel
  → Session ends when quota hits 0 or user taps "End"
  → POST /session/end → send transcript + duration to backend
```

---

## Memory Flow (app side)

```
Start of session:
  1. App fetches latest memory via backend API (GET /api/memories)
  2. Display context hint to user (e.g. "Last time you talked about...")
  3. Backend injects memory into AI persona prompt via ephemeral token

End of session:
  → App sends transcript + duration to backend (POST /session/end)
  → Backend handles summarization and storage
  → App can fetch updated memory on next session
```

---

## Backend API Endpoints (Golang)

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | /session/init | Auth, check quota, build prompt, return ephemeral token |
| POST | /session/end | Receive transcript + duration, summarize, store memory |
| GET | /session/quota | Return remaining time + session count for profile |
| GET | /api/profile | Fetch user profile |
| POST | /api/profile | Create/update profile |
| GET | /api/memories | Fetch conversation history |

---

## User Limits

| Tier | Session length | Sessions/day |
|---|---|---|
| Free | 10 minutes | 1 |
| Premium | 30 minutes | Unlimited |

---

## Code Conventions

- All code, comments, variable names, and strings in **English only**
- Feature-first folder structure
- No over-engineering — MVP first, optimize later
- Every feature must serve the core UX: open app → tap → talk
- Audio format: PCM16, 24kHz, mono (matches OpenAI Realtime API)

---

## Development Order

1. Google Sign-in (via Supabase)
2. Major selection screen
3. Conversation screen — OpenAI Realtime API (S2S) + transcript
4. Memory fetch + context hint on session start
5. Quota tracking on profile screen
6. End-to-end test with real backend + OpenAI
