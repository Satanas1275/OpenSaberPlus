extends RefCounted
class_name ColorNoteInfo

var beat: float
var line_index: float
var line_layer: float
var color: int # 0=left, 1=right
var cut_angle: float
var rotation: float

# Chroma / Noodle Extensions per-note overrides
var has_custom_color := false
var custom_color := Color.WHITE
var has_custom_scale := false
var spawn_scale := Vector3.ONE
# Noodle Extensions "position" override, in line_space units (x, y). When set,
# it replaces the integer grid computed from lineIndex/lineLayer, allowing floats
# (e.g. [1.5, 2.0]).
var has_custom_position := false
var custom_position := Vector2.ZERO
var note_speed := 0.0 # 0 = use difficulty note jump movement speed
var start_beat_offset := 0.0 # per-note noteJumpStartBeatOffset override
var fake := false
var disable_spawn_effect := false

# Noodle animation, as two keyframes (spawn value -> settled value)
var animation_position := Vector3.ZERO
var animation_position_to := Vector3.ZERO
var animation_rotation := Vector3.ZERO
var animation_rotation_to := Vector3.ZERO
var animation_scale := Vector3.ONE
var animation_scale_to := Vector3.ONE
var has_animation := false

# last keyframe time of each animation, in fractions of the note jump.
# The animation holds its final value once this fraction of the flight is over.
var animation_position_duration := 1.0
var animation_rotation_duration := 1.0
var animation_scale_duration := 1.0

@warning_ignore("shadowed_variable")
func _init(beat: float, line_index: float, line_layer: float, color: int, cut_angle: float, rotation_degrees: float) -> void:
	self.beat = beat
	self.line_index = Utils.adjust_horizontal(line_index)
	self.line_layer = Utils.adjust_vertical(line_layer)
	self.color = Utils.adjust_color(color)
	self.cut_angle = cut_angle
	self.rotation = Utils.adjust_lane_rotation(rotation_degrees * (PI/180.))
	if abs(Settings.gradual_rotation) > Constants.ROTATION_EPS:
		self.rotation += Settings.gradual_rotation * beat

static func new_v2(note_dict: Dictionary) -> ColorNoteInfo:
	var info := ColorNoteInfo.new(
		Utils.get_float(note_dict, "_time", 0.0),
		Utils.precise_measurement(Utils.get_float(note_dict, "_lineIndex", 0)),
		Utils.precise_measurement(Utils.get_float(note_dict, "_lineLayer", 0)),
		int(Utils.get_float(note_dict, "_type", -1.0)),
		Utils.precise_angle_rad(Utils.get_float(note_dict, "_cutDirection", 0), 0),
		Utils.get_float(note_dict, "r", 0)
	)
	info.parse_custom_data(Utils.get_dict(note_dict, "_customData", {}), true)
	return info

static func new_v3(note_dict: Dictionary) -> ColorNoteInfo:
	var info := ColorNoteInfo.new(
		Utils.get_float(note_dict, "b", 0.0),
		Utils.precise_measurement(Utils.get_float(note_dict, "x", 0)),
		Utils.precise_measurement(Utils.get_float(note_dict, "y", 0)),
		int(Utils.get_float(note_dict, "c", 0)),
		Utils.precise_angle_rad(Utils.get_float(note_dict, "d", 0), Utils.get_float(note_dict, "a", 0)),
		Utils.get_float(note_dict, "r", 0)
	)
	info.parse_custom_data(Utils.get_dict(note_dict, "customData", {}), false)
	return info

func parse_custom_data(custom_data: Dictionary, v2: bool) -> void:
	if custom_data.is_empty():
		return
	var prefix := "_" if v2 else ""
	
	var color_v: Variant = custom_data.get(prefix + "color")
	if color_v is Array or color_v is Dictionary:
		has_custom_color = true
		custom_color = _parse_color(color_v)
	
	var scale_v: Variant = custom_data.get(prefix + "scale")
	if scale_v is Array and (scale_v as Array).size() >= 3:
		has_custom_scale = true
		var arr := scale_v as Array
		spawn_scale = Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	
	var position_v: Variant = custom_data.get(prefix + "position")
	if position_v is Array and (position_v as Array).size() >= 2:
		has_custom_position = true
		var p := position_v as Array
		custom_position = Vector2(float(p[0]), float(p[1]))
		if Settings.flip & Constants.FLIP_HORIZONTAL:
			custom_position.x = 3.0 - custom_position.x
		if Settings.flip & Constants.FLIP_VERTICAL:
			custom_position.y = 2.0 - custom_position.y
	
	note_speed = Utils.get_number(custom_data, prefix + "noteJumpMovementSpeed", 0.0)
	start_beat_offset = Utils.get_number(custom_data, prefix + "noteJumpStartBeatOffset", 0.0)
	fake = Utils.get_number(custom_data, prefix + "fake", 0.0) != 0.0
	disable_spawn_effect = Utils.get_number(custom_data, prefix + "disableSpawnEffect", 0.0) != 0.0
	
	var animation_v: Variant = custom_data.get(prefix + "animation")
	if animation_v is Dictionary:
		var ad := animation_v as Dictionary
		var anim_prefix := "_" if v2 else ""
		animation_position = _anim_frame(ad.get(anim_prefix + "offsetPosition"), Vector3.ZERO)
		animation_position_to = _anim_last_frame(ad.get(anim_prefix + "offsetPosition"), Vector3.ZERO)
		animation_rotation = _anim_frame(ad.get(anim_prefix + "localRotation"), Vector3.ZERO)
		animation_rotation_to = _anim_last_frame(ad.get(anim_prefix + "localRotation"), Vector3.ZERO)
		animation_scale = _anim_frame(ad.get(anim_prefix + "scale"), Vector3.ONE)
		animation_scale_to = _anim_last_frame(ad.get(anim_prefix + "scale"), Vector3.ONE)
		animation_position_duration = _anim_frame_duration(ad.get(anim_prefix + "offsetPosition"))
		animation_rotation_duration = _anim_frame_duration(ad.get(anim_prefix + "localRotation"))
		animation_scale_duration = _anim_frame_duration(ad.get(anim_prefix + "scale"))
		if animation_position != Vector3.ZERO or animation_rotation != Vector3.ZERO \
				or animation_scale != Vector3.ONE:
			has_animation = true

static func _parse_color(color: Variant) -> Color:
	if color is Array:
		var arr := color as Array
		if arr.size() >= 3:
			var a := 1.0
			if arr.size() > 3:
				a = float(arr[3])
			return Color(float(arr[0]), float(arr[1]), float(arr[2]), a)
	elif color is Dictionary:
		var d := color as Dictionary
		return Color(
			Utils.get_number(d, "r", 1.0),
			Utils.get_number(d, "g", 1.0),
			Utils.get_number(d, "b", 1.0)
		)
	return Color.WHITE

static func _anim_frame(frames: Variant, default_value: Vector3) -> Vector3:
	if frames is Array and not (frames as Array).is_empty():
		var first: Variant = (frames as Array)[0]
		if first is Array and (first as Array).size() >= 3:
			return Vector3(float(first[0]), float(first[1]), float(first[2]))
	return default_value

static func _anim_frame_duration(frames: Variant) -> float:
	if frames is Array and not (frames as Array).is_empty():
		var last: Variant = (frames as Array)[(frames as Array).size() - 1]
		if last is Array and (last as Array).size() >= 4:
			var t := float((last as Array)[3])
			if t > 0.0:
				return t
	return 1.0

static func _anim_last_frame(frames: Variant, default_value: Vector3) -> Vector3:
	if frames is Array and not (frames as Array).is_empty():
		var last: Variant = (frames as Array)[(frames as Array).size() - 1]
		if last is Array and (last as Array).size() >= 3:
			return Vector3(float(last[0]), float(last[1]), float(last[2]))
	return default_value
