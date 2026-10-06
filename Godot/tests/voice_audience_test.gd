extends SceneTree
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var session = load("res://game_modes/murder_mystery/murder_session.gd").new()
	var voice = load("res://Networking/voice_chat.gd").new()
	session.snapshot = {"phase": "active", "players": {
		2: {"alive": true, "participating": true},
		3: {"alive": false, "participating": true},
		4: {"alive": false, "participating": false},
		5: {"alive": true, "participating": true}}}
	voice.set_audience_policy(session._voice_allowed)
	check(voice.can_hear(2, 5), "Living players must hear living players")
	check(not voice.can_hear(3, 2), "Ghost speech must not reach living players")
	check(not voice.can_hear(4, 2), "Visitor speech must not reach living players")
	check(not voice.can_hear(99, 2), "Unknown spectator must not reach living players")
	check(voice.can_hear(2, 3) and voice.can_hear(3, 4), "Spectators may hear living players and each other")
	session.snapshot.phase = "results"
	check(voice.can_hear(3, 2), "Results must restore shared room conversation")
	var manager = load("res://player/player_manager.gd").new()
	manager.voice_chat = voice
	session.manager = manager
	session.snapshot.phase = "active"
	session.clear()
	check(voice.can_hear(3, 2) and not voice.audience_policy.is_valid(), "Game teardown must restore normal room voice")
	manager.free()
	voice.free()
	session.free()
	print("Voice audiences: ", failures, " failures")
	quit(1 if failures else 0)
