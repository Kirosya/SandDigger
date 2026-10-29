extends Node
## Session manager for the 1-4 player beach.
##
## The host owns the world: the sand heightmap, the loot and every player's
## progression. Clients only send intents (dig, take loot, sell) and apply what
## the host broadcasts. This autoload is the one place that knows whether the
## game is running offline (single player), hosting or joined to a host, and
## which transport is carrying the packets:
##
##   ENET  - direct IP, used on LAN and during development
##   STEAM - SteamNetworkingSockets through GodotSteam, with Steam lobbies
##
## Both transports expose the same MultiplayerPeer contract, so nothing outside
## this file cares which one is in use. The peer id doubles as the player id:
## the host is always 1 on both transports, clients get the ids the peer assigns.
##
## GodotSteam is optional at runtime: the extension is looked up through the
## singleton table and ClassDB, never referenced by name, so the project still
## boots (and single player still works) on a machine without it installed.

signal session_started(hosting: bool)
signal join_failed(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal disconnected(reason: String)
## Steam lobby search finished; each entry is {id, name, players, max, host}.
signal steam_lobbies_listed(lobbies: Array)
## Something in the Steam path failed (lobby creation, join, no client...).
signal steam_failed(reason: String)
## A friend invited us to their lobby through the Steam overlay.
signal steam_invite(lobby_id: int)

enum Transport { OFFLINE, ENET, STEAM }

const DEFAULT_PORT := 8910
const MAX_PLAYERS := 4
const DEFAULT_ADDRESS := "127.0.0.1"

## Valve's public test app ("Spacewar"). Used until SandDigger has its own app
## id on Steam; replace it here and in steam_appid.txt when that happens.
const STEAM_APP_ID := 480
## Steamworks lobby enums (stable ABI values, kept local so the script compiles
## without the extension).
const STEAM_LOBBY_FRIENDS := 1
const STEAM_LOBBY_PUBLIC := 2
const STEAM_LOBBY_COMPARISON_EQUAL := 0
const STEAM_RESULT_OK := 1
const STEAM_LOBBY_JOIN_OK := 1
## Every SandDigger lobby carries this key so the browser only lists our game.
const STEAM_LOBBY_GAME_KEY := "game"
const STEAM_LOBBY_GAME_VALUE := "sanddigger"

## Spawn slots, one per player id, on the open beach in front of the stalls.
const SPAWN_POINTS := [
	Vector3(0.0, 0.3, 6.0),
	Vector3(-2.6, 0.3, 7.6),
	Vector3(2.6, 0.3, 7.6),
	Vector3(0.0, 0.3, 9.8),
]

var hosting := false
var active := false
## Our own peer id (1 when hosting or offline, 0 until the connection is up).
var local_id := 1
## Every peer in the session, host included.
var peers: Array[int] = []
## Clients that have finished loading the beach and can receive world RPCs.
## The host never sends player streams to a peer that is still on the menu.
var ready_peers: Array[int] = []
## Which transport is (or was last) carrying the session.
var transport := Transport.OFFLINE
## The Steam lobby we host or sit in (0 when not using Steam).
var lobby_id := 0
## Human readable Steam state for the menu ("Signed in as ...", errors, ...).
var steam_status := "Steam has not been started yet."

var _wired := false
var _steam: Object = null
var _steam_wired := false
var _steam_ready := false
var _steam_init_tried := false
var _steam_pending_host := false
var _steam_pending_lobby := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	# Lobby and networking callbacks only arrive while the Steam API is pumped.
	# GodotSteam names these in snake_case (run_callbacks / runNetworkingCallbacks);
	# older builds used runCallbacks, so probe instead of hardcoding one spelling.
	if not _steam_ready or _steam == null:
		return
	if _steam.has_method("run_callbacks"):
		_steam.call("run_callbacks")
	elif _steam.has_method("runCallbacks"):
		_steam.call("runCallbacks")


## --- Shared session state ------------------------------------------------

## True offline or on the host; false on a joined client.
func is_host() -> bool:
	return not active or hosting


func is_online() -> bool:
	return active


func is_steam() -> bool:
	return transport == Transport.STEAM


## --- ENet (LAN / development) --------------------------------------------

func host_game(port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	transport = Transport.ENET
	hosting = true
	active = true
	local_id = 1
	peers = [1]
	_wire()
	session_started.emit(true)
	return OK


func join_game(address: String = DEFAULT_ADDRESS, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	transport = Transport.ENET
	hosting = false
	active = true
	local_id = 0
	_wire()
	return OK


## --- Steam ---------------------------------------------------------------

## True when this build can talk to Steam at all (extension present).
func steam_supported() -> bool:
	return Engine.has_singleton("Steam") and ClassDB.class_exists("SteamMultiplayerPeer")


## Starts the Steam API once. Returns true when we are signed in and can use
## lobbies and P2P; steam_status explains what went wrong when it is false.
func steam_init() -> bool:
	if _steam_ready:
		return true
	if not steam_supported():
		steam_status = "GodotSteam is not installed in this build."
		return false
	if _steam == null:
		_steam = Engine.get_singleton("Steam")
		_wire_steam()
	if _steam_init_tried:
		# A second steamInitEx would fail; keep the first verdict.
		return _steam_ready
	_steam_init_tried = true
	var result = _steam.call("steamInitEx", STEAM_APP_ID, false)
	var status := 0
	var verbal := ""
	if result is Dictionary:
		status = int(result.get("status", 0))
		verbal = str(result.get("verbal", ""))
	else:
		status = int(result)
	if status != 0:
		_steam_ready = false
		steam_status = verbal if verbal != "" else "Steam returned error %d." % status
		print("[steam] init failed: %s" % steam_status)
		return false
	_steam_ready = true
	steam_status = "Signed in as %s" % str(_steam.call("getPersonaName"))
	print("[steam] %s (app %d, lobby %s)" % [
		steam_status, STEAM_APP_ID, str(ClassDB.class_exists("SteamMultiplayerPeer"))])
	return true


func steam_name() -> String:
	if not _steam_ready or _steam == null:
		return ""
	return str(_steam.call("getPersonaName"))


func steam_id() -> int:
	if not _steam_ready or _steam == null:
		return 0
	return int(_steam.call("getSteamID"))


## Creates a Steam lobby and hosts the beach in it. Asynchronous: the session
## starts from the lobby_created callback, so listen to session_started.
func host_steam(public_lobby: bool = false) -> Error:
	if not steam_init():
		return ERR_UNAVAILABLE
	leave()
	_steam_pending_host = true
	steam_status = "Creating a Steam lobby..."
	var kind := STEAM_LOBBY_PUBLIC if public_lobby else STEAM_LOBBY_FRIENDS
	var result = _steam.call("createLobby", kind, MAX_PLAYERS)
	if result is Dictionary and not bool(result.get("success", true)):
		_steam_pending_host = false
		steam_status = "Steam refused to create a lobby."
		return ERR_CANT_CREATE
	return OK


## Joins a Steam lobby by id (from the browser, an invite or a friend's id).
func join_steam_lobby(id: int) -> Error:
	if id == 0:
		return ERR_INVALID_PARAMETER
	if not steam_init():
		return ERR_UNAVAILABLE
	leave()
	_steam_pending_lobby = id
	steam_status = "Joining the lobby..."
	var result = _steam.call("joinLobby", id)
	if result is Dictionary and not bool(result.get("success", true)):
		_steam_pending_lobby = 0
		steam_status = "Steam refused to join that lobby."
		return ERR_CANT_CREATE
	return OK


## Connects straight to a host's Steam id, skipping lobbies (used by tests and
## by "join by id" if the lobby list is empty).
func join_steam_friend(id: int) -> Error:
	if id == 0:
		return ERR_INVALID_PARAMETER
	if not steam_init():
		return ERR_UNAVAILABLE
	leave()
	var peer := _make_steam_peer()
	if peer == null:
		return ERR_CANT_CREATE
	var err: int = peer.call("create_client", id, 0)
	if err != OK:
		steam_status = "Steam could not reach that player (%s)." % error_string(err)
		return err
	_activate_steam_peer(peer)
	hosting = false
	active = true
	local_id = 0
	return OK


## Asks Steam for the public SandDigger lobbies; the answer arrives on
## steam_lobbies_listed.
func request_steam_lobbies() -> void:
	if not steam_init():
		steam_failed.emit(steam_status)
		return
	_steam.call("addRequestLobbyListStringFilter",
		STEAM_LOBBY_GAME_KEY, STEAM_LOBBY_GAME_VALUE, STEAM_LOBBY_COMPARISON_EQUAL)
	_steam.call("addRequestLobbyListResultCountFilter", 30)
	_steam.call("requestLobbyList")


## Opens the Steam overlay's invite dialog for the current lobby.
func invite_friends() -> void:
	if not _steam_ready or _steam == null or lobby_id == 0:
		return
	if _steam.has_method("activateGameOverlayInviteDialog"):
		_steam.call("activateGameOverlayInviteDialog", lobby_id)


func steam_shutdown() -> void:
	if _steam_ready and _steam != null and _steam.has_method("steamShutdown"):
		_steam.call("steamShutdown")
	_steam_ready = false


func _wire_steam() -> void:
	if _steam_wired or _steam == null:
		return
	_steam_wired = true
	_steam.connect("lobby_created", _on_steam_lobby_created)
	_steam.connect("lobby_joined", _on_steam_lobby_joined)
	_steam.connect("lobby_match_list", _on_steam_lobby_match_list)
	_steam.connect("lobby_invite", _on_steam_lobby_invite)


func _make_steam_peer() -> MultiplayerPeer:
	var peer := ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	if peer == null:
		steam_status = "SteamMultiplayerPeer could not be created."
		steam_failed.emit(steam_status)
		return null
	# Clients talk to the host only; the host relays between them.
	peer.set("server_relay", true)
	return peer


func _activate_steam_peer(peer: MultiplayerPeer) -> void:
	multiplayer.multiplayer_peer = peer
	transport = Transport.STEAM
	_wire()


func _on_steam_lobby_created(connect: int, new_lobby: int) -> void:
	if not _steam_pending_host:
		return
	_steam_pending_host = false
	if connect != STEAM_RESULT_OK:
		steam_status = "Steam could not create a lobby (code %d)." % connect
		steam_failed.emit(steam_status)
		return

	_steam.call("setLobbyData", new_lobby, STEAM_LOBBY_GAME_KEY, STEAM_LOBBY_GAME_VALUE)
	_steam.call("setLobbyData", new_lobby, "name", "%s's beach" % steam_name())
	_steam.call("setLobbyData", new_lobby, "players", "1/%d" % MAX_PLAYERS)

	var peer := _make_steam_peer()
	if peer == null:
		_steam.call("leaveLobby", new_lobby)
		return
	var err: int = peer.call("host_with_lobby", new_lobby)
	if err != OK:
		_steam.call("leaveLobby", new_lobby)
		steam_status = "Steam could not host the lobby (%s)." % error_string(err)
		steam_failed.emit(steam_status)
		return

	_activate_steam_peer(peer)
	lobby_id = new_lobby
	hosting = true
	active = true
	local_id = 1
	peers = [1]
	steam_status = "Hosting lobby %d as %s" % [new_lobby, steam_name()]
	print("[steam] hosting lobby %d" % new_lobby)
	session_started.emit(true)


func _on_steam_lobby_joined(lobby: int, _permissions: int, _locked: bool, response: int) -> void:
	if _steam_pending_lobby == 0:
		return
	_steam_pending_lobby = 0
	if response != STEAM_LOBBY_JOIN_OK:
		steam_status = "Steam refused the lobby join (code %d)." % response
		join_failed.emit(steam_status)
		return

	var owner_id := int(_steam.call("getLobbyOwner", lobby))
	if owner_id == steam_id():
		# We are the owner; this is our own lobby, so host it instead.
		_steam_pending_host = true
		_on_steam_lobby_created(STEAM_RESULT_OK, lobby)
		return

	var peer := _make_steam_peer()
	if peer == null:
		return
	var err: int = peer.call("connect_to_lobby", lobby)
	if err != OK:
		steam_status = "Steam could not connect to the lobby host (%s)." % error_string(err)
		join_failed.emit(steam_status)
		return

	_activate_steam_peer(peer)
	lobby_id = lobby
	hosting = false
	active = true
	local_id = 0
	steam_status = "Connecting to %s's beach..." % str(_steam.call("getLobbyData", lobby, "name"))
	print("[steam] joining lobby %d" % lobby)


func _on_steam_lobby_match_list(lobbies: Array) -> void:
	var out: Array[Dictionary] = []
	for raw in lobbies:
		var id := int(raw)
		out.append({
			"id": id,
			"name": str(_steam.call("getLobbyData", id, "name")),
			"players": int(_steam.call("getNumLobbyMembers", id)),
			"max": int(_steam.call("getLobbyMemberLimit", id)),
			"host": int(_steam.call("getLobbyOwner", id)),
		})
	steam_lobbies_listed.emit(out)


func _on_steam_lobby_invite(_inviter: int, lobby: int, _game: int) -> void:
	if lobby != 0:
		steam_invite.emit(lobby)


## --- Leaving -------------------------------------------------------------

func leave() -> void:
	if active:
		var peer := multiplayer.multiplayer_peer
		if peer != null and not (peer is OfflineMultiplayerPeer):
			peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if transport == Transport.STEAM and _steam_ready and _steam != null and lobby_id != 0:
		_steam.call("leaveLobby", lobby_id)
	active = false
	hosting = false
	transport = Transport.OFFLINE
	lobby_id = 0
	local_id = 1
	peers.clear()
	ready_peers.clear()
	_steam_pending_host = false
	_steam_pending_lobby = 0


## --- Players -------------------------------------------------------------

## Spawn slots follow join order, not the raw peer id: both transports hand out
## large ids, so `peer_id - 1` would index far past the four slots.
func spawn_point_for(peer_id: int) -> Vector3:
	var index := peers.find(peer_id)
	if index < 0:
		index = 0
	return SPAWN_POINTS[index % SPAWN_POINTS.size()]


func mark_ready(peer_id: int) -> void:
	if not ready_peers.has(peer_id):
		ready_peers.append(peer_id)


func unmark_ready(peer_id: int) -> void:
	ready_peers.erase(peer_id)


## The player node this machine controls (null before the beach is loaded).
func local_player() -> FirstPersonPlayer:
	for node in get_tree().get_nodes_in_group("player"):
		if node is FirstPersonPlayer and node.is_local_player():
			return node
	return null


## The local player's progression state (null before the beach is loaded).
func local_state() -> PlayerState:
	var player := local_player()
	if player == null:
		return null
	return player.get_node_or_null("PlayerState") as PlayerState


## Any player node by its player id.
func player_by_id(player_id: int) -> FirstPersonPlayer:
	for node in get_tree().get_nodes_in_group("player"):
		if node is FirstPersonPlayer and node.player_id == player_id:
			return node
	return null


## --- Multiplayer signals -------------------------------------------------

func _wire() -> void:
	if _wired:
		return
	_wired = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(id: int) -> void:
	if not peers.has(id):
		peers.append(id)
	_refresh_lobby_data()
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	print("[net] peer %d left" % id)
	peers.erase(id)
	unmark_ready(id)
	_refresh_lobby_data()
	peer_left.emit(id)


## Keeps the lobby browser's "2/4 players" honest while the beach is running.
func _refresh_lobby_data() -> void:
	if transport != Transport.STEAM or not hosting or lobby_id == 0 or _steam == null:
		return
	_steam.call("setLobbyData", lobby_id, "players", "%d/%d" % [peers.size(), MAX_PLAYERS])


func _on_connected_to_server() -> void:
	local_id = multiplayer.get_unique_id()
	peers = [1, local_id]
	session_started.emit(false)


func _on_connection_failed() -> void:
	leave()
	join_failed.emit("Could not reach the host. Check the address and that the host is waiting.")


func _on_server_disconnected() -> void:
	var was_steam := transport == Transport.STEAM
	leave()
	disconnected.emit("The host closed the beach." if not was_steam else "The host left the Steam lobby.")
