class_name BoonSelectUI
extends CanvasLayer

## 神明选择 UI（2c-2）。Hades 式节奏：
## - 开局（起始房间）弹一次，作为 build 起手赐福
## - 普通房清场不弹
## - 击败精英怪后再弹一次（掉落奖励）
## 弹卡时暂停游戏（真暂停），选完恢复。本节点 process_mode=ALWAYS 保证暂停时仍响应点击。
## Phase B：抽卡改为从卡池（10 张机制卡）加权随机抽 2~3 张不重复，
## 偏向与已持有卡同神/同标签的卡；已持有的卡再次抽到即升级，卡面显示等级与联动提示。

const BoonClass = preload("res://boon.gd")

var _panel: Panel
var _dim: ColorRect
var _cards_box: Control
var _title: Label
var _op_hint: Label

var _pool: Array[BoonClass] = []
var _is_open: bool = false

## 手柄导航状态：当前焦点下标 + 本批卡片按钮/对应赐福（_populate_cards 时重建）
var _focus_idx: int = 0
var _card_buttons: Array[Button] = []
var _current_choices: Array[BoonClass] = []

## 摇杆焦点移动最小间隔（秒）：摇杆保持倾斜时 JoypadMotion 事件持续产生，
## 不限频焦点会在卡片间飞速连跳；限频后推住 = 每 0.22s 走一步、轻推 = 只走一步。
## 只对摇杆限频——键盘按键是离散物理按压，必须每次响应。数值按手感调。
const FOCUS_MOVE_INTERVAL := 0.22
var _last_focus_move_tick: int = -1000000   ## 上次摇杆焦点移动的 Time.get_ticks_msec()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_build_pool()
	if not EventBus.boon_offer_requested.is_connected(_on_boon_offer_requested):
		EventBus.boon_offer_requested.connect(_on_boon_offer_requested)
	## 键盘/手柄切换时刷新操作提示行
	if not InputDevice.device_changed.is_connected(_on_device_changed):
		InputDevice.device_changed.connect(_on_device_changed)
	# Boss 击杀奖励：回到主场景后自动弹一次赐福选择（消费一次性标记，不限神/卡）
	if RunState.pending_boon_offer:
		RunState.pending_boon_offer = false
		call_deferred("_open_offer", &"", &"")

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
	_panel.size = Vector2(860, 400)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	_panel.visible = false
	add_child(_panel)

	_title = Label.new()
	_title.name = "Title"
	_title.text = "选择一张祝福"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 8.0
	_title.offset_bottom = 36.0
	_panel.add_child(_title)

	# 卡片区：纯绝对定位容器，避免 HBox 在动态创建+拉伸时把末张挤出面板
	_cards_box = Control.new()
	_cards_box.name = "Cards"
	_cards_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cards_box.offset_top = 56.0
	_cards_box.offset_left = 16.0
	_cards_box.offset_right = -16.0
	_cards_box.offset_bottom = -16.0
	_panel.add_child(_cards_box)

	# 操作提示行：键盘 "鼠标点选 / ESC 跳过" ↔ 手柄 "摇杆选择 · A 确认 / B 跳过"
	_op_hint = Label.new()
	_op_hint.name = "OpHint"
	_op_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_op_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_op_hint.offset_top = 40.0
	_op_hint.offset_bottom = 54.0
	_op_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 1))
	_panel.add_child(_op_hint)
	_refresh_op_hint()

func _build_pool() -> void:
	_pool = Boon.make_all_boons()

func _on_boon_offer_requested(god_filter: StringName, card_id: StringName) -> void:
	call_deferred("_open_offer", god_filter, card_id)

## 打开赐福选择。[param god_filter] 为空=任意神；指定神名=只在该神卡池抽。
## [param card_id] 非空时只出这一张卡（雕像代表卡池里的一张具体机制卡）。
func _open_offer(god_filter: StringName = &"", card_id: StringName = &"") -> void:
	if _is_open:
		return
	_is_open = true
	_clear_cards()
	var pool := _pool.duplicate()
	if card_id != &"":
		pool = pool.filter(func(b: BoonClass) -> bool: return b.card_id == card_id)
	elif god_filter != &"":
		pool = pool.filter(func(b: BoonClass) -> bool: return b.god == god_filter)
	# 已持有的卡不排除（抽到即升级），但已满级的卡不占卡位
	var not_maxed := pool.filter(func(b: BoonClass) -> bool: return not _is_maxed(b))
	if not not_maxed.is_empty():
		pool = not_maxed
	if pool.is_empty():
		# 指定卡/该神卡全满级：退而从对应池（排除满级）中抽，保证有卡可选
		pool = _pool.duplicate()
		if god_filter != &"":
			pool = pool.filter(func(b: BoonClass) -> bool: return b.god == god_filter)
		pool = pool.filter(func(b: BoonClass) -> bool: return not _is_maxed(b))
	if pool.is_empty():
		pool = _pool.duplicate()
	if god_filter != &"":
		_title.text = "%s 的赐福 · 已持有 %d 张" % [String(god_filter), BoonManager.active_boons.size()]
	else:
		_title.text = "选择一张祝福（已持有 %d 张）" % BoonManager.active_boons.size()
	var choices := _draw_offer_from(pool, god_filter != &"")
	_populate_cards(choices)
	_panel.visible = true
	_dim.visible = true
	PauseGuard.acquire(&"boon_select")

## 操作提示行：用 hint() 按当前设备拼，键盘 "鼠标点选 / ESC 跳过" ↔ 手柄 "摇杆选择 · A 确认 / B 跳过"
func _refresh_op_hint() -> void:
	if InputDevice.gamepad:
		_op_hint.text = "摇杆选择 · %s 确认 / %s 跳过" % [InputDevice.hint(&"roll"), InputDevice.hint(&"ui_cancel")]
	else:
		_op_hint.text = "鼠标点选 / %s 跳过" % InputDevice.hint(&"ui_cancel")

func _on_device_changed(_gamepad: bool) -> void:
	_refresh_op_hint()

func _clear_cards() -> void:
	for c in _cards_box.get_children():
		c.queue_free()
	_card_buttons.clear()
	_current_choices.clear()

## 查已持有的同 card_id 卡（未持有返回 null）：升级判定与卡面等级显示用
func _owned_card(p_card_id: StringName) -> BoonClass:
	return BoonManager.find_owned(p_card_id) as BoonClass

## 该卡已持有且满级（不再进入卡池）
func _is_maxed(b: BoonClass) -> bool:
	var owned := _owned_card(b.card_id)
	return owned != null and owned.level >= Boon.MAX_LEVEL

## 加权随机抽 2~3 张不重复：同神权重 +2、每张同标签权重 +1。
## 普通 offer 强制不同神——否则持有某神后权重倾斜，三张卡经常全是同一神，读起来就是"重复"。
## 单神神像（force_same_god=true）则只去重，从该神卡池随机抽 3 张三选一。
func _draw_offer_from(pool: Array[BoonClass], force_same_god: bool = false) -> Array[BoonClass]:
	var n := 3 if force_same_god else randi_range(2, 3)
	if pool.size() < n:
		n = pool.size()
	var weights: Array[float] = []
	for b in pool:
		var w := 1.0
		if BoonManager.owned_by_god.get(b.god, 0) > 0:
			w += 2.0
		for t in b.tags:
			if BoonManager.owned_tags.get(t, 0) > 0:
				w += 1.0
		weights.append(w)

	var chosen: Array[BoonClass] = []
	var idxs: Array[int] = []
	for i in range(pool.size()):
		idxs.append(i)
	for _k in range(n):
		if idxs.is_empty():
			break
		var total_w := 0.0
		for i in idxs:
			total_w += weights[i]
		var r := randf() * total_w
		var acc := 0.0
		var pick := idxs[0]
		for i in idxs:
			acc += weights[i]
			if r <= acc:
				pick = i
				break
		chosen.append(pool[pick])
		if force_same_god:
			# 单神池：只去重卡，允许同神多张（三选一来自同一神）
			idxs = idxs.filter(func(i: int) -> bool: return i != pick)
		else:
			# 抽中的神整组移出候选，保证每张卡来自不同的神
			var picked_god: StringName = pool[pick].god
			idxs = idxs.filter(func(i: int) -> bool: return pool[i].god != picked_god)
	return chosen

func _populate_cards(choices: Array[BoonClass]) -> void:
	var total := choices.size()
	if total <= 0:
		## 防御：抽卡结果为空时直接关界面，避免下方 card_w 除零（当前上游兜底已保证非空）。
		## 注意此时 PauseGuard 尚未 acquire，_close 里的 release 是无害空操作。
		_close()
		return
	var area_w := _panel.size.x - 32.0
	var area_h := _panel.size.y - 56.0 - 16.0   ## 56 = 标题+操作提示行高度（与 _cards_box.offset_top 一致）
	var gap := 16.0
	var card_w := (area_w - gap * float(total - 1)) / float(total)
	_card_buttons.clear()
	_current_choices = choices
	for i in range(total):
		_add_card(choices[i], i, card_w, area_h, gap)
	## 默认焦点：3 张取中间、2 张取第 1 张（即 (total-1)/2），打开即有明确高亮，手柄不用先推一下
	_focus_idx = (total - 1) / 2
	_update_focus_visual()

## 标签中文名
func _tag_label(t: StringName) -> String:
	match t:
		&"thunder": return "雷"
		&"tide": return "潮"
		&"blood": return "血"
		&"area": return "范围"
		&"ultimate": return "终极"
		&"gale": return "风"
		&"forge": return "锻造"
		_: return String(t)

## 计算本卡与已持有集合的联动提示
func _synergy_hint(b: BoonClass) -> String:
	var parts: Array[String] = []
	if BoonManager.owned_by_god.get(b.god, 0) > 0:
		parts.append("同神:" + String(b.god))
	for t in b.tags:
		if BoonManager.owned_tags.get(t, 0) > 0:
			parts.append("标签:" + _tag_label(t))
	if parts.is_empty():
		return "新系列 · 暂无联动"
	return "联动 → " + ", ".join(parts)

func _add_card(boon: BoonClass, index: int, card_w: float, card_h: float, gap: float) -> void:
	var btn := Button.new()
	btn.name = "Card" + str(index)
	btn.size = Vector2(card_w, card_h)
	btn.position = Vector2(index * (card_w + gap), 0.0)
	var owned := _owned_card(boon.card_id)
	var lv_txt := "新卡 Lv.1"
	if owned != null:
		lv_txt = "升级 Lv.%d → Lv.%d" % [owned.level, owned.level + 1]
	var hint := _synergy_hint(boon)
	## 终极（ultimate）卡：给新手补一句"这是什么/怎么用"的引导，避免看不懂标签
	var guide := ""
	if boon.tags.has(&"ultimate"):
		guide = "\n\n【新手提示】终极祝福是本局最强力的流派词缀，效果极强，优先围绕它搭配其余祝福。"
	btn.text = boon.god + " · " + lv_txt + "\n" + boon.boon_name + "\n\n" + boon.description + guide + "\n\n[" + hint + "]"
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	btn.pressed.connect(_on_card_picked.bind(boon))
	_cards_box.add_child(btn)
	_card_buttons.append(btn)

func _on_card_picked(boon: BoonClass) -> void:
	_close()
	## 选卡确认 + 获得强化（新卡/升级都响，不走 boons_changed——避免商店随机赐福等路径也触发）
	AudioManager.play(&"confirm")
	AudioManager.play(&"powerup")
	if _owned_card(boon.card_id) != null:
		BoonManager.grant_boon(boon)   ## 已持有：升级，不占新格
	elif BoonManager.is_full():
		# 满格且是新卡（仅兜底，卡池仅 10 张）：进背包替换模式，玩家选槽位或放弃新卡
		InventoryUI.open_replace(boon)
	else:
		BoonManager.grant_boon(boon)

## ESC/手柄 B（ui_cancel 动作）跳过：不选卡直接关闭，发跳过信号（存档房雕像靠它恢复原样，防止软锁）
## 手柄导航：左摇杆/方向键左右移焦点（循环），A（roll）/X（attack）确认当前焦点卡。
## 摇杆保持倾斜会持续产生 JoypadMotion 事件，焦点移动走 _move_focus 的限频（键盘按键不受限）。
func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		_close()
		EventBus.boon_offer_skipped.emit()
		get_viewport().set_input_as_handled()   ## 消费掉，避免背包面板跟着弹开
	elif event.is_action_pressed("move_right"):
		_move_focus(1, event is InputEventJoypadMotion)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_left"):
		_move_focus(-1, event is InputEventJoypadMotion)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("roll") or event.is_action_pressed("attack"):
		_confirm_focus()
		get_viewport().set_input_as_handled()   ## 消费掉，避免确认选卡后玩家原地翻滚/攻击

## 焦点左右循环移动。[param from_stick] 为 true（摇杆事件）时吃 FOCUS_MOVE_INTERVAL 限频；
## 键盘按键传 false，离散按压每次必响应，快速点按不会被吞。
func _move_focus(dir: int, from_stick: bool = false) -> void:
	var total := _card_buttons.size()
	if total == 0:
		return
	if from_stick:
		var now := Time.get_ticks_msec()
		if now - _last_focus_move_tick < int(FOCUS_MOVE_INTERVAL * 1000.0):
			return
		_last_focus_move_tick = now
	_focus_idx = (_focus_idx + dir + total) % total
	_update_focus_visual()

## 确认当前焦点卡，等同鼠标点击
func _confirm_focus() -> void:
	if _focus_idx < 0 or _focus_idx >= _current_choices.size():
		return
	_on_card_picked(_current_choices[_focus_idx])

## 焦点高亮：焦点卡提亮，非焦点卡压暗，一眼看出手柄选中在哪
func _update_focus_visual() -> void:
	for i in range(_card_buttons.size()):
		_card_buttons[i].modulate = Color(1.2, 1.2, 1.2) if i == _focus_idx else Color(0.65, 0.65, 0.65)

func _close() -> void:
	_panel.visible = false
	_dim.visible = false
	_clear_cards()
	PauseGuard.release(&"boon_select")
	_is_open = false
