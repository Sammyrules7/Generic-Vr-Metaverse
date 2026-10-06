# Player movement

`network_player.tscn` composes a `CharacterBody3D`, a device-specific controls
adapter, and a `Motor` node. `MovementInput` is the small shared adapter
contract; there is no player inheritance hierarchy. The motor owns
acceleration, braking, gravity, jumping, and `move_and_slide()`. Configure
speed, acceleration, deceleration, and jump height on the Motor node.

Adapters sample before each motor step and supply a world-space horizontal
movement vector (length 0–1) and a consumed-once jump request. A new device
adapter only needs to extend `MovementInput` and implement `sample(delta)`.
Physics uses the body's collision-adjusted velocity, including after walls
and ceilings. Jump requests in the air are discarded; holding jump does not
cause automatic jumping when landing.

Desktop: WASD/arrows or left stick move; mouse or right stick look; Space/gamepad
A jumps. Escape opens the room menu, including browser pointer-lock release;
Resume captures the cursor again. Mouse
sensitivity and gamepad angular speed are separate settings on Input.

XR: left stick moves relative to headset yaw, right stick smoothly turns around
the headset, and right A/X jumps. Both OpenXR primary and WebXR thumbstick inputs
are supported. Stick deadzones preserve analog speed. A
thumb/index pinch moves forward when the stick is idle, with separate press and
release thresholds. Missing trackers or invalid joint positions cancel pinch.
The body follows horizontal room-scale motion through collision checks; blocked
motion corrects the virtual origin. The capsule remains a fixed standing height
(crouching and climbing are not implemented).

The VR menu follows the left hand with smoothing and faces the headset. Touch
it with the right index finger; it holds still during a touch for dragging.
Controllers retain a ray that is visible only over the menu. In a room, Menu or
Select returns directly to the home screen. B/Y remains available for world
interactions. With hands only, hold a left thumb/ring-finger pinch for 0.4 seconds
to return home.
Optical hands use the tracked skeleton instead of grip/trigger animations.

Run from the repository root, using Godot 4.7:

```sh
godot --headless --editor --path Godot --import --quit
godot --headless --path Godot --xr-mode off --script res://tests/movement_test.gd
```

The suite exercises the production motor and both controls scripts against real
Jolt floor collisions, including acceleration, braking, diagonal speed, jump
height, and landing. Adapter checks cover desktop input/look, XR deadzones and
stick direction, pinch hysteresis, head-pivot turning, room-scale following,
and one-shot jump consumption. It returns nonzero on failure.

Headless tests do not validate physical headset comfort or runtime tracking.
On a headset, check stick directions, turn pivot with an offset head, room-scale
walls, jumping under a ceiling, pinch release/tracking loss, and controller
reconnection. On desktop, check cursor capture/release and simultaneous mouse
and gamepad look. Smooth turning and the default 5 m/s speed can be tuned on
Input and Motor for comfort.
