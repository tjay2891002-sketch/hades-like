extends CanvasLayer

## 背包面板（autoload）：ESC 开合，全场景可用。
## 两个区：消耗品（可使用）+ 赐福（n/10，只读列表）。
## 替换模式：赐福满格后再获得新卡时自动打开（open_replace），
## 玩家选择替换哪个槽位，或放弃新卡。（现卡池仅 10 张机制卡，此流程仅作兜底）
## process_mode=ALWAYS 保证暂停时仍可操作。

var _dim: ColorRect
var _panel: Panel
var _list: VBoxContainer
var _title: Label
var _hint: Label
var _is_open: bool = false
var _replace_pending: Boon = null   ## 替换模式下待安放的新卡

func _ready() -> void:
	layer = 5   ## 高于游戏内 UI（选卡2/商店3），低于 DeathUI(10)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	RunState.inventory_changed.connect(_on_inventory_changed)
	## 键盘/手柄切换时刷新关闭键名提示
	if not InputDevice.device_changed.is_connected(_on_device_changed):
		InputDevice.device_changed.connect(_on_device_changed)

func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.0, 0.0, 0.0, 0.6)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	add_child(_dim)

	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.size = Vector2(560.0, 500.0)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	_panel.visible = false
	add_child(_panel)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 8.0
	_title.offset_bottom = 34.0
	_panel.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 38.0
	scroll.offset_left = 16.0
	scroll.offset_right = -16.0
	scroll.offset_bottom = -40.0
	_panel.add_child(scroll)

	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	_hint = Label.new()
	_hint.text = "按 %s 关闭" % InputDevice.hint(&"ui_cancel")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_bottom = -8.0
	_hint.offset_top = -32.0
	_panel.add_child(_hint)

## 键盘/手柄切换：刷新关闭键名提示（面板隐藏时改文本也无害）；开着时重建列表（热键文案）
func _on_device_changed(_gamepad: bool) -> void:
	_hint.text = "按 %s 关闭" % InputDevice.hint(&"ui_cancel")
	if _is_open:
		_refresh()

func _unhandled_input(event: InputEvent) -> void:
	## ui_cancel 动作（ESC / 手柄 B）：开着则关（替换模式=放弃新卡），没开且游戏未暂停则开
	if not event.is_action_pressed("ui_cancel"):
		return
	if _is_open:
		if _replace_pending != null:
			_cancel_replace()   ## 替换模式下 ESC = 放弃新卡
		else:
			_close()
		get_viewport().set_input_as_handled()
	elif not get_tree().paused:
		# 其他 UI 开着（游戏已暂停）时不抢 ESC，让商店/选卡自己处理
		_open()
		get_viewport().set_input_as_handled()

## 赐福满格后获得新卡：打开背包进入替换模式（由选卡界面/商店调用）
func open_replace(new_boon: Boon) -> void:
	_replace_pending = new_boon
	_open()

func _open() -> void:
	_is_open = true
	_refresh()
	_panel.visible = true
	_dim.visible = true
	PauseGuard.acquire(&"inventory")

func _close() -> void:
	_is_open = false
	_replace_pending = null
	_panel.visible = false
	_dim.visible = false
	PauseGuard.release(&"inventory")

func _on_inventory_changed() -> void:
	if _is_open:
		_refresh()

# ---------- 内容构建 ----------

func _refresh() -> void:
	_title.text = "背包（替换模式：选择要换下的赐福）" if _replace_pending != null else "背包"
	for c in _list.get_children():
		c.queue_free()

	# 替换模式：新卡信息置顶
	if _replace_pending != null:
		var new_info := Label.new()
		new_info.text = "新赐福：%s · %s\n%s" % [
			_replace_pending.god, _replace_pending.boon_name,
			_replace_pending.description,
		]
		new_info.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0, 1))
		_list.add_child(new_info)
		var discard_btn := Button.new()
		discard_btn.text = "放弃这张新卡"
		discard_btn.pressed.connect(_cancel_replace)
		_list.add_child(discard_btn)
		_list.add_child(HSeparator.new())

	# 消耗品区
	var inv_header := Label.new()
	inv_header.text = "— 消耗品 —"
	_list.add_child(inv_header)
	if RunState.inventory.is_empty():
		var empty := Label.new()
		empty.text = "（空）"
		_list.add_child(empty)
	else:
		for id in RunState.inventory.keys():
			_add_item_row(id)
	_list.add_child(HSeparator.new())

	# 赐福区
	var boon_header := Label.new()
	boon_header.text = "— 赐福（%d/%d）—" % [BoonManager.active_boons.size(), BoonManager.MAX_BOONS]
	_list.add_child(boon_header)
	for b in BoonManager.active_boons:
		_add_boon_row(b)

func _add_item_row(id: StringName) -> void:
	var def: Dictionary = Items.DEFS.get(id, {})
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 44.0)
	var info := Label.new()
	info.text = "%s ×%d\n%s [按 %s]" % [
		def.get("name", String(id)),
		RunState.item_count(id),
		def.get("desc", ""),
		Items.hotkey_label(id),   ## 键名随输入设备变化
	]
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var use_btn := Button.new()
	use_btn.text = "使用"
	use_btn.custom_minimum_size = Vector2(72.0, 36.0)
	use_btn.pressed.connect(_on_use.bind(id))
	row.add_child(use_btn)
	_list.add_child(row)

func _add_boon_row(b: Boon) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 44.0)
	var info := Label.new()
	info.text = "%s · %s (Lv.%d)\n%s" % [b.god, b.boon_name, b.level, b.description]
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	if _replace_pending != null:
		var btn := Button.new()
		var same := (b.card_id == _replace_pending.card_id)
		btn.text = "相同" if same else "替换"
		btn.disabled = same
		btn.custom_minimum_size = Vector2(72.0, 36.0)
		btn.pressed.connect(_on_replace_chosen.bind(b))
		row.add_child(btn)
	_list.add_child(row)

# ---------- 操作 ----------

func _on_use(id: StringName) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if RunState.use_item(id, player):
		AudioManager.play(&"confirm")   ## 使用成功才响；无效/空则不响
	# use_item 会发 inventory_changed → 自动刷新列表

func _on_replace_chosen(old: Boon) -> void:
	var new_boon := _replace_pending
	_replace_pending = null
	BoonManager.replace_boon(old, new_boon)
	_close()

## 放弃新卡（替换模式 ESC 或点按钮）：新卡直接丢弃，不动现有槽位
func _cancel_replace() -> void:
	_replace_pending = null
	_close()
