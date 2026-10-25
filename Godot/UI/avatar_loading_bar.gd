extends Control
## Determinate byte progress, then one softly bouncing pill while preparing.
var indeterminate := false:
	set(next):
		indeterminate = next
		queue_redraw()
var value := 0.0:
	set(next):
		value = next
		queue_redraw()
var _elapsed := 0.0
func _process(delta: float) -> void:
	if is_visible_in_tree() and indeterminate:
		_elapsed += delta
		queue_redraw()
func _draw() -> void:
	var background := get_theme_stylebox("background", "ProgressBar")
	var fill := get_theme_stylebox("fill", "ProgressBar")
	draw_style_box(background, Rect2(Vector2.ZERO, size))
	var width := size.x * (0.28 if indeterminate else clampf(value / 100.0, 0, 1))
	if width <= 0:
		return
	width = maxf(minf(size.y, size.x), width)
	var start := (size.x - width) * (0.5 - 0.5 * cos(_elapsed * 3.5)) if indeterminate else 0.0
	draw_style_box(fill, Rect2(Vector2(start, 0), Vector2(width, size.y)))
