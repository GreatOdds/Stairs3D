@tool
extends EditorPlugin

const CSG_STAIR_SCRIPT := preload("csg_stairs.gd")
const CSG_STAIR_ICON := preload("CSGStairs.svg")

func _enter_tree():
	add_custom_type("CSGStairs", "Path", CSG_STAIR_SCRIPT, CSG_STAIR_ICON)


func _exit_tree():
	remove_custom_type("CSGStairs")
