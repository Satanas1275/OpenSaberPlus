extends Node3D
class_name EventDriver

var ring_rot_speed := 0.0
var ring_rot_inv_dir := false
var rings_in := false

# multiplier applied to light colours when colour boost is active
var _boost_mult := 1.0

var left_color: Color
var right_color: Color

@onready var ring_holder := $Level/rings as Node3D
@onready var diagonal_lasers_holder := $Level/DiagonalLasers as Node3D
@onready var diagonal_lasers := [
	$Level/DiagonalLasers/laser1,
	$Level/DiagonalLasers/laser2,
	$Level/DiagonalLasers/laser3,
	$Level/DiagonalLasers/laser4,
	$Level/DiagonalLasers/laser5,
	$Level/DiagonalLasers/laser6,
	$Level/DiagonalLasers/laser7,
	$Level/DiagonalLasers/laser8,
	$Level/DiagonalLasers/laser9,
	$Level/DiagonalLasers/laser10
]
@onready var square_lasers_holder := $Level/SquareLasers as Node3D
@onready var left_waving_lasers_holder := $Level/LeftWavingLasers as Node3D
@onready var right_waving_lasers_holder := $Level/RightWavingLasers as Node3D
@onready var track_lights_holder := $Level/TrackLights as Node3D

@onready var sphere_material := ($Level/Sphere as MeshInstance3D).material_override as ShaderMaterial
@onready var diagonal_lasers_material := ($Level/DiagonalLasers/laser1/Bar7 as MeshInstance3D).material_override as StandardMaterial3D
@onready var square_lasers_material := ($Level/SquareLasers/Bar7 as MeshInstance3D).material_override as StandardMaterial3D
@onready var left_waving_lasers_material := ($Level/LeftWavingLasers/laser1/Bar7 as MeshInstance3D).material_override as StandardMaterial3D
@onready var right_waving_lasers_material := ($Level/RightWavingLasers/laser1/Bar7 as MeshInstance3D).material_override as StandardMaterial3D
@onready var track_lights_material := ($Level/TrackLights/Bar1 as MeshInstance3D).material_override as StandardMaterial3D
@onready var floor_mesh := ($Level/floor as MeshInstance3D).mesh as PlaneMesh
@onready var floor_material := ($Level/floor as MeshInstance3D).material_override as StandardMaterial3D
@onready var track_lights_right := $Level/TrackLights/Bar1 as MeshInstance3D
@onready var track_lights_left := $Level/TrackLights/Bar2 as MeshInstance3D
@onready var end_path := $Level/Endpath as MeshInstance3D

@onready var ring_anim_player := $Level/rings/AnimationPlayer as AnimationPlayer
@onready var left_laser_anim_player := $Level/LeftWavingLasers/AnimationPlayer as AnimationPlayer
@onready var right_laser_anim_player := $Level/RightWavingLasers/AnimationPlayer as AnimationPlayer

@export var disabled := false

func _ready() -> void:
	track_lights_holder.hide()
	
	set_background_texture()
	
	# get_rendering_device() returns null in opengl, meaning this block is skipped in vulkan
	
	set_background()
	
	if not RenderingServer.get_rendering_device():
		sphere_material.set_shader_parameter("contrast", 1)
		for background_side in 5:
			var shader_param := StringName("bg_%s_intensity_mult" % background_side)
			sphere_material.set_shader_parameter(
				shader_param,
				(sphere_material.get_shader_parameter(shader_param) as float) * 2.2
			)

func set_background_texture() -> void:
	if not Settings.background_texture.begins_with("res:"):
		var img := Image.new()
		if OK == img.load(Constants.APPDATA_PATH + "Backgrounds/" + Settings.background_texture):
			img.flip_x()
			sphere_material.set_shader_parameter("bg_base", ImageTexture.create_from_image(img))
			return
		Settings.background_texture = Settings.default_values["background_texture"]
	var texture : Resource = null
	texture = load(Settings.background_texture)
	sphere_material.set_shader_parameter("bg_base", texture)	

func set_background() -> void:
	var width_scale := 2 * Settings.LANE_DISTANCE_X / 3.
	var track_lights_width := track_lights_right.get_aabb().size.x
	track_lights_right.global_transform.origin.x = track_lights_width / 2 + 2 * Settings.LANE_DISTANCE_X - .01
	track_lights_left.global_transform.origin.x = -track_lights_right.transform.origin.x
	end_path.scale.z = track_lights_right.global_transform.origin.x + track_lights_width / 2 - .01
	floor_mesh.size.y = 4 * Settings.LANE_DISTANCE_X
	($Level/floor/line1).global_transform.origin.x = Settings.LANE_DISTANCE_X
	($Level/floor/line2).global_transform.origin.x = -Settings.LANE_DISTANCE_X
	($Level/floor/line3).global_transform.origin.x = 2 * Settings.LANE_DISTANCE_X
	($Level/floor/line4).global_transform.origin.x = -2 * Settings.LANE_DISTANCE_X
	($Level/floor).scale.z = 1
	for laser in diagonal_lasers:
		laser.transform.origin.x = 4.5 * width_scale * sign(laser.transform.origin.x)
	
	if Settings.background == "simple":
		ring_holder.hide()
		diagonal_lasers_holder.hide()
		square_lasers_holder.hide()
		left_waving_lasers_holder.hide()
		right_waving_lasers_holder.hide()
		($Level/DiagonalLasers/laser1).hide()
		($Level/DiagonalLasers/laser2).hide()
		($Level/DiagonalLasers/laser3).hide()
		($Level/DiagonalLasers/laser4).hide()
		($Level/DiagonalLasers/laser5).hide()
		($Level/DiagonalLasers/laser6).hide()
		($Level/DiagonalLasers/laser7).hide()
		($Level/DiagonalLasers/laser8).hide()
		($Level/DiagonalLasers/laser9).hide()
		($Level/DiagonalLasers/laser10).hide()
		track_lights_holder.hide()
		set_all_off()
		turn_light_on(EventInfo.TYPE_FLOOR_LIGHTS, Color.WHITE)
		disabled = true
	else:
		ring_holder.show()
		diagonal_lasers_holder.show()
		square_lasers_holder.show()
		left_waving_lasers_holder.show()
		right_waving_lasers_holder.show()
		($Level/DiagonalLasers/laser1).show()
		($Level/DiagonalLasers/laser2).show()
		($Level/DiagonalLasers/laser3).show()
		($Level/DiagonalLasers/laser4).show()
		($Level/DiagonalLasers/laser5).show()
		($Level/DiagonalLasers/laser6).show()
		($Level/DiagonalLasers/laser7).show()
		($Level/DiagonalLasers/laser8).show()
		($Level/DiagonalLasers/laser9).show()
		($Level/DiagonalLasers/laser10).show()
		track_lights_holder.hide()
		if Settings.background == "dynamic":
			disabled = false
			set_all_on(Settings.color_left, Settings.color_right)
		else:
			disabled = true
			set_all_off()
			turn_light_on(EventInfo.TYPE_FLOOR_LIGHTS, Color.WHITE)

func _process(delta: float) -> void:
	# update the level animations
	#procces ring rotations
	if ring_rot_speed != 0.0:
		for ring in ring_holder.get_children():
			if ring is Node3D:
				var rot := ring_rot_speed
				if ring_rot_inv_dir: rot *= -1
				(ring as Node3D).rotate_z((rot * delta) * (float(ring.get_index()+1)/5))

# apply Noodle "AnimateTrack" custom events that target nodes that exist in
# our level (e.g. moving the SquareLasers holder).  Tracks we don't have are
# ignored, matching maps (like Planet tracks in Aurora maps) do nothing.
func apply_map_custom_tracks() -> void:
	if Map.custom_tracks.is_empty() or disabled:
		return
	for track_name: String in Map.custom_tracks:
		var node := _find_level_node(track_name)
		if node == null:
			continue
		var entries: Array = Map.custom_tracks[track_name]
		if entries.is_empty():
			continue
		# apply the settled (last) keyframe of the final track event
		var entry := entries[entries.size() - 1] as Dictionary
		var animation := entry.get("animation", {}) as Dictionary
		node.position = _anim_end_value(animation, "offsetPosition", Vector3.ZERO)
		node.rotation_degrees = _anim_end_value(animation, "localRotation", Vector3.ZERO)
		node.scale = _anim_end_value(animation, "scale", node.scale)

func _find_level_node(track_name: String) -> Node3D:
	var level := $Level as Node3D
	for child in level.get_children():
		if child is Node3D and child.name.to_lower() == track_name.to_lower():
			return child as Node3D
	return null

func _anim_end_value(animation: Dictionary, key: String, default_value: Vector3) -> Vector3:
	var frames: Variant = animation.get(key)
	if frames is Array and not (frames as Array).is_empty():
		var last: Variant = (frames as Array)[(frames as Array).size() - 1]
		if last is Array and (last as Array).size() >= 3:
			return Vector3(float(last[0]), float(last[1]), float(last[2]))
	return default_value

func update_left_color(color: Color) -> void:
	left_color = color
	turn_light_on(EventInfo.TYPE_DIAGONAL_LASERS, color)
	turn_light_on(EventInfo.TYPE_LEFT_WAVING_LASERS, color)
	turn_light_on(EventInfo.TYPE_RIGHT_WAVING_LASERS, color)

func update_right_color(color: Color) -> void:
	right_color = color
	turn_light_on(EventInfo.TYPE_SQUARE_LASERS, color)
	turn_light_on(EventInfo.TYPE_FLOOR_LIGHTS, color)

func set_all_off() -> void:
	if disabled:
		for i in range(1,4):
			turn_light_off(i)
		ring_holder.visible = false
	else:
		for i in range(5):
			turn_light_off(i)

func set_all_on(left: Color, right: Color) -> void:
	if !disabled:
		update_left_color(left)
		update_right_color(right)
		ring_holder.visible = true

func process_event(data: EventInfo) -> void:
	if disabled: return
	if data.type in range(0,5):
		match data.value:
			EventInfo.VALUE_LIGHTS_OFF:
				turn_light_off(data.type)
				return
		var color: Color
		match data.value:
			EventInfo.VALUE_LIGHTS_RIGHT_ON:
				color = right_color
			EventInfo.VALUE_LIGHTS_RIGHT_FLASH:
				color = right_color
			EventInfo.VALUE_LIGHTS_RIGHT_FADE:
				color = right_color
			EventInfo.VALUE_LIGHTS_FADE_TO_RIGHT:
				color = right_color
			EventInfo.VALUE_LIGHTS_LEFT_ON:
				color = left_color
			EventInfo.VALUE_LIGHTS_LEFT_FLASH:
				color = left_color
			EventInfo.VALUE_LIGHTS_LEFT_FADE:
				color = left_color
			EventInfo.VALUE_LIGHTS_FADE_TO_LEFT:
				color = left_color
			EventInfo.VALUE_LIGHTS_WHITE_ON:
				color = Color.WHITE
			EventInfo.VALUE_LIGHTS_WHITE_FLASH:
				color = Color.WHITE
			EventInfo.VALUE_LIGHTS_WHITE_FADE:
				color = Color.WHITE
			EventInfo.VALUE_LIGHTS_FADE_TO_WHITE:
				color = Color.WHITE
		if _boost_mult != 1.0:
			color = color * _boost_mult
		# brightness from v3/v4 light colour events lives in float_value
		if data.float_value > 0.0:
			color = color * data.float_value
		match data.value:
			EventInfo.VALUE_LIGHTS_RIGHT_ON:
				turn_light_on(data.type, color)
			EventInfo.VALUE_LIGHTS_RIGHT_FLASH:
				flash_light_on(data.type, color)
			EventInfo.VALUE_LIGHTS_RIGHT_FADE:
				flash_light_then_fade_off(data.type, color)
			EventInfo.VALUE_LIGHTS_FADE_TO_RIGHT:
				fade_light_from_current(data.type, color)
			EventInfo.VALUE_LIGHTS_LEFT_ON:
				turn_light_on(data.type, color)
			EventInfo.VALUE_LIGHTS_LEFT_FLASH:
				flash_light_on(data.type, color)
			EventInfo.VALUE_LIGHTS_LEFT_FADE:
				flash_light_then_fade_off(data.type, color)
			EventInfo.VALUE_LIGHTS_FADE_TO_LEFT:
				fade_light_from_current(data.type, color)
			EventInfo.VALUE_LIGHTS_WHITE_ON:
				turn_light_on(data.type, color)
			EventInfo.VALUE_LIGHTS_WHITE_FLASH:
				flash_light_on(data.type, color)
			EventInfo.VALUE_LIGHTS_WHITE_FADE:
				flash_light_then_fade_off(data.type, color)
			EventInfo.VALUE_LIGHTS_FADE_TO_WHITE:
				fade_light_from_current(data.type, color)
	else:
		match data.type:
			EventInfo.TYPE_RING_SPIN:
				ring_rot_speed = data.float_value
			EventInfo.TYPE_COLOR_BOOST:
				_boost_mult = 1.6 if data.value > 0 else 1.0
			8:
				var ringtween := ring_holder.create_tween()
				if absf(ring_rot_speed) < 1.0:
					ring_rot_inv_dir = not ring_rot_inv_dir
				@warning_ignore("return_value_discarded")
				ringtween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).tween_property(self, ^"ring_rot_speed", 0.0, 2.0).from(3.0)
				ringtween.play()
			9:
				ring_anim_player.stop(false)
				ring_anim_player.play(&"out" if rings_in else &"in")
				rings_in = not rings_in
			12:
				var val := float(data.value) * 0.125
				left_laser_anim_player.speed_scale = val
				left_laser_anim_player.seek(randf_range(0.0, left_laser_anim_player.current_animation_length), true)
			13:
				var val := float(data.value) * 0.125
				right_laser_anim_player.speed_scale = val
				right_laser_anim_player.seek(randf_range(0.0, right_laser_anim_player.current_animation_length), true)

var prev_tweeners: Array[Tween] = [null,null,null,null,null]

func stop_prev_tween(type: int) -> void:
	if prev_tweeners[type] != null:
		prev_tweeners[type].kill()
		prev_tweeners[type] = null

func turn_light_off(type: int) -> void:
	stop_prev_tween(type)
	_on_Tween_tween_step(Color.BLACK, type)
	match type:
		EventInfo.TYPE_DIAGONAL_LASERS:
			diagonal_lasers_holder.visible = false
			diagonal_lasers_material.albedo_color = Color.BLACK
		EventInfo.TYPE_SQUARE_LASERS:
			square_lasers_holder.visible = false
			square_lasers_material.albedo_color = Color.BLACK
		EventInfo.TYPE_LEFT_WAVING_LASERS:
			left_waving_lasers_holder.visible = false
			left_waving_lasers_material.albedo_color = Color.BLACK
		EventInfo.TYPE_RIGHT_WAVING_LASERS:
			right_waving_lasers_holder.visible = false
			right_waving_lasers_material.albedo_color = Color.BLACK
		EventInfo.TYPE_FLOOR_LIGHTS:
			track_lights_holder.visible = false
			track_lights_material.albedo_color = Color.BLACK
			floor_material.albedo_color = Color.BLACK
	
func turn_light_on(type: int, color: Color) -> void:
	sphere_material.set_shader_parameter("bg_%d_tint"%type, color)
	stop_prev_tween(type)
	_on_Tween_tween_step(color, type)
	match type:
		EventInfo.TYPE_DIAGONAL_LASERS:
			diagonal_lasers_holder.visible = true
			diagonal_lasers_material.albedo_color = color
		EventInfo.TYPE_SQUARE_LASERS:
			square_lasers_holder.visible = true
			square_lasers_material.albedo_color = color
		EventInfo.TYPE_LEFT_WAVING_LASERS:
			left_waving_lasers_holder.visible = true
			left_waving_lasers_material.albedo_color = color
		EventInfo.TYPE_RIGHT_WAVING_LASERS:
			right_waving_lasers_holder.visible = true
			right_waving_lasers_material.albedo_color = color
		EventInfo.TYPE_FLOOR_LIGHTS:
			track_lights_holder.visible = true
			track_lights_material.albedo_color = color
			floor_material.albedo_color = color

func flash_light_on(type: int, color: Color) -> void:
	sphere_material.set_shader_parameter("bg_%d_tint"%type, color)
	fade_light(type, color * 3.0, color, false, Tween.TRANS_LINEAR, Tween.EASE_OUT)

func flash_light_then_fade_off(type: int, color: Color) -> void:
	sphere_material.set_shader_parameter("bg_%d_tint"%type, color)
	fade_light(type, color * 3.0, Color.BLACK, true, Tween.TRANS_QUAD, Tween.EASE_IN)

func fade_light_from_current(type: int, to_color: Color) -> void:
	var current_color: Color
	match type:
		EventInfo.TYPE_DIAGONAL_LASERS:
			current_color = diagonal_lasers_material.albedo_color
		EventInfo.TYPE_SQUARE_LASERS:
			current_color = square_lasers_material.albedo_color
		EventInfo.TYPE_LEFT_WAVING_LASERS:
			current_color = left_waving_lasers_material.albedo_color
		EventInfo.TYPE_RIGHT_WAVING_LASERS:
			current_color = right_waving_lasers_material.albedo_color
		EventInfo.TYPE_FLOOR_LIGHTS:
			current_color = floor_material.albedo_color
	fade_light(type, current_color, to_color, false, Tween.TRANS_LINEAR, Tween.EASE_IN)

func fade_light(type: int, from: Color, to: Color, turn_off_after_fade: bool, trans_type: Tween.TransitionType, ease_type: Tween.EaseType) -> void:
	stop_prev_tween(type)
	
	var group: Node3D
	var material: Array[StandardMaterial3D] = []
	match type:
		EventInfo.TYPE_DIAGONAL_LASERS:
			group = diagonal_lasers_holder
			material = [diagonal_lasers_material]
		EventInfo.TYPE_SQUARE_LASERS:
			group = square_lasers_holder
			material = [square_lasers_material]
		EventInfo.TYPE_LEFT_WAVING_LASERS:
			group = left_waving_lasers_holder
			material = [left_waving_lasers_material]
		EventInfo.TYPE_RIGHT_WAVING_LASERS:
			group = right_waving_lasers_holder
			material = [right_waving_lasers_material]
		EventInfo.TYPE_FLOOR_LIGHTS:
			group = track_lights_holder
			material = [track_lights_material, floor_material]
	
	group.visible = true
	
	var tween := group.create_tween()
	@warning_ignore("return_value_discarded")
	tween.set_parallel().set_trans(trans_type).set_ease(ease_type)
	for m in material:
		@warning_ignore("return_value_discarded")
		tween.tween_property(m, ^"albedo_color", to, 1).from(from)
	@warning_ignore("return_value_discarded")
	tween.tween_method(_on_Tween_tween_step.bind(type), from, to, 1)
	tween.play()
	prev_tweeners[type] = tween
	await tween.finished
	if turn_off_after_fade:
		group.visible = false
		tween.kill()
		_on_Tween_tween_step(Color.BLACK, type)

func _on_Tween_tween_step(value: Color, id: int) -> void:
	sphere_material.set_shader_parameter("bg_%d_intensity"%id,value.v)
