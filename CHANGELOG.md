# Campfire Dad Jokes changelog

## 1.3.7

- Choose where jokes go: **Tell in:** on the Campfire tab, or `/joke to`. Emote (the default), say, yell, party, raid, instance, guild, officer, a whisper (`/joke to w Name`) or a numbered channel (`/joke to 2`).
- Clicks and **Share addon link** use your choice. Auto-tell uses it for party, raid, instance, guild, officer and whispers, and your party or raid otherwise.
- If the chosen chat isn't available (no group, no guild, channel not joined), the click says why and the line waits. Auto-tell stops when its whisper target is offline.

## 1.3.6

- Auto-tell works again after the October 2026 client update, which only lets addons post emotes from a click. It now posts in group chat: party, raid or instance. Start it in a group; outside one, use Tell a joke.
- If the game ever blocks a line, auto-tell stops and says why instead of failing every few seconds.

## 1.3.5

- Updating the addon never resets your jokes. Saved jokes from older versions are upgraded, jokes saved by a newer version are kept, and only unreadable entries are dropped.

## 1.3.4

First CurseForge release.

- Tell a joke in two clicks: the first says a random setup, the second its punch line, as a speech-style emote ("Bo says: …").
- Auto-tell (`/joke auto`): jokes keep coming on their own until `/joke stop`. Set the pauses on the Campfire tab or with `/joke pace <before punch line> <between jokes>` (4 s and 3 s by default).
- 25 starter jokes, plus your own on the My jokes tab: add, edit, delete, and restore the starters.
- No repeats until every joke has been told.
- Compact view (`/joke mini`): just the buttons, movable anywhere, remembered across sessions.
- Share addon link says where to get the addon (this CurseForge page) in /say.
