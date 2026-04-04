# VieSpeak — CLAUDE.md

## Project Overview

VieSpeak is an AI voice companion app that helps Vietnamese IT and Economics university students practice English speaking. Users have real, natural conversations with Alex — an AI persona that speaks like a human (with hesitations, laughter, pauses) and remembers personal context across sessions.

**Core philosophy: Open app → tap one button → start talking. Nothing else.**

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile | Flutter (iOS + Android) |
| Backend | Golang |
| Hosting | Railway |
| Auth + DB | Supabase |
| AI (Voice) | OpenAI Realtime API |
| Memory | Supabase PostgreSQL |

---

## Architecture

```
Flutter App
    ↕ WebSocket (realtime voice)
    ↕ REST (auth, memory)
Golang Server (Railway)
    ↕ WebSocket → OpenAI Realtime API (STT + LLM + TTS)
    ↕ REST      → Supabase (auth, users, memory, sessions)
```

---

## Golang — Folder Structure

```
viespeak-be/
├── cmd/
│   └── server/
│       └── main.go
├── internal/
│   ├── handler/
│   │   ├── ws.go           # WebSocket voice handler
│   │   └── rest.go         # REST endpoints
│   ├── openai/
│   │   └── realtime.go     # OpenAI Realtime API client
│   ├── memory/
│   │   └── memory.go       # Summarize + store memory after session
│   ├── persona/
│   │   └── persona.go      # System prompts for Alex (IT) and Sarah (Economics)
│   └── supabase/
│       └── client.go       # Supabase client wrapper
├── config/
│   └── config.go           # Load env vars
├── Dockerfile
├── railway.toml
└── .env.example
```

---

## Flutter — Folder Structure

```
viespeak-app/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/
│   │   ├── config/
│   │   │   └── env.dart          # API URLs, keys
│   │   ├── services/
│   │   │   ├── auth_service.dart     # Supabase auth
│   │   │   ├── ws_service.dart       # WebSocket connection
│   │   │   └── memory_service.dart   # Fetch/store memory
│   │   └── router/
│   │       └── app_router.dart
│   ├── features/
│   │   ├── onboarding/
│   │   │   └── major_selection_screen.dart  # Choose IT or Economics
│   │   ├── auth/
│   │   │   └── login_screen.dart            # Google Sign-in
│   │   └── conversation/
│   │       ├── conversation_screen.dart     # Main screen — one tap to talk
│   │       └── transcript_widget.dart       # Realtime transcript display
│   └── shared/
│       └── widgets/
```

---

## Supabase Schema

```sql
-- Users
create table users (
  id uuid primary key references auth.users,
  name text,
  major text check (major in ('IT', 'Economics')),
  level text default 'B1',
  created_at timestamp default now()
);

-- Sessions
create table sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id),
  started_at timestamp default now(),
  ended_at timestamp,
  duration_seconds int
);

-- Memory (one row per session summary)
create table memories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id),
  session_id uuid references sessions(id),
  summary text,             -- compact summary of the conversation
  facts jsonb,              -- structured facts: {"job": "intern at FPT", "project": "graduation thesis"}
  pending_followup text,    -- what Alex should ask next session
  created_at timestamp default now()
);
```

---

## Environment Variables

```bash
# .env.example

# OpenAI
OPENAI_API_KEY=

# Supabase
SUPABASE_URL=
SUPABASE_SERVICE_KEY=

# Server
PORT=8080
ENV=development
```

---

## Railway Config

```toml
# railway.toml
[build]
builder = "dockerfile"

[deploy]
startCommand = "./server"
restartPolicyType = "on-failure"
```

---

## AI Personas

### Alex — IT Persona
- **Role:** Senior Software Engineer, 28, working at a fintech startup in Singapore
- **Personality:** Chill, likes mentoring juniors, shares real stories about failing projects, never judgmental, curious about user's side projects
- **Speech style:** Uses fillers naturally ("you know...", "I mean...", "hmm let me think..."), laughs lightly, pauses to think, occasionally self-corrects mid-sentence
- **Topics:** System design, career advice, code reviews, interview prep, side projects, tech news
- **Correction style:** Never interrupts. Waits for a natural moment, then gently suggests a better phrasing

### Sarah — Economics Persona
- **Role:** Marketing Manager, 30, working at a multinational FMCG company in Singapore
- **Personality:** Energetic, practical, likes sharing real work experiences, sometimes stressed about deadlines but stays positive
- **Speech style:** Same human-like naturalness as Alex
- **Topics:** Market trends, campaign strategy, career growth, internship experience, business English

---

## Core Features — MVP Scope

### Must Have
- [ ] Google Sign-in via Supabase Auth
- [ ] Major selection screen (IT → Alex, Economics → Sarah)
- [ ] One tap to start voice conversation
- [ ] Realtime transcript display
- [ ] Session time limit: 10 minutes (free tier)
- [ ] Memory: summarize session after end, inject into next session

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
  → WebSocket connects to Golang server
  → Golang proxies to OpenAI Realtime API
  → Voice streams both ways
  → Transcript displays in realtime
  → Session ends after 10 minutes or user taps "End"
  → Golang summarizes session → stores to Supabase memory
```

---

## Memory Flow

```
End of session:
  1. Golang sends conversation transcript to OpenAI API
  2. Prompt: "Summarize this conversation. Extract: key facts about the user,
     emotional context, topics discussed, what to follow up next session."
  3. Store structured result in memories table

Start of next session:
  1. Fetch latest memory for user from Supabase
  2. Inject into Alex system prompt:
     "Last session: [summary]. Follow up on: [pending_followup]. 
      Known facts: [facts]."
  3. Alex naturally references previous context in conversation
```

---

## User Limits

| Tier | Session length | Sessions/day |
|---|---|---|
| Free | 10 minutes | 1 |
| Premium | 30 minutes | Unlimited |

---

## Code Conventions

- All code, comments, variable names, and strings must be in **English only**
- Golang: follow standard Go project layout
- Flutter: feature-first folder structure
- No over-engineering — MVP first, optimize later
- Every feature must serve the core UX: open app → tap → talk

---

## Development Order

1. Supabase: create project, run schema SQL, enable Google Auth
2. Golang: project init, config, Supabase client, health check endpoint
3. Golang: OpenAI Realtime API WebSocket integration
4. Golang: memory summarize + store endpoint
5. Flutter: Google Sign-in
6. Flutter: major selection screen
7. Flutter: conversation screen — WebSocket + transcript
8. Flutter: memory fetch + inject on session start
9. End-to-end test with real users
