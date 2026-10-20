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
thumb/middle-finger pinch on either hand moves forward when the stick is idle,
starting below 2 cm and staying engaged until separation exceeds 3.5 cm for
80 ms across at least two samples. The same confirmation filters transient
tracking gaps and invalid joints; sustained tracking loss stops movement.
Only the hand that started the
pinch keeps it engaged, so an idle second hand cannot prolong a release.
The body follows horizontal room-scale motion through collision checks; blocked
motion corrects the virtual origin. The capsule remains a fixed standing height
(crouching and climbing are not implemented).

Every VR menu tilts upward 20 degrees, about 38 cm ahead. The lobby sits 12 cm
below the player's eyes; the full in-game menu sits 32 cm below them.
A 10 cm horizontal / 15 cm vertical deadzone filters small
head movements; larger room-scale movement gently keeps it within reach. A
heading difference over 15 degrees starts a gentle turn. The tablet moves with
the playspace during locomotion and resets on opening or switching rigs.
Touch buttons with either index finger: they activate on contact, play a
short tone, and require a small withdrawal beyond 1.2 cm from the original
contact plane before another touch. A 100 ms cooldown per button blocks
contact bounce (including the other hand) while allowing rapid deliberate
taps. Controls receive one mouse event stream; touch events feed drag
navigation only, avoiding duplicate button presses/toggles. Tracking loss,
UI changes, and locomotion do not
rearm a resting finger. The panel holds still during contact for dragging.

Controllers retain a ray over the panel, with a short haptic pulse on button
activation. Tone and haptic feedback only run in VR; bare hands receive the
tone. In a room, the left controller triple-line Menu button opens/closes the
room menu. Closing restores a compact microphone/menu panel 26 cm below eye
height. Runtime system buttons are unbound, and opening the runtime dashboard
preserves app menu state. B/Y remains available for world interactions. With
hands only, touch Menu on the compact bar. No hand gesture toggles the menu.
Leaving a room requires its explicit Leave Room action.
Optical hands use Godot XRNode3D and XRHandModifier3D with the official humanoid
hand meshes. The engine applies joint positions and orientations without custom
axis conversions; fingertips share tracking data with UI contact. Incomplete
tracking hides the mesh until valid data returns.

Run from the repository root, using Godot 4.7:

```sh
godot --headless --editor --path Godot --import --quit
godot --headless --path Godot --xr-mode off --script res://tests/movement_test.gd
godot --headless --path Godot --xr-mode off --script res://tests/tracked_hand_test.gd
godot --headless --path Godot --xr-mode off --script res://tests/hand_menu_test.gd
godot --headless --path Godot --xr-mode off res://UI/tests/lobby_test.tscn
```

The suite exercises the production motor and both controls scripts against real
Jolt floor collisions, including acceleration, braking, diagonal speed, jump
height, and landing. Adapter checks cover desktop input/look, XR deadzones and
stick direction, pinch hysteresis, head-pivot turning, room-scale following,
and one-shot jump consumption. The XR tests check joint alignment against raw
OpenXR fixtures, neutral skin deformation/normals, tracking loss, world scale,
playspace anchoring and the heading deadzone across real frames, rig switching,
and fingertip press/drag/release and withdrawal latching. UI checks cover menu
toggles, compact controls, both hands, rapid taps, debounce, microphone
synchronization across all menus, immediate touch activation, VR feedback routing,
and desktop feedback isolation. Tests return nonzero on failure.

Headless tests do not validate physical headset comfort or runtime tracking.
On a headset, check stick directions, turn pivot with an offset head, room-scale
walls, jumping under a ceiling, pinch release/tracking loss, and controller
reconnection. On desktop, check cursor capture/release and simultaneous mouse
and gamepad look. Smooth turning and the default 5 m/s speed can be tuned on
Input and Motor for comfort.
