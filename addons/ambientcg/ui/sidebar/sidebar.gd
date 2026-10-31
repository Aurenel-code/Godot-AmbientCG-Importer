@tool
extends VBoxContainer

const CONFIG = preload("res://addons/ambientcg/core/ambient_config.gd")
const UI_HELPERS = preload("res://addons/ambientcg/utils/ui_helpers.gd")
const UTILS = preload("res://addons/ambientcg/utils/ambient_utils.gd")
const OPTIONS = preload("res://addons/ambientcg/core/ambient_download_options.gd")

var current_asset_id: String = ""
var asset_data: Dictionary = {}

var _parsed_implementations: Array[Dictionary] = []
var _last_request_id: int = 0

var _format_options: OptionButton
var _lod_options: OptionButton
# HDRIs have one resolution; texture sets have one per channel.
var _size_options: OptionButton
var _channel_options: Dictionary = {}
var _download_button: Button
var _download_note: Label

@onready var asset_inspector: VBoxContainer = %AssetInspector
@onready var sidebar_placeholder: CenterContainer = %SidebarPlaceholder
@onready var asset_title: Label = %AssetTitle
@onready var preview_rect: TextureRect = %PreviewRect
@onready var groups_container: VBoxContainer = %GroupsContainer
@onready var id_edit: LineEdit = %IdEdit
@onready var load_button: Button = %LoadButton


func _ready() -> void:
	asset_inspector.hide()
	sidebar_placeholder.show()
	id_edit.text_submitted.connect(_on_manual_id_submitted)
	load_button.pressed.connect(func(): _on_manual_id_submitted(id_edit.text))


func display_asset(asset: Dictionary) -> void:
	var new_asset_id = asset.get("id", "")

	if current_asset_id == new_asset_id and not current_asset_id.is_empty():
		asset_inspector.show()
		sidebar_placeholder.hide()
		return

	current_asset_id = new_asset_id
	asset_inspector.hide()
	sidebar_placeholder.show()

	for child in groups_container.get_children():
		child.queue_free()

	asset_data = asset

	if asset_data.is_empty():
		var ambient_cg = CONFIG.get_instance(self)
		if ambient_cg:
			ambient_cg.logger.error("Failed to fetch asset details", "UI")
		return

	asset_title.text = current_asset_id

	_last_request_id += 1
	var request_id = _last_request_id

	var thumbnail_url = asset_data.get("thumbnail", "")
	if not thumbnail_url.is_empty():
		_load_preview(thumbnail_url, request_id)
	else:
		preview_rect.texture = null

	sidebar_placeholder.hide()
	asset_inspector.show()

	_parsed_implementations.clear()
	if asset_data.has("download_data"):
		_parsed_implementations.append_array(asset_data["download_data"])
		_build_download_ui()
	else:
		var err_label = Label.new()
		err_label.text = "No download data available."
		err_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		groups_container.add_child(err_label)


func _build_download_ui() -> void:
	if not CONFIG.is_plugin_enabled():
		return

	for c in groups_container.get_children():
		c.queue_free()

	var container_ext = _pick_container_format(_parsed_implementations)
	_parsed_implementations = _parsed_implementations.filter(
		func(opt): return str(opt.get("local_file_name", "")).get_extension() == container_ext
	)
	if _parsed_implementations.is_empty():
		var err_label = Label.new()
		err_label.text = "Failed to load downloads."
		err_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		groups_container.add_child(err_label)
		return

	var is_hdri: bool = asset_data.get("asset_type", "") == "hdri"
	var formats := OPTIONS.get_formats(_parsed_implementations)
	_format_options = _add_option_row("File Format")
	for format in formats:
		_add_option(_format_options, OPTIONS.FORMAT_LABELS[format], format)
	_select_metadata(_format_options, CONFIG.get_value(CONFIG.SETTING_DEFAULT_FORMAT))
	_format_options.get_parent().visible = not formats.is_empty()

	var lods := OPTIONS.get_lods(_parsed_implementations)
	_lod_options = _add_option_row("Model Quality")
	for lod in lods:
		_add_option(_lod_options, OPTIONS.LOD_LABELS[lod], lod)
	_select_metadata(_lod_options, CONFIG.get_value(CONFIG.SETTING_DEFAULT_MODEL_QUALITY))
	_lod_options.get_parent().visible = not lods.is_empty()

	_size_options = null
	_channel_options.clear()
	if is_hdri:
		_size_options = _add_option_row("Resolution")
		_size_options.item_selected.connect(func(_i): _refresh_download())
	else:
		var header := Label.new()
		header.text = "Texture Resolution"
		groups_container.add_child(header)
		var maps: Array = asset_data.get("maps", [])
		for channel in OPTIONS.get_channels(maps):
			var label_text: String = OPTIONS.CHANNEL_LABELS[channel]
			if channel == "color" and asset_data.get("has_transparency", false):
				label_text = "Color + Opacity"
			var options := _add_option_row(label_text)
			options.item_selected.connect(func(_i): _refresh_download())
			_channel_options[channel] = options

	_download_button = Button.new()
	_download_button.custom_minimum_size = Vector2(0, 32)
	_download_button.pressed.connect(_on_download_pressed)
	groups_container.add_child(_download_button)

	_download_note = Label.new()
	_download_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_download_note.add_theme_font_size_override("font_size", 11)
	_download_note.add_theme_color_override("font_color", Color(0.67, 0.67, 0.67))
	groups_container.add_child(_download_note)

	_format_options.item_selected.connect(func(_i): _refresh_sizes())
	_lod_options.item_selected.connect(func(_i): _refresh_sizes())
	_refresh_sizes()


func _add_option_row(label_text: String) -> OptionButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)
	var options := OptionButton.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(options)
	groups_container.add_child(row)
	return options


static func _add_option(options: OptionButton, text: String, metadata: Variant) -> void:
	options.add_item(text)
	options.set_item_metadata(options.item_count - 1, metadata)


static func _select_metadata(options: OptionButton, metadata: Variant) -> bool:
	for i in options.item_count:
		if options.get_item_metadata(i) == metadata:
			options.select(i)
			return true
	return false


static func _selected_metadata(options: OptionButton, fallback: Variant) -> Variant:
	if options.selected < 0:
		return fallback
	return options.get_item_metadata(options.selected)


# Lists the resolutions for the chosen format and model quality, keeping the
# current choices when they are still available.
func _refresh_sizes() -> void:
	var format: String = _selected_metadata(_format_options, "")
	var lod: String = _selected_metadata(_lod_options, "")
	if _size_options:
		# HDRIs are only offered in the sizes ambientCG has.
		var hdri_sizes := OPTIONS.get_sizes(_parsed_implementations, format, lod, false)
		_fill_sizes(_size_options, hdri_sizes, CONFIG.get_value(CONFIG.SETTING_DEFAULT_HDRI_SIZE))
	var sizes := OPTIONS.get_sizes(_parsed_implementations, format, lod, true)
	for channel in _channel_options:
		var preferred: int = CONFIG.get_value(CONFIG.channel_size_setting(channel))
		_fill_sizes(_channel_options[channel], sizes, preferred)
	_refresh_download()


static func _fill_sizes(options: OptionButton, sizes: Array, preferred: int) -> void:
	var previous: int = _selected_metadata(options, 0)
	options.clear()
	for size in sizes:
		_add_option(options, OPTIONS.size_label(size), size)
	if not _select_metadata(options, previous):
		_select_metadata(options, OPTIONS.pick_default_size(sizes, preferred))


func _refresh_download() -> void:
	var download := _build_selected_download()
	_download_button.disabled = download.is_empty()
	if download.is_empty():
		_download_button.text = "Not Available"
		_download_note.text = ""
		return

	_download_button.text = "Download (%s)" % UTILS.format_file_size(download.get("file_size", 0))
	var import_options: Dictionary = download["import_options"]
	var source_size: int = OPTIONS.parse_attributes(import_options["source_attributes"])["size"]
	var steps := PackedStringArray()
	var downscaled := _describe_downscaled(import_options["channel_sizes"], source_size)
	if not downscaled.is_empty():
		steps.append("downscales %s" % downscaled)
	if not import_options["convert_to"].is_empty():
		steps.append("converts to %s" % OPTIONS.FORMAT_LABELS[import_options["convert_to"]])
	_download_note.text = "Imported as %s" % download["attributes"]
	if not steps.is_empty():
		_download_note.text = (
			"Downloads the %s set, then %s while importing."
			% [import_options["source_attributes"], " and ".join(steps)]
		)


# "Color to 1K, Roughness/Ambient Occlusion to 512" for the channels that are
# smaller than the downloaded set.
static func _describe_downscaled(channel_sizes: Dictionary, source_size: int) -> String:
	var by_size := {}
	for channel in channel_sizes:
		var size: int = channel_sizes[channel]
		if size < source_size:
			if not by_size.has(size):
				by_size[size] = PackedStringArray()
			by_size[size].append(OPTIONS.CHANNEL_LABELS[channel])
	var sizes := by_size.keys()
	sizes.sort()
	sizes.reverse()
	var parts := PackedStringArray()
	for size in sizes:
		parts.append("%s to %s" % ["/".join(by_size[size]), OPTIONS.size_label(size)])
	return ", ".join(parts)


func _build_selected_download() -> Dictionary:
	var channel_sizes := {}
	for channel in _channel_options:
		channel_sizes[channel] = _selected_metadata(_channel_options[channel], 0)
	return OPTIONS.build_download(
		_parsed_implementations,
		_selected_metadata(_format_options, ""),
		_selected_metadata(_lod_options, ""),
		_selected_metadata(_size_options, 0) if _size_options else 0,
		channel_sizes
	)


func _on_download_pressed() -> void:
	var download := _build_selected_download()
	var ambient_cg = CONFIG.get_instance(self)
	if ambient_cg and not download.is_empty():
		ambient_cg.file_handler.download_file_from_data(download, self)


# ZIP archives are what the extractor is built for, so they win whenever an
# asset offers them; otherwise fall back to whatever format is available.
static func _pick_container_format(implementations: Array[Dictionary]) -> String:
	var fallback := ""
	for opt in implementations:
		var ext = str(opt.get("local_file_name", "")).get_extension().to_lower()
		if ext == "zip":
			return ext
		if fallback.is_empty():
			fallback = ext
	return fallback


func _load_preview(url: String, request_id: int) -> void:
	var helpers = UI_HELPERS.new()
	var texture = await helpers.load_image_from_url(self, url)
	helpers.queue_free()

	if request_id != _last_request_id:
		return

	if texture:
		preview_rect.texture = texture


func _on_manual_id_submitted(id: String) -> void:
	if id.is_empty():
		return

	var ambient_cg = CONFIG.get_instance(self)
	if not ambient_cg:
		return

	# Show placeholder/loading state
	asset_inspector.hide()
	sidebar_placeholder.show()
	var placeholder_label = sidebar_placeholder.get_node("Label")
	var original_text = placeholder_label.text
	placeholder_label.text = "Fetching asset %s..." % id

	var result = await ambient_cg.api.search_assets("", "Any", "", id)
	var parsed = ambient_cg.Parser.parse_search_query_data(result)
	var assets = parsed.get("assets", [])

	if assets.is_empty():
		placeholder_label.text = "Asset '%s' not found." % id
		await get_tree().create_timer(3.0).timeout
		placeholder_label.text = original_text
		return

	# Find exact match or just take the first one
	var found_asset = assets[0]
	for a in assets:
		if a.get("id", "").to_lower() == id.to_lower():
			found_asset = a
			break

	display_asset(found_asset)
	placeholder_label.text = original_text
