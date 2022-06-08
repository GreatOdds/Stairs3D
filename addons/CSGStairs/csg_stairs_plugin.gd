tool
extends EditorPlugin


func _enter_tree():
	add_custom_type("CSGStairs", "Path", preload("csg_stairs.gd"), preload("CSGStairs.svg"))


func _exit_tree():
	remove_custom_type("CSGStairs")
