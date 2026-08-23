class_name ShopUI
extends CanvasLayer

## 商店界面（Phase 2）：玩家与商人 F 交互触发 EventBus.shop_opened 后弹出。
## 真暂停游戏，提供三类商品：治疗药水 / 大治疗 / 随机赐福，按金币扣费。
## process_mode=ALWAYS 保证暂停时仍可点击购买；ESC 或关闭按钮退出。

const BoonClass = preload("res://boon.gd")

## 商品条目（数据驱动，便于后续扩展）。kind 决定购买时的结算分支。
class ShopItem:
	var item_name: String
	var desc: String
	var cost: float
	var kind: String
	var value: float
	var item_id: StringName = &""   ## kind=="item" 时入背包的物品 id

	func _init(p_name: String, p_desc: String, p_cost: float, p_kind: String, p_value: float, p_item_id: StringName = &"") -> void:
		item_name = p_name
		desc = p_desc
		cost = p_cost
		kind = p_kind
		value = p_value
		item_id = p_item_id

var ITEMS: Array[ShopItem] = [
	ShopItem.new("血瓶", "恢复 30 点生命（入背包）", 5.0, "item", 0.0, &"potion"),
	ShopItem.new("大血瓶", "恢复 70 点生命（入背包）", 12.0, "item", 0.0, &"greater_potion"),
	ShopItem.new("随机赐福", "抽取一张神明祝福（已持有则升级）", 10.0, "boon", 0.0),
]

var _panel: Panel
var _dim: ColorRect
var _list: VBoxContainer
var _title: Label
var _hint: Label

var _is_open: bool = false

## 手柄导航状态（同 boon_select_ui 的模式）：当前焦点下标 + 商品按钮数组（_populate_items 时重建）
var _focus_idx: int = 0
var _item_buttons: Array[Button] = []

## 摇杆焦点移动最小间隔（秒，与 boon_select_ui.FOCUS_MOVE_INTERVAL 同值；两处各自定义，
## 改手感时注意同步）：摇杆保持倾斜会持续产生 JoypadMotion 事件，限频后推住 = 每 0.22s 走一步。
## 只对摇杆限频——键盘按键是离散按压，每次必响应。
const FOCUS_MOVE_INTERVAL := 0.22
var _last_focus_move_tick: int = -1000000   ## 上次摇杆焦点移动的 Time.get_ticks_msec()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	EventBus.shop_opened.connect(_on_shop_opened)
	## 键盘/手柄切换时刷新退出键名提示
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
	_panel.size = Vector2(440.0, 380.0)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	_panel.visible = false
	add_child(_panel)

	_title = Label.new()
	_title.name = "Title"
	_title.text = "商店"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 10.0
	_title.offset_bottom = 40.0
	_panel.add_child(_title)

	_list = VBoxContainer.new()
	_list.name = "List"
	_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_list.offset_top = 48.0
	_list.offset_left = 24.0
	_list.offset_right = -24.0
	_list.offset_bottom = -52.0
	_list.add_theme_constant_override("separation", 10)
	_panel.add_child(_list)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = _default_hint_text()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_bottom = -12.0
	_hint.offset_top = -36.0
	_panel.add_child(_hint)

	var close_btn := Button.new()
	close_btn.name = "CloseBtn"
	close_btn.text = "关闭"
	close_btn.size = Vector2(120.0, 32.0)
	close_btn.position = Vector2((_panel.size.x - 120.0) * 0.5, _panel.size.y - 44.0)
	close_btn.pressed.connect(_close)
	_panel.add_child(close_btn)

func _on_shop_opened() -> void:
	call_deferred("_open_shop")

func _open_shop() -> void:
	if _is_open:
		return
	_is_open = true
	_hint.text = _default_hint_text()
	_populate_items()
	_panel.visible = true
	_dim.visible = true
	PauseGuard.acquire(&"shop")

## 退出提示：键名随输入设备变化。键盘 "按 ESC 或点关闭离开" ↔ 手柄 "摇杆选择 · A 确认 / B 关闭"
func _default_hint_text() -> String:
	if InputDevice.gamepad:
		return "摇杆选择 · %s 确认 / %s 关闭" % [InputDevice.hint(&"roll"), InputDevice.hint(&"ui_cancel")]
	return "按 %s 或点关闭离开" % InputDevice.hint(&"ui_cancel")

## 键盘/手柄切换：开着时刷新退出提示（会覆盖 _flash 的瞬时消息，可接受）并重建商品行（热键文案）
func _on_device_changed(_gamepad: bool) -> void:
	if _is_open:
		_hint.text = _default_hint_text()
		_populate_items()

func _populate_items() -> void:
	for child in _list.get_children():
		child.queue_free()
	_item_buttons.clear()
	for it in ITEMS:
		var item := it as ShopItem
		var btn := Button.new()
		btn.name = "Item_" + item.item_name
		btn.custom_minimum_size = Vector2(392.0, 64.0)
		## 消耗品的热键提示按当前输入设备拼（键盘 1/2 ↔ 手柄 LB/RT）
		var desc := item.desc
		if item.item_id != &"":
			desc += "（按 %s 使用）" % Items.hotkey_label(item.item_id)
		btn.text = "%s\n%s\n花费 %d 💰" % [item.item_name, desc, int(item.cost)]
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(_on_buy.bind(item))
		_list.add_child(btn)
		_item_buttons.append(btn)
	## 默认焦点第 1 个商品，打开即有明确高亮，手柄不用先推一下
	_focus_idx = 0
	_update_focus_visual()

func _on_buy(item: ShopItem) -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	if not player.spend_currency(item.cost):
		_flash("金币不足")
		AudioManager.play(&"error")
		return
	AudioManager.play(&"coin")
	match item.kind:
		"item":
			RunState.add_item(item.item_id)
			_flash("已购买 %s（按 %s 使用）" % [item.item_name, Items.hotkey_label(item.item_id)])
		"boon":
			_grant_random_boon(player)

## 随机给一张祝福：已满级的卡不进池；抽到已持有的卡即升级（grant_boon 内部处理）。
func _grant_random_boon(_player: Player) -> void:
	var pool := Boon.make_all_boons()
	var not_maxed := pool.filter(func(b: BoonClass) -> bool: return not _is_maxed(b))
	if not not_maxed.is_empty():
		pool = not_maxed
	var picked := pool[randi_range(0, pool.size() - 1)] as BoonClass
	var is_upgrade := BoonManager.find_owned(picked.card_id) != null
	BoonManager.grant_boon(picked)
	_flash("%s：%s · %s" % ["升级赐福" if is_upgrade else "获得赐福", picked.god, picked.boon_name])

## 该卡已持有且满级
func _is_maxed(b: BoonClass) -> bool:
	var owned := BoonManager.find_owned(b.card_id)
	return owned != null and owned.level >= Boon.MAX_LEVEL

func _flash(msg: String) -> void:
	_hint.text = msg

## 手柄导航（同 boon_select_ui 的模式）：上下移焦点（循环，摇杆限频），A（roll）/X（attack）确认购买，
## ESC/手柄 B 关闭。全部消费掉，防穿透到背包/玩家。
func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()   ## 消费掉，避免背包面板跟着弹开
	elif event.is_action_pressed("move_down"):
		_move_focus(1, event is InputEventJoypadMotion)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_up"):
		_move_focus(-1, event is InputEventJoypadMotion)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("roll") or event.is_action_pressed("attack"):
		_confirm_focus()
		get_viewport().set_input_as_handled()

## 焦点上下循环移动。[param from_stick] 为 true（摇杆事件）时吃 FOCUS_MOVE_INTERVAL 限频
func _move_focus(dir: int, from_stick: bool = false) -> void:
	var total := _item_buttons.size()
	if total == 0:
		return
	if from_stick:
		var now := Time.get_ticks_msec()
		if now - _last_focus_move_tick < int(FOCUS_MOVE_INTERVAL * 1000.0):
			return
		_last_focus_move_tick = now
	_focus_idx = (_focus_idx + dir + total) % total
	_update_focus_visual()

## 确认购买当前焦点商品，等同点击（按钮与 ITEMS 按下标一一对应）
func _confirm_focus() -> void:
	if _focus_idx < 0 or _focus_idx >= ITEMS.size():
		return
	_on_buy(ITEMS[_focus_idx])

## 焦点高亮：焦点商品提亮，非焦点压暗（同选卡界面风格）
func _update_focus_visual() -> void:
	for i in range(_item_buttons.size()):
		_item_buttons[i].modulate = Color(1.2, 1.2, 1.2) if i == _focus_idx else Color(0.65, 0.65, 0.65)

func _close() -> void:
	_panel.visible = false
	_dim.visible = false
	_item_buttons.clear()
	_is_open = false
	PauseGuard.release(&"shop")
