class_name TimeUtil

# TimeUtil.gd
# 时间相关工具，静态方法，直接 TimeUtil.xxx() 调用

# ==========
## 格式化
# ==========

## 秒数 → "MM:SS" 格式，如 125 → "02:05"
static func format_seconds(seconds: float) -> String:
	var s := int(round(seconds))
	var m := s / 60
	s = s % 60
	return "%02d:%02d" % [m, s]


## 秒数 → "HH:MM:SS" 格式
static func format_seconds_hms(seconds: float) -> String:
	var s := int(round(seconds))
	var h := s / 3600
	var m := (s % 3600) / 60
	s = s % 60
	return "%02d:%02d:%02d" % [h, m, s]


## 毫秒 → "MM:SS.ms" 格式
static func format_ms(milliseconds: float) -> String:
	var s := int(milliseconds / 1000.0)
	var ms := int(fmod(milliseconds, 1000.0))
	var m := s / 60
	s = s % 60
	return "%02d:%02d.%03d" % [m, s, ms]


# ==========
## 计时器简化
# ==========

## 创建一个延时回调（比手写 Timer + 连接信号更简洁）
## 注意：调用者需要持有返回的 Timer 引用，防止被 GC
static func delay(node: Node, seconds: float, callback: Callable) -> Timer:
	var timer := Timer.new()
	timer.wait_time = seconds
	timer.one_shot = true
	timer.timeout.connect(callback)
	node.add_child(timer)
	timer.start()
	return timer


## 创建一个反复触发的计时器
static func interval(node: Node, seconds: float, callback: Callable, times: int = 0) -> Timer:
	var timer := Timer.new()
	timer.wait_time = seconds
	timer.one_shot = false
	var count := 0
	var handler := func():
		callback.call()
		count += 1
		if times > 0 and count >= times:
			timer.stop()
			timer.queue_free()
	timer.timeout.connect(handler)
	node.add_child(timer)
	timer.start()
	return timer


# ==========
## 帧率
# ==========

## 获取当前帧率（平滑值，基于最近 10 帧）
static var _fps_samples: Array[float] = []
static var _fps_index: int = 0

static func get_smooth_fps() -> float:
	var fps := Engine.get_frames_per_second()
	if _fps_samples.size() < 10:
		_fps_samples.append(fps)
	else:
		_fps_samples[_fps_index] = fps
	_fps_index = (_fps_index + 1) % 10

	var sum := 0.0
	for v in _fps_samples:
		sum += v
	return sum / _fps_samples.size()
