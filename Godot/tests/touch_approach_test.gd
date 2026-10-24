extends SceneTree
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var approach := TouchApproach.new()
	for i in 8:
		approach.sample(Vector3(0, i * 0.003, 0.018 - i * 0.002), i * 16)
	check(approach.intent() == "scroll", "Lateral motion before contact must identify a swipe")
	approach.reset()
	for i in 8:
		approach.sample(Vector3(i * 0.0002, 0, 0.04 - i * 0.005), i * 16)
	check(approach.intent() == "press", "A normal approach with tracking tremor must identify a press")
	approach.reset()
	approach.sample(Vector3(0, 0, 0.008), 0)
	approach.sample(Vector3(0.001, 0, 0.005), 16)
	check(approach.intent() == "unknown", "Insufficient history must not confirm a deep-contact press")
	approach.sample(Vector3(0, 0.03, 0.005), 500)
	check(approach.intent() == "unknown", "Stale sideways movement must expire")
	approach.sample(Vector3(0, 0, 0.2), 516)
	check(approach.intent() == "unknown", "Leaving the near surface must clear intent")
	print("Touch approach: %d failures" % failures)
	quit(1 if failures else 0)
