@tool
# AmbientModelMaker
# Writes scenes for ambientCG 3D models: a MeshInstance3D using the
# archive's OBJ mesh with the generated material applied.

const Writer = preload("res://addons/ambientcg/handlers/ambient_resource_writer.gd")


static func find_mesh(files: PackedStringArray) -> String:
	for file in files:
		if file.get_extension().to_lower() == "obj":
			return file
	return ""


static func write_model_scene(
	path: String, node_name: String, mesh_path: String, material_path: String
) -> Error:
	if mesh_path.is_empty():
		return ERR_FILE_NOT_FOUND

	var writer := Writer.new()
	var props := {"mesh": writer.ext("Mesh", mesh_path)}
	if not material_path.is_empty():
		props["material_override"] = writer.ext("Material", material_path)
	return Writer.save_text(path, writer.build_scene(node_name, "MeshInstance3D", props))
