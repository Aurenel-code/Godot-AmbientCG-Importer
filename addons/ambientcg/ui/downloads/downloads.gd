@tool
extends Control

const DOWNLOAD_ITEM_SCENE = preload(
	"res://addons/ambientcg/ui/components/download/download_item.tscn"
)
const CONFIG = preload("res://addons/ambientcg/core/ambient_config.gd")
const TAB_TITLE = "Downloads"
const HISTORY_PATH = "user://ambientcg_download_history.json"
const MAX_HISTORY = 100

# Past downloads, newest first.
var _history: Array = []

@onready var download_list: VBoxContainer = %DownloadList
@onready var active_empty_label: Label = %ActiveEmptyLabel
@onready var history_list: VBoxContainer = %HistoryList
@onready var history_empty_label: Label = %HistoryEmptyLabel
@onready var clear_button: Button = %ClearButton


func _ready() -> void:
	var ambient_cg = CONFIG.get_instance(self)
	if ambient_cg:
		ambient_cg.signals.download_started.connect(_on_download_started)
	download_list.child_order_changed.connect(_update_view)
	clear_button.pressed.connect(_on_clear_pressed)

	_history = load_history(HISTORY_PATH)
	for record in _history:
		_add_history_row(record, false)
	_update_view.call_deferred()


func _on_download_started(
	url: String, asset_name: String, asset_type: String, file_size: int
) -> void:
	var item = DOWNLOAD_ITEM_SCENE.instantiate()
	item.finished.connect(_on_item_finished.bind(item))
	download_list.add_child(item)
	item.setup(url, asset_name, asset_type, file_size)


func _on_item_finished(record: Dictionary, item: Node) -> void:
	item.queue_free()
	_history.push_front(record)
	if _history.size() > MAX_HISTORY:
		_history.resize(MAX_HISTORY)
		var rows := history_list.get_children()
		for i in range(MAX_HISTORY - 1, rows.size()):
			rows[i].queue_free()
	save_history(HISTORY_PATH, _history)
	_add_history_row(record, true)
	_update_view()


func _add_history_row(record: Dictionary, at_top: bool) -> void:
	var row = DOWNLOAD_ITEM_SCENE.instantiate()
	row.setup_from_record(record)
	history_list.add_child(row)
	if at_top:
		history_list.move_child(row, 0)


func _on_clear_pressed() -> void:
	_history.clear()
	save_history(HISTORY_PATH, _history)
	for row in history_list.get_children():
		row.queue_free()
	_update_view()


# Shows the number of running downloads in the tab title.
func _update_view() -> void:
	if not is_inside_tree():
		return
	var active := 0
	for item in download_list.get_children():
		if not item.is_queued_for_deletion():
			active += 1
	active_empty_label.visible = active == 0
	history_empty_label.visible = _history.is_empty()
	clear_button.disabled = _history.is_empty()
	var tabs := get_parent() as TabContainer
	if tabs:
		var title := TAB_TITLE if active == 0 else "%s (%d)" % [TAB_TITLE, active]
		tabs.set_tab_title(get_index(), title)


static func load_history(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var json := JSON.new()
	var history: Array = []
	if json.parse(FileAccess.get_file_as_string(path)) == OK and json.data is Array:
		for record in json.data:
			if record is Dictionary:
				history.append(record)
	return history.slice(0, MAX_HISTORY)


static func save_history(path: String, history: Array) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(history, "\t"))
		file.close()
