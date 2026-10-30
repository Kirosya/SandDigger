# Sound, feedback, the saved profile and the saved beach

Phase 4 gives the beach a voice and makes progress survive a restart. Both systems are
deliberately small: no third-party assets, no new network messages, and a single save
file per machine (two once the beach itself is persisted).

## Sounds

Every sound effect is **synthesised by the project itself**, so there is no audio
licence to track and every sound can be re-tuned by editing numbers:

```
godot --headless --path . res://tools/gen_sfx.tscn
godot --headless --import --path .          # let Godot import the new .wav files
```

`tools/gen_sfx.gd` writes fourteen 16-bit mono WAVs (22050 Hz) into `assets/audio/`:

| id | when it plays |
| --- | --- |
| `dig_soft` / `dig_sand` / `dig_deep` / `dig_massive` | a shovelful, picked by the cut radius (0.15 / 0.30 / 0.45 / 0.70 m), so the tier is audible with no protocol change |
| `loot_reveal` | something uncovered (the ring version is louder and never pitch-shifted) |
| `pickup` | an item went into the bag |
| `coin` | sold an item at the junkyard |
| `levelup` | crossed an XP threshold |
| `upgrade` | bought the detector or a shovel tier |
| `denied` | a purchase or sale that cannot happen |
| `ui_click` / `ui_open` | menu and shop buttons |
| `step_sand` | footsteps, quicker while sprinting |
| `waves` | the looping surf (8 s, cross-faded so the loop has no click) |

The generator is the source of truth: change a duration, a filter cutoff or a pitch in
`tools/gen_sfx.gd`, run the two commands above, and listen again.

`scripts/sfx.gd` (autoload `Sfx`) plays them from pools — 12 `AudioStreamPlayer3D` for
the world and 5 `AudioStreamPlayer` for UI — so digging while sprinting never allocates
a player per sound. Buttons are wired to the click automatically when they enter the
tree, including shop rows and the lobby list built at runtime.

There is one master volume only (`Settings` in the menu). Separate SFX/ambience sliders
were intentionally skipped: one slider is enough for a build this size.

## Settings, in both menus

`scenes/settings_panel.tscn` + `scripts/settings_panel.gd` (`class_name SettingsPanel`) is
one scene used twice: by the main menu and by the pause overlay, so the two screens can
never drift apart. It holds the mouse sensitivity slider, the master volume slider and the
fullscreen checkbox, writes every change straight into the `GameSettings` autoload (so a
slider is heard while the beach is paused) and writes `user://settings.cfg` once, when the
panel closes — not on every pixel of a drag.

The panel is a plain `Control`: the owner decides what Esc means. In-game the pause menu
closes the panel first and only then unpauses, and `open()` / `close()` / the `closed`
signal keep the focus handling on the owner's side.

## Feedback

`scripts/fx.gd` (autoload `Fx`) spawns one short `SandPuff` (GPUParticles3D) per dig,
scaled by the cut radius, and plays the matching shovel sound.

Triggering is free of new RPCs. `SandTerrain.dug` and `LootManager.loot_revealed` already
reach every peer, so each machine simply reacts to them locally: a client hears the dig
when the host's carve comes back, and everyone hears a find at the same moment.

## The profile

One profile per machine, at `user://profile.cfg` (Windows:
`%APPDATA%\Godot\appdata\SandDigger\profile.cfg`), written with `ConfigFile` in a single
`[local]` section. It stores:

- lifetime XP and money,
- equipment tier index and whether the detector was bought,
- the 7 bag slots, item ids/names/kinds/values included,
- how many treasure chests this beachcomber has opened.

The beach itself is now saved as well, in a second file next to the profile
(`user://beach.save`, see the next section).

`scripts/main.gd` restores the profile into the player **this machine controls** (host or
client — every peer keeps its own `PlayerState`), and saves again on the events that
actually change something: sale, purchase, pickup, level up, detector purchase. Leaving
the beach or closing the game flushes once more. Digging never touches the disk.

Loading is defensive. A missing, unreadable or hand-edited file falls back to a fresh
profile instead of blocking the game, and derived values are **recomputed rather than
trusted**: the level comes from the XP total and the tier is clamped to the equipment
list, so editing the file cannot hand out a shovel that was never earned.

`Profile.path_override` lets the tests use a scratch file instead of the real profile.

One machine, one beachcomber. A per-Steam-account profile would only change the section
key (`steam_<id>`), not the format, whenever that becomes worth doing.

## The saved beach

A dug beach has to still be dug tomorrow, so the heightmap and the changed loot live in
`user://beach.save`. Only the machine that **owns the world** reads or writes it:

- single player and the host load and save it,
- a client never touches it — its beach arrives in the host's late-join snapshot, so a
  guest can never overwrite the host's island with a stale copy.

`scripts/beach_store.gd` holds the format. The 128×128 heightmap (64 KB raw) and a
`var_to_bytes` loot snapshot are both zstd-compressed behind a small header
(magic, version, vertex count, blob lengths). A beach dug all over still saves in well
under a kilobyte, so writing it is cheap enough to do without hitching:

| when | what |
| --- | --- |
| on start, before the first player spawns | restore the heightmap and re-derive what is uncovered |
| 20 s after the first dig or loot change | autosave, so a crash does not erase the session |
| on leaving the beach / quitting | final flush next to the profile flush |

Restoring is not just "load the heights": `LootManager.restore_world()` re-derives every
item's state from the new sand. Anything the sand has been dug past is revealed again
(silently — a reloaded beach must not replay a dozen "Uncovered!" announcements), surface
junk is set back onto the new surface, and the saved claims remove what was taken. Without
that a reloaded beach would keep its holes but hide every already-dug ring again.

Loading is as defensive as the profile. A wrong magic, an unknown version, a truncated or
random file, a decompression failure or a wrong vertex count all mean "no beach": the game
keeps the freshly generated one. Heights are clamped to the beach's real range (sea floor
to flat sand), so even a hand-edited save can only make holes, never spikes.

The loot snapshot is deliberately minimal - claimed ids, the tide-spawned items and the
unopened treasure chest if one is out. The
200-item scatter comes from a fixed seed on every peer, so it never needs saving; revealed
state is recomputed from the sand instead of trusted.

`Profile.world_path_override` points the tests at a scratch file, and `beach_test` drives
the real `main._save_world()` / `main._load_world()` path rather than re-implementing it.

## The endgame: treasure maps

The shovel chain ends at the Earth Shovel, and for a while that was the end of the
economy: money kept coming in with nothing left to buy. The market's fifth row fixes that
with a repeatable loop that gives the deepest dig a purpose.

| constant | value | meaning |
| --- | --- | --- |
| `PlayerState.TREASURE_TIER_REQUIRED` | 3 | the map is only sold once the Earth Shovel is owned |
| `PlayerState.TREASURE_MAP_PRICE` | $400 | the map, paid up front |
| `PlayerState.TREASURE_FIRST_PAYOUT` | $1500 | the first chest a profile ever opens |
| `PlayerState.TREASURE_PAYOUT_MIN/MAX` | $1000–$1400 | every chest after that |
| `LootManager.TREASURE_DEPTH` | 1.85 m | the chest's depth (`SandTerrain.MAX_DEPTH` is 2.0) |
| `LootManager.TREASURE_BEACON_RADIUS` | 3.6 m | the ring the map draws on the sand |

Buying a map has `LootManager.spawn_treasure()` bury a **Sunken Chest** in dry sand, clear
of the spawn and the stalls, at a random spot with a fixed payout for that hunt. The map
does not give the exact point: a slim gold beam marks the centre and a ring shows the area,
so the detector still has a job inside it. Only one map can be out at a time.

The chest is an ordinary `LootItem` with `is_treasure = true`, so it reuses everything the
trash already has: it is hidden by the sand above it, revealed by `dig_at` cutting past its
depth, claimed first-wins by the host, and it travels to late joiners and into the save file
(the snapshot gained a `treasure` key next to `claimed` and `sea`). Two things differ:

- a claim pays **straight into money** via `PlayerState.register_treasure_find()` instead
  of putting an item in the bag — a chest would fill half the bag on its own,
- the find count (`treasure_finds`) is persisted, so the first-find payout really is once
  per profile.

Feedback needs no new RPC either: `LootManager.treasure_opened` already reaches every peer,
the HUD turns it into a banner with the payout and the running chest count, everyone hears
the world sound, and the beacon is dropped on every machine by the claim itself.

An unopened chest survives a restart with its position, payout and light, because it is in
the `treasure` key of the loot snapshot and the saved heightmap decides whether it is
already uncovered. Once opened it is a claimed id, so it never comes back.

## Tests

```
godot --headless --path . res://tests/sfx_test.tscn       # streams, tier->sound, puffs, buttons, surf
godot --headless --path . res://tests/profile_test.tscn   # round trip, damaged files, derived values, bag
godot --headless --path . res://tests/beach_test.tscn     # save/restore a real dug beach, damaged files
godot --headless --path . res://tests/treasure_test.tscn  # map offer, deep chest, payout, saved chest
```

Sound output cannot be heard headless, so the assertions check which stream was handed
to which player and which node was spawned. The actual mix still has to be judged by ear.
