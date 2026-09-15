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
		if not await _check_scene_lifecycle():
			push_error("场景服务的原生切换、重载或请求覆盖回归失败")
			get_tree().quit(1)
			return
		var mode := "ASYNC_" if asynchronous else ""
		print("UFRAME_%sSCENE_TRANSITION_OK" % mode)
		get_tree().quit(0)
		return
	push_error("场景过渡没有完成，或全屏遮罩仍未恢复透明")
	get_tree().quit(1)

## 本探针归 UFrame 所有，能够在真实场景替换后检查最终状态。
func _check_scene_lifecycle() -> bool:
	var tree := get_tree()
	var service := UFrame.scenes
	var native_path := "res://tests/performance/performance_pool_item.tscn"
	if tree.change_scene_to_file(native_path) != OK:
		return false
	await tree.scene_changed
	if service.current_scene_path != native_path:
		return false
	var previous_id := tree.current_scene.get_instance_id()
	if service.reload_current() != OK:
		return false
	await service.scene_changed
	if tree.current_scene.get_instance_id() == previous_id:
		return false
	var overlay_path := "res://tests/scene_transition_target.tscn"
	var overlay := service.add_scene(overlay_path)
	if overlay == null or service.add_scene(overlay_path) != overlay:
		return false
	if not service.remove_scene(overlay_path) or service.remove_scene(overlay_path):
		return false
	await tree.process_frame
	await tree.process_frame
	if is_instance_valid(overlay):
		return false
	# 请求通知内发起的新请求应胜出，外层请求不能随后覆盖它。
	service.scene_changing.connect(func(_from: String, _to: String) -> void:
		service.change_scene(native_path)
	, CONNECT_ONE_SHOT)
	if service.change_scene(overlay_path) != ERR_SKIP:
		return false
	await service.scene_changed
	if service.current_scene_path != native_path:
		return false
	# 无效路径必须及时返回失败，并撤下遮罩，不等待永远不会发生的场景信号。
	var failed := await UFrame.transitions.change_scene("", 0.0)
	var curtain := UFrame.transitions.get("_overlay") as ColorRect
	return not failed and not UFrame.transitions.is_busy() and is_zero_approx(curtain.color.a)
