extends Node
## Ambiente tenso: drone grave continuo (ruido marrón) + golpes/clangs
## distantes al azar cada tanto. Cada cliente lo genera y reproduce
## localmente -- no necesita estar sincronizado por red.

var _drone_player: AudioStreamPlayer
var _next_event_in: float = 0.0


func _ready() -> void:
	_drone_player = AudioStreamPlayer.new()
	add_child(_drone_player)
	_drone_player.stream = ProceduralSound.brown_noise(4.0, 0.35)
	_drone_player.volume_db = -16.0
	_drone_player.play()
	_schedule_next_event()


func _process(delta: float) -> void:
	_next_event_in -= delta
	if _next_event_in <= 0.0:
		_play_distant_event()
		_schedule_next_event()


func _schedule_next_event() -> void:
	_next_event_in = randf_range(6.0, 16.0)


func _play_distant_event() -> void:
	var player := AudioStreamPlayer.new()
	add_child(player)
	player.stream = ProceduralSound.noise_burst(randf_range(0.15, 0.4), 0.5)
	player.volume_db = randf_range(-20.0, -9.0)
	player.pitch_scale = randf_range(0.5, 0.85)
	player.play()
	player.finished.connect(player.queue_free)
