extends Control
## Shared world-space feeding target and satiety presentation for roaming and working staff.
var member: StaffMember
const LAUGH_AUDIO: AudioStream = preload("res://assets/audio/nailong_laugh.mp3")
const LAUGH_INTERVAL_MIN: float = 5.0
const LAUGH_INTERVAL_MAX: float = 12.0
const LAUGH_DURATION_MIN: float = 2.0
const LAUGH_DURATION_MAX: float = 5.0
var _laugh_frame_timer := 0.0
var _laugh_cooldown: float = randf_range(LAUGH_INTERVAL_MIN, LAUGH_INTERVAL_MAX)
var _laugh_left: float = 0.0
var _audio: AudioStreamPlayer2D
var _label: Label
var _sprite: AnimatedSprite2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_sprite = get_parent().get_node("AnimatedSprite2D")
	_audio = AudioStreamPlayer2D.new()
	_audio.stream = LAUGH_AUDIO
	_audio.volume_db = -10.0
	_audio.max_distance = 1600.0
	_audio.position = Vector2(48, 82)
	add_child(_audio)
	# Expand only the UI drop target by 12 pixels per side; physics stays unchanged.
	position = _sprite.position - Vector2(48, 82)
	size = Vector2(96, 130)
	_label = Label.new()
	_label.position = Vector2(-12, 7)
	_label.size = Vector2(120, 20)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 3)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

func bind_member(value: StaffMember) -> void:
	if member == value:
		return
	_end_laugh()
	member = value
	_laugh_cooldown = randf_range(LAUGH_INTERVAL_MIN, LAUGH_INTERVAL_MAX)

func _end_laugh() -> void:
	_laugh_left = 0.0
	_laugh_frame_timer = 0.0
	if member != null:
		member.is_laughing = false
	if _audio != null:
		_audio.stop()

func _exit_tree() -> void:
	_end_laugh()

func blocks_movement(delta: float, facing_right: bool) -> bool:
	visible = member != null
	if member == null:
		return false
	if member.is_working or member.satiety <= 0.0:
		_end_laugh()
	elif _laugh_left > 0.0:
		StaffCare.consume_laugh_energy(member, minf(delta, _laugh_left))
		_laugh_left = maxf(0.0, _laugh_left - delta)
		if _laugh_left <= 0.0 or member.satiety <= 0.0:
			_end_laugh()
			_laugh_cooldown = randf_range(LAUGH_INTERVAL_MIN, LAUGH_INTERVAL_MAX)
	else:
		# Only actual wandering advances the timer. Standing idle cannot trigger laughter.
		var actor := get_parent() as CharacterBody2D
		if actor != null and actor.velocity.length() > 8.0:
			_laugh_cooldown -= delta
			if _laugh_cooldown <= 0.0:
				_laugh_left = randf_range(LAUGH_DURATION_MIN, LAUGH_DURATION_MAX)
				member.is_laughing = true
				_audio.play()
	_label.text = "%d/100" % roundi(member.satiety)
	var sad := member.satiety <= 0.0
	if sad or _laugh_left > 0.0:
		var action := "sad" if sad else "laugh"
		var anim := StringName(action + ("_right" if facing_right else "_left"))
		if _sprite.sprite_frames.has_animation(anim):
			if sad:
				_sprite.play(anim)
			else:
				_sprite.animation = anim
				_sprite.pause()
				_laugh_frame_timer -= delta
				if _laugh_frame_timer <= 0.0:
					var count := _sprite.sprite_frames.get_frame_count(anim)
					_sprite.frame = (_sprite.frame + randi_range(1, maxi(1, count - 1))) % count
					_laugh_frame_timer = randf_range(0.10, 0.18)
		return true
	return false

func _can_drop_data(_pos: Vector2, payload: Variant) -> bool:
	if member == null or member.satiety >= StaffMember.MAX_SATIETY or not payload is Dictionary or payload.get("kind") != "warehouse_item":
		return false
	var source: Variant = payload.get("source")
	if not is_instance_valid(source) or not source.valid_payload(payload):
		return false
	var item: ItemData = ItemDB.get_item(String(payload.get("item_id", "")))
	return item != null and item.satiety_restore > 0.0 and Inventory.has(item.id, 1)

func _drop_data(pos: Vector2, payload: Variant) -> void:
	if _can_drop_data(pos, payload):
		StaffCare.feed(member.id, String(payload.item_id), int(payload.index))
