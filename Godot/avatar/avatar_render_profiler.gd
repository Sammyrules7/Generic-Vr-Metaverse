class_name AvatarRenderProfiler
extends Node
## Opt-in bounded capture. Frame intervals use real monotonic time, not clamped delta.
const DURATION_MS := 30000
const MAX_HITCHES := 40
const PIPELINES := {
	"canvas": Performance.PIPELINE_COMPILATIONS_CANVAS,
	"mesh": Performance.PIPELINE_COMPILATIONS_MESH,
	"surface": Performance.PIPELINE_COMPILATIONS_SURFACE,
	"draw": Performance.PIPELINE_COMPILATIONS_DRAW,
	"specialization": Performance.PIPELINE_COMPILATIONS_SPECIALIZATION,
}
var active := false
var focused := true
var last_frame_ms := 0.0
var peak_frame_ms := 0.0
var peak_submission_ms := 0.0
var frame_count := 0
var hitches: Array[Dictionary] = []
var worst_hitch := {}
var activity := "idle"
var _end_at := 0
var _previous_frame := 0
var _previous_focus := true
var _draw_started := 0
var _last_submission_ms := 0.0
var _pipeline_start := {}
var _pipeline_last := {}
var _pipeline_end := {}
var _measured := {}
var _view_samples := {}
var _next_views := 0
var _web_installed := false
var _web_report := "not captured"

func _ready() -> void:
	add_to_group("avatar_render_profilers")
	focused = get_window().has_focus()
	process_priority = -100
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	RenderingServer.frame_post_draw.connect(_post_draw)
	set_process(false)

func start_capture() -> void:
	if active:
		stop_capture()
	active = true
	last_frame_ms = 0
	peak_frame_ms = 0
	peak_submission_ms = 0
	frame_count = 0
	hitches.clear()
	worst_hitch.clear()
	_view_samples.clear()
	_previous_frame = 0
	_previous_focus = focused
	_last_submission_ms = 0
	_pipeline_start = _pipeline_counts()
	_pipeline_last = _pipeline_start.duplicate()
	_pipeline_end.clear()
	_end_at = Time.get_ticks_msec() + DURATION_MS
	_next_views = 0
	_web_report = "native build: WebGL call tracing unavailable"
	if OS.has_feature("web"):
		_web_installed = bool(JavaScriptBridge.eval(AvatarWebGLCapture.INSTALL, true))
		if _web_installed:
			JavaScriptBridge.eval("globalThis.__vrAvatarRenderCapture.base = %d" % Time.get_ticks_msec(), true)
			_web_report = "capturing browser main-context calls"
		else:
			_web_report = "WebGL hooks unavailable; protected prototypes or renderer in another context"
	set_process(true)

func reset_capture() -> void:
	stop_capture()
	hitches.clear()
	worst_hitch.clear()
	_view_samples.clear()
	_pipeline_end.clear()
	frame_count = 0
	peak_frame_ms = 0
	peak_submission_ms = 0
	_web_report = "not captured"

func stop_capture() -> void:
	if not active:
		return
	_pipeline_end = _pipeline_counts()
	if _web_installed:
		_read_web_report()
		JavaScriptBridge.eval("globalThis.__vrAvatarRenderCapture.stop()", true)
		_web_installed = false
	for reference: WeakRef in _measured.values():
		var viewport := reference.get_ref() as Viewport
		if is_instance_valid(viewport):
			RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), false)
	_measured.clear()
	active = false
	set_process(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	sample_frame(now)
	if Time.get_ticks_msec() >= _next_views:
		_sample_viewports()
		_next_views = Time.get_ticks_msec() + 1000
	if Time.get_ticks_msec() >= _end_at:
		stop_capture()

func sample_frame(now: int) -> void:
	if _previous_frame > 0 and focused and _previous_focus:
		last_frame_ms = float(now - _previous_frame) / 1000.0
		peak_frame_ms = maxf(peak_frame_ms, last_frame_ms)
		frame_count += 1
		var counts := _pipeline_counts()
		var delta := {}
		for name in counts:
			var change := int(counts[name]) - int(_pipeline_last.get(name, 0))
			if change > 0:
				delta[name] = change
		if last_frame_ms >= 20.0:
			hitches.append({"at_ms": now / 1000, "frame_ms": snappedf(last_frame_ms, 0.1), "submission_ms": snappedf(_last_submission_ms, 0.1), "activity": activity, "pipelines": delta})
			if last_frame_ms >= float(worst_hitch.get("frame_ms", 0)):
				worst_hitch = hitches.back()
			if hitches.size() > MAX_HITCHES:
				hitches.pop_front()
		_pipeline_last = counts
	else:
		_pipeline_last = _pipeline_counts()
	_previous_frame = now
	_previous_focus = focused

func note_activity(description: String) -> void:
	activity = description.left(140)

func _pre_draw() -> void:
	if active:
		_draw_started = Time.get_ticks_usec()

func _post_draw() -> void:
	if active and _draw_started > 0:
		_last_submission_ms = float(Time.get_ticks_usec() - _draw_started) / 1000.0
		if focused:
			peak_submission_ms = maxf(peak_submission_ms, _last_submission_ms)
		_draw_started = 0

func _pipeline_counts() -> Dictionary:
	var result := {}
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		for name in PIPELINES:
			result[name] = int(Performance.get_monitor(PIPELINES[name]))
	return result

func _sample_viewports() -> void:
	var viewports: Array[Viewport] = [get_viewport()]
	for node in get_tree().get_nodes_in_group("avatar_render_viewports"):
		if node is Viewport and node != get_viewport():
			viewports.append(node)
	for viewport in viewports:
		var id := viewport.get_instance_id()
		if not _measured.has(id):
			_measured[id] = weakref(viewport)
			RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
		var cpu := RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid())
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
		var label := str(viewport.get_path())
		var record: Dictionary = _view_samples.get(label, {"cpu_peak_ms": 0.0, "gpu_peak_ms": 0.0})
		record.cpu_peak_ms = maxf(record.cpu_peak_ms, cpu)
		record.gpu_peak_ms = maxf(record.gpu_peak_ms, gpu)
		record["size"] = viewport.get_visible_rect().size
		record["msaa"] = viewport.msaa_3d
		if viewport.use_xr:
			for name in ["WebXR", "OpenXR"]:
				var interface := XRServer.find_interface(name)
				if interface != null and interface.is_initialized():
					record["xr_target_size"] = interface.get_render_target_size()
					break
		_view_samples[label] = record

func _read_web_report() -> void:
	var raw: Variant = JavaScriptBridge.eval("globalThis.__vrAvatarRenderCapture.snapshot()", true)
	var parsed: Variant = JSON.parse_string(str(raw))
	if parsed is Dictionary:
		_web_report = JSON.stringify(parsed, "  ")

func report() -> String:
	if active and _web_installed:
		_read_web_report()
	var lines: Array[String] = ["Render hitch capture: %s" % ("%ds remaining" % maxi(0, (_end_at - Time.get_ticks_msec()) / 1000) if active else "stopped"), "Focused frames: %d | wall peak %.1f ms | render submission peak %.1f ms" % [frame_count, peak_frame_ms, peak_submission_ms], "Submission time is CPU wall time, not a GPU timer. Unfocused/resume gaps excluded."]
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		lines.append("Compatibility: pipeline precompilation counters unavailable; zero cannot rule out shader stalls.")
	else:
		var counts := _pipeline_counts() if active else _pipeline_end
		var changes := {}
		for name in counts:
			changes[name] = int(counts[name]) - int(_pipeline_start.get(name, 0))
		lines.append("Pipeline compilation deltas: %s" % changes)
	lines.append("Viewport samples (once/sec, last-rendered peaks; zero = unavailable, not zero cost): %s" % _view_samples)
	lines.append("Worst focused hitch: %s" % worst_hitch)
	lines.append("Hitches >=20 ms, recent 40 (correlation, not proof of cause):")
	for hitch in hitches:
		lines.append(str(hitch))
	lines.append("GLES shader waits can appear in compile/link status queries, not just compileShader. Compare their timestamps with the worst hitch.")
	lines.append("WebGL calls: " + _web_report)
	return "\n".join(lines)

func _exit_tree() -> void:
	stop_capture()
