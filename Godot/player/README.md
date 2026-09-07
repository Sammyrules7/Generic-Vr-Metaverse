# Player movement

Both player scenes compose a `CharacterBody3D`, an `Input` adapter, and a
`Motor` node. `MovementInput` is the small shared adapter contract; there is no
player inheritance hierarchy. The motor owns acceleration, braking, gravity,
jumping, and `move_and_slide()`. Configure speed, acceleration, deceleration,
and jump height on the scene's Motor node.

Adapters sample before each motor step and supply a world-space horizontal
movement vector (length 0–1) and a consumed-once jump request. A new device
adapter only needs to extend `MovementInput` and implement `sample(delta)`.
Physics uses the body's collision-adjusted velocity, including after walls
and ceilings. Jump requests in the air are discarded; holding jump does not
cause automatic jumping when landing.

Desktop: WASD/arrows or left stick move; mouse or right stick look; Space/gamepad
A jumps. Escape releases the cursor, and left click captures it again. Mouse
sensitivity and gamepad angular speed are separate settings on Input.

XR: left stick moves relative to headset yaw, right stick smoothly turns around
the headset, and right A/X jumps. Stick deadzones preserve analog speed. A left
thumb/index pinch moves forward when the stick is idle, with separate press and
release thresholds. Missing trackers or invalid joint positions cancel pinch.
The body follows horizontal room-scale motion through collision checks; blocked
motion corrects the virtual origin. The capsule remains a fixed standing height
(crouching and climbing are not implemented).

Run from the repository root, using Godot 4.7:

```sh
godot --headless --editor --path Godot --import --quit
godot --headless --path Godot --xr-mode off --script res://tests/movement_test.gd
```

The suite instantiates both production player scenes and exercises real Jolt
floor, wall, and ceiling collisions, acceleration, braking, diagonal speed,
jump height and landing. Adapter checks cover desktop input/look and simulated
XR tracker input/disconnection, pinch hysteresis, head-pivot turning, room-scale
following, and one-shot jump consumption. It returns nonzero on failure.

Headless tests do not validate physical headset comfort or runtime tracking.
On a headset, check stick directions, turn pivot with an offset head, room-scale
walls, jumping under a ceiling, pinch release/tracking loss, and controller
reconnection. On desktop, check cursor capture/release and simultaneous mouse
and gamepad look. Smooth turning and the default 5 m/s speed can be tuned on
Input and Motor for comfort.
