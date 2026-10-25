extends SceneTree
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func run() -> void:
	var profiler := AvatarRenderProfiler.new()
	root.add_child(profiler)
	profiler.focused = true
	profiler.start_capture()
	profiler.set_process(false)
	profiler.sample_frame(1000)
	profiler.sample_frame(251000)
	check(profiler.peak_frame_ms == 250.0, "Use real wall time rather than the engine's clamped delta")
	check(profiler.hitches.size() == 1, "Record a focused hitch")
	profiler.focused = false
	profiler.sample_frame(1000000)
	profiler.focused = true
	profiler.sample_frame(2000000)
	profiler.sample_frame(2011000)
	check(profiler.hitches.size() == 1 and profiler.peak_frame_ms == 250, "Exclude hidden and focus-resume gaps")
	for index in 100:
		profiler.sample_frame(2111000 + index * 100000)
	check(profiler.hitches.size() == profiler.MAX_HITCHES, "Bound capture memory")
	check(profiler.worst_hitch.frame_ms == 250, "Retain the worst hitch even after it leaves recent history")
	profiler.stop_capture()
	check(not profiler.active and not profiler.is_processing(), "Stop all capture overhead")
	check(profiler.report().contains("not a GPU timer"), "Never label wall submission time as GPU time")
	profiler.reset_capture()
	check(profiler.hitches.is_empty() and profiler.peak_frame_ms == 0 and profiler.frame_count == 0, "Reset clears a completed capture")
	profiler.start_capture()
	profiler.set_process(false)
	var viewport := SubViewport.new()
	viewport.name = "RenderProbe"
	viewport.add_to_group("avatar_render_viewports")
	root.add_child(viewport)
	profiler._sample_viewports()
	check(profiler._view_samples.has(str(viewport.get_path())), "Capture registered off-screen viewports")
	viewport.free()
	profiler._end_at = Time.get_ticks_msec() - 1
	profiler._process(0)
	check(not profiler.active and profiler._measured.is_empty(), "Expiration must clean up even after a measured viewport is freed")
	profiler.free()
	print("Avatar render profiler: %d failures" % failures)
	quit(1 if failures else 0)
