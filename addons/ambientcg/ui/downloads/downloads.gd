@tool
extends Control

const DOWNLOAD_ITEM_SCENE = preload(
	"res://addons/ambientcg/ui/components/download/download_item.tscn"
)
const CONFIG = preload("res://addons/ambientcg/core/ambient_config.gd")
const TAB_TITLE = "Active Downloads"

@onready var download_list: VBoxContainer = %DownloadList
@onready var empty_label: Label = %EmptyLabel


func _ready() -> void:
	var ambient_cg = CONFIG.get_instance(self)
	if ambient_cg:
		ambient_cg.signals.download_started.connect(_on_download_started)
	download_list.child_order_changed.connect(_update_count)
	_update_count.call_deferred()


func _on_download_started(url: String, asset_name: String, asset_type: String) -> void:
	var item = DOWNLOAD_ITEM_SCENE.instantiate()
	download_list.add_child(item)
	item.setup(url, asset_name, asset_type)


# Shows the number of running downloads in the tab title.
func _update_count() -> void:
	if not is_inside_tree():
		return
	var count := download_list.get_child_count()
	empty_label.visible = count == 0
	var tabs := get_parent() as TabContainer
	if tabs:
		var title := TAB_TITLE if count == 0 else "%s (%d)" % [TAB_TITLE, count]
		tabs.set_tab_title(get_index(), title)
