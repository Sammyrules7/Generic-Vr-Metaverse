@tool
class_name WorldDefinition
extends Resource

## Stable ID shared with the server and other clients.
## Adding a world requires TWO edits that must stay in sync:
## 1. Add a WorldDefinition entry in res://worlds/world_registry.tres
## 2. Add the same ID to supportedWorlds in Server/room.go (then redeploy).
## The server treats world_id as an opaque allowlisted string.
@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export_file("*.tscn") var scene_path: String
## Optional screenshot or artwork. Worlds without one use a text-only button.
@export var preview: Texture2D
