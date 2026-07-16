extends Node

@onready var client: NakamaClient = Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http", Nakama.DEFAULT_TIMEOUT, NakamaLogger.LOG_LEVEL.ERROR )
@onready var socket: NakamaSocket = Nakama.create_socket_from(client)

var session: NakamaSession
var channel

func _ready():
	session = await client.authenticate_device_async("_test" + str(OS.get_process_id()))
	if session.is_exception():
		print("Session failed to authenticate or sum: %s" % session)
		return
	print("Session secuessful: %s" % session)


	var connected: NakamaAsyncResult = await socket.connect_async(session)
	if connected.is_exception():
		print("An error occurred: %s" % connected)
		return
	print("Socket connected.")


	# ======Join=Match========
	channel = await socket.join_chat_async("global", NakamaSocket.ChannelType.Room, false, false)

	await socket.write_chat_message_async(channel.id, {"Hello,": "World!"})

	var messages = await client.list_channel_messages_async(session, channel.id, 100, false)

	for m: NakamaAPI.ApiChannelMessage in messages.messages:
		print(m.user_id_one, m.user_id_two, m.content)


# Try to invalidate session before exit
func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed(&"exit"):
		await client.session_logout_async(session)

	if Input.is_action_just_pressed(&"jump"):

			await socket.write_chat_message_async(channel.id, {"Hello,": "World!"})

			var messages = await client.list_channel_messages_async(session, channel.id, 100, false)

			for m: NakamaAPI.ApiChannelMessage in messages.messages:
				print(m.user_id_one, m.user_id_two, m._sender_id, m.content)
