extends Node

## 打击感（autoload）：命中顿帧（hitstop）+ 屏幕震动（shake）。
## 计时全部用 Time.get_ticks_msec（真实时间）：_process 的 delta 会被 Engine.time_scale 缩放，
## 顿帧期间用 delta 计时会永远走不完；也不能用 Timer（同样受 time_scale 影响）。
## process_mode=ALWAYS：游戏暂停（选卡/商店/死亡）时本节点仍在跑，保证 time_scale 与
## 相机偏移在任何边界（暂停中、切场景瞬间）都能被收回，不会卡死在慢动作/歪相机状态。

var _hitstop_until: int = 0     ## 顿帧结束时刻（ticks msec）
var _shake_until: int = 0       ## 震屏结束时刻
var _shake_duration: int = 1    ## 本次震屏总时长（衰减归一化用）
var _shake_strength: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## 命中顿帧：time_scale 降到 [param scale]，真实时间 [param duration] 秒后恢复 1.0。
## 连续触发只刷新结束时刻，不叠加（顿帧时长不会越打越长）。
func hitstop(duration: float = 0.05, scale: float = 0.3) -> void:
	_hitstop_until = Time.get_ticks_msec() + int(duration * 1000.0)
	Engine.time_scale = scale

## 屏幕震动：当前相机 offset 随机偏移，随剩余时间线性衰减归零。
## 强度刻意小：俯视角原型，宁弱勿晃吐。相机不存在（如 headless）时静默跳过。
func shake(strength: float = 4.0, duration: float = 0.15) -> void:
	_shake_strength = strength
	_shake_duration = maxi(int(duration * 1000.0), 1)
	_shake_until = Time.get_ticks_msec() + _shake_duration

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	## 顿帧恢复：不依赖任何场景内节点，暂停/切场景都拦不住它回到 1.0
	if Engine.time_scale != 1.0 and now >= _hitstop_until:
		Engine.time_scale = 1.0
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	if now < _shake_until:
		var t := float(_shake_until - now) / float(_shake_duration)
		cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_strength * t
	elif cam.offset != Vector2.ZERO:
		cam.offset = Vector2.ZERO
