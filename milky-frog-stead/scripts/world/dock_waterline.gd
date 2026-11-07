extends Sprite2D
## Reuse the ocean's moving terrain window; never turn the entire dock into land.
@export var sea_path: NodePath
func _process(_delta: float) -> void:
 var sea := get_node_or_null(sea_path) as MeshInstance2D
 if sea == null or not sea.material is ShaderMaterial:
  return
 var source := sea.material as ShaderMaterial
 var target := material as ShaderMaterial
 for key in ["mask_tex", "rect_origin", "rect_size"]:
  var value = source.get_shader_parameter(key)
  if value != null:
   target.set_shader_parameter(key, value)
