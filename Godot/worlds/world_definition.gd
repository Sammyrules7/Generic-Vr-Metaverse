@tool
class_name WorldDefinition
extends Resource

## Stable ID shared with the server and other clients.
@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export_file("*.tscn") var scene_path: String
## Optional screenshot or artwork. Worlds without one use a text-only button.
@export var preview: Texture2D
