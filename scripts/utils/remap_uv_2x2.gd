@tool
extends EditorScript

const MESHES := [
	"res://models/Library/track-straight.mesh",
	"res://models/Library/track-corner.mesh",
	"res://models/Library/track-finish.mesh",
	"res://models/Library/track-ramp.mesh",
	"res://models/Library/track-half-ramp.mesh",
]

func _run() -> void:
	var ref_img: Image = load("res://models/Textures/colormap.png").get_image()
	for path in MESHES:
		if not ResourceLoader.exists(path):
			continue
		var mesh: ArrayMesh = load(path)
		var mdt := MeshDataTool.new()
		if mdt.create_from_surface(mesh, 0) != OK:
			continue

		for i in mdt.get_vertex_count():
			var uv := mdt.get_vertex_uv(i)
			var n := mdt.get_vertex_normal(i)
			var px := clampi(int(uv.x * ref_img.get_width()), 0, ref_img.get_width() - 1)
			var py := clampi(int(uv.y * ref_img.get_height()), 0, ref_img.get_height() - 1)
			var c := ref_img.get_pixel(px, py)
			var sat := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
			var min_c := minf(c.r, minf(c.g, c.b))

			# 1. White markings -> Bottom-Right (0.75, 0.75)
			if min_c > 0.72:
				mdt.set_vertex_uv(i, Vector2(0.75, 0.75))
			# 2. Colored stripes -> Bottom-Left (0.25, 0.75)
			elif sat > 0.18:
				mdt.set_vertex_uv(i, Vector2(0.25, 0.75))
			# 3. Flat upward road surface -> Top-Left (0.25, 0.25)
			elif n.y > 0.7:
				mdt.set_vertex_uv(i, Vector2(0.25, 0.25))
			# 4. Walls -> Top-Right (0.75, 0.25)
			else:
				mdt.set_vertex_uv(i, Vector2(0.75, 0.25))

		var mat := mesh.surface_get_material(0)
		mesh.clear_surfaces()
		mdt.commit_to_surface(mesh)
		if mat != null:
			mesh.surface_set_material(0, mat)
		ResourceSaver.save(mesh, path)
		print("Remapped 2x2 UVs: ", path)
