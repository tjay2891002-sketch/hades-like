extends CanvasLayer

## 死亡界面（autoload）：监听 RunState.player_died，暂停游戏并显示死亡面板。
## "重新开始"：重置 RunState + BoonManager，回到存档房开启新一局。
## 除鼠标点按钮外，面板打开时按 attack/roll/ui_accept 任一键也可重开（键盘 J/空格/回车、手柄 X/A 兼容）。
## process_mode=ALWAYS 保证暂停时按钮仍可点击、_unhandled_input 仍能收到输入。

var _dim: ColorRect
var _panel: Panel
var _info: Label
var _hint: Label
var _is_open: bool = false
var _banked_line: String = ""   ## 局外成长结算行（run_banked 先于 player_died 面板弹出到达）

func _ready() -> void:
	layer = 10   ## 压在所有游戏内 UI 之上
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	RunState.player_died.connect(_on_player_died)
	## 结算行走信号而非直接读 MetaState.last_earned：autoload 连接顺序保证本信号先于 _on_player_died 到达
	MetaState.run_banked.connect(_on_run_banked)
	## 键盘/手柄切换时刷新重开键名提示
	if not InputDevice.device_changed.is_connected(_on_device_changed):
		InputDevice.device_changed.connect(_on_device_changed)

func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.05, 0.0, 0.0, 0.75)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	add_child(_dim)

	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.size = Vector2(360.0, 220.0)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	_panel.visible = false
	add_child(_panel)

	var title := Label.new()
	title.text = "你死了"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 24.0
	title.offset_bottom = 60.0
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35, 1))
	_panel.add_child(title)

	_info = Label.new()
	_info.name = "Info"
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_info.offset_top = 70.0
	_info.offset_bottom = 130.0
	_panel.add_child(_info)

	var btn := Button.new()
	btn.text = "重新开始"
	btn.size = Vector2(140.0, 40.0)
	btn.position = Vector2((_panel.size.x - 140.0) * 0.5, 150.0)
	btn.pressed.connect(_on_restart)
	_panel.add_child(btn)

	## 键位提示行：键盘 "按 J / 空格 重新开始" ↔ 手柄 "按 X / A 重新开始"
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_bottom = -6.0
	_hint.offset_top = -26.0
	_hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8, 1))
	_panel.add_child(_hint)
	_refresh_hint()

## 重开键名提示：用 hint() 按当前设备拼（attack + roll 两路都可重开）
func _refresh_hint() -> void:
	_hint.text = "按 %s / %s 重新开始" % [InputDevice.hint(&"attack"), InputDevice.hint(&"roll")]

func _on_device_changed(_gamepad: bool) -> void:
	_refresh_hint()

## 面板打开时：attack/roll/ui_accept 任一键 = 点"重新开始"（复用 _on_restart，鼠标按钮保留可点）
func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("attack") or event.is_action_pressed("roll") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()   ## 消费掉，防止复活后原地攻击/翻滚
		_on_restart()

func _on_run_banked(earned: int, total: int) -> void:
	_banked_line = "+%d 英灵碎片（共 %d）" % [earned, total]

func _on_player_died() -> void:
	if _is_open:
		return
	_is_open = true
	_info.text = "坚持到了房间 %d · 等级 %d\n祝福与进度已消散\n%s" % [RunState.room_index, RunState.level, _banked_line]
	_panel.visible = true
	_dim.visible = true
	PauseGuard.acquire(&"death")

func _on_restart() -> void:
	PauseGuard.release(&"death")
	_panel.visible = false
	_dim.visible = false
	_is_open = false
	RunState.reset_run()
	BoonManager.reset()
	get_tree().change_scene_to_file("res://save_room.tscn")
