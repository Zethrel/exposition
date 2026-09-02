# Changelog

## 1.0.0

First release.

- Composer window (`/expo`) for writing a long post in one place.
- Splits text into 255-byte chat messages without ever cutting a word in half.
  Measures bytes rather than characters, the way the server does, so accented
  text and emoji are counted correctly and never split mid-character.
- Optional sentence-aware breaks, so a message ends on a full stop where one
  falls close enough to the limit. Abbreviations and initials are not mistaken
  for sentence ends.
- Live preview of exactly what will be sent, message by message, with the
  character count for each.
- Configurable delay between messages, defaulting to 15 seconds. Never sends
  faster than one message every 0.75s, and re-sends a message the server
  throttled rather than losing it.
- Six marker styles: none, `1/5`, `[1/5]`, `(1/5)`, `...` and raid target
  icons. Marker width is budgeted before splitting, so a marked message still
  fits.
- Ten destinations: say, emote, yell, party, raid, instance, guild, officer,
  whisper and numbered channels. The destination is checked before anything is
  sent, and a post to a missing whisper target aborts rather than continuing.
- Movable, resizable window; settings and an unsent draft persist across
  sessions.
- Confirmation prompt for posts longer than eight messages.
