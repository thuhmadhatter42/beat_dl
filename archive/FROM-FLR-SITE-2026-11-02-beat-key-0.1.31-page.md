# From the FLR site session: /beat-key updated for 0.1.31 (2026-11-02 10:58)

Live: https://fourletterrecords.com/beat-key (Sofia ~/fourletterrecords ba7ba13, site VERSION 0.0.32). J asked for it; the download already serves 0.1.31 (beat-key-latest.json).

- Hero unchanged ("YouTube to MP3 / with the BPM/Key", J's line), body now adds "or let it listen to whatever is playing".
- New sections: "Three keys, not one." (file name, 92% GiantSteps+, click key 2/3, file types) with a screenshot of the main window; "It listens, too." (sources, menu bar, lamp shapes, decimal BPM, half/double, tuning) with a screenshot of the menu-bar panel; "Straight into your session." (Send to DAW per DAW, Analyze Selection, Send to Auto-Tune + Waves Tune preset, shortcuts).
- Last section: "updates itself, and its downloader too", permissions line (Mic / Screen & System Audio / Accessibility), each only when used.
- Screenshots: taken from 0.1.31 on J's MBP, a copy of a beat renamed "Some Beat.mp3" (75.00, Eb / Cm / Ab). Files: next/assets/beat-key-window.jpg, beat-key-panel.jpg.
- Still not on the page: the source-and-licences link (Essentia AGPL / ffmpeg). Send the URL and it goes in the Get section.

## J tested 2026-11-02 12:34 (0.1.31)
- Ableton: works. Artemis: works. (J's words: "works fine" / "also works in artemis".) Tick these on your MBP test list.

## Finder service not showing (J 12:36: "i dont see this anywhere")
- 0.1.31 Info.plist declares NSServices "Analyze with Beat Key" and pbs has it registered (com.jshriver.orion), but it has no NSRequiredContext. Every other registered service on J's MBP (21) carries one. Likely cause (not verified): without NSRequiredContext macOS keeps a third-party service off by default, so it shows in neither the right-click menu nor Services until turned on in Keyboard Shortcuts > Services. Fix to try: add `NSRequiredContext = {}` (empty dict) to the NSServices entry, then `/System/Library/CoreServices/pbs -update` and test on a file in Finder.
- I removed "or right-click it in Finder" from /beat-key (Sofia b0c5428, 0.0.33). Tell me when it works and I'll put it back.
- J 12:37: live listening to Mac audio checked after the 0.1.22 48 kHz fix, about 20 songs, keys right. Tick it.
- 21:46 Finder fix: agent commit 1a91765 on branch finder-service (worktree ~/dev/beat_dl/.claude/worktrees/finder-service), NSRequiredContext {} added per Apple's Services Properties doc. Test build 0.1.32 (unnotarized) installed in /Applications; pbs shows it, Services menu lists it, NSPerformService ran it. Not merged; J's right-click not yet done.

## For the Beat Key session to take over (22:28)
- Branch `finder-service` (commit 1a91765, worktree ~/dev/beat_dl/.claude/worktrees/finder-service) is yours: merge it into main (made from be0a9ce, before your 0.1.33), then remove the worktree. Not merged by me.
- /Applications/Beat Key.app on the MBP is that branch's unnotarized 0.1.32 test build (installed 21:46), not your 0.1.33.
- J still has to right-click an audio file in Finder once to confirm the item shows.
- Site: /beat-key now carries "Source code and licences" → the GitHub repo (Sofia cf8bd73). When the Finder item is confirmed, tell the FLR site session to put "or right-click it in Finder" back.
