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

---

## Architecture

```
Flutter App
    ↕ WebSocket (realtime voice)       → Golang Backend API
    ↕ REST (auth, memory, users, etc.) → Golang Backend API
```

The Golang backend is a separate repo. This repo is the **Flutter app only**.
All communication goes through the backend API — auth, data, and voice.

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
│   │   ├── auth_service.dart       # Auth via backend API
│   │   ├── ws_service.dart         # WebSocket to backend
│   │   └── api_service.dart        # REST calls to backend API (memory, users, sessions)
│   └── router/
│       └── app_router.dart
├── features/
│   ├── onboarding/
│   │   └── major_selection_screen.dart  # Choose IT or Economics
│   ├── auth/
│   │   └── login_screen.dart            # Google Sign-in
│   └── conversation/
│       ├── conversation_screen.dart     # Main screen — one tap to talk
│       └── transcript_widget.dart       # Realtime transcript display
└── shared/
    └── widgets/
```

---

## Environment Variables

```bash
# .env
API_BASE_URL=          # Golang backend REST API base URL
WS_BASE_URL=           # Golang backend WebSocket URL
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
- [ ] Google Sign-in (via backend API)
- [ ] Major selection screen (IT → Alex, Economics → Sarah)
- [ ] One tap to start voice conversation
- [ ] Realtime transcript display
- [ ] Session time limit: 10 minutes (free tier)
- [ ] Memory: fetch previous session context, inject on session start

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
  → WebSocket connects to backend API
  → Voice streams both ways
  → Transcript displays in realtime
  → Session ends after 10 minutes or user taps "End"
```

---

## Memory Flow (app side)

```
Start of session:
  1. App fetches latest memory via backend API (GET /api/memory/:userId)
  2. Display context hint to user (e.g. "Last time you talked about...")
  3. Backend injects memory into AI persona prompt automatically

End of session:
  → Backend handles summarization and storage
  → App can fetch updated memory on next session
```

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

---

## Development Order

1. Google Sign-in (via backend API)
2. Major selection screen
3. Conversation screen — WebSocket + transcript
4. Memory fetch + inject on session start
5. End-to-end test with real backend
