@tool
extends Path3D

const THREAD_SURFACE = 0
const RISER_SURFACE = 1
const STRINGER_SURFACE = 2

const EPSILON = 0.001

# Controls whether the stair generates a base to the path or not
@export var generate_bottom := true: set = set_generate_bottom
@export var height := 1.0: set = set_height
@export var width := 1.0: set = set_width
@export var step_height := 0.25: set = set_step_height

# Sides and bottom of a stair
@export var stringer_material: Material: set = set_stringer_material

# Vertical sections of the steps
@export var riser_material: Material: set = set_riser_material

# Top of the steps
@export var thread_material: Material: set = set_thread_material

# CSG stuff
@export var use_collision := false: set = set_use_collision
@export_flags_3d_physics var collision_layer := 0: set = set_collision_layer
@export_flags_3d_physics var collision_mask := 0: set = set_collision_mask

var _path_follow: PathFollow3D
var _csg_mesh: CSGMesh3D

func _ready() -> void:
	curve_changed.connect(update_polygon)
	if curve.get_point_count() < 2:
		curve.clear_points()
		curve.add_point(Vector3.ZERO)
		curve.add_point(Vector3.FORWARD)
	_init_children()
	update_polygon()


func set_generate_bottom(p_generate_bottom: bool) -> void:
	generate_bottom = p_generate_bottom
	update_polygon()


func set_height(p_height: float) -> void:
	height = clamp(p_height, 0.001, 100)
	update_polygon()


func set_width(p_width: float) -> void:
	width = clamp(p_width, 0.001, 100)
	update_polygon()


func set_step_height(p_step_height: float) -> void:
	step_height = clamp(p_step_height, 0.001, 100)
	update_polygon()


func set_stringer_material(p_material: Material) -> void:
	stringer_material = p_material
	if _csg_mesh and _csg_mesh.mesh.get_surface_count() >= STRINGER_SURFACE:
		_csg_mesh.mesh.surface_set_material(STRINGER_SURFACE, stringer_material)
	set_riser_material(riser_material)
	set_thread_material(thread_material)
	notify_property_list_changed()


func set_riser_material(p_material: Material) -> void:
	riser_material = p_material
	if _csg_mesh and _csg_mesh.mesh.get_surface_count() >= RISER_SURFACE:
		_csg_mesh.mesh.surface_set_material(
			RISER_SURFACE,
			stringer_material if riser_material == null else riser_material
		)


func set_thread_material(p_material: Material) -> void:
	thread_material = p_material
	if _csg_mesh and _csg_mesh.mesh.get_surface_count() >= THREAD_SURFACE:
		_csg_mesh.mesh.surface_set_material(
			THREAD_SURFACE,
			stringer_material if thread_material == null else thread_material
		)


func set_use_collision(p_use_collision: bool) -> void:
	use_collision = p_use_collision
	if _csg_mesh:
		_csg_mesh.use_collision = use_collision


func set_collision_layer(p_collision_layer: int) -> void:
	collision_layer = p_collision_layer
	if _csg_mesh:
		_csg_mesh.collision_layer = collision_layer


func set_collision_mask(p_collision_mask: int) -> void:
	collision_mask = p_collision_mask
	if _csg_mesh:
		_csg_mesh.collision_mask = collision_mask


func _init_children() -> void:
	if !_csg_mesh:
		_csg_mesh = CSGMesh3D.new()
		add_child(_csg_mesh)

	_csg_mesh.mesh = Mesh.new()
	_csg_mesh.use_collision = use_collision
	_csg_mesh.collision_layer = collision_layer
	_csg_mesh.collision_mask = collision_mask

	if !_path_follow:
		_path_follow = PathFollow3D.new()
		_path_follow.use_model_front = true
		add_child(_path_follow)

	_path_follow.transform = Transform3D.IDENTITY
	_path_follow.loop = false
	_path_follow.progress_ratio = 0.0
	_path_follow.rotation_mode = PathFollow3D.ROTATION_ORIENTED


func _get_vertex_position(progress_ratio: float, h_offset: float, v_offset: float) -> Vector3:
	if !_path_follow:
		return Vector3.ZERO
	_path_follow.progress_ratio = progress_ratio
	_path_follow.h_offset = h_offset
	_path_follow.v_offset = v_offset
	return _path_follow.transform.origin


func update_polygon() -> void:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)

	#    Thread
	#    1----3
	#    |   /|
	#    |  / |
	#    | /  |
	#    |/   |
	#    0----2
	var thread_vertices := PackedVector3Array()
	var thread_uvs := PackedVector2Array()
	var thread_indices := PackedInt32Array()
	var curr_thread_index := 0

	#    Riser
	#    1----3
	#    |   /|
	#    |  / |
	#    | /  |
	#    |/   |
	#    0----2
	var riser_vertices := PackedVector3Array()
	# riser is generated using thread indices

	#    Stringer       BACK       BTM
	#    RIGHT8---12    12---13    0-----4----10
	#         | __/|    |\    |    |    /|    /|
	#         |/   |    | \   |    |   / |   / |
	#    2----6    |    |  \  |    |  /  |  /  |
	#    | __/|\__ |    |   \ |    | /   | /   |
	#    |/   |   \|    |    \|    |/    |/    |
	#    0----4---10    10---11    1-----5----11
	var stringer_vertices := PackedVector3Array()
	var stringer_indices := PackedInt32Array()
	var curr_stringer_index := 0

	var num_steps := height / step_height
	var progress_ratio := 0.0
	var curr_height := 0.0
	var curr_point := Vector3.ZERO

	# Generate steps until end of last step
	for i in range(num_steps):
		progress_ratio = i / num_steps
		curr_height = i * step_height

		if i != 0:
			if generate_bottom:
				curr_point = _get_vertex_position(progress_ratio, -width / 2, 0)  # stringer [4]
			else:
				curr_point = _get_vertex_position(
					progress_ratio, -width / 2, curr_height - step_height
				)
			stringer_vertices.append(curr_point)

			if generate_bottom:
				curr_point = _get_vertex_position(progress_ratio, width / 2, 0)  # stringer [5]
			else:
				curr_point = _get_vertex_position(
					progress_ratio, width / 2, curr_height - step_height
				)
			stringer_vertices.append(curr_point)

			curr_point = _get_vertex_position(
				progress_ratio, -width / 2, curr_height
			)  # stringer [6], riser [4, 8], thread [2, 6]
			thread_vertices.append(curr_point)
			riser_vertices.append(curr_point)
			stringer_vertices.append(curr_point)

			curr_point = _get_vertex_position(
				progress_ratio, width / 2, curr_height
			)  # stringer [7], riser [5, 9], thread [3, 7]
			thread_vertices.append(curr_point)
			riser_vertices.append(curr_point)
			stringer_vertices.append(curr_point)

			# Right Btm Tri [starts at stringer 6]
			stringer_indices.append(curr_stringer_index)
			stringer_indices.append(curr_stringer_index + 4)
			stringer_indices.append(curr_stringer_index - 2)
			# Left Btm Tri
			stringer_indices.append(curr_stringer_index + 1)
			stringer_indices.append(curr_stringer_index - 1)
			stringer_indices.append(curr_stringer_index + 5)
			# Btm Front Tri
			stringer_indices.append(curr_stringer_index - 2)
			stringer_indices.append(curr_stringer_index + 4)
			stringer_indices.append(curr_stringer_index - 1)
			# Btm Back Tri
			stringer_indices.append(curr_stringer_index - 1)
			stringer_indices.append(curr_stringer_index + 4)
			stringer_indices.append(curr_stringer_index + 5)
		else:
			curr_point = _get_vertex_position(
				progress_ratio, -width / 2, curr_height
			)  # stringer [0], riser [0]
			riser_vertices.append(curr_point)
			stringer_vertices.append(curr_point)

			curr_point = _get_vertex_position(
				progress_ratio, width / 2, curr_height
			)  # stringer [1], riser [1]
			riser_vertices.append(curr_point)
			stringer_vertices.append(curr_point)

			# Btm Front Tri [starts at stringer 0]
			stringer_indices.append(curr_stringer_index)
			stringer_indices.append(curr_stringer_index + 4)
			stringer_indices.append(curr_stringer_index + 1)
			# Btm Back Tri
			stringer_indices.append(curr_stringer_index + 1)
			stringer_indices.append(curr_stringer_index + 4)
			stringer_indices.append(curr_stringer_index + 5)

		curr_point = _get_vertex_position(
			progress_ratio, -width / 2, curr_height + step_height
		)  # stringer [2, 8], riser [2, 6], thread [0, 4]
		thread_vertices.append(curr_point)
		riser_vertices.append(curr_point)
		stringer_vertices.append(curr_point)

		curr_point = _get_vertex_position(
			progress_ratio, width / 2, curr_height + step_height
		)  # stringer [3, 9], riser [3, 7], thread [1, 5]
		thread_vertices.append(curr_point)
		riser_vertices.append(curr_point)
		stringer_vertices.append(curr_point)

		thread_uvs.append(Vector2(1,1))
		thread_uvs.append(Vector2(0,1))
		thread_uvs.append(Vector2(1,0))
		thread_uvs.append(Vector2(0,0))
		# Top Front Tri, Front Btm Tri
		thread_indices.append(curr_thread_index)
		thread_indices.append(curr_thread_index + 1)
		thread_indices.append(curr_thread_index + 3)
		# Top Back Tri, Front Top Tri
		thread_indices.append(curr_thread_index)
		thread_indices.append(curr_thread_index + 3)
		thread_indices.append(curr_thread_index + 2)
		# Right Middle Tri
		stringer_indices.append(curr_stringer_index)
		stringer_indices.append(curr_stringer_index + 6)
		stringer_indices.append(curr_stringer_index + 4)
		# Left Middle Tri
		stringer_indices.append(curr_stringer_index + 1)
		stringer_indices.append(curr_stringer_index + 5)
		stringer_indices.append(curr_stringer_index + 7)
		# Right Top Tri
		stringer_indices.append(curr_stringer_index)
		stringer_indices.append(curr_stringer_index + 2)
		stringer_indices.append(curr_stringer_index + 6)
		# Left Top Tri
		stringer_indices.append(curr_stringer_index + 1)
		stringer_indices.append(curr_stringer_index + 7)
		stringer_indices.append(curr_stringer_index + 3)

		curr_stringer_index += 6
		curr_thread_index += 4

	# Generate end of stairs
	var final_height = snappedf(height - step_height * 0.5, step_height)
	if generate_bottom:
		curr_point = _get_vertex_position(1, -width / 2, 0)  # stringer [10]
	else:
		curr_point = _get_vertex_position(
			1, -width / 2, final_height - step_height
		)
	stringer_vertices.append(curr_point)

	if generate_bottom:
		curr_point = _get_vertex_position(1, width / 2, 0)  # stringer [11]
	else:
		curr_point = _get_vertex_position(
			1, width / 2, final_height - step_height
		)
	stringer_vertices.append(curr_point)

	curr_point = _get_vertex_position(1, -width / 2, final_height)  # stringer [12], thread [6]
	thread_vertices.append(curr_point)
	stringer_vertices.append(curr_point)

	curr_point = _get_vertex_position(1, width / 2, final_height)  # stringer [13], thread [7]
	thread_vertices.append(curr_point)
	stringer_vertices.append(curr_point)

	# Back Btm Tri
	stringer_indices.append(curr_stringer_index)
	stringer_indices.append(curr_stringer_index - 1)
	stringer_indices.append(curr_stringer_index - 2)
	# Back Top Tri
	stringer_indices.append(curr_stringer_index)
	stringer_indices.append(curr_stringer_index + 1)
	stringer_indices.append(curr_stringer_index - 1)

	var mesh := ArrayMesh.new()
	# Construct thread surfaces
	if thread_vertices.size() < 4:
		return
	arr[Mesh.ARRAY_VERTEX] = thread_vertices
	arr[Mesh.ARRAY_INDEX] = thread_indices
	arr[Mesh.ARRAY_TEX_UV] = thread_uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(
		THREAD_SURFACE,
		stringer_material if thread_material == null else thread_material
	)
	arr.clear()

	# Construct riser surfaces
	arr.resize(Mesh.ARRAY_MAX)
	if riser_vertices.size() < 4:
		return
	arr[Mesh.ARRAY_VERTEX] = riser_vertices
	arr[Mesh.ARRAY_INDEX] = thread_indices
	arr[Mesh.ARRAY_TEX_UV] = thread_uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(
		RISER_SURFACE,
		stringer_material if riser_material == null else riser_material
	)
	arr.clear()

	# Construct stringer surfaces
	arr.resize(Mesh.ARRAY_MAX)
	if stringer_vertices.size() < 8:
		return
	arr[Mesh.ARRAY_VERTEX] = stringer_vertices
	arr[Mesh.ARRAY_INDEX] = stringer_indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(STRINGER_SURFACE, stringer_material)

	if _csg_mesh:
		_csg_mesh.mesh = mesh
