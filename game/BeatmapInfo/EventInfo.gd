extends RefCounted
class_name EventInfo

const TYPE_DIAGONAL_LASERS := 0
const TYPE_SQUARE_LASERS := 1
const TYPE_LEFT_WAVING_LASERS := 2
const TYPE_RIGHT_WAVING_LASERS := 3
const TYPE_FLOOR_LIGHTS := 4

# v2 event that our engine uses for ring rotation speed
const TYPE_RING_SPIN := 5

# synthetic events produced from v3/v4 colour boost data (value = 0 or 1)
const TYPE_COLOR_BOOST := 100

const VALUE_LIGHTS_OFF := 0
const VALUE_LIGHTS_RIGHT_ON := 1
const VALUE_LIGHTS_RIGHT_FLASH := 2
const VALUE_LIGHTS_RIGHT_FADE := 3
const VALUE_LIGHTS_FADE_TO_RIGHT := 4
const VALUE_LIGHTS_LEFT_ON := 5
const VALUE_LIGHTS_LEFT_FLASH := 6
const VALUE_LIGHTS_LEFT_FADE := 7
const VALUE_LIGHTS_FADE_TO_LEFT := 8
const VALUE_LIGHTS_WHITE_ON := 9
const VALUE_LIGHTS_WHITE_FLASH := 10
const VALUE_LIGHTS_WHITE_FADE := 11
const VALUE_LIGHTS_FADE_TO_WHITE := 12
const VALUE_EARLY_LANE_ROTATION := 14
const VALUE_LATE_LANE_ROTATION := 15

var beat: float
var type: int
var value: int
var float_value: float

@warning_ignore("shadowed_variable")
func _init(beat: float, type: int, value: int, float_value: float) -> void:
	self.beat = beat
	self.type = type
	self.value = value
	self.float_value = float_value

static func new_v2(event_dict: Dictionary) -> EventInfo:
	return EventInfo.new(
		Utils.get_float(event_dict, "_time", 0.0),
		int(Utils.get_float(event_dict, "_type", 0)),
		int(Utils.get_float(event_dict, "_value", 0)),
		Utils.get_float(event_dict, "_floatValue", -1.0)
	)

static func new_v3(event_dict: Dictionary) -> EventInfo:
	return EventInfo.new(
		Utils.get_float(event_dict, "b", 0.0),
		int(Utils.get_float(event_dict, "et", 0)),
		int(Utils.get_float(event_dict, "i", 0)),
		Utils.get_float(event_dict, "f", -1.0)
	)

# v4 lightshows share the v3 field layout, but store event data in a
# separate indexed array instead of inlined in each event.
static func new_v4_lightshow(basic_events: Array, basic_events_data: Array) -> Array[EventInfo]:
	var events: Array[EventInfo] = []
	for raw: Variant in basic_events:
		if raw is not Dictionary:
			continue
		var e := raw as Dictionary
		var index := int(Utils.get_float(e, "i", 0))
		var data := {}
		if 0 <= index and index < basic_events_data.size() and basic_events_data[index] is Dictionary:
			data = basic_events_data[index]
		events.append(EventInfo.new(
			Utils.get_float(e, "b", 0.0),
			int(Utils.get_float(data, "t", 0)),
			int(Utils.get_float(data, "i", 0)),
			Utils.get_float(data, "f", -1.0)
		))
	return events

static func new_color_boost(beat: float, boosted: bool) -> EventInfo:
	return EventInfo.new(beat, TYPE_COLOR_BOOST, 1 if boosted else 0, -1.0)

# translate a v3/v4 light colour event into one of the classic value codes.
# returns -1 when the event should be skipped entirely.
static func light_color_event_value(color_type: int, transition: int, frequency: float, strobe_brightness: float) -> int:
	if color_type < 0:
		return -1
	var strobe := frequency > 0.0 or strobe_brightness > 0.0
	var fade := transition > 0 and not strobe
	match color_type:
		0:
			if strobe: return VALUE_LIGHTS_LEFT_FLASH
			elif fade: return VALUE_LIGHTS_FADE_TO_LEFT
			else: return VALUE_LIGHTS_LEFT_ON
		1:
			if strobe: return VALUE_LIGHTS_RIGHT_FLASH
			elif fade: return VALUE_LIGHTS_FADE_TO_RIGHT
			else: return VALUE_LIGHTS_RIGHT_ON
		2:
			if strobe: return VALUE_LIGHTS_WHITE_FLASH
			elif fade: return VALUE_LIGHTS_FADE_TO_WHITE
			else: return VALUE_LIGHTS_WHITE_ON
	return -1
