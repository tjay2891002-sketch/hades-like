extends Node

## 输入设备跟踪（autoload）：键盘/手柄模式自动切换，UI 提示文案按当前设备出对应键名。
## 判据：手柄按钮按下、或摇杆推动（|axis_value|>0.3 防漂移误触）→ 手柄模式；
## 键盘按键 / 鼠标点击 → 键盘模式。不监听鼠标移动，避免悬停误切。默认键盘模式。
## 切换时发 device_changed 信号，各 UI 监听后刷新提示文本。

signal device_changed(gamepad: bool)

## 动作 -> [键盘键名, 手柄键名]（键名按 Xbox 布局习惯标注，与 project.godot InputMap 绑定一致）
const HINTS: Dictionary = {
	&"attack": ["J", "X"],
	&"roll": ["空格", "A"],
	&"interact": ["F", "RB"],
	&"weapon_switch": ["Q", "Y"],
	&"item_1": ["1", "LB"],
	&"item_2": ["2", "RT"],
	&"ui_cancel": ["ESC", "B"],
}

var gamepad: bool = false   ## true=手柄模式

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_set_gamepad(true)
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.3:
		_set_gamepad(true)
	elif event is InputEventKey or event is InputEventMouseButton:
		_set_gamepad(false)

func _set_gamepad(v: bool) -> void:
	if gamepad == v:
		return
	gamepad = v
	device_changed.emit(v)

## 当前设备下动作对应的键名提示（未收录的动作返回 "?"，调用点一眼能看出漏配）
func hint(action: StringName) -> String:
	var pair: Array = HINTS.get(action, ["?", "?"])
	return pair[1] if gamepad else pair[0]
