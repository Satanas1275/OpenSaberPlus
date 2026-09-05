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

# Noodle animation as keyframe lists. Each entry is a dictionary
# { "v": Vector3, "t": float, "e": String } where "t" is a fraction of the
# note flight (0 = spawn, 1 = hit plane) and "e" the easing curve name applied
# over the segment that ends at that keyframe.
var animation_position_frames: Array = []
var animation_rotation_frames: Array = []
var animation_scale_frames: Array = []
var has_animation := false

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
		animation_position_frames = _anim_frames(ad.get(anim_prefix + "offsetPosition"), Vector3.ZERO, false)
		# Noodle Extensions spec: "one unit in offsetPosition is equal to the
		# width of one lane" (0.6m), uniformly across x/y/z. z is also negated:
		# this port's away-from-player axis is -Z (see the "-" in the beat-time
		# origin.z formula in BeepCube.spawn), flipped vs. Beat Saber/Unity's
		# convention that Noodle authors against. x/y don't need this flip.
		for frame in animation_position_frames:
			var v := frame["v"] as Vector3
			frame["v"] = Vector3(v.x, v.y, -v.z) * Settings.LANE_DISTANCE_X
		animation_rotation_frames = _anim_frames(ad.get(anim_prefix + "localRotation"), Vector3.ZERO, false)
		animation_scale_frames = _anim_frames(ad.get(anim_prefix + "scale"), Vector3.ONE, true)
		if not animation_position_frames.is_empty() or not animation_rotation_frames.is_empty() \
				or not animation_scale_frames.is_empty():
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

# Standard Beat Saber / Noodle easing curves, evaluated on [0,1].
static func anim_ease(easing: String, x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	match easing:
		"easeInQuad": return t * t
		"easeOutQuad": return t * (2.0 - t)
		"easeInOutQuad":
			if t < 0.5: return 2.0 * t * t
			return -1.0 + (4.0 - 2.0 * t) * t
		"easeInCubic": return t * t * t
		"easeOutCubic":
			var u1 := t - 1.0
			return u1 * u1 * u1 + 1.0
		"easeInOutCubic":
			if t < 0.5: return 4.0 * t * t * t
			var u2 := 2.0 * t - 2.0
			return 0.5 * u2 * u2 * u2 + 1.0
		"easeInQuart": return t * t * t * t
		"easeOutQuart":
			var u3 := t - 1.0
			return 1.0 - u3 * u3 * u3 * u3
		"easeInOutQuart":
			if t < 0.5: return 8.0 * t * t * t * t
			var u4 := t - 1.0
			return 1.0 - 8.0 * u4 * u4 * u4 * u4
		"easeInQuint": return t * t * t * t * t
		"easeOutQuint":
			var u5 := t - 1.0
			return 1.0 + u5 * u5 * u5 * u5 * u5
		"easeInOutQuint":
			if t < 0.5: return 16.0 * t * t * t * t * t
			var u6 := 2.0 * t - 2.0
			return 0.5 * u6 * u6 * u6 * u6 * u6 + 1.0
		"easeInSine": return 1.0 - cos(t * PI * 0.5)
		"easeOutSine": return sin(t * PI * 0.5)
		"easeInOutSine": return -0.5 * (cos(PI * t) - 1.0)
		"easeInExpo": return 1.0 if t <= 0.0 else pow(2.0, 10.0 * (t - 1.0))
		"easeOutExpo": return 1.0 if t >= 1.0 else -pow(2.0, -10.0 * t) + 1.0
		"easeInOutExpo":
			if t <= 0.0: return 0.0
			if t >= 1.0: return 1.0
			if t < 0.5: return 0.5 * pow(2.0, 20.0 * t - 10.0)
			return -0.5 * pow(2.0, -20.0 * t + 10.0) + 1.0
		"easeInCirc": return 1.0 - sqrt(1.0 - t * t)
		"easeOutCirc":
			var u7 := t - 1.0
			return sqrt(1.0 - u7 * u7)
		"easeInOutCirc":
			if t < 0.5: return 0.5 * (1.0 - sqrt(1.0 - 4.0 * t * t))
			var u8 := -2.0 * t + 2.0
			return 0.5 * (sqrt(1.0 - u8 * u8) + 1.0)
		"easeInBack":
			var c1 := 1.70158
			var c3 := c1 + 1.0
			return c3 * t * t * t - c1 * t * t
		"easeOutBack":
			var c4 := 1.70158
			var c5 := c4 + 1.0
			var u9 := t - 1.0
			return 1.0 + c5 * u9 * u9 * u9 + c4 * u9 * u9
		"easeInOutBack":
			var c6 := 1.70158
			var c7 := c6 * 1.525
			if t < 0.5: return 0.5 * (2.0 * t) * (2.0 * t) * ((c7 + 1.0) * 2.0 * t - c7)
			var u10 := 2.0 * t - 2.0
			return 0.5 * (u10 * u10 * ((c7 + 1.0) * u10 + c7) + 2.0)
		"easeInElastic":
			if t <= 0.0: return 0.0
			if t >= 1.0: return 1.0
			var c8 := 2.0 * PI / 3.0
			return -pow(2.0, 10.0 * t - 10.0) * sin((t * 10.0 - 10.75) * c8)
		"easeOutElastic":
			if t <= 0.0: return 0.0
			if t >= 1.0: return 1.0
			var c9 := 2.0 * PI / 3.0
			return pow(2.0, -10.0 * t) * sin((t * 10.0 - 0.75) * c9) + 1.0
		"easeInOutElastic":
			if t <= 0.0: return 0.0
			if t >= 1.0: return 1.0
			var c10 := 2.0 * PI / 4.5
			if t < 0.5:
				return -0.5 * pow(2.0, 20.0 * t - 10.0) * sin((20.0 * t - 11.125) * c10)
			return pow(2.0, -20.0 * t + 10.0) * sin((20.0 * t - 11.125) * c10) * 0.5 + 1.0
		"easeInBounce":
			return 1.0 - anim_ease("easeOutBounce", 1.0 - t)
		"easeOutBounce":
			var n1 := 7.5625
			var d1 := 2.75
			if t < 1.0 / d1: return n1 * t * t
			if t < 2.0 / d1:
				var u11 := t - 1.5 / d1
				return n1 * u11 * u11 + 0.75
			if t < 2.5 / d1:
				var u12 := t - 2.25 / d1
				return n1 * u12 * u12 + 0.9375
			var u13 := t - 2.625 / d1
			return n1 * u13 * u13 + 0.984375
		"easeInOutBounce":
			if t < 0.5: return 0.5 * anim_ease("easeOutBounce", 2.0 * t)
			return 0.5 * anim_ease("easeOutBounce", 2.0 * t - 1.0) + 0.5
	return t

# parse a Noodle animation property into a list of keyframe dictionaries.
# Accepts both keyframe lists [[x,y,z,t?,easing?], ...] and bare values
# ([x,y,z] or a scalar for scale properties).
static func _anim_frames(frames: Variant, default_value: Vector3, scalar: bool) -> Array:
	var result: Array = []
	if not (frames is Array):
		return result
	var arr := frames as Array
	if arr.is_empty():
		return result
	if _is_number(arr[0]):
		result.append(_frame_from_value(arr, default_value, scalar))
		return result
	for raw in arr:
		result.append(_frame_from_value(raw, default_value, scalar))
	return result

static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

static func _frame_from_value(raw: Variant, default_value: Vector3, scalar: bool) -> Dictionary:
	var v := default_value
	var t := 0.0
	var e := ""
	if _is_number(raw):
		if scalar:
			v = Vector3(raw, raw, raw)
	elif raw is Array:
		var a := raw as Array
		if a.size() >= 3:
			v = Vector3(float(a[0]), float(a[1]), float(a[2]))
		if a.size() >= 4 and _is_number(a[3]):
			t = float(a[3])
		if a.size() >= 5 and a[4] is String:
			e = a[4] as String
	return { "v": v, "t": t, "e": e }
