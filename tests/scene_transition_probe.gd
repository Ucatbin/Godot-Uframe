extends Node

## 挂到 UFrame 下，因此旧主场景释放后仍能检查过渡的最终结果。

var target_path := ""
var asynchronous := false

func run() -> void:
	await get_tree().process_frame
	var succeeded: bool
	if asynchronous:
		succeeded = await UFrame.transitions.change_scene_async(target_path, 0.0)
	else:
		succeeded = await UFrame.transitions.change_scene(target_path, 0.0)
	var overlay := UFrame.transitions.get("_overlay") as ColorRect
	var current := get_tree().current_scene
	var path_matches := current != null and current.scene_file_path == target_path
	var service_matches := UFrame.scenes.current_scene_path == target_path
	var overlay_cleared := overlay != null and is_zero_approx(overlay.color.a)
	if succeeded and path_matches and service_matches and overlay_cleared and not UFrame.transitions.is_busy():
		var mode := "ASYNC_" if asynchronous else ""
		print("UFRAME_%sSCENE_TRANSITION_OK" % mode)
		get_tree().quit(0)
		return
	push_error("场景过渡没有完成，或全屏遮罩仍未恢复透明")
	get_tree().quit(1)

