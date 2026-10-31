@tool
extends RefCounted
# AmbientResourceWriter
# Builds Godot text resources (.tres / .tscn) directly as text.
# Textures are referenced by path, so a resource can be written the moment
# its textures are extracted, without waiting for the editor to import them.


class Raw:
	var text: String

	func _init(p_text: String) -> void:
		text = p_text


var _ext_resources: Array = []
var _sub_resources: Array = []


## Adds an external resource and returns a value usable as a property.
func ext(type: String, path: String) -> Raw:
	var id := "%d_ext" % (_ext_resources.size() + 1)
	_ext_resources.append([type, path, id])
	return Raw.new('ExtResource("%s")' % id)


## Adds an embedded sub-resource and returns a value usable as a property.
func sub(type: String, properties: Dictionary) -> Raw:
	var id := "%d_sub" % (_sub_resources.size() + 1)
	_sub_resources.append([type, id, properties])
	return Raw.new('SubResource("%s")' % id)


func build_resource(type: String, properties: Dictionary) -> String:
	var text := '[gd_resource type="%s" format=3]\n\n' % type
	text += _build_dependencies()
	text += "[resource]\n" + _build_properties(properties)
	return text


func build_scene(root_name: String, root_type: String, properties: Dictionary) -> String:
	var text := "[gd_scene format=3]\n\n"
	text += _build_dependencies()
	text += '[node name="%s" type="%s"]\n' % [root_name.c_escape(), root_type]
	text += _build_properties(properties)
	return text


static func save_text(path: String, text: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK


func _build_dependencies() -> String:
	var text := ""
	for entry in _ext_resources:
		text += (
			'[ext_resource type="%s" path="%s" id="%s"]\n'
			% [entry[0], entry[1].c_escape(), entry[2]]
		)
	if not _ext_resources.is_empty():
		text += "\n"
	for entry in _sub_resources:
		text += '[sub_resource type="%s" id="%s"]\n' % [entry[0], entry[1]]
		text += _build_properties(entry[2]) + "\n"
	return text


static func _build_properties(properties: Dictionary) -> String:
	var text := ""
	for key in properties:
		var value = properties[key]
		var formatted: String = value.text if value is Raw else var_to_str(value)
		text += "%s = %s\n" % [key, formatted]
	return text
