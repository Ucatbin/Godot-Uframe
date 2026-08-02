class_name UFrameSceneService
extends Node

## 可选的场景切换与叠加场景服务，通过 UFrame.scenes 使用。
##
## change_scene() 立即提交普通切换；change_scene_async() 在线程中加载大场景。[br]
## scene_changed 只在新场景真正成为 current_scene 后发出，失败不会伪报成功。

## 场景切换请求通过验证、即将提交时发出。
signal scene_changing(from: String, to: String)
## 新场景已成为 SceneTree.current_scene 时发出。
signal scene_changed(new_scene: String)

## 最近一次确认完成的主场景路径。
var current_scene_path := ""
var _overlay_scenes: Dictionary[String, Node] = {}
var _request_generation := 0

# Godot 会在当前帧末尾释放旧场景，再在后续帧登记新的 current_scene。
# 不应假定等待一帧就一定完成；这里给同步切换留出一个很小但明确的上限。
const SCENE_CONFIRMATION_MAX_FRAMES := 16

func _ready() -> void:
	var current := get_tree().current_scene
	if current:
		current_scene_path = current.scene_file_path

## 请求普通场景切换并返回 Godot Error。成功后可等待 scene_changed 信号。
func change_scene(path: String) -> Error:
	var request := _submit_scene_change(path)
	var error: Error = request.error
	if error == OK:
		_confirm_scene_change.call_deferred(path, int(request.generation))
	return error

## 切换场景并等待新场景真正成为 current_scene。
## 画面过渡等必须知道最终结果的系统应使用本方法，避免无限等待信号。
func change_scene_confirmed(path: String) -> Error:
	var request := _submit_scene_change(path)
	var error: Error = request.error
	if error != OK:
		return error
	return await _confirm_scene_change(path, int(request.generation))

## 在线程中加载场景。返回 OK 只表示新场景已经成为 current_scene。
func change_scene_async(path: String, on_progress: Callable = Callable()) -> Error:
	if not _is_valid_scene_path(path):
		return ERR_FILE_NOT_FOUND
	_request_generation += 1
	var generation := _request_generation
	var previous := current_scene_path
	scene_changing.emit(previous, path)
	var error := ResourceLoader.load_threaded_request(path)
	if error != OK:
		push_error("[UFrameSceneService] 无法开始加载：%s (%d)" % [path, error])
		return error
	var progress: Array[float] = []
	while generation == _request_generation:
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				if on_progress.is_valid():
					on_progress.call(progress[0] if not progress.is_empty() else 0.0)
			ResourceLoader.THREAD_LOAD_LOADED:
				var packed := ResourceLoader.load_threaded_get(path) as PackedScene
				if packed == null:
					return ERR_FILE_CORRUPT
				error = get_tree().change_scene_to_packed(packed)
				if error != OK:
					return error
				_clear_overlay_records()
				error = await _confirm_scene_change(path, generation)
				if error != OK:
					return error
				if on_progress.is_valid():
					on_progress.call(1.0)
				return OK
			ResourceLoader.THREAD_LOAD_FAILED:
				return ERR_CANT_OPEN
			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				return ERR_INVALID_DATA
		await get_tree().process_frame
	return ERR_SKIP

## 重新加载当前主场景。
func reload_current() -> Error:
	var path := current_scene_path
	if path.is_empty() and get_tree().current_scene:
		path = get_tree().current_scene.scene_file_path
	return change_scene(path) if not path.is_empty() else ERR_DOES_NOT_EXIST

## 在当前主场景下实例化一个叠加场景；相同路径只会存在一份。
func add_scene(path: String) -> Node:
	if _overlay_scenes.has(path) and is_instance_valid(_overlay_scenes[path]):
		return _overlay_scenes[path]
	if not _is_valid_scene_path(path) or get_tree().current_scene == null:
		return null
	var packed := ResourceLoader.load(path) as PackedScene
	if packed == null:
		return null
	var instance := packed.instantiate()
	get_tree().current_scene.add_child(instance)
	_overlay_scenes[path] = instance
	instance.tree_exited.connect(func() -> void:
		if _overlay_scenes.get(path) == instance:
			_overlay_scenes.erase(path)
	, CONNECT_ONE_SHOT)
	return instance

## 移除一个由 add_scene() 创建的叠加场景。
func remove_scene(path: String) -> bool:
	var instance := _overlay_scenes.get(path) as Node
	if not is_instance_valid(instance):
		_overlay_scenes.erase(path)
		return false
	_overlay_scenes.erase(path)
	instance.queue_free()
	return true

func _submit_scene_change(path: String) -> Dictionary:
	if not _is_valid_scene_path(path):
		return {"error": ERR_FILE_NOT_FOUND, "generation": _request_generation}
	_request_generation += 1
	var generation := _request_generation
	var previous := current_scene_path
	scene_changing.emit(previous, path)
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		push_error("[UFrameSceneService] 场景切换失败：%s (%d)" % [path, error])
		return {"error": error, "generation": generation}
	_clear_overlay_records()
	return {"error": OK, "generation": generation}

func _confirm_scene_change(path: String, generation: int) -> Error:
	# 场景切换的提交点位于帧边界。有限轮询既兼容不同渲染后端，
	# 又能在请求被覆盖或引擎没有完成切换时明确返回错误。
	for attempt in range(SCENE_CONFIRMATION_MAX_FRAMES + 1):
		if generation != _request_generation:
			return ERR_SKIP
		if _current_scene_matches(path):
			current_scene_path = path
			scene_changed.emit(path)
			return OK
		if attempt < SCENE_CONFIRMATION_MAX_FRAMES:
			await get_tree().process_frame
	push_error("[UFrameSceneService] 等待新场景超时：%s" % path)
	return ERR_TIMEOUT

func _current_scene_matches(path: String) -> bool:
	var current := get_tree().current_scene
	return current != null and current.scene_file_path == path

func _is_valid_scene_path(path: String) -> bool:
	if path.is_empty() or not ResourceLoader.exists(path, "PackedScene"):
		push_error("[UFrameSceneService] 场景不存在：%s" % path)
		return false
	return true

func _clear_overlay_records() -> void:
	# 叠加节点属于旧主场景，场景切换会统一释放；这里只清理持有的引用。
	_overlay_scenes.clear()
