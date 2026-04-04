# VieSpeak

AI voice companion app for Vietnamese university students to practice English speaking via OpenAI Realtime API (Speech-to-Speech).

**Core philosophy: Open app -> tap one button -> start talking.**

## Tech Stack

- **Mobile:** Flutter (iOS + Android)
- **Backend:** Golang (separate repo) — auth, quota, memory, token generation
- **Voice:** OpenAI Realtime API — app connects directly via ephemeral token (backend does NOT proxy audio)

## Environment Variables (.env)

```
API_BASE_URL=          # Golang backend REST API
SUPABASE_URL=          # Supabase project URL
SUPABASE_ANON_KEY=     # Supabase anonymous key
DEV_MODE=false         # true = mock services, no backend/OpenAI needed
```

## Design System

All UI must follow `DESIGN.md` (ElevenLabs-inspired). Key rules:
- Waldenburg weight 300 for display headings — never bold
- Inter with +0.14–0.18px letter-spacing for body text
- Pill buttons (9999px radius), warm stone CTA (`rgba(245,242,239,0.8)`)
- Multi-layer shadows at sub-0.1 opacity (inset + outline + elevation)
- Warm tints throughout — no cool grays, no heavy shadows
- See `DESIGN.md` for full color palette, typography scale, component specs

## Code Conventions

- All code, comments, variable names, strings in **English only**
- Feature-first folder structure (`lib/features/`, `lib/core/`, `lib/shared/`)
- No over-engineering — MVP first, optimize later
- Audio format: PCM16, 24kHz, mono
