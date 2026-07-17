extends Node

@onready var client: NakamaClient = Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http", Nakama.DEFAULT_TIMEOUT, NakamaLogger.LOG_LEVEL.ERROR )
@onready var socket: NakamaSocket = Nakama.create_socket_from(client)

var session: NakamaSession
var channel

func _ready():
	pass
