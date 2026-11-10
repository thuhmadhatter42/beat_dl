# To the FLR site session: full /beat-key update (2026-11-09 13:15, updated 17:03, from the Beat Key session)

**17:03 UPDATE: Beat Key 0.1.57 is PUBLIC (J published 16:58; beat-key-latest.json = 0.1.57, GitHub release + appcast verified). Screenshots are READY in `~/dev/beat_dl/handoff/flr-assets/` (README.md lists them; .jpg for the site, .png 2x). So: build on preview, J reviews, then swap live — no release wait.**

Also since this was written: 0.1.53 footer buttons all one style; 0.1.55 Manual Key Selection (click any key on the wheel / top 3 / MANUAL menu / play it: shown white, MANUAL on the dial, hover the dial to reset); key names always Auto-Tune's spelling (no sharps/flats switch).

J (13:07): "/beat-key needs an entire update, not just this stale small piece." This replaces
TO-FLR-SITE-2026-11-03-finder-item.md (fold that in; it is item 3 below).

## Where it is
- Live /beat-key = written for 0.1.31 (Sofia ~/fourletterrecords cf8bd73, built 2026-11-02).
  Screenshots next/assets/beat-key-window.jpg + beat-key-panel.jpg are from 0.1.31: the window has
  changed almost completely since.
- Public app = 0.1.34. J's MBP runs 0.1.50 (0.1.51 coming: % back on the dial). Everything
  0.1.35 → 0.1.51 ships in ONE release when J runs `tools/publish.sh` in the Beat Key repo.

## Where it needs to be
A page that describes the app J is about to publish, with fresh screenshots, live the moment that
release is public, and not before (never advertise features the download doesn't have).
Build it on preview.fourletterrecords.com now; swap to live after J says the release is out
(check https://fourletterrecords.com/beat-key-latest.json shows 0.1.51 or later).

## What changed in the app since the page was written (source: Beat Key repo, read-only for you)
1. Window redesigned (0.1.33, 0.1.41–0.1.50): matches the menu-bar panel; big BPM with small
   decimals; key dial showing the confidence %; top three keys each with its own %; one type scale,
   amber on black; smooth motion. Old "three keys" copy still holds.
2. Live tuning (0.1.37, 0.1.45): a TUNING meter (±50 cents, green within 5) and "A4 = 443.1 Hz";
   key stays sure when the music is detuned (Spotify pitched +7/+14/+50 cents).
3. Finder right-click "Analyze with Beat Key" works since 0.1.34 (J confirmed 2026-11-03): put
   "or right-click it in Finder" back.
4. Advanced Mode (View › Advanced Mode, ⌥⌘A): Camelot code + relative key; key wheel (circle of
   fifths, three rings; hover a key for how sure it is and why it fits; click to choose it); notes
   heard; chord strip: the key's 7 chords + borrowed ones, triad/7th/9th, inversions, click to hear,
   drag a chord into your DAW as MIDI; MATCH TO (transpose −6..+6).
5. MINI (0.1.45): a small floating chord pad that plays the key's chords live into your DAW over
   MIDI (virtual MIDI source "Beat Key": set an instrument track's input to it). Keys 1–7 + Q W E R.
6. HELP button: turn it on and everything explains itself on hover.
7. Keyboard: play notes (A S D F…) to find the key yourself; space flips major/minor.
8. MANUAL key dropdown (was "WRONG? IT'S…"): pick the key yourself and it's used for everything.
9. One PASTE + DOWNLOAD button (DOWNLOAD when a link is typed); HOLD freezes the reading, reset icon
   beside it starts a new song.
10. Listen falls back to Mac audio when your saved interface isn't plugged in.
11. Better tempo model (fine-tuned TempoCNN, 2026-11-09).
12. Send to DAW: if anything can't be confirmed it now sends nothing rather than a wrong tempo.
    The DAW list on the page is still right (code: app/Sources/Orion/DAWSend/DAWSend.swift).
    Analyze Selection now has NO default shortcut (⌥⌘B is Pro Tools' Bounce): set one in Settings.
    Lamp shapes unchanged (octagon locked / triangle unsure / circle listening).
13. COLOR button (bottom right, between SETTINGS and HELP; being built 2026-11-09): pick any
    display colour from the macOS colour wheel instead of amber; Reset to amber.

Verify every claim before it goes on the page against the Beat Key repo (read only, never edit it):
`~/dev/beat_dl/README.md` (the "Beat Key app" section), `app/Sources/Orion/Help.swift` (HelpText:
one line per control, the app's own words), and `PICKUP.md` top block. Anything unclear → ask the
Beat Key session through J, don't guess.

## Screenshots
Don't screenshot J's screen. The Beat Key session will make fresh renders with a real reading
(default window, Advanced window, menu-bar panel, MINI) at the release version into
`~/dev/beat_dl/handoff/flr-assets/` and tell J when they're there. Recent drafts to lay out with now:
`~/dev/beat_dl/docs/research/mini-2026-11-09/` (render-default.png, render-advanced.png,
popover-locked.png, mini-cminor.png).

## Rules that still apply (your CLAUDE.md)
Edit Sofia next/build.py + next/assets, check preview, then copy to live; commit with explicit
file names; never mention installing anything else; brand bone #EAE0CE on #060606. The page must
not grow into a manual: lead with the three keys + listening + DAW, then a tight "Advanced" section
(wheel, chords, MINI, tuning). J reviews preview before the live swap.

## Report back
Write `~/dev/beat_dl/handoff/FROM-FLR-SITE-2026-11-09-beat-key-page.md`: preview URL, sections,
what you couldn't verify, and "live" or "waiting for release".
