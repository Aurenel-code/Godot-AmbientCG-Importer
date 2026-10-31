@tool
extends Node

enum JpgChoice { CONTINUE, PNG, CANCEL }

var config: Script
var logger: Node
var signals: Node
var api: Node
var utils: Script


func download_file_from_data(file_information: Dictionary, _source_window: Node) -> void:
	# JPG color maps have no alpha channel, so warn before downloading a
	# JPG set of a transparent asset and offer the PNG set instead.
	var warned := false
	if needs_jpg_warning(file_information):
		match await ask_jpg_transparency(file_information):
			JpgChoice.PNG:
				file_information = file_information["png_alternative"]
			JpgChoice.CANCEL:
				_log_info("Download cancelled by user.")
				return
		warned = true

	var download_path: String = config.get_setting(
		config.SETTING_DOWNLOAD_PATH, config.DEFAULT_DOWNLOAD_PATH
	)
	var file_name: String = file_information.get("local_file_name", "")
	var file_uri: String = file_information.get("uri", "")

	if not utils.is_safe_file_name(file_name):
		_log_error("Refusing download with unsafe file name: '%s'" % file_name)
		return
	if not utils.is_trusted_url(file_uri):
		_log_error("Refusing download from untrusted URL: '%s'" % file_uri)
		return

	var path: String = download_path.path_join(file_name)

	_log_info("Initiating download to Project: %s" % file_uri)

	var text = (
		"File will be Downloaded to %s and is Approx. %s.\nDownload?"
		% [path, utils.format_file_size(file_information.get("file_size", 0))]
	)

	var confirmed = true
	if not warned and config.get_setting(config.SETTING_ASK_BEFORE_DOWNLOAD, true):
		confirmed = await confirm_file_path(path, text)

	if not confirmed:
		_log_info("Download cancelled by user.")
		return

	if signals:
		signals.download_started.emit(
			file_uri,
			file_name,
			str(file_information.get("asset_type", "")),
			int(file_information.get("file_size", 0))
		)
	if api:
		await api.http_request_download(file_uri, path, file_information.get("file_size", 0))


static func needs_jpg_warning(file_information: Dictionary) -> bool:
	return (
		file_information.get("has_transparency", false)
		and str(file_information.get("attributes", "")).contains("JPG")
	)


func ask_jpg_transparency(file_information: Dictionary) -> JpgChoice:
	if not Engine.is_editor_hint():
		return JpgChoice.CONTINUE

	var png: Dictionary = file_information.get("png_alternative", {})
	var jpg_size: String = utils.format_file_size(file_information.get("file_size", 0))
	var text := "This asset has transparency, but JPG does not support transparency.\n\n"
	text += "Continue with JPG (%s)" % jpg_size
	if not png.is_empty():
		text += ", download PNG instead (%s)" % utils.format_file_size(png.get("file_size", 0))
	text += " or cancel?"

	var dialog := ConfirmationDialog.new()
	add_child(dialog)
	dialog.exclusive = false
	dialog.title = "JPG Has No Transparency"
	dialog.dialog_text = text
	dialog.ok_button_text = "Continue with JPG"
	if not png.is_empty():
		dialog.add_button("Download PNG", false, "png")

	var state = [false, JpgChoice.CANCEL]  # [finished, choice]
	dialog.confirmed.connect(
		func():
			state[0] = true
			state[1] = JpgChoice.CONTINUE
	)
	# Extra buttons do not close the dialog on their own.
	dialog.custom_action.connect(
		func(_action):
			state[0] = true
			state[1] = JpgChoice.PNG
			dialog.hide()
	)
	dialog.canceled.connect(func(): state[0] = true)

	dialog.popup_centered()
	while not state[0]:
		await get_tree().process_frame

	dialog.queue_free()
	return state[1]


func confirm_file_path(_path: String, dialog_text: String) -> bool:
	if not Engine.is_editor_hint():
		return true

	var confirmation_dialog = ConfirmationDialog.new()
	add_child(confirmation_dialog)
	confirmation_dialog.exclusive = false
	confirmation_dialog.title = "Confirm Download"
	confirmation_dialog.dialog_text = dialog_text

	var state = [false, false]  # [finished, confirmed]

	confirmation_dialog.confirmed.connect(
		func():
			state[0] = true
			state[1] = true
	)

	confirmation_dialog.canceled.connect(func(): state[0] = true)

	confirmation_dialog.popup_centered()

	while not state[0]:
		await get_tree().process_frame

	confirmation_dialog.queue_free()
	return state[1]


func _log_info(message: String) -> void:
	if logger:
		logger.info(message, "Downloader")


func _log_error(message: String) -> void:
	if logger:
		logger.error(message, "Downloader")
