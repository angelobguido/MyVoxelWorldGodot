extends Node3D

func _ready() -> void:
	var proj_mat : Projection = Projection()
	#var proj_mat_bytes : PackedByteArray = var_to_bytes(proj_mat)
	#var proj_mat_bytes_data : PackedByteArray = proj_mat_bytes.slice(0, proj_mat_bytes.size())
	#print(proj_mat_bytes_data.to_float32_array())
	
	print(get_mat4_bytes(proj_mat))


func get_mat4_bytes(mat : Projection) -> PackedFloat32Array:
	var arr : PackedFloat32Array
	
	arr.append_array(var_to_bytes(mat.x).to_float32_array().slice(1, 5))
	arr.append_array(var_to_bytes(mat.y).to_float32_array().slice(1, 5))
	arr.append_array(var_to_bytes(mat.z).to_float32_array().slice(1, 5))
	arr.append_array(var_to_bytes(mat.w).to_float32_array().slice(1, 5))
	
	return arr
