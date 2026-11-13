@tool
extends CanvasModulate
## Visual clock. Set auto_advance=false to preview a fixed hour.
@export_range(0.0, 24.0, 0.01) var hour: float = 9.0
@export var auto_advance: bool = true
@export_range(30.0, 7200.0, 1.0) var day_duration_seconds: float = 300.0
@export var environment_gradient: GradientTexture1D
@export var water_path: NodePath = NodePath("../Level/SeaCanvas")
var day: int = 1
var _water_material: ShaderMaterial

func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group("day_night_cycle")
		var saved: Dictionary = SaveManager.consume_pending_clock()
		if not saved.is_empty():
			day = maxi(1, int(saved.get("day", 1)))
			hour = fposmod(float(saved.get("hour", 9.0)), 24.0)
	var water := get_node_or_null(water_path) as MeshInstance2D
	if water and water.material is ShaderMaterial:
		_water_material = water.material as ShaderMaterial
	_apply_lighting()

func _process(delta: float) -> void:
	if auto_advance and not Engine.is_editor_hint():
		var next_hour := hour + delta * 24.0 / maxf(day_duration_seconds, 1.0)
		day += int(floor(next_hour / 24.0))
		hour = fposmod(next_hour, 24.0)
	_apply_lighting()

func _apply_lighting() -> void:
	if environment_gradient == null or environment_gradient.gradient == null:
		return
	color = environment_gradient.gradient.sample(clampf(hour / 24.0, 0.0, 1.0))
	# Night holds through midnight; smooth sunrise 5-8, sunset 17-21.
	var night := 1.0 - smoothstep(5.0, 8.0, hour) + smoothstep(17.0, 21.0, hour)
	if is_instance_valid(_water_material):
		_water_material.set_shader_parameter("environment_tint", color)
		_water_material.set_shader_parameter("night_amount", night)

func get_phase_name() -> String:
	if hour >= 5.0 and hour < 12.0:
		return "早晨"
	if hour >= 12.0 and hour < 17.0:
		return "午后"
	if hour >= 17.0 and hour < 21.0:
		return "黄昏"
	return "夜晚"

func advance_phase() -> void:
	if hour < 5.0:
		hour = 9.0
	elif hour < 12.0:
		hour = 13.0
	elif hour < 17.0:
		hour = 18.0
	elif hour < 21.0:
		hour = 22.0
	else:
		hour = 9.0
		day += 1
	_apply_lighting()

func get_clock_state() -> Dictionary:
	return {"day": day, "hour": hour}
