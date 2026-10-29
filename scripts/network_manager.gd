extends Node
## ENet session manager for the 1-4 player beach.
##
## The host owns the world: the sand heightmap, the loot and every player's
## progression. Clients only send intents (dig, take loot, sell) and apply what
## the host broadcasts. This autoload is the one place that knows whether the
## game is running offline (single player), hosting or joined to a host.
##
## The peer id doubles as the player id: the host is always 1, clients get the
## ids ENet assigns. Nothing here depends on the scene, so the menu can start a
## session before the beach is loaded.

signal session_started(hosting: bool)
signal join_failed(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal disconnected(reason: String)

const DEFAULT_PORT := 8910
const MAX_PLAYERS := 4
const DEFAULT_ADDRESS := "127.0.0.1"

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

var _wired := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## True offline or on the host; false on a joined client.
func is_host() -> bool:
	return not active or hosting


func is_online() -> bool:
	return active


func host_game(port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
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
	hosting = false
	active = true
	local_id = 0
	_wire()
	return OK


func leave() -> void:
	if active:
		var peer := multiplayer.multiplayer_peer
		if peer is ENetMultiplayerPeer:
			peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	active = false
	hosting = false
	local_id = 1
	peers.clear()
	ready_peers.clear()


## Spawn slots follow join order, not the raw peer id: ENet hands out large
## random ids, so `peer_id - 1` would index far past the four slots.
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
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	print("[net] peer %d left" % id)
	peers.erase(id)
	unmark_ready(id)
	peer_left.emit(id)


func _on_connected_to_server() -> void:
	local_id = multiplayer.get_unique_id()
	peers = [1, local_id]
	session_started.emit(false)


func _on_connection_failed() -> void:
	leave()
	join_failed.emit("Could not reach the host. Check the address and that the host is waiting.")


func _on_server_disconnected() -> void:
	leave()
	disconnected.emit("The host closed the beach.")
