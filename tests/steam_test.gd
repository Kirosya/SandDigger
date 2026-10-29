extends Node
## Steam transport smoke test.
##
## Two outcomes are valid because the test has to run on machines with and
## without a signed-in Steam client:
##   - Steam unavailable / not signed in: every Steam entry point must fail
##     politely (error return + human readable status) and leave the game able
##     to fall back to ENet.
##   - Steam signed in: hosting through a lobby must actually start a session
##     with transport STEAM and a real lobby id, and leaving must tear it down.
##
## Run headless: godot --headless --path . res://tests/steam_test.tscn

const HOST_WAIT := 8.0

var _failures := 0
var _started := false
var _hosting_seen := false
var _steam_reason := ""
var _lobbies: Array = []


func _on_lobbies_listed(entries: Array) -> void:
	_lobbies = entries


func _on_session_started(hosting: bool) -> void:
	_started = true
	_hosting_seen = hosting


func _on_steam_failed(reason: String) -> void:
	_steam_reason = reason


func _ready() -> void:
	print("STEAM extension: %s" % str(Net.steam_supported()))
	_check("steam_supported matches the engine",
		Net.steam_supported() == Engine.has_singleton("Steam"))

	var ready := Net.steam_init()
	print("STEAM init: %s  (%s)" % [str(ready), Net.steam_status])
	if not ready:
		await _test_unavailable()
	else:
		await _test_ready()
	Net.leave()

	print("STEAM %s" % ("OK" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


## No Steam: the game must say why and stay playable over ENet.
func _test_unavailable() -> void:
	_check("status explains the failure", not Net.steam_status.is_empty())
	_check("host_steam refuses", Net.host_steam() != OK)
	_check("join_steam_lobby refuses", Net.join_steam_lobby(12345) != OK)
	_check("no session was started", not Net.is_online())
	_check("no lobby id", Net.lobby_id == 0)

	var failed := [""]
	Net.steam_failed.connect(_on_steam_failed)
	Net.request_steam_lobbies()
	_check("lobby search reports the reason", not _steam_reason.is_empty())
	Net.steam_failed.disconnect(_on_steam_failed)

	# The LAN transport must still work after a failed Steam init.
	var err := Net.host_game(8921)
	_check("ENet still hosts", err == OK and Net.is_online() and Net.is_host())
	_check("ENet transport is tagged", Net.transport == Net.Transport.ENET)
	Net.leave()
	_check("leave clears the session", not Net.is_online() and Net.lobby_id == 0)


## Signed in: a lobby must turn into a real session.
func _test_ready() -> void:
	_check("signed in with a steam id", Net.steam_id() != 0)
	_check("persona name is known", not Net.steam_name().is_empty())

	Net.session_started.connect(_on_session_started)

	var err := Net.host_steam(true)
	_check("host_steam accepted", err == OK)
	await _wait_until(func() -> bool: return _started, HOST_WAIT)
	_check("lobby started a session", _started)
	_check("we are the host", _hosting_seen and Net.is_host())
	_check("transport is steam", Net.transport == Net.Transport.STEAM)
	_check("lobby id is set", Net.lobby_id != 0)
	_check("peers contain only us", Net.peers == [1])

	# The lobby browser must find the beach we just published. Steam indexes
	# lobby data with a short delay, so give it a moment and retry once.
	Net.steam_lobbies_listed.connect(_on_lobbies_listed)
	var found := false
	for attempt in 2:
		await get_tree().create_timer(1.5).timeout
		_lobbies = []
		Net.request_steam_lobbies()
		await _wait_until(func() -> bool: return not _lobbies.is_empty(), HOST_WAIT)
		for entry in _lobbies:
			if int(entry.get("id", 0)) == Net.lobby_id:
				found = true
				_check("browser shows the lobby name", not str(entry.get("name", "")).is_empty())
				_check("browser shows the player count", int(entry.get("players", 0)) == 1)
		if found:
			break
	Net.steam_lobbies_listed.disconnect(_on_lobbies_listed)
	_check("lobby browser finds our beach", found)

	Net.leave()
	await get_tree().process_frame
	_check("leave drops the lobby", Net.lobby_id == 0 and not Net.is_online())
	_check("transport resets", Net.transport == Net.Transport.OFFLINE)


func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
