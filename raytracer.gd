@tool
class_name RayTracer extends CompositorEffect

var rd : RenderingDevice
var shader : RID
var pipeline : RID

func _init() -> void:
	RenderingServer.call_on_render_thread(initialize_compute_shader)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and shader.is_valid():
		RenderingServer.free_rid(shader)
		
func _render_callback(effect_callback_type: int, render_data: RenderData) -> void:
	if not rd: return
	
	var scene_buffers : RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	var scene_data : RenderSceneDataRD = render_data.get_render_scene_data()
	if not scene_buffers or not scene_data: return
	
	var size : Vector2i = scene_buffers.get_internal_size()
	if size.x == 0 or size.y == 0: return
	
	var x_groups : int = size.x / 16 + 1
	var y_groups : int = size.y / 16 + 1
	
	var push_constants : PackedFloat32Array = PackedFloat32Array()
	push_constants.append(size.x)
	push_constants.append(size.y)
	push_constants.append(0)
	push_constants.append(0)
	
	for view in scene_buffers.get_view_count():
		var screen_tex : RID = scene_buffers.get_color_layer(view)
		
		var uniform : RDUniform = RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = 0
		uniform.add_id(screen_tex)
		
		var image_uniform_set : RID = UniformSetCacheRD.get_cache(shader, 0, [uniform])

		
		var inv_proj_mat : Projection = scene_data.get_view_projection(view).inverse()
		var cam_position : Vector3 = scene_data.get_cam_transform().origin
		var inv_view_mat : Projection = get_mat4_from_transform3D(scene_data.get_cam_transform())

		var camera_data_bytes : PackedFloat32Array
		camera_data_bytes.append(cam_position.x)
		camera_data_bytes.append(cam_position.y)
		camera_data_bytes.append(cam_position.z)
		camera_data_bytes.append(0)
		camera_data_bytes.append_array(get_mat4_bytes(inv_proj_mat))
		camera_data_bytes.append_array(get_mat4_bytes(inv_view_mat))
		
		var camera_data : RID = rd.storage_buffer_create(camera_data_bytes.size()*4, camera_data_bytes.to_byte_array())
		
		uniform = RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = 0
		uniform.add_id(camera_data)
		
		var camera_uniform_set : RID = UniformSetCacheRD.get_cache(shader, 1, [uniform])
		
		var compute_list : int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, image_uniform_set, 0)
		rd.compute_list_bind_uniform_set(compute_list, camera_uniform_set, 1)
		rd.compute_list_set_push_constant(compute_list, push_constants.to_byte_array(), push_constants.size() * 4)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()
	
	
		
func initialize_compute_shader() -> void:
	rd = RenderingServer.get_rendering_device()
	if not rd: return
	
	var glsl_file : RDShaderFile = load("res://shaders/raytracer.glsl")
	shader = rd.shader_create_from_spirv(glsl_file.get_spirv())
	pipeline = rd.compute_pipeline_create(shader)

func get_mat4_bytes(mat : Projection) -> PackedFloat32Array:
	var arr : PackedFloat32Array
	
	arr.append_array(var_to_bytes(mat.x).to_float32_array().slice(1, 5))
	arr.append_array(var_to_bytes(mat.y).to_float32_array().slice(1, 5))
	arr.append_array(var_to_bytes(mat.z).to_float32_array().slice(1, 5))
	arr.append_array(var_to_bytes(mat.w).to_float32_array().slice(1, 5))
	
	return arr
	
func get_mat4_from_transform3D(transform : Transform3D) -> Projection:
	
	var proj : Projection
	var pos : Vector3 = transform.origin
	var basis : Basis = transform.basis
	
	proj.x = Vector4(basis.x.x, basis.x.y, basis.x.z, 0)
	proj.y = Vector4(basis.y.x, basis.y.y, basis.y.z, 0)
	proj.z = Vector4(basis.z.x, basis.z.y, basis.z.z, 0)
	proj.w = Vector4(pos.x, pos.y, pos.z, 1)
	
	return proj
	
	
	
