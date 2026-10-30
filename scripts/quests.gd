class_name Quests
extends Node
## The story of the beach, told as a chain of five quests.
##
## Each quest asks for specific things to be dug up, and pays money and XP the
## moment the last one is brought up - so quests are a second income next to
## selling junk, and the reason to keep digging once the shovel chain is done.
## The chain deliberately walks the same path as the tools: plain junk first, then
## metal finds (the detector's job), then antiques from the deep band, and finally
## the one gold ring, which is buried deeper than anything else on the beach.
##
## Quests are per player: the findings only count when this player claimed them,
## and the progress lives in PlayerState (and therefore in the profile). The
## definitions live here, so the save only has to remember the index.
##
## Quest text is in the game's language (English, like the HUD and the shop).

signal quest_changed()
signal quest_completed(index: int, title: String, money: float, xp: float)

## `match` decides which findings count:
##   trash   - any piece of junk (surface or buried)
##   metal   - junk a metal detector reacts to (see LootManager.METAL_NAMES)
##   antique - a deep antique
##   ring    - the gold ring (there is exactly one in the world)
const QUESTS := [
	{
		"title": "First Haul",
		"hint": "Bring up 3 pieces of junk.",
		"match": "trash",
		"count": 3,
		"money": 80.0,
		"xp": 150.0,
	},
	{
		"title": "Detector Practice",
		"hint": "Find 2 metal pieces: a rusty can, scrap metal or a tin lid.",
		"match": "metal",
		"count": 2,
		"money": 160.0,
		"xp": 300.0,
	},
	{
		"title": "The Deep Band",
		"hint": "Dig up an antique from the deep sand.",
		"match": "antique",
		"count": 1,
		"money": 450.0,
		"xp": 800.0,
	},
	{
		"title": "Keeper of the Deep",
		"hint": "Bring up 3 antiques in total.",
		"match": "antique",
		"count": 3,
		"money": 900.0,
		"xp": 1500.0,
	},
	{
		"title": "The Golden Ring",
		"hint": "There is one gold ring on this beach, deeper than anything else. Find it.",
		"match": "ring",
		"count": 1,
		"money": 2500.0,
		"xp": 5000.0,
	},
]

var _state: PlayerState
var _loot: LootManager


func _ready() -> void:
	add_to_group("quests")
	_loot = get_tree().get_first_node_in_group("loot_manager") as LootManager
	if _loot != null:
		_loot.loot_claimed.connect(_on_loot_claimed)


func _process(_delta: float) -> void:
	# The local player is spawned a few frames after the beach, on a client even
	# later, so the state is bound lazily rather than in _ready.
	if _state == null:
		var state := Net.local_state()
		if state != null:
			_bind(state)


func _bind(state: PlayerState) -> void:
	_state = state
	_state.quest_changed.connect(_on_state_quest_changed)
	# An old save may have brought the ring up before this chain existed.
	_sync_ring_quest()
	quest_changed.emit()


func _on_state_quest_changed(_index: int, _progress: int) -> void:
	# A quest just advanced: if the ring was already brought up long ago, the
	# final quest completes itself right here.
	_sync_ring_quest()
	quest_changed.emit()


## The quest this player is working on, or {} once the story is finished.
func current_quest() -> Dictionary:
	if _state == null:
		return {}
	var index := _state.quest_index
	if index < 0 or index >= QUESTS.size():
		return {}
	return QUESTS[index]


func quest_index() -> int:
	return 0 if _state == null else _state.quest_index


func quest_progress() -> int:
	return 0 if _state == null else _state.quest_progress


func total() -> int:
	return QUESTS.size()


func is_finished() -> bool:
	return quest_index() >= QUESTS.size()


## One line for the HUD: the active quest and how far along it is.
func progress_line() -> String:
	var def := current_quest()
	if def.is_empty():
		return "STORY COMPLETE  -  the gold ring is yours"
	return "QUEST %d/%d   %s   %d/%d" % [
		quest_index() + 1, total(), str(def["title"]),
		quest_progress(), int(def["count"])]


## A finding was claimed by this player. `kind` is the loot kind and `name` the
## display name, exactly as the claim broadcast carries them.
func note_find(kind: String, display_name: String) -> void:
	var index := quest_index()
	var def := current_quest()
	if def.is_empty():
		return
	if not _matches(str(def["match"]), kind, display_name):
		return
	if not _state.note_quest_find(int(def["count"])):
		return
	_pay(index)


## Marks the ring as found for this player. The chain owns the payout, so this is
## kept separate from the generic counting above.
func note_gold_ring() -> void:
	if _state == null:
		return
	_state.gold_ring_found = true
	_sync_ring_quest()


## Settles the last quest when the ring was already brought up before the chain
## got that far.
func _sync_ring_quest() -> void:
	if _state == null:
		return
	if _state.quest_index != QUESTS.size() - 1 or not _state.gold_ring_found:
		return
	# The ring has already been counted by `note_gold_ring`, so pay the quest
	# directly instead of asking for one more finding.
	if _state.quest_progress < int(QUESTS[QUESTS.size() - 1]["count"]):
		_state.quest_progress = int(QUESTS[QUESTS.size() - 1]["count"])
	_pay(_state.quest_index)


func _pay(index: int) -> void:
	if _state == null or index < 0 or index >= QUESTS.size():
		return
	var def: Dictionary = QUESTS[index]
	var title := str(def["title"])
	var money := float(def["money"])
	var xp := float(def["xp"])
	_state.complete_quest(index, title, money, xp)
	print("[quest] completed '%s'  +$%d  +%d XP" % [title, int(money), int(xp)])
	quest_completed.emit(index, title, money, xp)


func _on_loot_claimed(item: Dictionary) -> void:
	if _state == null:
		return
	if int(item.get("owner", 0)) != _state.player_id:
		return
	var kind := str(item.get("kind", "trash"))
	if kind == "ring":
		note_gold_ring()
	note_find(kind, str(item.get("name", "")))


## Which findings satisfy a quest. Kept in one place so the shop, the HUD and the
## tests all agree on what "a metal find" means.
static func _matches(rule: String, kind: String, display_name: String) -> bool:
	match rule:
		"trash":
			return kind == "trash"
		"metal":
			return kind == "trash" and display_name in LootManager.METAL_NAMES
		"antique":
			return kind == "antique"
		"ring":
			return kind == "ring"
	return false
