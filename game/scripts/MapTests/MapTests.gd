extends Node2D

# Run MapTests scene headless to validate custom-map handling:
#   godot --headless --path . res://game/scripts/MapTests/MapTests.tscn
#
# Expects the test maps from BeatSaver to be available as zip files in
# MAPS_DIR (each zip is rendered as a folder by Map loading).
#
# Checks resilient parsing for v2, v3 and v4 maps, Chroma/Noodle per-note
# overrides, v3/v4 GLS light boxes, colour boost events and the v4 lightshow
# file that is stored separately from the beatmap data.

const MAPS_DIR := "C:/Users/satanas/DATA/codage/BeatSaverMap"

var _failures := 0
var _checks := 0

func _ready() -> void:
	var test_methodnames := []
	for method in get_method_list():
		var method_name: String = method.name
		if method_name.begins_with("testcase_"):
			test_methodnames.append(method_name)
	print("Running %d test case(s)" % len(test_methodnames))
	for test_methodname in test_methodnames:
		print("--- BEGIN '%s' " % test_methodname)
		call(test_methodname)
		print("--- END '%s' " % test_methodname)
	if _failures > 0:
		push_error("%d/%d checks failed!" % [_failures, _checks])
	else:
		print("All %d tests passed (%d checks)!" % [len(test_methodnames), _checks])
	get_tree().quit(1 if _failures > 0 else 0)

# find the zip file that starts with the map key (map key prefix)
func _find_zip(prefix: String) -> String:
	if not DirAccess.dir_exists_absolute(MAPS_DIR):
		_fail("test maps dir does not exist: %s" % MAPS_DIR)
		return ""
	for file in DirAccess.get_files_at(MAPS_DIR):
		if file.to_lower().ends_with(".zip") and file.begins_with(prefix):
			return MAPS_DIR + "/" + file
	_fail("no zip starting with '%s' found in %s" % [prefix, MAPS_DIR])
	return ""

func _load_map(info: MapInfo, diff: DifficultyInfo) -> bool:
	var map_data := Utils.binary_to_json(Utils.read_binary_file(info.filepath, diff.beatmap_filename))
	if map_data.is_empty():
		_fail("could not read beatmap data %s/%s" % [info.filepath, diff.beatmap_filename])
		return false
	return Map.load_beatmap(info, diff, map_data)

func _pick_difficulty(info: MapInfo, characteristic: String, difficulty: String) -> DifficultyInfo:
	for d in info.difficulty_beatmaps:
		if d.characteristic == characteristic and d.difficulty == difficulty:
			return d
	return null

func _load_map_zip(prefix: String, characteristic: String, difficulty: String) -> void:
	var zip_path := _find_zip(prefix)
	if zip_path.is_empty():
		return
	var info := Map.load_map_info(zip_path)
	_check(info != null, "%s: info.dat parsed" % prefix)
	if info == null:
		return
	var diff := _pick_difficulty(info, characteristic, difficulty)
	_check(diff != null, "%s: difficulty %s/%s present" % [prefix, characteristic, difficulty])
	if diff == null:
		return
	Map.load_map_info(zip_path)
	var ok := _load_map(info, diff)
	_check(ok, "%s: map loaded" % prefix)
	# remember the info for later statics (e.g. BPM parser)
	Map.current_info = info

func _count_type(types: Array, type: int) -> int:
	var count := 0
	for e: EventInfo in types:
		if e.type == type:
			count += 1
	return count

func _count_light_box_events() -> int:
	var count := 0
	for e in Map.event_stack:
		if e.type in range(0, 5) and e.float_value > 0.0:
			count += 1
	return count

# ---------------------------------------------------------------- individual maps

func testcase_loads_all_map_infos() -> void:
	# all six maps should expose a parseable info.dat and at least one difficulty
	for prefix in ["112aa", "18ec4", "228f", "3a733", "50b1e", "53df1"]:
		var zip_path := _find_zip(prefix)
		if zip_path.is_empty():
			continue
		var info := Map.load_map_info(zip_path)
		_check(info != null, "%s: info parsed" % prefix)
		if info == null:
			continue
		_check(not info.difficulty_beatmaps.is_empty(), "%s: has difficulties" % prefix)
		_check(info.beats_per_minute > 0.0, "%s: bpm sane" % prefix)

func testcase_112aa_v2_basic() -> void:
	_load_map_zip("112aa", "Standard", "ExpertPlus")
	_check(Map.note_stack.size() == 648, "112aa: 648 notes got %d" % Map.note_stack.size())
	_check(Map.obstacle_stack.size() == 38, "112aa: 38 obstacles got %d" % Map.obstacle_stack.size())
	_check(Map.event_stack.size() == 5377, "112aa: 5377 events got %d" % Map.event_stack.size())
	_check(Map.bpm_changes.is_empty(), "112aa: no bpm changes")
	_check(not Map.one_saber, "112aa: Standard is not one-saber")

func testcase_18ec4_360degree() -> void:
	_load_map_zip("18ec4", "360Degree", "ExpertPlus")
	_check(Map.note_stack.size() == 487, "18ec4: 487 notes got %d" % Map.note_stack.size())
	_check(Map.obstacle_stack.size() == 382, "18ec4: 382 obstacles got %d" % Map.obstacle_stack.size())
	_check(Map.event_stack.size() == 1647, "18ec4: 1647 events got %d" % Map.event_stack.size())
	var rotated := 0
	for n in Map.note_stack:
		if absf(n.rotation) > 0.01:
			rotated += 1
	_check(rotated > 0, "18ec4: lane rotation events applied (%d rotated notes)" % rotated)

func testcase_228f_chroma_events() -> void:
	_load_map_zip("228f", "Standard", "ExpertPlus")
	_check(Map.note_stack.size() == 1301, "228f: 1301 notes got %d" % Map.note_stack.size())
	_check(Map.event_stack.size() == 2872, "228f: 2872 events got %d" % Map.event_stack.size())
	# Chroma maps use light values beyond the official 0-4 (extended off/on/fade)
	var max_value := 0
	var colored := 0
	for e in Map.event_stack:
		if e.type in range(0, 5):
			max_value = maxi(max_value, e.value)
			if e.value >= EventInfo.VALUE_LIGHTS_LEFT_ON:
				colored += 1
	_check(colored > 0, "228f: Chroma coloured light events present (%d)" % colored)
	_check(max_value >= EventInfo.VALUE_LIGHTS_LEFT_ON, "228f: extended Chroma values reached (%d)" % max_value)

func testcase_3a733_v3_light_boxes() -> void:
	_load_map_zip("3a733", "Standard", "Expert")
	_check(Map.note_stack.size() == 336, "3a733: 336 notes got %d" % Map.note_stack.size())
	_check(Map.obstacle_stack.size() == 40, "3a733: 40 obstacles got %d" % Map.obstacle_stack.size())
	_check(Map.arc_stack.size() == 21, "3a733: 21 sliders got %d" % Map.arc_stack.size())
	# 734 basic events + 39 colour boosts + flattened GLS light/rotation boxes
	_check(Map.event_stack.size() > 734, "3a733: events beyond basic (%d)" % Map.event_stack.size())
	_check(_count_type(Map.event_stack, EventInfo.TYPE_COLOR_BOOST) == 39, "3a733: 39 colour boost events")
	_check(_count_type(Map.event_stack, EventInfo.TYPE_RING_SPIN) > 0, "3a733: ring spin from light rotation boxes")
	_check(_count_light_box_events() > 0, "3a733: light colour boxes flattened with brightness")
	var event_stack: Array[EventInfo] = Map.event_stack
	_check(not event_stack.is_empty(), "3a733: event stack ordered")
	if not event_stack.is_empty():
		_check(event_stack[0].beat >= event_stack[event_stack.size() - 1].beat, "3a733: events ordered for pop_back()")
	_check(not Map.fx_events_collection.is_empty(), "3a733: Vivify fx event collection surfaced")
	_check(Map.bpm_changes.is_empty(), "3a733: no bpm changes")

func testcase_50b1e_noodle_notes() -> void:
	_load_map_zip("50b1e", "Standard", "Hard")
	_check(Map.note_stack.size() == 98, "50b1e: 98 notes got %d" % Map.note_stack.size())
	_check(Map.arc_stack.size() == 104, "50b1e: 104 sliders got %d" % Map.arc_stack.size())
	var animated := 0
	var scaled := 0
	var njs := 0
	for n in Map.note_stack:
		if n.has_animation:
			animated += 1
		if n.has_custom_scale:
			scaled += 1
		if n.note_speed > 0.0:
			njs += 1
	_check(animated == 98, "50b1e: all notes animated (%d)" % animated)
	_check(scaled == 98, "50b1e: all notes scaled (%d)" % scaled)
	_check(njs > 0, "50b1e: per-note note jump speed (%d)" % njs)
	# AnimateTrack custom events parsed (track "Planet")
	_check(Map.custom_tracks.has("Planet"), "50b1e: AnimateTrack track Planet captured")
	if Map.custom_tracks.has("Planet"):
		var entries: Array = Map.custom_tracks["Planet"]
		_check(entries.size() == 3, "50b1e: 3 AnimateTrack entries for Planet (%d)" % entries.size())
	_check(Map.map_environment is Array, "50b1e: environment customData surfaced")
	_check(Map.event_stack.is_empty(), "50b1e: no light events in beatmap data")

func testcase_53df1_v4_lightshow() -> void:
	var zip_path := _find_zip("53df1")
	if zip_path.is_empty():
		return
	var info := Map.load_map_info(zip_path)
	_check(info != null and info.version.begins_with("4."), "53df1: v4 info parsed")
	if info == null:
		return
	var diff := _pick_difficulty(info, "Standard", "ExpertPlus")
	_check(diff != null, "53df1: difficulty present")
	if diff == null:
		return
	_check(diff.lightshow_data_filename == "Common.lightshow.dat",
			"53df1: lightshow file referenced (%s)" % diff.lightshow_data_filename)
	Map.current_info = info
	var ok := _load_map(info, diff)
	_check(ok, "53df1: map loaded")
	if not ok:
		return
	_check(Map.note_stack.size() == 997, "53df1: 997 notes got %d" % Map.note_stack.size())
	_check(Map.obstacle_stack.size() == 125, "53df1: 125 obstacles got %d" % Map.obstacle_stack.size())
	_check(Map.arc_stack.size() == 39, "53df1: 39 arcs got %d" % Map.arc_stack.size())
	# 2435 basic events + 63 colour boost events from the separate lightshow file
	_check(Map.event_stack.size() == 2435 + 63,
			"53df1: lightshow events (2498) got %d" % Map.event_stack.size())
	_check(_count_type(Map.event_stack, EventInfo.TYPE_COLOR_BOOST) == 63,
			"53df1: colour boost events from lightshow")

# ---------------------------------------------------------------- pure parser checks

func testcase_bpm_changes_parsing() -> void:
	var zip_path := _find_zip("112aa")
	if zip_path.is_empty():
		return
	Map.current_info = Map.load_map_info(zip_path)
	Map.parse_bpm_changes([
		{"b": 1.0, "m": 120.0},
		{"b": 0.0, "m": 150.0}
	], "b", "m")
	_check(Map.bpm_changes.size() == 2, "bpm parser: two sections")
	if Map.bpm_changes.size() == 2:
		_check(Map.bpm_changes[0][0] == 0.0, "bpm parser: sorted, first at 0")
		_check(Map.bpm_changes[0][1] == 150.0, "bpm parser: first bpm is 150")
	# a bpm change at beat 0 overrides the map's base BPM
	_check(is_equal_approx(Map.current_info.beats_per_minute,
			150.0 * Settings.music_speed / 100.0), "bpm parser: base BPM overridden")

func testcase_event_info_value_mapping() -> void:
	_check(EventInfo.light_color_event_value(0, 0, 0.0, 0.0) == EventInfo.VALUE_LIGHTS_LEFT_ON, "map: red instant -> left on")
	_check(EventInfo.light_color_event_value(1, 0, 0.0, 0.0) == EventInfo.VALUE_LIGHTS_RIGHT_ON, "map: blue instant -> right on")
	_check(EventInfo.light_color_event_value(2, 0, 0.0, 0.0) == EventInfo.VALUE_LIGHTS_WHITE_ON, "map: white instant -> white on")
	_check(EventInfo.light_color_event_value(1, 1, 0.0, 0.0) == EventInfo.VALUE_LIGHTS_FADE_TO_RIGHT, "map: blue interpolate -> fade to right")
	_check(EventInfo.light_color_event_value(0, 0, 8.0, 0.0) == EventInfo.VALUE_LIGHTS_LEFT_FLASH, "map: red strobe -> left flash")
	_check(EventInfo.light_color_event_value(2, 2, 0.0, 2.0) == EventInfo.VALUE_LIGHTS_WHITE_FLASH, "map: white strobe -> white flash")
	_check(EventInfo.light_color_event_value(-1, 0, 0.0, 0.0) == -1, "map: no colour -> skipped")

func testcase_color_note_custom_data() -> void:
	var note := ColorNoteInfo.new_v3({
		"b": 2.0, "x": 0, "y": 1, "c": 1, "d": 1,
		"customData": {
			"color": [0.9, 0.1, 0.9, 1.0],
			"scale": [2.0, 1.0, 1.0],
			"noteJumpMovementSpeed": 12.0,
			"noteJumpStartBeatOffset": -1.5,
			"fake": true,
			"animation": {
				"offsetPosition": [[5.0, 10.0, -100.0, 0.0], [0.0, 0.0, 0.0, 0.5]],
				"localRotation": [[0.0, 0.0, 180.0, 0.1], [0.0, 0.0, 0.0, 0.4]]
			}
		}
	})
	_check(note.has_custom_color, "notes: custom color parsed")
	_check(note.custom_color.r == 0.9 and note.custom_color.g == 0.1, "notes: custom color values")
	_check(note.has_custom_scale and note.spawn_scale.x == 2.0, "notes: custom scale parsed")
	_check(note.note_speed == 12.0, "notes: per-note NJS parsed")
	_check(note.start_beat_offset == -1.5, "notes: per-note offset parsed")
	_check(note.fake, "notes: fake flag parsed")
	_check(note.has_animation, "notes: animation keyframes parsed")
	_check(note.animation_position.z == -100.0, "notes: animation spawn offset")
	_check(note.animation_rotation_to == Vector3.ZERO, "notes: animation settles to zero rotation")

func testcase_color_note_v2_underscore_keys() -> void:
	var note := ColorNoteInfo.new_v2({
		"_time": 2.0, "_lineIndex": 1, "_lineLayer": 0, "_type": 0, "_cutDirection": 4,
		"_customData": {
			"_color": {"r": 1.0, "g": 0.5, "b": 0.0},
			"_scale": [0.5, 0.5, 0.5]
		}
	})
	_check(note.has_custom_color, "v2 notes: _color parsed")
	_check(note.custom_color.g == 0.5, "v2 notes: dictionary colour")
	_check(note.has_custom_scale and note.spawn_scale == Vector3(0.5, 0.5, 0.5), "v2 notes: _scale parsed")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
	else:
		print("  ok: %s" % message)

func _fail(message: String) -> void:
	_checks += 1
	_failures += 1
	push_error(message)