class_name SaveRoom
extends Node2D

## 开局存档房间（R4）：
## - 5 座单神神像（宙斯/波塞冬/阿瑞斯/赫尔墨斯/赫菲斯托斯），供奉后从该神卡池随机抽 3 张三选一；只选一张，选完锁其余神像
## - 2 座永久加成雕像（生命/金币），花英灵碎片解锁，解锁后是点亮的装饰，不提供选卡
## - 武器架：5 把武器逐步解锁，开局选择武器（战斗中不可切换）
## - 选卡前锁定顶部出口；获得至少 1 张赐福后出口解锁
## - 从顶部出口离开时切换至战斗场景 main.tscn

const WALL_T: float = 32.0
const ROOM_W: float = 960.0
const ROOM_H: float = 540.0
const GATE_W: float = 40.0
const GATE_CX: float = 480.0

## 显式 preload：class_name 全局解析在本加载顺序下不可靠，preload 保证 Statue/WeaponRack 类型可用
const STATUE_SCRIPT := preload("res://statue.gd")
const WEAPON_SCRIPT := preload("res://weapon_rack.gd")

## 地板/墙/门贴图（替代原色块）：地板与墙平铺，门用单个 32×32 门贴图
const FLOOR_TEX := preload("res://assets/sprites/tiles/floor.png")
const WALL_TEX := preload("res://assets/sprites/tiles/wall.png")
const DOOR_CLOSED_TEX := preload("res://assets/sprites/tiles/door_closed.png")
const DOOR_OPEN_TEX := preload("res://assets/sprites/tiles/door_open.png")

var _gate: StaticBody2D
var _gate_sprite: Sprite2D
var _exit_area: Area2D
var _exit_prompt: Label
var _title_label: Label
var _unlocked: bool = false

func _ready() -> void:
	_build_background()
	_build_walls()
	_build_top_exit()
	_spawn_statues()
	_spawn_weapon_racks()
	## 键盘/手柄切换时刷新房间标题里的交互键名
	if not InputDevice.device_changed.is_connected(_on_device_changed):
		InputDevice.device_changed.connect(_on_device_changed)
	if not BoonManager.boons_changed.is_connected(_on_boons_changed):
		BoonManager.boons_changed.connect(_on_boons_changed)
	## 局中解锁（玩家已选完卡后）的雕像直接锁定：本次不能再选卡，下一局才可用
	if not MetaState.statue_unlocked.is_connected(_on_statue_unlocked):
		MetaState.statue_unlocked.connect(_on_statue_unlocked)
	# 若已有赐福（例如重玩），直接解锁并锁定全部雕像
	if BoonManager.active_boons.size() >= 1:
		_finalize_choice()

## 固定镜头中心：存档房室内为 960×540，镜头固定在房间中点。
func _room_camera_center() -> Vector2:
	return Vector2(ROOM_W * 0.5, ROOM_H * 0.5)

## 玩家已选完卡（出口已开）后局中解锁的雕像：立即锁定，本次不可再选卡
func _on_statue_unlocked(key: StringName) -> void:
	if not _unlocked:
		return
	var s := get_node_or_null("Statue_" + String(key))
	if s != null and s.has_method("lock"):
		s.lock()

## ---------- 背景 ----------
func _build_background() -> void:
	## 地板贴图平铺（替代原纯色块）：装饰层压在最底层，避免动态 add_child 后绘制顺序覆盖玩家
	## modulate 压暗：沙色地砖原色太亮，乘深板岩调后呈地牢暗色、与敌人拉开对比
	var floor_rect := TextureRect.new()
	floor_rect.name = "Floor"
	floor_rect.texture = FLOOR_TEX
	floor_rect.modulate = Color(0.3, 0.32, 0.44, 1.0)
	floor_rect.stretch_mode = TextureRect.STRETCH_TILE
	floor_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_rect.position = Vector2(0.0, 0.0)
	floor_rect.size = Vector2(ROOM_W, ROOM_H)
	floor_rect.z_index = -10
	add_child(floor_rect)
	var title := Label.new()
	title.text = "存档神殿 · 神像供奉 / 武器解锁装备 · 按 %s 交互" % InputDevice.hint(&"interact")
	title.position = Vector2(280.0, 70.0)
	title.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 1))
	add_child(title)
	_title_label = title

## 键盘/手柄切换：刷新房间标题里的交互键名
func _on_device_changed(_gamepad: bool) -> void:
	if _title_label != null:
		_title_label.text = "存档神殿 · 神像供奉 / 武器解锁装备 · 按 %s 交互" % InputDevice.hint(&"interact")

## ---------- 墙体 ----------
func _add_wall(rect: Rect2, _color: Color) -> void:
	var body := StaticBody2D.new()
	body.z_index = -10   ## 墙体压在底层，不遮挡玩家
	body.add_to_group("wall")
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = rect.position + rect.size * 0.5
	body.add_child(col)
	## 墙体贴图平铺（替代原色块 Polygon2D；_color 参数保留仅为不改 _build_walls 调用签名）
	## modulate 压暗：与 room.gd _make_tiled_rect 同值，比地板略亮以区分层级
	var tex := TextureRect.new()
	tex.texture = WALL_TEX
	tex.modulate = Color(0.6, 0.6, 0.7, 1.0)
	tex.stretch_mode = TextureRect.STRETCH_TILE
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.position = rect.position
	tex.size = rect.size
	body.add_child(tex)
	add_child(body)

func _build_walls() -> void:
	var wall_col := Color(0.30, 0.33, 0.40, 1)
	_add_wall(Rect2(0.0, ROOM_H - WALL_T, ROOM_W, WALL_T), wall_col)   # 底
	_add_wall(Rect2(0.0, 0.0, WALL_T, ROOM_H), wall_col)               # 左
	_add_wall(Rect2(ROOM_W - WALL_T, 0.0, WALL_T, ROOM_H), wall_col)   # 右
	var left_end := GATE_CX - GATE_W * 0.5
	var right_start := GATE_CX + GATE_W * 0.5
	_add_wall(Rect2(0.0, 0.0, left_end, WALL_T), wall_col)             # 顶-左
	_add_wall(Rect2(right_start, 0.0, ROOM_W - right_start, WALL_T), wall_col)  # 顶-右
	# 中间闸门（初始锁定）
	_gate = StaticBody2D.new()
	_gate.name = "TopGate"
	_gate.add_to_group("wall")
	var gshape := RectangleShape2D.new()
	gshape.size = Vector2(GATE_W, WALL_T)
	var gcol := CollisionShape2D.new()
	gcol.shape = gshape
	gcol.position = Vector2(GATE_CX, WALL_T * 0.5)
	_gate.add_child(gcol)
	## 门贴图（替代原色块）：居中在门洞里，初始关闭，选卡后 _unlock 换 door_open
	_gate_sprite = Sprite2D.new()
	_gate_sprite.texture = DOOR_CLOSED_TEX
	_gate_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_gate_sprite.position = Vector2(GATE_CX, WALL_T * 0.5)
	_gate.add_child(_gate_sprite)
	## 门贴图按门洞宽度拉伸到与门洞同宽，关门/开门都不漏侧缝
	_gate_sprite.scale = Vector2(GATE_W / 32.0, 1.0)
	add_child(_gate)

## ---------- 顶部出口 ----------
func _build_top_exit() -> void:
	_exit_area = Area2D.new()
	_exit_area.name = "TopExit"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(GATE_W, 44.0)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(GATE_CX, 22.0)
	_exit_area.add_child(col)
	_exit_area.body_entered.connect(_on_exit_entered)
	_exit_area.monitoring = false   # 仅解锁后开启
	add_child(_exit_area)
	_exit_prompt = Label.new()
	_exit_prompt.text = "出口（选卡后开启）↑"
	_exit_prompt.position = Vector2(GATE_CX - 90.0, 48.0)
	_exit_prompt.size = Vector2(180.0, 18.0)
	_exit_prompt.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	add_child(_exit_prompt)

func _on_exit_entered(body: Node) -> void:
	if body.is_in_group("player") and _unlocked:
		## body_entered 处于 physics callback，不能立即切换场景（会移除 CollisionObject 节点）
		call_deferred("_do_exit")

func _do_exit() -> void:
	get_tree().change_scene_to_file("res://main.tscn")

## ---------- 雕像 / 武器架 ----------
const GOD_DEFS: Array[Dictionary] = [
	{"god": &"宙斯", "x": 160.0, "y": 270.0},
	{"god": &"波塞冬", "x": 315.0, "y": 270.0},
	{"god": &"阿瑞斯", "x": 470.0, "y": 270.0},
	{"god": &"赫尔墨斯", "x": 625.0, "y": 270.0},
	{"god": &"赫菲斯托斯", "x": 780.0, "y": 270.0},
]
const BONUS_DEFS: Array[Dictionary] = [
	{"key": &"bonus_hp", "x": 330.0, "y": 390.0},
	{"key": &"bonus_gold", "x": 630.0, "y": 390.0},
]
const WEAPON_XS: Array[float] = [160.0, 315.0, 470.0, 625.0, 780.0]
const WEAPON_Y: float = 475.0

func _spawn_statues() -> void:
	## 神像：免费可供奉（unlocked=true），按 F 从该神卡池抽 3 张选一。
	for d in GOD_DEFS:
		var s := STATUE_SCRIPT.new()
		s.position = Vector2(d["x"], d["y"])
		s.z_index = -5   ## 雕像低于玩家，玩家走在雕像前仍可见
		s.name = "Statue_god_" + String(d["god"])
		s.unlock_key = &""
		s.god = d["god"]
		s.card_id = &""
		s.unlocked = true
		add_child(s)
	## 永久加成雕像：需花碎片解锁，解锁后为点亮装饰。
	for d in BONUS_DEFS:
		var s := STATUE_SCRIPT.new()
		s.position = Vector2(d["x"], d["y"])
		s.z_index = -5
		s.name = "Statue_" + String(d["key"])
		s.unlock_key = d["key"]
		s.god = &""
		s.card_id = &""
		s.unlocked = false
		add_child(s)

## 武器架：5 把武器一排摆出，未解锁的花碎片解锁，已解锁的按 F 装备。
func _spawn_weapon_racks() -> void:
	for i in range(WEAPON_XS.size()):
		var r := WEAPON_SCRIPT.new()
		r.position = Vector2(WEAPON_XS[i], WEAPON_Y)
		r.z_index = -5
		r.name = "WeaponRack_" + str(i)
		r.weapon_index = i
		add_child(r)

func _unlock() -> void:
	if _unlocked:
		return
	_unlocked = true
	var col := _gate.get_child(0) as CollisionShape2D
	if col != null:
		col.set_deferred("disabled", true)
	_gate.remove_from_group("wall")
	if _gate_sprite != null:
		_gate_sprite.texture = DOOR_OPEN_TEX   ## 开门换贴图
	_exit_area.monitoring = true
	if _exit_prompt != null:
		_exit_prompt.text = "出口已开启 ↑ 前往战斗"
		_exit_prompt.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5, 1))

func _on_boons_changed(_count: int) -> void:
	if BoonManager.active_boons.size() >= 1:
		_finalize_choice()

## 玩家完成选择：解锁顶部出口，并锁定其余未选雕像（只选一张）
func _finalize_choice() -> void:
	_unlock()
	for s in get_tree().get_nodes_in_group("interactable"):
		if s.has_method("lock"):
			s.lock()
