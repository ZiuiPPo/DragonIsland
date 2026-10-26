class_name WaterCanvas
extends MeshInstance2D
## 覆盖整个视口的一块四边形，挂 water_world.gdshader。
##
## 它每帧跟着相机走（尺寸 = 视口大小），但**内容是世界锚定的**：
## 顶点里算出的 world_pos 加上 shader 里的 rect_origin/rect_size 决定了采哪一块高度图，
## 所以相机移动不会让水纹跟着滑。四边形只负责"盖住屏幕"，不参与定位。

const CAUSTICS_PATH := "res://assets/textures/water/caustics.png"
const FOAM_PATH := "res://assets/textures/water/foam.png"

var _quad: QuadMesh


func _ready() -> void:
	_quad = QuadMesh.new()
	# 尺寸固定 1x1，用 scale 拉伸：QuadMesh 每次改 size 都会重建网格，别每帧改
	_quad.size = Vector2.ONE
	mesh = _quad
	z_index = -1
	# 贴图采样方式由 shader 的 uniform hint 决定，这里不影响
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if material is ShaderMaterial:
		var mat := material as ShaderMaterial
		var caus := load(CAUSTICS_PATH) as Texture2D
		if caus:
			mat.set_shader_parameter("caustics_tex", caus)
		var foam := load(FOAM_PATH) as Texture2D
		if foam:
			mat.set_shader_parameter("foam_mask_tex", foam)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var view := get_viewport_rect().size
	# 留一点余量，防止缩放平滑过程中露边
	var world_size := view / cam.zoom * 1.08
	scale = world_size
	global_position = cam.get_screen_center_position()
