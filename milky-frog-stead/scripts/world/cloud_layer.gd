extends CanvasLayer
## World-anchored clouds follow camera panning and zoom.
## UI remains above this layer. Animation pauses with the game.

var _elapsed: float = 0.0
@onready var _clouds: ColorRect = $Clouds
@onready var _material: ShaderMaterial = _clouds.material as ShaderMaterial

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_material.set_shader_parameter("noise_offset", Vector2(rng.randf(), rng.randf()))
	_process(0.0)

func _process(delta: float) -> void:
	_elapsed += delta
	var inverse := get_viewport().get_canvas_transform().affine_inverse()
	_material.set_shader_parameter("camera_origin", inverse.origin)
	_material.set_shader_parameter("camera_axis_x", inverse.x)
	_material.set_shader_parameter("camera_axis_y", inverse.y)
	_material.set_shader_parameter("elapsed", _elapsed)
