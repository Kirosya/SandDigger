# Sound, feedback and the saved profile

Phase 4 gives the beach a voice and makes progress survive a restart. Both systems are
deliberately small: no third-party assets, no new network messages, and a single save
file per machine.

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
- the 7 bag slots, item ids/names/kinds/values included.

The beach itself is regenerated every launch; only progress is persisted.

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

## Tests

```
godot --headless --path . res://tests/sfx_test.tscn       # streams, tier->sound, puffs, buttons, surf
godot --headless --path . res://tests/profile_test.tscn   # round trip, damaged files, derived values, bag
```

Sound output cannot be heard headless, so the assertions check which stream was handed
to which player and which node was spawned. The actual mix still has to be judged by ear.
