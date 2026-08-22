extends SceneTree

## Screenshot harness: boots the real main scene, waits, captures PNG.
## Usage: xvfb godot --path . --script tools/screenshot.gd -- out.png

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "/tmp/shot.png"
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for i in range(8):
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("SAVED ", out_path, " ", img.get_size())
	# Dump button rects for CDP-driven QA later.
	_dump_rects(main)
	quit(0)


func _dump_rects(main) -> void:
	var btns: Array = main.find_children("*", "Button", true, false)
	for b in btns:
		var g: Rect2 = b.get_global_rect()
		print("BTN %s=(%d,%d,%d,%d)" % [b.text, int(g.position.x), int(g.position.y), int(g.size.x), int(g.size.y)])
