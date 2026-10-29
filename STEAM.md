# Steam multiplayer (development on Spacewar)

The game already had host-authoritative multiplayer over ENet (LAN/IP). Steam is a
second transport for the same session code: the host still owns the sand, the loot and
every player's progression, and clients still only send intents.

While SandDigger has no Steam page of its own, the build pretends to be **Spacewar**
(Valve's public test app, app id **480**). That means Steam P2P and lobbies are real,
but only people who also run this dev build can see each other's beaches.

## What you need

1. **Steam client running and signed in.** Without it `steamInitEx` returns
   `ConnectToGlobalUser failed` and both Steam buttons only show an explanation.
2. **The GodotSteam extension**, already in the repo at `addons/godotsteam/` (win64
   library + `steam_api64.dll`). Godot registers it the first time the project is
   imported, so open the editor once after cloning. Only Windows x86_64 binaries are
   committed; other platforms can copy the matching folder from the GodotSteam
   GDExtension release (`godotsteam-4.x-gdextension-plugin-4.4.zip`) into
   `addons/godotsteam/` and re-add those lines to `godotsteam.gdextension`.
3. `steam_appid.txt` next to the project (and next to the exported executable) with
   `480`. The app id is also passed explicitly in `scripts/network_manager.gd`.

The Steam code is looked up through `Engine.get_singleton("Steam")` and `ClassDB`, never
by the `Steam` identifier, so the project still boots and single player still works on
a machine without the extension.

## Playing

- **Steam Host** — creates a friends-only Steam lobby, publishes it with the lobby key
  `game=sanddigger` and hosts the beach in it. Open the Steam overlay (Shift+Tab) and
  invite a friend; the invite lands them straight in your lobby.
- **Steam Join** — lists the open SandDigger lobbies (host name, players/max) and joins
  the one you pick. It also accepts invites sent while the menu is open.
- **Host Game / Join Game** — unchanged ENet path, still the fastest way to test two
  windows on one PC.

## Testing status

- Verified live against a signed-in Steam client: extension load, `steamInitEx(480)`,
  lobby creation, lobby data (`name`, `game`, `players`), `host_with_lobby`, session
  start with transport `STEAM`, lobby browser finding the lobby, and teardown.
- **Not verified live:** a client actually joining, because both processes on this
  machine share one Steam account and Steam P2P cannot connect an account to itself.
  The join path (`joinLobby` -> `lobby_joined` -> `connect_to_lobby`) is exercised by
  code review and the ENet multiplayer test covers the shared session logic.

## Tests

```
godot --headless --path . res://tests/steam_test.tscn     # adaptive: works signed in or not
godot --headless --path . res://tests/menu_test.tscn      # includes the Steam buttons
```

`steam_test` passes in two modes: with no signed-in Steam every Steam entry point must
fail politely and ENet must still host; with Steam signed in it creates a real lobby,
checks the session/lobby id/peer list and that the browser finds the beach again.
