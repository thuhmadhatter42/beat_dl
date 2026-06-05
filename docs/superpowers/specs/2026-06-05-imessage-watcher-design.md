# iMessage Beat Watcher — Design

**Date:** 2026-06-05
**Status:** Approved (pending spec review)

## Purpose

When CCASH2 or DOUBLE CUP text J a YouTube link, automatically download it as a
tagged MP3 via the existing beat_dl pipeline, then confirm by sending a 👍
(like) tapback on their message. Replaces the manual loop: see text → paste URL
into run.command → heart the message.

## Senders (allowlist)

| Contact | Handle | Destination |
|---------|--------|-------------|
| CCASH2 | `+15042748877` | `~/Downloads` |
| DOUBLE CUP | `+15127391532` | `~/Downloads/other-beats/` (auto-created) |

No other senders trigger anything. Handles are constants at the top of
`watcher.sh`.

## Architecture

Orchestration is ours; the two hard Messages problems are delegated to
[`imsg`](https://github.com/openclaw/imsg) (`brew install steipete/tap/imsg`):

- **Reading**: `imsg history --chat-id N --json` returns decoded message text
  (avoids hand-parsing `attributedBody` typedstream blobs).
- **Reacting**: `imsg react --chat-id N --reaction like` sends a verified
  tapback via UI automation. Constraint: it can only react to the **most
  recent incoming message** in a chat.

### Components

| File | Role |
|------|------|
| `watch.command` | Double-click launcher (same pattern as `run.command`). Foreground; stops when the terminal closes. |
| `watcher.sh` | Poll loop. Every ~3s, fetch new messages (ROWID > last seen) for the two chats, extract YouTube URLs, drive the pipeline, react, notify on failure. |
| `process_url.sh` | Per-URL pipeline factored out of `run.sh`: download → BPM/key analysis → rename → append to daily `LINKS.txt`. Sourced by both `run.sh` and `watcher.sh` so there is one code path. |
| `downloader.py` (1-line change) | `DOWNLOADS` becomes `Path(os.environ.get("BEAT_DL_OUTDIR", str(Path.home() / "Downloads")))`. Default unchanged, so `run.command` behaves exactly as before. |
| `.watch_state.json` | Last-processed message ROWID per chat + set of processed URLs. Git-ignored. |

## Flow (per new message, oldest first)

1. Extract YouTube URL(s) (`youtube.com` / `youtu.be`) from message text.
2. **Dedupe**: skip if URL already in today's `LINKS.txt` or in
   `.watch_state.json` (no re-download, no double-👍).
3. Set `BEAT_DL_OUTDIR` from the sender mapping; run `process_url.sh`.
4. **On success**: if this message is still the latest incoming message in its
   chat → `imsg react --reaction like`. If newer messages arrived meanwhile
   (burst), skip the react and keep draining — only the batch's final message
   gets the 👍. Never react twice at the same chat head (a repeat like
   toggles to unlike).
5. **On failure**: macOS notification banner
   (`osascript -e 'display notification ...'`) naming the sender + URL, plus a
   line in `watcher.log`. No 👍 — its absence is the sender-visible signal.

## Startup behavior

- Lookback is **today only**: state initializes to the first message of the
  current day, deduped against today's `LINKS.txt` (manually downloaded links
  are not re-fetched and not reacted to).
- Launches Messages.app if not running (required by `imsg react`).

## Logging

- Successful downloads: existing daily `~/Downloads/(YY-M-D) Youtube DL
  LINKS.txt`, unified for both senders.
- Watcher events (polls are silent; detections, downloads, reacts, failures):
  `watcher.log` in the project root, git-ignored.

## One-time setup

1. `brew install steipete/tap/imsg`
2. Grant Terminal: Full Disk Access (already granted), Automation → Messages,
   Accessibility (System Events) — macOS prompts on first react.
3. Chrome signed into YouTube (existing cookie requirement, unchanged).

## Error handling

- `imsg` missing / permissions not granted → watcher exits at startup with a
  plain-English message telling J exactly what to grant.
- Download failure (cookie expiry, deleted video, network) → notification +
  log, URL recorded as failed in state so it isn't retried in a loop.
- React failure (Messages UI rejection) → log + notification; download is
  already safe on disk.
- chat.db locked/busy → skip poll tick, retry next tick.

## Out of scope

- Plain CCASH (+1 737 390 9213) and all other senders.
- Always-on launchd agent (J chose double-click foreground; can be added later).
- Reacting to specific non-latest messages (no public API).
- Backfill earlier than today.
