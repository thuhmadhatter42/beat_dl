# Beat Key: design audit, 2026-11-09

Written as a senior product designer from the pro-audio plugin world. Covers the window at 0.1.41
(default + advanced, result and idle states). Research and findings only; no app code was changed.

- Renders audited: `render-default.png`, `render-advanced.png`, `render-advanced-idle.png`,
  `render-advanced-no-chroma.png` (from `HarmonyTests/testRender`), plus `docs/research/orra-parity/*.png`.
- Values come from `app/Sources/Orion` at 6b64b9a (Theme, Chassis, Controls, FaceplateView, LCD,
  PocketView, HarmonyView). Counts come from grepping those files.
- Annotated renders: `design-audit-2026-11-09/annotated-default.png`, `annotated-advanced.png`.
  Their callout numbers match the findings below.
- Method note: Impeccable's critique wants a second, detector-based pass, but its `detect` tool only
  reads web markup, so it can't scan SwiftUI. This audit is one reviewer's read (mine), checked
  against measured values and contrast maths.
- Already being fixed by another agent, so not re-reported: the MANUAL dropdown, a taller keyboard,
  smaller big buttons with bigger legends, PASTE + DOWNLOAD, the reset icon next to HOLD, and the
  new key wheel. Advice on doing those well is in section 5.

---

## 1. Verdict

1. The concept is right and specific: an amber VFD inside a screwed faceplate, a big BPM, a key dial and a lit wheel. Nothing here looks generic.
2. It reads as "80%" because nothing is set from a system. There are **20 font sizes (5.5 to 68 pt), 28 tracking values, 17 amber alphas, 16 spacing values and 8 corner radii**. Every element was tuned by eye on its own, so nothing lines up with anything else.
3. Everything is amber, bold, uppercase, tracked and glowing, so hierarchy can only come from alpha. Most secondary text is too small (7 to 8.5 pt) or too dim (alpha 0.35 to 0.45, under 3:1 contrast) to read. The fix is about six token tables and a sweep, not 40 one-offs.

---

## 2. Findings (most impact first)

Each finding has six parts: **What**, **Why** (the principle and a researched example), **Fix**
(concrete values), **Effort** (S/M/L), **Proof** (how to check it) and **Ref** (callout number).

### F1. No type scale: 20 sizes, many below the macOS floor  `[systemic]`
**What.** The sizes in use are 5.5, 6.5, 7, 7.5, 8, 8.5, 9, 10, 11, 12, 13, 14, 15, 18, 24, 26, 34, 38, 58 and 68 pt. About 45 call sites sit at 8.5 pt or below. Examples:
- `SOURCE` 6.5 pt (PocketView:896)
- `CAMELOT` 5.5 pt (HarmonyView:341)
- `BORROWED`, `BAR` and `CLICK = HEAR…` at 7 pt
- notes-heard letters at 7 pt
- the `BPM 142` caption and `Text.cap` at 8 pt
- send-cap legends at 9 pt

**Why.**
- Apple's HIG gives **13 pt as the default and 10 pt as the minimum on macOS**. Its built-in ramp is 26 / 22 / 17 / 15 / 13 / 12 / 11 / 10 ([HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography)).
- Reviewers name small grey text as the most common fault in plugin UIs. Sound On Sound wrote of Output Arcade: "some of the buttons had grey rather than black text" ([SOS](https://www.soundonsound.com/reviews/output-arcade)). MusicTech wrote of Sonible smart:EQ 4: "some of the grey text is illegible" (search snippet).
- Pro-Q and Pigments sell their resizable windows on legibility ([FabFilter help](https://www.fabfilter.com/help/pro-q/using/overview), [Arturia](https://www.arturia.com/products/analog-classics/pigments/overview)).
- A fixed 552 pt window has no resize escape hatch, so its type has to be legible at 1x.

**Fix.** Add six roles to `Theme` and route every `Theme.face(n)` call through one of them. Nothing goes below 10 pt.

| Token | Size / weight | Tracking | Case | Used for |
|---|---|---|---|---|
| `T.hero` | 68 Bold, tabular | +0.02em (1.4) | digits | BPM |
| `T.key` | 34 Bold | +0.03em | mixed | key in the dial, Doctor title |
| `T.title` | 18 Bold | +0.04em | UPPER | LCD stage words (WORKING, LISTENING, DROP…) |
| `T.value` | 13 Bold | 0 | mixed | top-3 keys, chord names, wheel major ring, filename |
| `T.label` | 11 Bold | +0.08em (0.9) | UPPER | cap legends, section heads (KEY WHEEL, CHORDS), status legend |
| `T.caption` | 10 Medium | +0.10em (1.0) | UPPER ≤ 3 words, else mixed | `SOURCE`, `BPM`, `REL Eb`, roman numerals, note letters, chip text, footer |

- Add `HelveticaNeue-Medium`. Today `Theme.face` only offers Bold and Regular, which is why everything is Bold. Medium at 10 pt gives the caption tier a different voice from the 11 pt Bold labels.
- `T.key` replaces 26/34/38; `T.title` replaces 14/15/18; `T.value` replaces 11.5/12/13.
- Drop the per-call `tracking(size * k)` maths. Each token carries its own tracking.
- Raising the 7 to 8.5 pt text to 10 pt costs room. F3 frees that room by deleting duplicate text.

**Effort** M. **Proof:** grep for `face(` in Faceplate, Pocket and HarmonyView should return only token names. **Ref** 1.

### F2. One colour, 17 alphas: amber can't carry the hierarchy alone  `[systemic]`
**What.** The amber alphas in use are 1.0, .85, .7, .6, .55, .45, .4, .35, .3, .28, .25, .2, .14, .12, .1, .09, .06 and .05. Measured contrast on the LCD (#0c0a06):

| amber α | 1.0 | .85 | .7 | .6 | .55 | .45 | .4 | .35 |
|---|---|---|---|---|---|---|---|---|
| contrast | 10.8 | 8.0 | 5.7 | 4.4 | 3.9 | **2.9** | **2.6** | **2.2** |

- Text at .45 or below includes the scale notes `C D Eb F G Ab Bb`, the `BPM 142` caption, `BORROWED`, `BAR`, the notes-heard letters outside the scale and the `PITCH THE BEAT…` hint when idle.
- The amber glow (`Text.cap`, two shadows) sits on 8 pt text as well as on the BPM. A 2 to 8 pt blur on 8 pt glyphs smears them.

**Why.**
- The praised plugin UIs spend colour on *meaning*, not decoration:
  - Pigments: "nice use of colour to differentiate between modulation sources" ([SOS](https://www.soundonsound.com/reviews/arturia-pigments))
  - Parallel Aggressor: "the interactive displays will expand and develop an orange hue" as the amount rises ([MusicTech via Plugin Boutique](https://www.pluginboutique.com/articles/1689-Baby-Audio-Parallel-Aggressor-Review-at-MusicTech))
  - Captain Melody: "good use of colour here to indicate how much tension each note brings" ([MusicTech](https://www.musictech.com/reviews/plug-ins/mixed-in-key-captain-plugins-3/))
- A monochrome VFD is a legitimate look (the brief pins it), but then it needs a few strict steps, not a gradient of near-duplicates.

**Fix.** Use five amber steps (call them `A1` to `A5`) and nothing else:

| Token | α | Contrast | Role |
|---|---|---|---|
| `A1` | 1.0 | 10.8 | the reading: BPM, key, selected chip fill, lit section, in-scale keys |
| `A2` | 0.75 | ~6.3 | labels and secondary values (section heads, top-3 #2/#3, chord names) |
| `A3` | 0.62 | ~4.6 | tertiary text, **the floor for any text** |
| `A4` | 0.16 | n/a | structure: rules, chip outlines, inactive wheel lines, unlit bars |
| `A5` | 0.06 | n/a | fills: chip and cell backgrounds, unlit key bodies |

- **Glow only on `A1` text at `T.title` size or larger, and on lit shapes.** Remove the shadow from `Text.cap` and from every label under 18 pt. The BPM, the dial key and the lit wheel section keep their halo, so the glow marks "this is the answer".
- Under High Contrast, keep the current mapping, re-expressed on the five steps (A2 and A3 become A1; A4 becomes 0.3).
- Use the existing neutral `textHi` (0.9) for **content the user owns**: filename, source name, link field. Amber means "Beat Key's reading", warm-white means "your stuff". That is one meaningful colour split, Pigments-style, without a new hue.

**Effort** S to M. **Proof:** no text alpha below 0.62; `Theme.amber(` is called only through A1 to A5. **Ref** 2.

### F3. The same fact shown three times; how-to hints that never go away  `[hierarchy]`
**What.** In the result state, "Cm 64%" appears in three places:
1. the dial (`Cm ▲ 64%`)
2. the lamp line (`▲ UNSURE · Cm 64 · Eb 18 · Gm 9`)
3. the top-3 row (`1 Cm 64%`, `2 Eb 18%`, `3 Gm 9%`)

The BPM appears twice (`BPM 142` caption and `141.98`). Advanced adds `5A` twice (badge and wheel centre) and `REL Eb` next to a wheel that already lights Eb. Instruction text is always on: `CLICK = HEAR · DRAG = MIDI`, `PITCH THE BEAT −3 TO FIT Am` / `PICK YOUR PROJECT'S KEY`, `WRONG? IT'S…` (being fixed), and `PASTE A LINK · OPEN OR DROP A BEAT` (idle).

**Why.**
- Valhalla is praised because "all of the controls were visible on the screen at once" ([Gear Forum](https://thegearforum.com/threads/what-are-your-favourite-plugin-uis.7816)). That works because there are few of them.
- soothe2 added features "without noticeably adding to the plug-in's complexity" ([SOS](https://www.soundonsound.com/reviews/oeksound-soothe-2)).
- FabFilter shows a value only on hover: "The moment you move the mouse cursor over a knob, a parameter value display will pop up" ([FabFilter help, knobs](https://www.fabfilter.com/help/pro-q/using/knobs)).
- Minimal Audio uses interactive tooltips instead of printed instructions ([rekkerd](https://rekkerd.org/review-current-2-synthesizer-sound-platform-by-minimal-audio/)).
- Production Expert's essay on plugin UIs: hide what you don't need, and make every visual cue mean something ([Production Expert](https://www.production-expert.com/production-expert-1/plugin-designs-why-we-love-some-and-hate-others)).

**Fix.**
- **Lamp line:** keep only the lamp word (`▲ UNSURE` / `● SURE`) at `T.caption`; drop `· Cm 64 · Eb 18 · Gm 9`. The top-3 row is the breakdown.
- **BPM caption:** drop the `142` echo; keep `BPM` and the tempo light. See F8 for the decimals.
- **Wheel centre:** keep `5A`; drop `CAMELOT` (the wheel itself says it). Drop the separate `5A` badge in advanced, or keep the badge and show the key in the centre. One of the two, not both.
- **`REL Eb`:** show it as a tooltip on the badge, or light the relative section at `A4`. No text.
- **How-to hints:** put them in `.help()` tooltips, plus one shared hint line at the bottom of the LCD (`T.caption`, `A3`) that shows the hovered control's hint and is otherwise empty. FabFilter's hover readout and Minimal Audio's tooltips both work this way. `PITCH THE BEAT −3 TO FIT Am` is a *result*, so it stays, but in mixed case (see F6).
- The space freed (about 2 lines in the LCD and 1 in harmony) pays for F1's larger type.

**Effort** S. **Proof:** each fact appears once per view; no imperative sentence is permanently on screen. **Ref** 3, 12.

### F4. No spacing grid, and two column grids that disagree  `[systemic]`
**What.**
- Spacing values in use: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 16, 18, 20 and 22. Paddings mix 10 / 13 / 14 / 16.
- The module is padded 14 / 16 / 16 / 16 (top differs). Rows are spaced 14, then a 30 pt clipboard slot, then 10, 10, then 14 on each side of the rule.
- **Two column grids:** the cap column on the right of the fields starts at x = 380 pt. The third send cap starts at x = 361 pt, and the second send cap ends at 350 pt while the fields end at 368 pt. The eye catches a 19 pt jog right where the module ends.
- In advanced, the harmony LCD runs about 75 pt past its last row (empty amber-black under the transpose strip). Meanwhile the wheel and the notes-heard block are squeezed to 200 pt.

**Why.**
- Every finished tool UI in the reference set uses a 4/8 grid and shared column lines.
- Neural DSP is praised for a "clear left to right concept for signal flow" ([Gear Forum](https://thegearforum.com/threads/what-are-your-favourite-plugin-uis.7816)). The same thread faults UA's Studer UI for "wasting screen space".
- Captain Chords keeps one column structure across both chord rows ([SOS](https://www.soundonsound.com/reviews/mixed-key-captain-plug-ins)).

**Fix.**
- **Spacing tokens:** `S.xs 4 · S.s 8 · S.m 12 · S.l 16 · S.xl 24 · S.xxl 32`, plus 20 only for LCD inner padding. Every `spacing:` and `padding` uses a token.
  - Map 3 → 4, 5/6/7 → 8, 9/10 → 8 or 12, 13/14 → 12 or 16, 18/20/22 → 16 or 24.
- **Module rhythm:** padding 16 on all four sides. **8** between rows of one group (link / audio / source / new-song). **16** between groups (LCD → inputs, inputs → rule → sends).
- **One column grid** for the 464 pt module content:
  - field column 324 pt, gap 12, cap column 128 pt
  - send row: `[156][156][128]` with 12 pt gaps, so EXPORT MIDI sits exactly in the cap column (x = 380) and its edges line up with DOWNLOAD / FIND / LISTEN / HOLD above
  - put `capWidth` in one place and derive the send widths as `(content − capWidth − 2·gap) / 2`
- **Harmony panel:** make the panel's height fit its content, or give the spare ~75 pt back to the content: wheel side 200 → 224, chord cell height 42 → 48, and 24 pt section gaps instead of 14. Its bottom then lines up with the left module's bottom.
- **Rail:** 58 → 44 pt high and wordmark 24 → 18 pt (tracking 0.18em). Brand stays, and 14 pt goes back to the readout. Soundtoys and FabFilter keep the product name small in a corner (general knowledge).

**Effort** M. **Proof:** overlay an 8 pt grid on the 2x render; every edge sits on 4 pt and every right edge in the module lands on one of three x positions. **Ref** 6, 8, 11.

### F5. Four depth levels, three rings on every cap  `[systemic]`
**What.** Going inward:
1. **Plate:** 4 rings plus a drop shadow
2. **Module panel:** `modulePanel()`, 7 pt radius, ring, drop shadow, inner light
3. **Wells:** LCD bezel, fields; inner shadow, ring, lip
4. **Caps:** `SSLCapStyle`, 3 stacked rings (0x0a0a0b / 0x17181a / black) plus glow or drop

Because every element has a black ring and a 1 px highlight, nothing reads as more raised than anything else. The module panel also draws a box inside the plate that does nothing (render callout 7).

**Why.**
- Skeuomorphism pays when it is faithful and sparing. LANDR warns the hardware look "can imply a hardware match where none exists" (search snippet). The Gear Forum thread calls UA's tape graphics "wasting screen space".
- Goodhertz is the counter-example: "You won't find any knobs in any of our plug-ins"; "Simple look and feel encourages you to judge solely with your ears" ([SOS](https://www.soundonsound.com/reviews/goodhertz-plug-ins)).
- Beat Key should keep the faceplate (it's the brand) but limit it to three depth levels.

**Fix.**
- **Depth budget = 3:** chassis (raised) → wells (recessed: LCD, fields, source) → caps (raised).
- Remove `modulePanel()`'s fill, ring and shadow. Keep at most a 1 px `ModuleRule`-style engraved line between the two advanced halves.
- **Caps:** one 1 pt ring `#0a0a0b` plus a 0/2/3 black 0.6 drop. Remove the 3 pt and 4 pt rings. Corner radius 2.5 → 3.
- **Radius family:** plate 12, wells 6, caps and chips 3, LCD 6. Drop 0.8, 1.5, 2, 2.5, 4 and 7.

**Effort** S. **Proof:** count distinct ring/shadow recipes; there should be 3. **Ref** 7.

### F6. Everything is bold uppercase tracked, so content and labels look the same  `[systemic]`
**What.**
- The filename is drawn as a label: `BEAT A.WAV · BEATS`, uppercased and tracked, in the same style as `▲ UNSURE`. That throws away the file's real case and makes "your file" look like "a status".
- Full sentences are set in tracked caps: `PASTE A LINK · OPEN OR DROP A BEAT`, `NO KEY YET · PASTE, OPEN OR LISTEN`, `PITCH THE BEAT −3 TO FIT Am`. The last one also mixes lowercase `m` into a caps line.

**Why.**
- Uppercase is for 1 to 3 word labels with +5 to 10% tracking. Sentences read worse in caps (typography skill; Bringhurst).
- Pro-Q, Auto-Tune Pro and Ableton set labels in caps or small sizes and values in mixed case (general knowledge).
- Captain Chords and Scaler show chord names mixed-case on the cells, which is also the musical convention ([SOS Scaler 3](https://www.soundonsound.com/reviews/scaler-music-scaler-3)).

**Fix.** One casing rule:
- **UPPER + tracking** only for control legends and section heads of 1 to 3 words (`T.label` / `T.caption`).
- **Mixed case** for content and sentences:
  - filename `Beat A.wav` in `T.value`, `textHi`; folder `· Beats` in `textLo`
  - source name
  - key and chord names
  - hints as sentences: "Paste a link, open or drop a beat"; "Pitch the beat −3 to fit Am"
- Tracking per token as in F1. Never apply tracking to mixed case.

**Effort** S. **Proof:** no `.uppercased()` on user content; no tracked string longer than 3 words. **Ref** 4.

### F7. Disabled caps fade the whole cap, so they look broken, not off  `[components]`
**What.** `SSLCapStyle` applies `.opacity(0.45)` to the whole compositing group when the cap is not lit or ready. The cream cap turns grey-brown over the plate: DOWNLOAD and FIND KEY/BPM in the render look like a different, dirty component next to the cream send caps. The legend contrast drops to 2.6:1.

**Why.**
- On hardware (SSL, Teenage Engineering), an unavailable button is the same physical object with its legend or LED off. It doesn't go translucent (general knowledge).
- Reviewers read dim labels as "inactive and broken" ([SOS on Arcade](https://www.soundonsound.com/reviews/output-arcade)).
- HIG: "Always include a press state for a custom button" ([HIG Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)).

**Fix.**
- **Three states:**
  - **ready:** cream cap, legend `#3a372f`
  - **unavailable:** same cream cap at full opacity, legend at `#4a463c` α 0.45, no shine, cap gradient 10% darker (`#d8d5ca → #a9a698`)
  - **lit:** amber, as now
- Add hover: brightness +0.04. Keep press: −0.08 and 1 pt down.
- The cap still beeps when clicked while unavailable (current behaviour). Add `.help("Paste a YouTube link first")` so hover explains why.

**Effort** S. **Proof:** the cap's luminance is the same in ready and unavailable states; only the legend changes. **Ref** 5.

### F8. The BPM hero: decimals as loud as the integer  `[readout]`
**What.** `141.98` is set at 68 pt, every digit the same size, with a full glow, beside a `BPM 142` caption. The `.98` pulls as much weight as `141`.

**Why.**
- CDJ displays and many DAW tempo fields subordinate the decimal (general knowledge).
- Mixed In Key's pitch is "Key, BPM" first (its homepage: "Instantly see the Key, BPM, and notes", [mixedinkey.com](https://mixedinkey.com)). A producer types the integer into the DAW.

**Fix.**
- Integer at `T.hero` (68, `A1`, glow).
- `.98` at 34 pt (`T.key`, same weight, `A2`, no glow), baseline-aligned via `HStack(alignment: .firstTextBaseline, spacing: 0)`.
- Keep `.monospacedDigit()` so the integer doesn't shift between readings.
- Drop the `142` caption (F3).
- *Question for J:* should the hero be the rounded `142`, with `141.98` as the 34 pt secondary? This audit leans toward integer plus small decimals, which keeps both without the duplicate.

**Effort** S. **Ref** 3.

### F9. Four homemade segmented controls, each chip a separate box  `[components]`
**What.**
- Sets of separate boxes with 3 pt gaps: `TRIAD 7TH 9TH`, `ROOT 1ST 2ND OPEN`, `1 2 4 BAR`, the `×0.5 ×1 ×2` tempo chips, and the `−6…+6` transpose strip (13 boxes).
- Heights are 15, 18 and 20 pt; text is 7.5 to 8.5 pt; tracking varies.
- Selected = amber fill, but `0` in transpose has its own outline state as well.

**Why.**
- A segmented control is *one* object with internal dividers. That's how Pro-Q's bottom bar, Ableton and macOS's own `Picker(.segmented)` read (general knowledge for Ableton; HIG for macOS).
- Separate boxes with gaps read as 13 unrelated buttons.

**Fix.** Write one `SegmentedChips` view and use it for all five sets:
- **Shape:** height 20, radius 3, outer stroke 1 pt `A4`, internal 1 pt `A4` dividers, no gaps
- **Unselected:** text `T.caption` in `A2` on `A5` fill
- **Selected:** fill `A1`, text `#1a1204`, no glow
- **Hover:** fill `A1` α 0.12
- **Transpose:** one strip; mark `0` with a 2 pt `A3` tick under it, not a second outline style
- **Layout:** 12 pt between groups; group label (`BAR`) as `T.caption` `A3`, 8 pt from its group

**Effort** M. **Ref** 9.

### F10. Chord grid: 7 columns over 4, and dashed borders that read as placeholders  `[harmony]`
**What.** The diatonic row is 7 equal cells. The borrowed row is 4 wider cells starting after a 60 pt `BORROWED` label, so no column lines up. Borrowed cells use dashed strokes, which usually mean "empty / drop here". Long names step down from 11.5 to 9.5 pt.

**Why.**
- Captain Chords: "seven basic triad chords in the top row, plus a selection of harmonic variations in the bottom row" ([SOS](https://www.soundonsound.com/reviews/mixed-key-captain-plug-ins)). One grid, two rows.
- Scaler 3 is praised because the "arrangement and colour coding of the chord display provides a helpful steer" ([SOS](https://www.soundonsound.com/reviews/scaler-music-scaler-3)).

**Fix.**
- Use a **7-column grid for both rows.**
- Put each borrowed chord **under the degree it replaces**: `I` under `i`, `IV` under `iv`, `V` under `v`, `♭II` under `ii°`. Leave the other columns empty. The relationship then shows in the layout.
- Move the `BORROWED` label to the row's left gutter at `T.caption` `A3`, or to the section head (`CHORDS · C MINOR   BORROWED ▾`).
- **Cells:** height 48, gap 4, radius 3. Diatonic: fill `A5`, stroke `A4`. Borrowed: **solid** stroke `A4`, no fill, name in `A2`, with a 4 pt `A3` dot top-right as the "borrowed" mark. Selected or playing: `A1` stroke + glow.
- **Text:** name `T.value` 13 with `.minimumScaleFactor(0.85)` (no 9.5 pt step); roman `T.caption` `A3`.

**Effort** M. **Ref** 10.

### F11. Empty states show a skeleton of missing data  `[states]`
**What.** The idle LCD shows blocky `---.-` dashes, three `1 -- / 2 -- / 3 --` placeholders, an empty keyboard, a lone `SCALE` label and a small tracked-caps instruction. In advanced idle, the transpose strip and chord chips are fully drawn with nothing to act on.

**Why.**
- A skeleton only helps when it matches the coming content and the wait is short. Here, idle is the *start* state, not a load.
- Comeback Kid and Parallel Aggressor centre the UI on one display that is always meaningful ([MusicTech via Plugin Boutique](https://www.pluginboutique.com/articles/1623-Baby-Audio-Comeback-Kid-Review-at-MusicTech)).

**Fix.**
- **Idle LCD:**
  - one centred invitation in `T.title` mixed case `A2`: "Drop a beat"
  - a `T.caption` line in `A3`: "or paste a YouTube link · Listen"
  - the keyboard as `A4` outlines
- **Hide** the top-3 row and the `SCALE` label until a result exists. Keep the LCD height fixed so the window doesn't jump.
- **Advanced idle:** chips stay, as dimmed controls at α 0.5 of their normal state. The transpose strip shows "Pick your project key" in place of the 13 chips until a key exists.

**Effort** S. **Ref** (idle render).

### F12. Motion and hover feedback: decide one moment, add hover everywhere  `[interaction]`
**What.** The key wheel now has eased light and hover/press (0.1.41). Caps have press only. Chips, chord cells, footer links and the dial have no hover. A new result swaps in instantly.

**Why.**
- FabFilter knobs "light up when you move the mouse cursor around to indicate that you can adjust them" ([FabFilter help](https://www.fabfilter.com/help/pro-q/using/knobs)).
- Pigments is praised for "real-time animated feedback" ([Arturia](https://www.arturia.com/products/analog-classics/pigments/overview)).
- Minimal Audio: "excellent use of colour and animation" ([rekkerd](https://rekkerd.org/review-current-2-synthesizer-sound-platform-by-minimal-audio/)).

**Fix.**
- **Hover** on every interactive element: +0.04 brightness on caps; `A1` α 0.12 fill on chips and cells; `A3 → A2` on text links. Use `.onHover` + `.animation(.easeOut(duration: 0.12))`.
- **One authored moment:** when a reading lands, the readout fades in over 180 ms with a 2 pt rise, the dial's confidence arc draws from 0 to its value over 320 ms ease-out, and the wheel section lights (already done). The BPM digits never animate.
- Respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`: skip the draw and keep the fade.

**Effort** S to M.

### F13. Mac citizenship: small gaps  `[platform]`
- Tooltips: macOS shows `.help()` after a hover ([HIG Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)). Every cap, chip and the dial should have one. This is also where F3's hints go.
- HIG Layout: "Avoid placing controls or critical information at the bottom of a window" ([HIG Layout](https://developer.apple.com/design/human-interface-guidelines/layout)). RECENT / SETTINGS at the bottom is fine for secondary links. Keep SEND / EXPORT above them, as now.
- Check (not verified here) that every cap has a menu item with a shortcut, and that Settings is ⌘, in the app menu.

**Effort** S.

---

## 3. Praised UIs: what reviewers said and the move behind it

Quotes come from pages fetched on 2026-11-09 by the research agents; "(snippet)" means search-result text only.

| # | Product | Reviewer, own words | Design move | For Beat Key |
|---|---|---|---|---|
| 1 | Arturia Pigments | "The interface is clean and well designed with nice use of colour to differentiate between modulation sources." [SOS](https://www.soundonsound.com/reviews/arturia-pigments); "a masterpiece of UI and UX design" [MusicTech](https://musictech.com/reviews/software-instruments/arturia-pigments-3-review/) | one colour per source; rings drawn round modulated knobs; drag from any control | colour = meaning (F2: amber = reading, warm-white = your stuff) |
| 2 | Minimal Audio Current 2 | "continuity throughout the synth, largely through the excellent use of colour and animation" [rekkerd](https://rekkerd.org/review-current-2-synthesizer-sound-platform-by-minimal-audio/) | one shared header, sidebar and centre display across pages; interactive tooltips | one frame for default and advanced; hints as tooltips (F3) |
| 3 | Minimal Audio Rift | "its clever dual-format GUI makes the powerful processing accessible to novice and experienced sound designers alike." [SOS](https://www.soundonsound.com/reviews/minimal-audio-rift) | simple Play view over a full Advanced view | Beat Key's default/advanced split is the right idea; keep default lean |
| 4 | Baby Audio Comeback Kid | "the size and responsiveness of each parameter makes for quite a refreshing and immersive experience" [Mixdown](https://mixdownmag.com.au/reviews/plugins-and-software/reviewed-baby-audio-comeback-kid-delay/) | controls ringed round one central analogue-style display; two skins, two sizes | the LCD is the centre; controls serve it |
| 5 | Baby Audio Parallel Aggressor | "Easily understandable GUI…"; "the interactive displays will expand and develop an orange hue." [MusicTech via PB](https://www.pluginboutique.com/articles/1689-Baby-Audio-Parallel-Aggressor-Review-at-MusicTech) | the display *is* the control; amber intensity tracks the amount | amber α should encode confidence/energy, not decoration (F2) |
| 6 | Cableguys ShaperBox 3 | "a slick, modern GUI…"; "a very intuitive and visual process" [SOS](https://www.soundonsound.com/reviews/cableguys-shaperbox-3) | one drawn curve per module; drag to reorder | direct manipulation: click a chord to hear it, drag it out for MIDI (already there; teach by hover) |
| 7 | FabFilter Pro-Q 3/4 | "its graphical interface makes it a joy to use."; "widely imitated since its debut in 2011" [SOS](https://www.soundonsound.com/reviews/fabfilter-pro-q-3) | graph = control; value pops up on hover; resizable | hover readouts (F3, F12) |
| 8 | Goodhertz | "Simple look and feel encourages you to judge solely with your ears." [SOS](https://www.soundonsound.com/reviews/goodhertz-plug-ins) | no knobs, no skeuomorphism | the counterweight: limit the faceplate to 3 depth levels (F5) |
| 9 | oeksound soothe2 | "highly intutitive [sic] once you see and hear Soothe working"; features added "without noticeably adding to the plug-in's complexity" [SOS](https://www.soundonsound.com/reviews/oeksound-soothe-2) | three core controls; the graph is the surface | cut duplicates before adding (F3) |
| 10 | Vital | "everything is neatly arranged, color-coded, and easy to navigate." [pluginoise](https://pluginoise.com/vital-synth-review/) (blog) | live visual of the sound; tabs by function | the notes-heard bars are Beat Key's "live visual"; give them room (F4) |
| 11 | Kilohearts Phase Plant | "You click on a parameter and every possible destination… is then indicated." [MusicTech](https://www.musictech.com/reviews/software-instruments/kilohearts-phase-plant/) | selection highlights valid targets | hovering a chord could light its notes on the keyboard and its section on the wheel |
| 12 | Mixed In Key Captain Chords | "seven basic triad chords in the top row, plus a selection of harmonic variations in the bottom row." [SOS](https://www.soundonsound.com/reviews/mixed-key-captain-plug-ins); Captain Melody: "good use of colour here to indicate how much tension each note brings" [MusicTech](https://www.musictech.com/reviews/plug-ins/mixed-in-key-captain-plugins-3/) | one chord grid, two rows; colour by function | 7-column grid with borrowed under its degree (F10) |
| 13 | Scaler 3 | "arrangement and colour coding of the chord display provides a helpful steer." [SOS](https://www.soundonsound.com/reviews/scaler-music-scaler-3) | chords grouped and colour-coded; interactive circle of fifths | the wheel + chord strip pairing is the right instinct; link them on hover |
| 14 | Valhalla (Vintage Verb) | "all of the controls were visible on the screen at once" [Gear Forum](https://thegearforum.com/threads/what-are-your-favourite-plugin-uis.7816) | one screen, few controls, flat | one screen is fine *if* nothing repeats |
| 15 | Neural DSP (forum) | "clear left to right concept for signal flow" [Gear Forum](https://thegearforum.com/threads/what-are-your-favourite-plugin-uis.7816) | layout follows the workflow | Beat Key flows top-down: reading → inputs → send. Keep it, and align it (F4) |
| 16 | Output Arcade (warning) | "some of the buttons had grey rather than black text" [SOS](https://www.soundonsound.com/reviews/output-arcade) | n/a (criticism) | dim legends read as broken (F7) |

**Patterns across them**
1. The visual is the control.
2. Colour carries meaning.
3. Few controls, nothing repeated.
4. One consistent frame, with hover hints.
5. Legible labels. Grey-on-dark small text is the most-cited fault.

**Other references (general knowledge, not fetched this session)**
- Teenage Engineering OP-1 / EP-133: a tiny fixed palette in which each colour has one job; a segment display; no decoration.
- Soundtoys: white-on-black legends, one hero control per plugin. A Sonic Scoop snippet calls the bundle "a very simple white on black design with clearly labeled controls".
- UA hardware emulations: faithful faceplates; reviewers note they waste screen space.
- Ableton Live: flat, 4 pt grid, one typeface, colour reserved for meaning (its manual: purple "signifies scale awareness across Live", [Ableton manual](https://www.ableton.com/en/manual/live-concepts/)).
- Things 3 and Raycast: restraint, one accent, tight spacing scale.
- Antares Auto-Key shows the detected key's notes "on a keyboard at the bottom of the window" and has a "Send to Auto-Tune" button ([SOS](https://www.soundonsound.com/reviews/antares-auto-tune-pro)). That is Beat Key's model; the keyboard should be a first-class element.
- **Orra Key:** no public product page was found by web search, so it is compared only through the repo's `orra-parity` renders.

---

## 4. Scores (Nielsen, 0–4)

| # | Heuristic | Score | Key issue |
|---|---|---|---|
| 1 | Visibility of system status | 3 | READY lamp, LIVE, tempo light are good; no transition when a result lands |
| 2 | Match with the real world | 4 | faceplate, keyboard, Camelot wheel, roman numerals: all producer-native |
| 3 | User control and freedom | 3 | HOLD and reset exist; MANUAL key override being added |
| 4 | Consistency and standards | 1 | 20 sizes, 17 alphas, 4 segmented recipes, 2 column grids |
| 5 | Error prevention | 3 | unlit caps beep; no hover explanation of *why* |
| 6 | Recognition over recall | 3 | everything visible; hints permanent rather than contextual |
| 7 | Flexibility and efficiency | 2 | fixed window, no resize/scale; shortcuts not verified |
| 8 | Aesthetic and minimalist design | 2 | strong concept, diluted by duplicates and decoration on every level |
| 9 | Error recovery | 3 | error readout exists; not audited in depth |
| 10 | Help and documentation | 2 | instructions printed in the UI instead of tooltips/help |
| | **Total** | **26/40** | Good: a solid product with a consistency debt |

---

## 5. Doing the in-flight fixes well

- **MANUAL dropdown** (replaces WRONG? IT'S…):
  - use the F9 chip recipe at 20 pt high
  - label `MANUAL` at `T.caption` `A2`, plus SF Symbol `chevron.down` at 8 pt weight `.bold`, 4 pt after the text
  - when a manual key is active, the chip fills `A1`, and the dial shows a small `M` badge so the reading is never mistaken for detection
- **Taller keyboard** (now 44 pt):
  - 64 pt
  - black keys at 60% height, bottom corners 2 pt
  - letters only on in-scale keys (`T.caption`), root marked by `A1` fill + dot
  - out-of-scale whites at `A5`, in-scale at `A1` α 0.55, root at `A1`
- **Smaller big buttons, bigger text:**
  - caps 36 → **28 pt** (`H.md`), legend `T.label` 11 pt
  - keep 36 pt (`H.lg`) only for the field row (fields and their caps share a height)
  - control height family: `H.lg 36` fields and field caps · `H.md 28` send/action caps · `H.sm 20` chips and dropdowns · `H.xs 16` inline pills. Nothing else.
- **PASTE + DOWNLOAD / DOWNLOAD:** keep the cap width fixed (128) so the label switch doesn't move the column. `PASTE + DOWNLOAD` at 11 pt with 0.08em tracking is about 112 pt wide, which fits 128 with 8 pt padding. Check the measured width in the render.
- **Reset icon next to HOLD:**
  - 28 × 28 cap, SF Symbol `arrow.counterclockwise` 11 pt bold
  - `.help("New song: clear the reading")`
  - same cap recipe and unavailable state as F7
  - 8 pt gap to HOLD, with HOLD + reset together exactly the cap column width (128 = 92 + 8 + 28)

---

## 6. Top 5 to do next

1. **Type tokens (F1 + F6):** 6 roles (68/34/18/13/11/10), nothing under 10 pt, Medium for captions, caps only for ≤3-word labels; content in mixed case. M.
2. **Amber ramp (F2):** five steps A1–A5, text never under 0.62 (4.6:1), glow only on the reading. S–M.
3. **Cut duplicates, hints to hover (F3):** one "Cm 64%", no `142` echo, no `CAMELOT`/`REL`, `.help()` + one hover hint line. This pays for #1's bigger type. S.
4. **One grid (F4 + F9):** 4/8 spacing tokens, module rhythm 8/16, send row `[156][156][128]` aligned to the cap column, one `SegmentedChips`, control heights 36/28/20/16. M.
5. **Depth budget (F5 + F7):** remove the module panel bevel, single cap ring, radii 12/6/3, unavailable caps dim the legend instead of the whole cap. S.

Suggested order: tokens into `Theme.swift` first (T, A, S, H, radius). Then sweep LCD, PocketView and HarmonyView one file at a time, re-rendering `HarmonyTests/testRender` after each.
