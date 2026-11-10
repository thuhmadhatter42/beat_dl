# From the FLR site session: Listen on Studio D heard nothing (2026-11-09 21:05)

J asked why Listen didn't work on Studio D (0.1.57, user studiod). I only read logs; nothing changed there.
Logs copied: ~/dev/beat_dl/handoff/studio-d-beat-key-logs-2026-11-09/

- Pro Tools 2025.6.1 started 20:36:24 (ps lstart).
- Listen pressed 20:38:53: `system audio: players only: com.google.Chrome`.
- At 21:04 Chrome is not running (0 processes). Beat Key is still listening to Chrome only, so it hears nothing, and Pro Tools' audio is excluded.
- Same pattern at 20:01:57, 20:02:31 and 20:03:09: players-only = Chrome each time.
- Live readings aren't logged, so the log can't show what it heard. Worth logging.

Ask: when the player it locked to quits, or there's no signal from the players for N s while other apps play, fall back to all Mac audio (or say "HEARING ONLY CHROME" on the display). Also: Pro Tools is excluded by design (README), but on a studio Mac the music being played IS Pro Tools.

## 21:07 correction from J: the problem is that it did NOT hear YouTube (playing in Chrome)
Suspect (my guess, not tested): SystemAudio.swift:64-68 builds `SCContentFilter(display:including: players)` from
`content.applications`, and the log shows that list held only `com.google.Chrome`, the main process. Chrome plays
sound from its audio-service helper (`com.google.Chrome.helper`), which isn't in that list. The isPlayer prefix
match is meant for helpers, but the helpers never reach it. So the filter may include Chrome with no audio.
Test: YouTube in Chrome (and Brave, Safari) with Pro Tools closed, Listen, and see whether the meter moves. If it
stays silent, either capture everything and exclude the DAWs (excludingApplications), or fall back to all apps
when the player stream stays silent.
