# Exposition

A World of Warcraft addon for writing long roleplay posts in one window and
sending them to chat as clean, readable pieces.

Chat cuts you off at 255 characters. Doing that by hand leaves you counting
characters, and doing it naively leaves you with

```
Say: ...she turns to esc
Say: ape from here before the
```

Exposition never breaks a word. If a word does not fit, it leads the next
message instead.

**Interface version:** 120100

---

## Installing

Copy the repository into your addons folder so the path looks like:

```
World of Warcraft/_retail_/Interface/AddOns/Exposition/Exposition.toc
```

The folder name must be `Exposition`, matching the `.toc`. Then `/reload` or
restart the client.

## Using it

`/expo` (or `/exposition`, or the addon compartment button next to the minimap
clock) opens the composer.

1. Type or paste your post into the big box at the top.
2. The panel underneath shows exactly what will be sent, message by message,
   with the character count for each. It updates as you type.
3. Pick a channel, a marker style, and a delay.
4. **Send.** The first message goes out immediately; the rest follow on the
   timer. The status line counts down to the next one.

**Stop** cancels the remainder at any time. Messages already sent stay sent.

Posts longer than eight messages ask for confirmation first, so a stray paste
never turns into a wall of chat.

### Slash commands

| Command | Effect |
| --- | --- |
| `/expo` | Open or close the composer |
| `/expo stop` | Cancel a post that is still sending |
| `/expo delay <seconds>` | Set the gap between messages |
| `/expo marker <style>` | `none`, `count`, `bracket`, `paren`, `ellipsis`, `raid` |

## The delay

A full 255-character message is roughly 45 words. At a typical adult reading
speed of 238–250 words per minute that is about **12 seconds** of reading, and
longer for many readers, including dyslexic ones. The default is **15 seconds**,
which leaves a little room without dragging.

Exposition never sends faster than one message every 0.75 seconds regardless of
the setting: the server throttles rapid chat, and being disconnected halfway
through a post is worse than a slow post. If the server does throttle you,
Exposition pauses and re-sends the refused message rather than silently losing
it.

## Markers

| Style | Looks like | Costs |
| --- | --- | --- |
| None | `The tavern door swings...` | 0 characters |
| `1/5` | `1/5 The tavern door swings...` | ~4 |
| `[1/5]` | `[1/5] The tavern door swings...` | ~6 |
| `(1/5)` | `(1/5) The tavern door swings...` | ~6 |
| `...` | `The tavern door...` / `...swings open` | ~6 |
| `{rt1}` | Raid target icons | ~7 |

Markers are counted against the 255-character budget before the text is split,
so a message with a marker still fits.

> **On raid icons:** these are the same icons used for marking targets in
> combat, and many roleplayers read them as out-of-character chatter. They are
> offered because they are genuinely easy to scan, but they carry that baggage —
> plain numbering is the safer default. Only eight icons exist; past eight
> messages Exposition falls back to numbering automatically.

## How the splitting works

`Core/Splitter.lua` is a pure function with no WoW API in it, which is why it
can be tested outside the game.

- **Bytes, not characters.** Chat limits by bytes, so `é` costs two and an emoji
  costs four. Exposition measures the same way the server does.
- **Whole words.** It scans back from the last byte that fits to the previous
  space, and starts the next message from the word it could not fit.
- **Sentences where possible.** With *End on sentences* enabled, a message ends
  on a full stop if one falls within the last third of the budget, so pieces
  read as complete thoughts. `Dr.`, `Mr.`, initials and similar do not count.
- **Line breaks.** With *Keep line breaks* enabled, pressing Enter starts a new
  message. Chat cannot carry newlines, so the alternative is folding paragraphs
  into one continuous block.
- **Markers are budgeted up front.** The width of `12/25` depends on how many
  messages there are, which depends on the width of the marker, so the splitter
  iterates until the count settles.
- **Unbreakable words.** A single word longer than a whole message (a pasted URL,
  say) is cut, but never inside a UTF-8 character, and the counter warns you.

## Tests

```sh
./run-tests.sh
```

Needs `lua5.1`, the same interpreter the game ships (`apt install lua5.1`).

- `tests/run.lua` — the splitting engine: byte limits, word and UTF-8 integrity,
  marker budgeting, sentence handling, plus a fuzzer that asserts no split ever
  loses, reorders, or truncates a word.
- `tests/integration.lua` — loads the real addon files against a stubbed WoW
  client (`tests/wow_stub.lua`) and drives the window: typing, previewing,
  sending, throttling, stopping, saving settings.

The stub whitelists widget methods, so calling something that is not real WoW
API fails the test rather than silently doing nothing.

## Known limitations

- **Battle.net whispers are not supported.** They need a different API
  (`BNSendWhisper` with a presence ID); regular in-game whispers work.
- **No `Ctrl+Enter` to send.** WoW's multi-line edit boxes swallow Enter, so
  sending is the button.
- The window is intentionally built from long-lived widget templates rather than
  the options and dropdown APIs Blizzard has rewritten several times, so it
  should survive patches with less maintenance.

## Licence

Copyright (c) 2026 Zethrel. **All rights reserved.** See [LICENSE](LICENSE).

This repository is public so the code can be read and reviewed. It is not open
source. You are welcome to install and play with Exposition, and to read how it
works — but the code may not be copied into other projects, redistributed, or
republished in modified form without permission. Ask in an issue if you want to
do something the licence does not cover.

Exposition contains no third-party code: no Ace3, no LibStub, no embedded
libraries. Everything here is original, so there are no upstream licence terms
layered on top of the above.

## Layout

```
Exposition.toc          Addon manifest
Exposition.lua          Entry point: saved variables, slash commands
Core/Splitter.lua       The chunking engine (no WoW API, unit tested)
Core/Config.lua         Defaults, saved settings, channel and marker tables
Core/Sender.lua         The outgoing queue, timing, throttle handling
UI/MainFrame.lua        The composer window
tests/                  Test suites and the WoW client stub
```
