extends PanelContainer
signal closed
var _report: RichTextLabel
var _done: Button
var _elapsed := 0.0
func _ready() -> void:
	custom_minimum_size = Vector2(800, 600)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	add_child(content)
	var title := Label.new()
	title.text = "Debug"
	title.add_theme_font_size_override("font_size", 26)
	content.add_child(title)
	_report = RichTextLabel.new()
	_report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_report.selection_enabled = true
	_report.add_theme_font_size_override("normal_font_size", 15)
	content.add_child(_report)
	var actions := HBoxContainer.new()
	content.add_child(actions)
	var reset := Button.new()
	reset.text = "Reset"
	reset.pressed.connect(func():
		AvatarService.reset_diagnostics()
		refresh()
	)
	actions.add_child(reset)
	var copy := Button.new()
	copy.text = "Copy report"
	copy.pressed.connect(func(): DisplayServer.clipboard_set(report()))
	actions.add_child(copy)
	_done = Button.new()
	_done.text = "Done"
	_done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_done.pressed.connect(func(): closed.emit())
	actions.add_child(_done)
	hide()
func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	if _elapsed >= 0.5:
		_elapsed = 0
		refresh()
func refresh() -> void:
	_report.text = report()
func focus_entry() -> void:
	refresh()
	_done.grab_focus()
func report() -> String:
	var peer_count := multiplayer.get_peers().size()
	var replication = Networking.player_replication
	var mirrors: Array[String] = []
	for mirror in get_tree().get_nodes_in_group("planar_mirrors"):
		mirrors.append(mirror.debug_report())
	return "\n".join(mirrors) + "\n\n" + AvatarService.debug_report() + "\n\n" + (replication.avatar_transfer.debug_report() if replication != null and replication.avatar_transfer != null else "P2P unavailable") + "\n\nNetwork peers: %d\nReceived avatar IDs: %s" % [peer_count, replication._avatar_by_peer if replication != null else {}]


func handle_stick(stick: Vector2, delta: float) -> void:
	if absf(stick.y) > 0.25:
		_report.get_v_scroll_bar().value -= stick.y * 600 * delta
