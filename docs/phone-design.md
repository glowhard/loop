# Loop phone — CEO home and voice design

Designer spec for the phone/web app (`app/lib`). Colours are `C.*` from `app/lib/theme.dart` (dark only). Items marked **[OPT]** can ship later. All numbers (timers, tokens, %) use `FontFeature.tabularFigures()`.

## 0. Principles (they settle the edge cases)

- Every screen answers "does anything need me?" in under a second. When nothing does, the screen is calm and mostly empty.
- Voice first, but one tap always works too. The mic never sends a goal without one confirming tap (goals cost tokens).
- Only three colours carry meaning on Home: `C.busy` (amber) = needs you, `C.accent` = plan / primary action, `C.idle` (green) = done. Everything else is `C.text2` / `C.text3`.
- Primary button always on the right (thumb side).

## 1. Navigation — 3 tabs

`[Home] [Projects] [More]`

- **Home** = CEO home, the screen the app opens to. The Inbox tab merges into it: Home's feed *is* the inbox. The waiting badge moves to the Home icon (count = Need from you + Plan OK? only, never Done).
- **Recent** merges into Projects as its first section, "Recent" (5 rows max, then "See all"); projects below as today.
- **More** unchanged.
- Chats, terminals, board, team, notes, tasks: one tap deeper, from Projects or from a card's header.
- Tab bar: height 62, indicator transparent, selected icon `C.accent`, label 11.

## 2. CEO home at 390×844

16 dp side gutters throughout. Below the safe area:

### A. Top bar — h56, bg `C.chrome`, no title text

- **Left: project chip** — h32, radius 16, bg `C.raised`, padding 12 h. Project name 14 w600 `C.text` + `Icons.unfold_more` 16 `C.text3`. Tap → bottom sheet of projects: row h56, name 15 w600, then "2 need you" 12 `C.busy` or "All quiet" 12 `C.text3`, check on the current one. The chip picks which project the two doors belong to.
- **Right: usage ring** — 32 dp `CircularProgressIndicator`, strokeWidth 3, track `C.raised`, value = weekly %, colour `C.text2` → `C.busy` at ≥80 % → `C.danger` at ≥95 %. Number inside 10 w700. Tap → existing Usage sheet. The only usage element on Home.

### B. Front doors — two cards in a row, 12 dp below the top bar

Each card: width (390−32−12)/2 = **173**, height **148**, radius 18, bg `C.panel`, border 1 `C.line`, padding 14.

Top to bottom:
1. Row: 8 dp lamp (idle green / busy amber pulsing / `C.off` when not running) · 8 · **"CEO"** 17 w700 `C.text` · spacer · `Icons.chat_bubble_outline` 18 `C.text3` in a 40 dp hit box → opens the lead's chat.
2. 2 dp, subtitle "Business" (CTO: "Tech") 12 `C.text3`.
3. 10 dp, state line 13/1.35 `C.text2`, max 2 lines:
   - idle: "Ready"
   - planning: "Planning…" (shimmer)
   - working: "Working · 4m" (shimmer)
   - waiting on you: "Waiting for you" `C.busy` w600
   - not running: "Asleep — tap to wake" `C.text3`
4. Bottom-aligned **mic button**, full card width, h44, radius 22, bg `C.accent`, `Icons.mic` 20 + "Give a goal" 14 w600 `C.accentInk`. While the lead works: label "Add to goal", bg `C.raised2`, text `C.text` (still works; the message queues to the lead).

- Tap anywhere on the card except the chat icon = mic button. Long-press = open chat.
- Lead not running: the mic still works; the app wakes it first, the sheet shows "Waking CEO…", then listens.

### C. Feed — 24 dp below the doors

- Header row h28: "Needs you" 13 w600 `C.text2` + count chip (h20, radius 10, bg `C.busy` at 20 % alpha, 11 w700 `C.busy`). Hidden at zero.
- Cards 12 dp apart, **all projects** (each card names its project, so nothing hides behind the chip).
- Sort: Need from you → Plan OK? → Done; newest first within each.
- After the live cards: collapsed row h44 "Earlier today · 5" 13 `C.text3` + chevron; expands to the answered/expired one-liners.
- **Empty state:** 48 dp top padding, centred: `Icons.check_circle_outline` 28 `C.text3`, "Nothing needs you" 15 w600 `C.text2`, "Speak a goal to the CEO or CTO" 13 `C.text3`. Nothing else.

### D. Working bar

Above the tab bar, h34, bg `C.panel`, top border `C.line`, only while any session is busy: pulsing dot + "CTO working · 6m" 12.5 w500 `C.text2`. Tap → that chat.

## 3. The three cards

**Shared shell:** bg `C.panel`, radius 16, border 1 `C.line`, padding 16, 3 dp left stripe in the card colour (clip so the stripe follows the radius). Enters with 160 ms fade + 6 dp rise; state changes animate with `AnimatedSize` 200 ms.

**Header row (every card):** type tag 11 w700 letterSpacing 0.8 in the card colour · "Acme · CTO" 12 `C.text3` · spacer · "4m" 12 `C.text3`. Tap the header → that lead's chat, scrolled to this message.

**Buttons:** h48, radius 12, 8 dp apart.
- Primary: bg `C.accent`, text `C.accentInk` 15 w600.
- Secondary: bg `C.raised`, border 1 `C.line`, text `C.text` 15 w500.
- A secondary that means "speak a change" has `Icons.mic` 18 before the label.

### (a) Plan OK? — colour `C.accent`, tag "PLAN"

- Title: the goal, 16 w600 `C.text`, max 2 lines.
- 10 dp, the 3 bullets: 4 dp dot `C.text3` (top offset 8) · 10 · text 14/1.45 `C.text`; 6 dp between bullets.
- 14 dp, buttons 50/50: **[🎤 Change] [OK, go ahead]**.
- **OK** → sends "OK, go ahead." to the lead, `HapticFeedback.lightImpact`, card collapses to answered.
- **Change** → mic sheet titled "Change the plan"; after confirm sends "Change the plan: <transcript>".
- States:
  - *new* — as above.
  - *answered* — one line: `Icons.check` 16 `C.idle` + "Plan OK'd · <goal>" 13 `C.text2`, ellipsis; moves to Earlier after 3 s.
  - *expired* (a newer plan arrived, or the lead moved on/closed) — "Plan replaced" 13 `C.text3`, no buttons, straight to Earlier.

### (b) Need from you — colour `C.busy`, tag "NEEDS YOU"

Covers both AskUserQuestion cards and the must-ask permission gate (Yes/No).

- Question 16 w600 `C.text`, max 3 lines. Optional context line 13 `C.text2` (file name, amount, who gets messaged).
- Options as vertical full-width buttons, 8 dp apart, each with a leading number 13 at 60 % opacity. Option 1 is primary if it is the recommended one (AskUserQuestion puts "(Recommended)" first — strip the word from the label and use it as the signal); otherwise all secondary. For the must-ask gate: **Yes** primary, **No** secondary.
- Last button always secondary: **"🎤 Say something else"** → mic sheet, sends the transcript as the free-text answer (for the gate: as "No, and …").
- multiSelect: options become toggle rows (check icon right, selected bg `C.raised2`) plus a primary "Done", disabled until one is chosen. Restyle of `QuestionCard`, same logic.
- **Hold to confirm** for must-ask actions (go live, spend money, message customers, new access/keys, delete): the option that performs the action gets " · hold" 13 `C.text3` after its label. Press and hold 700 ms; a fill sweeps left→right (`C.accent` at 35 % over `C.raised`); `HapticFeedback.mediumImpact` on completion. A plain tap shows "Hold to confirm" under it for 1.5 s. All must-ask gate cards use this on Yes; for other questions use a data flag if there is one, else a keyword match (live, deploy, production, pay, spend, customers, delete, key, access).
- States:
  - *answered* — `Icons.check` 16 `C.idle` + "You said: Yes, deploy" 13 `C.text2`.
  - *expired* (question no longer current in that session) — "No longer needed" 13 `C.text3`.
  - Before sending any tap, check the question id is still current; if not, flip to expired and snackbar "That question already moved on". A stale tap must never reach the session.

### (c) Done — colour `C.idle`, tag "DONE"

- Title: the goal, 16 w600 `C.text`, max 2 lines.
- 10 dp, **listen row** h44: 44 dp circle bg `C.raised`, `Icons.play_arrow` 24 `C.accent` (playing: `Icons.pause`) · 12 · "Listen" 14 w500 `C.text` + " · 0:24" 13 `C.text3` (estimate = words ÷ 2.6 per second). Playing: label becomes "0:07 / 0:24" and a 2 dp `LinearProgressIndicator` (`C.accent` on `C.raised`) sits under the row.
- 10 dp, the bullets (max 5), same style as Plan.
  - **[OPT]** while reading aloud, the bullet being read is `C.text` and the rest `C.text2` (flutter_tts progress handler gives the offset).
- If the report has "Need from you: …": `Icons.arrow_forward` 16 `C.busy` + text 14 w600 `C.busy`.
- 12 dp, **tokens line**: "31.4k tokens · 12 min · 3 sessions" 12 `C.text3`. The headline number is **fresh** tokens. Format: <1000 raw, <1 M one-decimal k, else one-decimal M. Tap the line → it expands in place to "Fresh 31.4k · Cached 210k · 46 calls" (tap again to fold). **[OPT]** append " · 3 % of weekly".
- 14 dp, buttons 50/50:
  - work has something to ship: **[🎤 Change] [Go live]** — Go live is a hold button, sends "Go live."
  - otherwise: **[🎤 Change] [Looks good]** — archives the card to Earlier, sends nothing.
- States:
  - *new* — 8 dp unread dot `C.idle` before the tag until the card has been on screen 1 s.
  - *after Go live* — buttons replaced by a "Going live…" shimmer line; the deploy's own Done card follows.
  - *archived* — "✓ <goal>" 13 `C.text2` in Earlier.

## 4. Mic

Uses `Voice.I` (`lib/voice.dart`).

**Placement**
- Chat composer: the right-hand round button is **mic when the field is empty, send when it has text**. 40 dp; mic = bg `C.raised2` icon `C.text`, send = bg `C.accent` icon `C.accentInk`. Stop moves out of the composer into the working pill as a trailing chip "Stop" (h28, radius 14, bg `C.raised2`, 12 w600).
- Home "Give a goal", Plan/Done "Change", Need-from-you "Say something else": all open the same mic sheet.

**Mic sheet** — modal bottom sheet, bg `C.panel`, top radius 20, ~300 tall.
- Header: title 15 w600 `C.text` ("Goal for CEO · Acme" / "Change the plan" / the question's header) · spacer · language chip h28, radius 14, bg `C.raised`, "EN" / "हिं" / "ਪੰ" 12 w700; tap cycles, last choice remembered. Hide languages the phone lacks.
- **Listening starts as soon as the sheet opens** — one tap total to start speaking.
- Middle: live transcript 18/1.4; partial words `C.text2`, final words `C.text`; placeholder "Listening…" `C.text3`; scrolls when long.
- Under it: 5 level bars (4 dp wide, 4 dp gap, heights 6–28 from the sound level, `C.accent`) + timer 13 `C.text3`.
- Bottom row: ✕ 48 dp circle `C.raised` (cancel) · centred 72 dp circle `C.accent` with `Icons.stop` 32 `C.accentInk` · 48 dp spacer to balance.
- Auto-stop after 3 s of silence; hard limit 2 min.

**Review state** (always, after stop):
- Transcript becomes an editable `TextField` 17/1.4; the keyboard does **not** open by itself.
- Buttons 50/50 h48: **[🎤 Redo] [Send]**. Send → message goes, sheet closes, light haptic, the door flips to "Planning…".
- **[OPT]** More → Voice → "Send without review", off by default.

**Errors** — shown in the transcript area of the same sheet, no dialogs:

| Case | Message | Actions |
|---|---|---|
| Mic permission denied | `Icons.mic_off` 24 `C.danger`, "Loop needs the microphone" 15 w600 | [Open settings] · "Type instead" |
| Nothing heard | "Didn't catch that" 15 w600 `C.text2` | [Try again] |
| Language not on phone | "Punjabi isn't installed on this phone" | [Use English] |
| Speech unavailable / offline | "Voice isn't available right now" | [Type instead] |

"Type instead" closes the sheet and focuses the composer (on Home: opens the lead's chat with the composer focused). Web build without speech support: hide the mic and always show send.

## 5. Read-aloud

- **Where:** Done card listen row. In chat, the lead's final report gets the same listen row under it; any other assistant message: long-press → "Read aloud".
- **What's read:** goal title, bullets, the "Need from you" line. Never tokens, times or markdown symbols (`Voice.plain`).
- Language follows the text: Devanagari → hi-IN, Gurmukhi → pa-IN, else en-IN; fall back to English if the voice is missing.
- One player app-wide: starting one stops the other; leaving the screen stops it; duck other audio.
- **[OPT]** Done notification gets a "Listen" action that opens the card and starts playing.

## 6. Cut or hide to reduce reading

- **Lead chats (CEO/CTO):** collapse all tool activity in a turn into one row "Worked · 23 steps · 4m" (expandable). Lead chats should read as plan → report.
- **List rows:** drop session ids, model names, paths and the account chip. Show the machine name only when there is more than one machine.
- **Home:** no board, team, notes, tasks, usage text or session lists — only the doors and the cards.
- **Notifications:** heads-up only for Need from you and Plan OK?; Done = normal priority, grouped; nothing else notifies.
- Chat header ⋮ stays as is (Model / Effort / Usage / Context / Terminal); nothing new surfaces.
- Usage sheet: reachable from the ring and from More only.

## Build order

1. Nav merge + Home skeleton with the doors
2. The three cards (Need from you = restyled `QuestionCard` + the gate cards)
3. Mic sheet + composer mic/send swap
4. Listen row
5. Tokens line
6. Hold to confirm
7. The [OPT] items

Send screenshots once Home renders and the designer will do a review pass.
