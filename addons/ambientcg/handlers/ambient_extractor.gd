@tool
extends Node

# Only plain image data is extracted (plus OBJ meshes for 3D models).
# Anything else in an archive (scripts, scenes, resources) could execute
# code when the editor loads it.
const IMAGE_EXTENSIONS = ["jpg", "jpeg", "png", "exr", "hdr"]
const MODEL_EXTENSIONS = ["obj", "mtl"]
const TextureProcessor = preload("res://addons/ambientcg/handlers/ambient_texture_processor.gd")

var config: Script
var utils: Script
var logger: Node
var signals: Node
var material_maker: Script
var sky_maker: Script
var decal_maker: Script
var model_maker: Script

# Generated resources waiting to show up in the FileSystem dock, mapped to
# {"attempts": int, "stable": int}. They are checked from _process instead of
# an awaited loop, so imports finish right away and a script reload (which
# cancels suspended coroutines) cannot leave an import hanging.
var _pending_files: Dictionary = {}
var _register_cooldown := 0.0


## Extracts an asset and builds its resources. Returns the created paths
## (empty on failure).
func extract_all(
	source_file: String, target_path: String = "", options: Dictionary = {}
) -> PackedStringArray:
	_log_info("Starting automatic extraction for: %s" % source_file)

	var file_sys = _get_filesystem()
	var reader = _open_zip_reader(source_file)
	if not reader:
		return PackedStringArray()

	var files = reader.get_files()
	var extraction_path = await _get_extraction_path(target_path)
	if extraction_path.is_empty():
		reader.close()
		return PackedStringArray()

	var asset_name := source_file.get_file().get_basename()
	var asset_type := _get_asset_type(asset_name, options)
	# Atlases can serve as decals, sprites or particles, so no resource is
	# generated; their textures go to a folder of their own instead.
	if asset_type == "atlas":
		extraction_path = config.get_setting(
			config.SETTING_ATLAS_DIR, config.get_default(config.SETTING_ATLAS_DIR)
		)
	var final_extract_path = _prepare_extraction_path(extraction_path, source_file)
	_emit_extraction_started(asset_name)

	if DirAccess.dir_exists_absolute(final_extract_path):
		utils.clean_dir_content(final_extract_path)

	var saved_files = _extract_zip_contents(reader, files, final_extract_path, asset_type)
	reader.close()
	# HDRIs are used as they are; texture sets get their alpha merged and are
	# downscaled or converted as chosen in the import panel.
	if asset_type != "hdri":
		saved_files = TextureProcessor.process_set(saved_files, options)

	# Resources are written straight away from the extracted file names, so
	# they never depend on the editor having imported the textures first.
	var created := _build_resources(
		asset_type, asset_name, saved_files, final_extract_path, options
	)
	if created.is_empty():
		if signals:
			signals.extraction_failed.emit(source_file.get_file(), "Failed to create resource")
		return PackedStringArray()

	for path in created:
		_log_info("Created %s" % path)

	if file_sys:
		file_sys.scan()
		for path in created:
			# Textures are picked up by the scan; generated resources need help.
			if path.get_extension() in ["tres", "tscn"]:
				_pending_files[path] = {"attempts": 0, "stable": 0}

	_log_info("Success! Resources created and folders populated")
	_emit_extraction_completed(asset_name, final_extract_path)
	DirAccess.remove_absolute(source_file)
	return created


func _get_asset_type(asset_name: String, options: Dictionary) -> String:
	var asset_type: String = options.get("asset_type", "")
	if not asset_type.is_empty():
		return asset_type
	return "hdri" if asset_name.to_lower().contains("hdri") else "material"


func _extract_zip_contents(
	reader: ZIPReader, files: PackedStringArray, target_dir: String, asset_type: String
) -> PackedStringArray:
	utils.ensure_dir(target_dir)

	var allowed: Array = IMAGE_EXTENSIONS.duplicate()
	if asset_type == "3d-model":
		allowed.append_array(MODEL_EXTENSIONS)

	var res_regex = RegEx.new()
	res_regex.compile("\\d+K")

	var saved_files: PackedStringArray
	for file in files:
		var ext = file.get_extension().to_lower()
		if not ext in allowed:
			continue

		# Skips preview images such as "Bricks113A.png"
		if ext in ["jpg", "jpeg", "png"] and not res_regex.search(file):
			continue

		var file_name = file.get_file()
		if not utils.is_safe_file_name(file_name):
			_log_warn("Skipping archive entry with unsafe name: %s" % file)
			continue

		var file_data: PackedByteArray = reader.read_file(file)
		var new_file_path = target_dir.path_join(file_name)

		var fs := FileAccess.open(new_file_path, FileAccess.WRITE)
		if fs:
			fs.store_buffer(file_data)
			fs.close()
			saved_files.append(new_file_path)

	return saved_files


## Writes the Godot resources for an asset and returns their paths
## (empty if nothing could be created).
func _build_resources(
	asset_type: String,
	asset_name: String,
	saved_files: PackedStringArray,
	extract_dir: String,
	options: Dictionary
) -> PackedStringArray:
	var file_name: String = utils.sanitize_file_component(asset_name)
	var created := PackedStringArray()

	match asset_type:
		"hdri":
			var sky_path := _output_path(config.SETTING_HDRI_DIR, file_name + ".tres")
			if _check(sky_maker.write_sky_material(sky_path, saved_files), sky_path):
				created.append(sky_path)

		"atlas":
			created.append_array(saved_files)

		"decal":
			var decal_path := _output_path(config.SETTING_DECAL_DIR, file_name + ".tscn")
			var err = decal_maker.write_decal_scene(decal_path, file_name, saved_files, extract_dir)
			if _check(err, decal_path):
				created.append(decal_path)

		"3d-model":
			var mat_path := _output_path(config.SETTING_MATERIAL_DIR, file_name + ".tres")
			var err = material_maker.write_standard_material(mat_path, saved_files, options)
			if not _check(err, mat_path):
				return created
			created.append(mat_path)

			var scene_path := _output_path(config.SETTING_MODEL_DIR, file_name + ".tscn")
			var mesh_path: String = model_maker.find_mesh(saved_files)
			err = model_maker.write_model_scene(scene_path, file_name, mesh_path, mat_path)
			if _check(err, scene_path):
				created.append(scene_path)

		_:
			var mat_path := _output_path(config.SETTING_MATERIAL_DIR, file_name + ".tres")
			var err = material_maker.write_standard_material(mat_path, saved_files, options)
			if _check(err, mat_path):
				created.append(mat_path)

	return created


func _output_path(setting: String, file_name: String) -> String:
	var dir: String = config.get_setting(setting, config.get_default(setting))
	utils.ensure_dir(dir)
	return dir.path_join(file_name)


func _check(err: Error, path: String) -> bool:
	if err != OK:
		_log_error("Failed to create %s (%s)" % [path, error_string(err)])
	return err == OK


# Registers newly written files with the editor's FileSystem dock.
# update_file() does nothing for folders the editor has not scanned yet, and
# a scan that started before a file was written replaces the file list with a
# stale snapshot when it finishes. So keep (re)registering each file until it
# has stayed listed through a few quiet checks in a row.
func _process(delta: float) -> void:
	if _pending_files.is_empty():
		return
	_register_cooldown -= delta
	var file_sys = _get_filesystem()
	if _register_cooldown > 0.0 or (file_sys and file_sys.is_scanning()):
		return
	_register_cooldown = 0.5
	if not file_sys:
		_pending_files.clear()
		return

	var needs_scan := false
	for path in _pending_files.keys():
		var state: Dictionary = _pending_files[path]
		state["attempts"] += 1
		if file_sys.get_filesystem_path(path.get_base_dir()) == null:
			state["stable"] = 0
			needs_scan = true
		elif file_sys.get_file_type(path).is_empty():
			state["stable"] = 0
			file_sys.update_file(path)
		else:
			state["stable"] += 1

		if state["stable"] >= 4:
			_pending_files.erase(path)
		elif state["attempts"] >= 40:
			_pending_files.erase(path)
			_log_warn("Editor did not pick up %s; it will appear after a rescan" % path)
	if needs_scan:
		file_sys.scan()


func _get_extraction_path(target_path: String) -> String:
	var extraction_path: String = target_path
	if extraction_path.is_empty():
		extraction_path = await open_directory_dialog_for_path("Select path to Extract to")

	if extraction_path.is_empty():
		_log_warn("Extraction cancelled: No directory selected")

	return extraction_path


func open_directory_dialog_for_path(title: String) -> String:
	if not Engine.is_editor_hint():
		return "user://test_extract/"

	var dialog := FileDialog.new()
	add_child(dialog)
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.title = title
	dialog.current_dir = config.get_setting(
		config.SETTING_EXTRACT_PATH, config.DEFAULT_EXTRACT_PATH
	)
	dialog.show()
	return await dialog.dir_selected


func _get_filesystem() -> Variant:
	if Engine.is_editor_hint() and is_instance_valid(EditorInterface):
		return EditorInterface.get_resource_filesystem()
	return null


func _open_zip_reader(source_file: String) -> ZIPReader:
	var reader := ZIPReader.new()
	var err = reader.open(source_file)
	if err != OK:
		_log_error("Failed to open ZIP file: %d" % err)
		if signals:
			signals.extraction_failed.emit(source_file.get_file(), "Failed to open ZIP")
		return null
	return reader


func _prepare_extraction_path(extraction_path: String, source_file: String) -> String:
	var asset_name: String = source_file.get_file().get_basename()
	return extraction_path.path_join(asset_name)


func _emit_extraction_started(asset_name: String) -> void:
	if signals:
		signals.extraction_started.emit(asset_name)


func _emit_extraction_completed(asset_name: String, final_extract_path: String) -> void:
	if signals:
		signals.extraction_completed.emit(asset_name, {"path": final_extract_path})


func _log_info(message: String) -> void:
	if logger:
		logger.info(message, "Extractor")


func _log_warn(message: String) -> void:
	if logger:
		logger.warn(message, "Extractor")


func _log_error(message: String) -> void:
	if logger:
		logger.error(message, "Extractor")
