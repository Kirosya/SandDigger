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
- equipment tier index and the detector tier (0 = none, 1-4 = the upgrades);
  older saves that only stored a has_detector flag load as tier 1,
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
keeps the freshly generated one. Heights are clamped to the beach's real range
(`-SandTerrain.MAX_DEPTH` to flat sand), so even a hand-edited save can only make holes,
never spikes.

The loot snapshot is deliberately minimal - claimed ids, the tide-spawned items and the
unopened treasure chest if one is out. The
200-item scatter comes from a fixed seed on every peer, so it never needs saving; revealed
state is recomputed from the sand instead of trusted.

`Profile.world_path_override` points the tests at a scratch file, and `beach_test` drives
the real `main._save_world()` / `main._load_world()` path rather than re-implementing it.

## Deep sand

The beach is `SandTerrain.MAX_DEPTH = 8.0` metres deep, and the sand behaves like
sand: a wall steeper than the angle of repose slides into the hole it was dug
from. `dig_at` carves the bowl, then runs `_settle_sand()` over the touched area
a few times before the mesh is rebuilt.

Deep sand also **packs harder**. `dig_power_at()` reads the height at the dig
point and returns `clampf(1 + h / HARDEN_DEPTH, HARDEN_MIN, 1)`, which `dig_at`
applies before carving: `radius *= power` and the bite is softened by half that
much again (`depth *= lerpf(1, power, 0.5)`). A shovel is at full strength on the
surface, about half strength at 4 m, and never below `HARDEN_MIN`. Because it is
computed from the heightmap, the host and every client scale the same scoop the
same way - `sand_test` replays a host dig on a second terrain and still gets a
byte-identical beach.

| constant | value | meaning |
| --- | --- | --- |
| `SAND_SLOPE_STEP` | 0.50 m per 0.5 m cell | a wall steeper than ~45 degrees collapses |
| `SLUMP_PASSES` | 3 | how far a collapse travels per scoop |
| `SLUMP_RELAX` | 0.50 | how much of the offending step moves per pass |
| `SEA_DIG_MARGIN` | 1.4 m | a dig in the surf cannot go this far below the sea bed |
| `MAX_DIG_DISTANCE` | 9.0 m | the host accepts a dig this far from the sender |
| `HARDEN_DEPTH` | 8.0 m | depth over which a shovel fades to its weakest bite |
| `HARDEN_MIN` | 0.40 | the weakest a shovel ever gets (40 % of its surface power) |

Three properties make this safe rather than chaotic:

- **Volume is conserved.** Settling only moves sand between grid points, from a
  higher point to its lowest neighbour, so the beach never gains sand and a hole
  that fills in really did take the sand from its own walls.
- **It is deterministic.** Same heights, same scoop, same loop -> byte-identical
  result. `apply_dig` on a client replays exactly the host's call, so both
  beaches collapse the same way (`sand_test` asserts a difference of exactly 0).
- **XP follows net loss.** The XP awarded is the volume actually gone after the
  walls have fallen in (measured over the grown dirty rect), not the volume the
  scoop removed on paper.

The practical effect is the point of the whole rework: a 15 cm teaspoon hole in
one spot stops at about -1 m no matter how long you dig, because the rim keeps
sliding in. Going deeper means widening the excavation - and paying for it, since
the scoop itself shrinks with depth. A Trench Spade needs about 190 scoops to
stand a 4.6 m pit; the Dune Excavator reaches the 8 m floor in roughly 260. That
is the slow, deliberate digging loop the game was missing.

Shovels also gained a `reach`: 3.6 m at the teaspoon up to 7.4 m at the Dune
Excavator, because a deep pit is worked from its rim. `floor_max_angle` on the
player is 55 degrees so the ~45 degree crater walls stay walkable and nobody gets
stuck at the bottom of their own hole; the out-of-world respawn limit moved to
`FALL_LIMIT = -8.5` so standing at the bottom of a legal pit is not a "fell off
the beach".

## The shovel and detector chains

Seven shovels, four detectors. Each shovel is a wider bowl, a deeper bite and a
longer reach; each detector is a shorter recharge and a wider sweep.

| tier | shovel | level | price | radius | bite | reach |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | Teaspoon | 1 | - | 0.15 | 0.05 | 3.6 |
| 1 | Sand Shovel | 3 | $50 | 0.30 | 0.10 | 4.2 |
| 2 | Garden Shovel | 6 | $180 | 0.45 | 0.15 | 4.8 |
| 3 | Earth Shovel | 10 | $500 | 0.70 | 0.22 | 5.5 |
| 4 | Trench Spade | 14 | $1100 | 0.90 | 0.30 | 6.2 |
| 5 | Auger Shovel | 18 | $2400 | 1.15 | 0.42 | 6.8 |
| 6 | Dune Excavator | 24 | $4500 | 1.45 | 0.58 | 7.4 |

| detector tier | name | level | price | recharge | range |
| --- | --- | --- | --- | --- | --- |
| 0 | none | - | - | - | - |
| 1 | Metal Detector | 1 | $35 | 15 s | 8 m |
| 2 | Ground Scanner | 4 | $200 | 11 s | 10 m |
| 3 | Pulse Inductor | 10 | $600 | 8 s | 11 m |
| 4 | Deep Sounder | 16 | $1400 | 6 s | 12 m |

`PlayerState.has_detector` is now a derived getter (`detector_tier >= 1`), and
`detector_changed` carries the tier so the HUD and the profile both refresh on an
upgrade. The market sells exactly one detector row: it always shows the *next*
tier, so the panel stays eight rows (detector, six shovels, treasure map) no
matter how long the chains get.

## What is in the sand

Loot depth is what makes the beach a dig instead of a pickup walk. Only ~8 % of
the scatter lies in plain sight; everything else has a depth band:

| kind | share of buried | depth | value |
| --- | --- | --- | --- |
| trash | ~88 % | 0.30-1.20 m | $18-40 |
| antique | 3 % | 3.50-5.00 m | $400-700 |
| gold ring | exactly 1 per beach | 5.20 m | $1500 |

The antiques (Antique Amphora, Carved Idol, Bronze Lantern, Ancient Coin Hoard)
are the reason to sink a real hole: they are metal, so the detector hears them,
and they pay more than every junk item in the bag. They get their own banner and
the `upgrade` chime on reveal.

### The one gold ring

There is exactly one gold ring on the whole beach, and it is the last story
quest's target. The scatter still *rolls* a ring slot the way it always did (so
the other 200 items keep their points, ids and depths, and a beach saved by an
older build still lines up with its claims), but `LootManager._crown_gold_ring()`
then keeps the **deepest** rolled ring, moves it down to `RING_DEPTH` (5.20 m) and
makes it worth `RING_VALUE` ($1500). Every other rolled ring is turned back into
ordinary junk with its own deterministic RNG (`seed 20261030`), so the main
scatter stream is untouched and the beach can never hand out a second ring.
`LootManager.gold_ring()` returns that item until somebody digs it up.

5.20 m is deeper than any antique and only the later shovels keep a hole open
that far, so the ring is a real endgame dig, not a lucky scoop.


An item that the collapsing walls bury again goes back to "not revealed" and its
label is removed (`LootManager.REBURY_MARGIN`), so a hole that fills in really
does swallow what you had just uncovered.

Reach is measured to where the item **is**, not to the spot on the beach it was
buried at: `LootItem.world_position()` returns the item node's real position, so
standing at the bottom of a 4.6 m pit next to the chest is a 1 m reach, not a
4.6 m one. This is what used to leave deep junk and every chest with an `[E]` on
their label that pressing E did nothing about. The floating label itself no
longer says `[E]`; it just names the find and its value, and the HUD owns the
`[E] Take ...` prompt because only the HUD knows the real distance.

## Tide junk

The sea washes junk ashore while the tide comes in. It is deliberately
self-limiting: the more pieces are already lying on the beach, the longer the sea
waits before delivering the next one, and there is a hard ceiling so the shore can
never silt up completely.

| constant | value | meaning |
| --- | --- | --- |
| `SEA_SPAWN_INTERVAL` | 4 s | wait between deliveries on a clean beach |
| `SEA_LITTER_PENALTY` | 0.8 | each piece already ashore multiplies that wait |
| `SEA_MAX_TOTAL` | 18 | most tide junk allowed to lie on the beach at once |
| `SEA_MAX_FLOATING` | 4 | most pieces bobbing in the surf at once |

Clearing the beach is therefore rewarded twice: the junk is worth money, and the
sea immediately goes back to washing in a piece every few seconds. Left alone,
18 pieces is as dirty as the shore gets.

When the tide turns, junk still in the surf is **not** carried back out with the
wave: it stops travelling inland, rides the falling water down and is swallowed
by the wet sand where the wave left it, ending half buried but still visible and
pickable (`SEA_SINK_SPEED` 0.45 m/s, `SEA_SETTLE_DEPTH` 0.1 m). While the surf is
coming in it never sinks under the beach it is crossing - once the sand rises
above the water it is dragged along the wet surface instead.

## Sea rendering

The sea floor plane (`Sea.Seabed`) only exists past the edge of the sand mesh
(`Sea.SEABED_EDGE_Z = -31`, the heightmap ends at -31.75). It used to run all the
way to `z = 0`, three metres under the flat beach, so any pit dug at the shore
deeper than -3.2 m exposed it as a flat grey-blue slab with a perfectly straight
edge - the "dark blue area inside the beach". It is now only what it was meant to
be: the floor under the open water that keeps the transparent surface from fading
into the sky at the horizon.

There is no mask any more: the water inside the sand is a real shallow-water
simulation on the same 128x128 grid as the heightmap. Each half-metre cell holds
one number, `Sea._depth`, its water depth, and every 1/20 s (`WATER_STEP`) water
runs downhill from one cell into its lower neighbours. Volume is conserved except
at the sea, which is an endless source and sink at the tide height, and in the
sand, which drinks.

* `SandTerrain.height_texture` is a live `FORMAT_RF` copy of the 128x128 heightmap
  (`SandTerrain.revision` bumps on every dig). The sea binds it plus the world
  rectangle it covers, so the shader knows how high the sand is under every bit of
  water. `Sea._depth` is uploaded next to it as `water_depth` every frame.
* `Sea._flow_step` moves water from a cell to each lower neighbour: it compares
  water **surfaces** (`height + depth`), sends `FLOW_SHARE` (45%) of the head over,
  capped at `FLOW_SPEED` (6 m/s), and re-reads its own surface after every move.
  That last detail matters - with a stale surface the sheet sloshes back and forth
  forever and a cut-off pool keeps a permanent tilt instead of levelling.
* A cell that is undug (`absf(h - base) < 0.02`) and below the tide is the open
  sea: it is not simulated, and any simulated cell touching it is `_feed`-marked
  and topped up straight from the tide. That is how a pit fills over its rim,
  through a breach, or from the far end of a trench - the water really does
  arrive from where it can, and the surface climbs from the bottom.
* When the tide drops below the rim the feed stops: the pool is on its own, and
  what is up on a ledge runs down to the lowest point it can reach (a 12 m crater
  levels to within a few centimetres in about 10 s).
* The sand then soaks the pool away. Every wet cell loses `SEEP_MIN + depth *
  SEEP_RATE` per second (0.004 m/s film, 5%/s proportional), which empties a
  knee-deep puddle in seconds and a 7 m crater in about a minute. Fed cells are
  topped back up, so the shore does not drain while the tide is in.
* Only live cells cost anything: `_seed_dug_area` adds the dirty rectangle of a
  dig plus a margin and flow activates cells as it reaches them, so a step is
  linear in the wet cells (about 2.5 ms for 500 cells), not in the grid.
* The surface is drawn by one mesh that follows the sand grid: each vertex is
  raised by the vertex shader to its cell's water surface, and the fragment
  discards cells that are dry, so the sheet follows the sand instead of a flat
  plane. The open sea beyond the sand is a separate plane
  (`Sea.OpenWater`, `use_water_map = false`).
* Foam and the deep colour follow the **water depth** (`foam_depth` 0.30 m,
  `deep_depth` 2.0 m) instead of the distance from the waterline, so they look
  right on the open shore and on the rim of a flooded pit alike.
* The tide range is deliberately wide (`TIDE_LOW` -2.30, `TIDE_HIGH` -0.10 m).
  The shore slope is shallow, so the waterline walks about 13 m up and down the
  beach over one 60 s cycle: the sea visibly pulls out, and a shallow pit drains
  with it instead of sitting full forever.

The surface is double sided (`cull_disabled`) and the fragment shader flips
`NORMAL` on the back face, so looking up from inside the water shows a bright,
nearly opaque lid instead of the sky through a paper-thin sheet. While the camera
is under the water (`Sea.is_flooded_at` on the camera, i.e. below the tide *and*
inside a flooded cell) the sea fades in a blue-green screen veil
(`Sea.UNDERWATER_COLOR`, layer 5, under the HUD) and swaps the scene fog for the
water murk (`UNDERWATER_FOG_DENSITY` 0.11). The veil ramps in over the first
0.8 m of depth (`Sea._update_veil`), so wading with your eyes just under the
surface only tints the screen while the bottom of a flooded pit goes fully
under. Standing at the bottom of a flooded pit therefore looks like water, not
like dry sand under a blue lid.

## The endgame: treasure maps

The chest is now buried at `LootManager.TREASURE_DEPTH = 4.6 m`, near the bottom
of the sand, and **the map gives no hint at all**: no beam, no ring, no distance
readout. The HUD only says that a chest is buried somewhere on the beach. Finding
it is the detector's real job plus a genuinely wide, deep excavation.

| constant | value | meaning |
| --- | --- | --- |
| `PlayerState.TREASURE_TIER_REQUIRED` | 4 | the map is only sold once the Trench Spade is owned |
| `PlayerState.TREASURE_MAP_PRICE` | $500 | the map, paid up front |
| `PlayerState.TREASURE_FIRST_PAYOUT` | $2500 | the first chest a profile ever opens |
| `PlayerState.TREASURE_PAYOUT_MIN/MAX` | $1500-$2200 | every chest after that |
| `LootManager.TREASURE_DEPTH` | 4.6 m | the chest's depth (`MAX_DEPTH` is 8.0) |

Buying a map has `LootManager.spawn_treasure()` bury a **Sunken Chest** in dry sand,
clear of the spawn and the stalls, at a random spot with a fixed payout for that
hunt. Only one map can be out at a time. There is no marker of any kind: the old
`_spawn_beacon()` / `_beacon` / `TREASURE_BEACON_RADIUS` code is gone, and the
snapshot/claim paths no longer touch a beacon.

The chest is an ordinary `LootItem` with `is_treasure = true`, so it reuses
everything the trash already has: it is hidden by the sand above it, revealed by
`dig_at` cutting past its depth, claimed first-wins by the host, and it travels to
late joiners and into the save file (the snapshot has a `treasure` key next to
`claimed` and `sea`). One thing differs: a claim pays **straight into money** via
`PlayerState.register_treasure_find()` instead of putting an item in the bag, and
the find count is persisted so the first-find payout really is once per profile.

Feedback needs no new RPC: `LootManager.treasure_opened` already reaches every peer
and the HUD turns it into a banner with the payout and the running chest count.

An unopened chest survives a restart with its position and payout, because it is in
the `treasure` key of the loot snapshot and the saved heightmap decides whether it
is already uncovered. Once opened it is a claimed id, so it never comes back.

## The story quests

The beach has a five-quest chain that doubles as a second income next to selling
junk. It is designed to walk the same path as the tool chain: plain junk first,
then the metal finds the detector is for, then the deep antique band, and finally
the one gold ring.

| # | quest | asks for | pays |
| --- | --- | --- | --- |
| 1 | First Haul | 3 pieces of junk | $80 + 150 XP |
| 2 | Detector Practice | 2 metal finds (Rusty Can, Scrap Metal, Tin Lid) | $160 + 300 XP |
| 3 | The Deep Band | 1 antique | $450 + 800 XP |
| 4 | Keeper of the Deep | 3 antiques | $900 + 1500 XP |
| 5 | The Golden Ring | the one gold ring | $2500 + 5000 XP |

Together that is $4090 and 7750 XP, which is what pays for the later shovels
without grinding junk for hours.

`scripts/quests.gd` owns the definitions (`Quests.QUESTS`) and listens to
`LootManager.loot_claimed`, the same broadcast every peer already gets. A find
only counts if the payload's `owner` is this machine's player id, so in
multiplayer each player progresses through their own chain even when somebody
else digs the same item up first. The HUD shows the open quest and its counter in
the top-left corner, and completing one plays the `upgrade` chime, the gold
banner and a `+$X +Y XP` line.

Progress lives in `PlayerState` (`quest_index`, `quest_progress`,
`gold_ring_found`) and is written to the profile on every change, so a half
finished "2 of 3 antiques" survives a quit. Because there is only one ring in the
world, a player can dig it up before quest 5 opens; `gold_ring_found` remembers
that and the last quest settles itself as soon as the chain reaches it (and it
never pays twice).

## Tests

```
godot --headless --path . res://tests/sand_test.tscn      # collapse, depth hardness, volume, determinism, XP
godot --headless --path . res://tests/sfx_test.tscn       # streams, tier->sound, puffs, buttons, surf
godot --headless --path . res://tests/profile_test.tscn   # round trip, damaged files, derived values, bag
godot --headless --path . res://tests/beach_test.tscn     # save/restore a real dug beach, damaged files
godot --headless --path . res://tests/treasure_test.tscn  # map offer, deep chest, payout, saved chest
godot --headless --path . res://tests/sea_test.tscn       # beach profile, tide, seabed clip, surf junk, ebb sink, pit flooding from its rim, and a cut-off pool levelling and soaking away
godot --headless --path . res://tests/quest_test.tscn     # one gold ring deep down, quest chain, payouts, early ring, profile round trip
godot --path . res://tests/sea_shot.tscn                  # visual: low tide, high tide, a pit while it fills and full, from under water, and cut off by the ebb
godot --path . res://tests/quest_shot.tscn                # visual: the quest line and a quest completion banner
```

Sound output cannot be heard headless, so the assertions check which stream was handed
to which player and which node was spawned. The actual mix still has to be judged by ear.

