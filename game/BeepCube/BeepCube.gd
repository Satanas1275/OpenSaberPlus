# BeepCube is the standard cube that will get cut by the sabers
extends Cuttable
class_name BeepCube

# emitted when the cube gets cutted, correct_saber is true if the right saber was used
signal cutted(correct_saber: bool)

@onready var mi := $BeepCubeMesh as MeshInstance3D
@onready var collision_big := $BeepCube_Big/CollisionBig as CollisionShape3D
@onready var collision_small := $BeepCube_Small/CollisionSmall as CollisionShape3D
@onready var slice_particles := $SliceParticles as BeepCubeSliceParticles

var which_saber: int
var is_dot: bool

# the note info is kept around so the per-note Noodle animation can be
# applied each physics frame while the cube is flying towards the player
var note_info: ColorNoteInfo

# previous animation frame values, so we can incrementally adjust the node
var _anim_last_pos := Vector3.ZERO
var _anim_last_rot := Vector3.ZERO
var _anim_base_scale := Vector3.ONE

# base forward flight direction, captured at spawn (before Noodle animation
# mutates the rotation). Noodle spinning notes rotate their visual orientation
# but must keep flying along the base lane axis toward the player.
var _forward := Vector3.FORWARD
# base orientation basis at spawn, used to apply Noodle offsetPosition in the
# note's own (un-spun) coordinate space.
var _anim_base_basis := Basis()
# distance travelled along _forward from spawn to the hit plane, used to drive
# the Noodle animation progress from the actual flight position.
var _spawn_dist := 1.0
# base flight distance covered so far (excluding the Noodle animation offset).
var _base_travelled := 0.0

# we store the mesh here as part of the BeepCube for easier access because we will
# reuse it when we create the cut cube pieces
var _mesh: Mesh
var _mat: ShaderMaterial
@export var min_speed := 0.5

var piece_left : CutPiece = null
var piece_right : CutPiece = null
var arc_head = false
var arc_tail = false
var chain_head = false

func _ready() -> void:
	_mat = mi.material_override as ShaderMaterial
	_mesh = mi.mesh
	
	# init our cut pieces with unique copies of our own material for reference,
	# and enable "bouncy" physics behavior
	piece_left = CutPiece.new(self, _mesh, _mat.duplicate(true) as ShaderMaterial, true)
	piece_right = CutPiece.new(self, _mesh, _mat.duplicate(true) as ShaderMaterial, true)
	
	# slice_particles are within cube's tree, but want then to move in global space
	slice_particles.top_level = true
	
func spawn(note_info: ColorNoteInfo, current_beat: float) -> void:
	# re-enable our process_mode first otherwise it seems like Godot-internals
	# can behave weirdly (ex. AnimationPlayer won't always play correctly)
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	self.note_info = note_info
	_anim_last_pos = Vector3.ZERO
	_anim_last_rot = Vector3.ZERO
	
	var color := note_info.custom_color if note_info.has_custom_color \
			else (Map.color_left if note_info.color == 0 else Map.color_right)
	var njs := 0.0
	if note_info.note_speed > 0.0:
		njs = note_info.note_speed
	else:
		njs = Map.current_difficulty.note_jump_movement_speed
	var default_njs := Map.current_difficulty.note_jump_movement_speed
	if default_njs <= 0.0:
		default_njs = 9.0
	speed = Constants.BEAT_DISTANCE * Map.current_info.beats_per_minute * 0.016666666666666667 * (njs / default_njs)
	beat = note_info.beat
	which_saber = note_info.color
	is_dot = note_info.cut_angle >= Constants.DIRECTION8_COMPARE
	
	if is_dot:
		(collision_big.shape as BoxShape3D).size.y = 0.8
	else:
		(collision_big.shape as BoxShape3D).size.y = 0.5
	
	scale = Vector3(Settings.block_size/100.,Settings.block_size/100.,Settings.block_size/100.)
	_anim_base_scale = scale
	if note_info.has_custom_scale:
		scale *= note_info.spawn_scale
		_anim_base_scale = scale
	
	# "fake" notes are invisible and don't collide; they exist for visuals only
	if note_info.fake:
		mi.visible = false
		set_collision_disabled(true)
		return
	
	var pos := note_info.custom_position if note_info.has_custom_position \
			else Vector2(note_info.line_index, note_info.line_layer)
	transform.origin.x = Settings.LANE_DISTANCE_X * pos.x + Settings.LANE_ZERO_X
	transform.origin.y = Constants.LANE_DISTANCE_Y * pos.y + Constants.LAYER_ZERO_Y
	transform.origin.z = -(note_info.beat - current_beat) * Constants.BEAT_DISTANCE
	# per-note noteJumpStartBeatOffset shifts how late the note arrives
	transform.origin.z -= note_info.start_beat_offset * Constants.BEAT_DISTANCE
	
	add_lane_rotation(note_info.rotation)
	
	rotation.z = note_info.cut_angle
	
	# capture the flight direction from the base (un-animated) orientation
	_forward = transform.basis.orthonormalized().z
	_anim_base_basis = transform.basis.orthonormalized()
	_spawn_dist = maxf(-transform.origin.dot(_forward), 0.001)
	_base_travelled = 0.0
	
	# when the note has an extra spawn distance (noteJumpStartBeatOffset), it must
	# still reach the cut plane exactly at its beat: boost the flight speed so the
	# extra distance is covered within the remaining beats.
	if absf(note_info.start_beat_offset) > 0.001:
		var beats_to_hit := maxf(note_info.beat - current_beat, 0.001)
		var needed := _spawn_dist / (beats_to_hit * 60.0 / Map.current_info.beats_per_minute)
		speed = maxf(speed, needed)
	
	piece_left.set_color(color, is_dot)
	piece_right.set_color(color, is_dot)
	_mat.set_shader_parameter(&"color", color)
	_mat.set_shader_parameter(&"is_dot", is_dot)
	_mat.set_shader_parameter(&"arrows_enabled", Settings.arrows_enabled)
	# since cube instances get recycled, we gotta reset cubes that were chain
	# heads in a past life
	_mat.set_shader_parameter(&"is_chain_head", false)
	piece_left.set_chain_head(false)
	piece_right.set_chain_head(false)
	chain_head = false
	
	# separate cube collision layers to allow a diferent collider on right/wrong cuts.
	# opposing collision layers (ie. right note & left saber) will be placed on the
	# smalling collision shape, while similar collision layers (ie right note &
	# right saber) are placed on the larger collision shape.
	var is_left_note := note_info.color == 0
	var big_coll_area := $BeepCube_Big as Area3D
	big_coll_area.collision_layer = 0x0
	big_coll_area.set_collision_layer_value(CollisionLayerConstants.LeftNote_bit, is_left_note)
	big_coll_area.set_collision_layer_value(CollisionLayerConstants.RightNote_bit, not is_left_note)
	var small_coll_area := $BeepCube_Small as Area3D
	small_coll_area.collision_layer = 0x0
	small_coll_area.set_collision_layer_value(CollisionLayerConstants.LeftNote_bit, not is_left_note)
	small_coll_area.set_collision_layer_value(CollisionLayerConstants.RightNote_bit, is_left_note)
	
	# play the spawn animation when this cube enters the scene
	var anim := $AnimationPlayer as AnimationPlayer
	var anim_speed := Map.current_difficulty.note_jump_movement_speed / 9.0
	anim.speed_scale = maxf(min_speed,anim_speed)
	if not note_info.disable_spawn_effect:
		anim.play(&"Spawn")
	
	slice_particles.reset()
	mi.visible = true

func _physics_process(delta: float) -> void:
	# replicate Cuttable._physics_process so we can layer the Noodle animation
	# offsets on top of the travelled base position
	if Scoreboard.paused or not is_visible_in_tree() or not Map.current_info: return
	
	transform.origin += speed * delta * _forward
	_base_travelled += speed * delta
	var rz := global_transform.origin.dot(_forward)
	
	# fake notes are invisible and pass through everything
	if note_info != null and note_info.fake:
		return
	
	if rz > -3.0:
		set_collision_disabled(false)
	if rz > Constants.MISS_Z:
		on_miss()
	
	if note_info == null or not note_info.has_animation:
		return
	# flight fraction driven by the note's base travel along its direction:
	# 0 at spawn, 1 at the hit plane (the plane the player cuts on). The Noodle
	# animation offset is excluded so it doesn't skew the timing.
	var flight01 := clampf(_base_travelled / _spawn_dist, 0.0, 1.0)
	var pos := _anim_state(note_info.animation_position_frames, flight01, Vector3.ZERO)
	var rot := _anim_state(note_info.animation_rotation_frames, flight01, Vector3.ZERO)
	var scl := _anim_state(note_info.animation_scale_frames, flight01, Vector3.ONE)
	
	transform.origin += _anim_base_basis * (pos - _anim_last_pos)
	rotation.x += deg_to_rad(rot.x - _anim_last_rot.x)
	rotation.y += deg_to_rad(rot.y - _anim_last_rot.y)
	rotation.z += deg_to_rad(rot.z - _anim_last_rot.z)
	scale = _anim_base_scale * scl
	
	_anim_last_pos = pos
	_anim_last_rot = rot

# evaluate a Noodle keyframe list at a flight fraction (0 = spawn, 1 = hit plane),
# interpolating between keyframes with each segment's easing curve.
static func _anim_state(frames: Array, time: float, default_value: Vector3) -> Vector3:
	if frames.is_empty():
		return default_value
	var t := clampf(time, 0.0, 1.0)
	var first: Dictionary = frames[0]
	var last: Dictionary = frames[frames.size() - 1]
	if t <= float(first["t"]):
		return first["v"] as Vector3
	if t >= float(last["t"]):
		return last["v"] as Vector3
	for i in range(frames.size() - 1):
		var a: Dictionary = frames[i]
		var b: Dictionary = frames[i + 1]
		var ta := float(a["t"])
		var tb := float(b["t"])
		if t >= ta and t <= tb:
			if tb <= ta:
				return b["v"] as Vector3
			var x := clampf((t - ta) / (tb - ta), 0.0, 1.0)
			var easing := b["e"] as String
			var ex := ColorNoteInfo.anim_ease(easing, x) if not easing.is_empty() else x
			return (a["v"] as Vector3).lerp(b["v"] as Vector3, ex)
	return last["v"] as Vector3

# call this when clearing the track
func clear_from_track() -> void:
	hide_cube()
	piece_left.hide_piece()
	piece_right.hide_piece()
	if ! is_released():
		release()

func hide_cube() -> void:
	mi.visible = false
	set_collision_disabled(true)
	# disable processing on this node and all children to help with performance
	process_mode = Node.PROCESS_MODE_DISABLED

func make_chain_head() -> void:
	_mat.set_shader_parameter(&"is_chain_head", true)
	piece_left.set_chain_head(true)
	piece_right.set_chain_head(true)
	chain_head = true

func on_miss() -> void:
	Scoreboard.bad_cut(global_transform.origin+Vector3(0,0,-3.5), lane_rotation, "miss")
	hide_cube()
	release()

func set_collision_disabled(value: bool) -> void:
	collision_big.disabled = value
	collision_small.disabled = value
	
func set_arc_head() -> void:
	arc_head = true

func set_arc_tail() -> void:
	arc_tail = true

func cut(saber: LightSaber, cut_speed: Vector3, cut_plane: Plane, controller: BeepSaberController) -> void:
	# compute the angle between the cube orientation and the cut direction
	cut_speed = cut_speed.rotated(Vector3(0,1,0), -rotation.y)
	var cut_direction_xy := -Vector3(cut_speed.x, cut_speed.y, 0.0).normalized()
	var base_cut_angle_accuracy := global_transform.basis.orthonormalized().y.dot(cut_direction_xy)
	var cut_distance := cut_plane.distance_to(global_transform.origin)
	var distance_scale := 100./Settings.block_size
	
	if saber.type == which_saber or Map.one_saber or Settings.handedness != 0:
		var cut_angle_accuracy := clampf((base_cut_angle_accuracy-0.7)/0.3, 0.0, 1.0)
		if is_dot or not Settings.arrows_enabled: #ignore angle if is a dot
			cut_angle_accuracy = 1.0
		var cut_distance_accuracy := clampf((0.1 - absf(cut_distance*distance_scale))/0.1, 0.0, 1.0)
		var travel_distance_factor := controller.movement_aabb.get_longest_axis_size()
		travel_distance_factor = clampf((travel_distance_factor-0.5)/0.5, 0.0, 1.0)
		# allows a bit of save margin where the beat is considered 100% correct
		var beat_accuracy := clampf((1.0 - absf(global_transform.origin.z)) / 0.5, 0.0, 1.0)
		Scoreboard.note_cut(saber, transform.origin, lane_rotation, beat_accuracy, cut_angle_accuracy, cut_distance_accuracy, travel_distance_factor, arc_head, arc_tail, chain_head)
		cutted.emit(true)
	else:
		Scoreboard.bad_cut(transform.origin, lane_rotation, "wrong saber")
		cutted.emit(false)
	
	# reset the movement tracking volume for the next cut
	controller.reset_movement_aabb()
	
	hide_cube()
	if Settings.cube_cuts_falloff:
		_start_cut_pieces(cut_plane)
		# release() will be called by Cuttable class when it sees both pieces die
	else:
		release() # release now instead of waiting for cut pieces to die off

# cut the cube by creating two rigid bodies and using a CSGBox to create
# the cut plane
func _start_cut_pieces(cutplane: Plane) -> void:
	piece_left.scale = Vector3(Settings.block_size,Settings.block_size,Settings.block_size)/100.
	piece_right.scale = Vector3(Settings.block_size,Settings.block_size,Settings.block_size)/100.
	piece_left.global_transform = global_transform
	piece_right.global_transform = global_transform
	
	# calculate angle and position of the cut
	#var cut_angle_abs := Vector2(cutplane.normal.x, cutplane.normal.y).angle()
	
	_piece_death_count = 0

	var p := cutplane # ARP: fix rot global_transform * 
	piece_left.start_cut_plane(-p.normal, -p.d) # ARP: scale p.d for block size?
	piece_right.start_cut_plane(p.normal, p.d)
	
	# some impulse so the cube half moves
	var split_vector := p.normal * 2.0
	piece_left.apply_central_impulse(-split_vector) #piece_left.transform * -split_vector)
	piece_right.apply_central_impulse(split_vector)#piece_right.transform * split_vector)
	
	#slice_particles.global_transform.origin = global_transform.origin
	#slice_particles.rotation.z = cut_angle_abs+TAU*0.25
	#slice_particles.fire()
