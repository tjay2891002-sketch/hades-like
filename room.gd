class_name Room
extends Node2D

## 房间：边界 + 门 + 敌人波次（2c-3 重制版）。
## 拓扑：四面各有一扇门。玩家进入的那扇门为"入口"（琥珀常闭）；其余 3 扇为"出口"（绿色，清场后开）。
## 玩家从某出口踏入 → 下一关的入口设为该出口的"对侧"，并重刷房间。
## 出口门上显示下一关徽章：数字=敌人数，颜色紫=精英房、红=普通房。

@export var room_size: Vector2 = Vector2(960.0, 540.0)
@export var wall_thickness: float = 32.0
@export var door_width: float = 40.0
@export var wall_color: Color = Color(0.25, 0.28, 0.34, 1.0)
@export var entrance_color: Color = Color(0.6, 0.5, 0.3, 1.0)        ## 琥珀：入口常闭
@export var exit_closed_color: Color = Color(0.2, 0.5, 0.25, 1.0)    ## 绿：出口封闭
@export var exit_open_color: Color = Color(0.2, 0.6, 0.3, 0.3)       ## 绿半透明：出口开启
@export var exit_badge_normal: Color = Color(0.9, 0.3, 0.3, 1.0)     ## 普通战斗房徽章（红）
@export var exit_badge_elite: Color = Color(0.7, 0.3, 0.9, 1.0)      ## 精英房徽章（紫）
@export var exit_badge_merchant: Color = Color(0.25, 0.65, 0.9, 1.0) ## 商人房徽章（蓝）
@export var exit_badge_boss: Color = Color(0.9, 0.15, 0.15, 1.0)     ## BOSS房徽章（深红）
## 每波敌人数量曲线由 RoomDirector.wave_count_for 统一提供（勿在此复制公式）

const DropItemScript = preload("res://drop_item.gd")                  ## 精英掉落奖励
const PickupItemScript = preload("res://pickup_item.gd")              ## 消耗品掉落（血瓶入背包）
const RoomSpecScript = preload("res://room_spec.gd")                  ## 房间规格（Phase 4 多样性）
const EnemyScript = preload("res://enemy.gd")                         ## 敌人（动态生成，首波与换房共用）
const MerchantScript = preload("res://merchant.gd")                   ## 商人（商人房动态生成）

## 墙/门贴图（替代原色块）：墙用 wall.png 平铺，门用单个 32×32 门贴图居中在门洞里
const WALL_TEX := preload("res://assets/sprites/tiles/wall.png")
const DOOR_TEX_SIZE := 32.0   ## 门贴图边长（_make_door_sprite 与下面对齐共用）
const DOOR_CLOSED_TEX := preload("res://assets/sprites/tiles/door_closed.png")
const DOOR_OPEN_TEX := preload("res://assets/sprites/tiles/door_open.png")
const EXIT_TRIGGER_SLACK := 12.0   ## 出口触发区在门洞两侧各放宽的宽度：略微偏斜也能触发
const EXIT_TRIGGER_INSET := 24.0  ## 出口触发区向房间内延伸的深度：走到门口附近即触发，不必硬挤窄门洞

enum Dir { TOP, BOTTOM, LEFT, RIGHT }

var _walls: Array[StaticBody2D] = []
var _doors: Dictionary = {}            ## Dir -> StaticBody2D
var _exit_areas: Dictionary = {}       ## Dir -> Area2D
var _exit_badges: Dictionary = {}      ## Dir -> Node2D
var _entrance_dir: Dir = Dir.BOTTOM    ## 默认从底部进入（初始 main.tscn 玩家也在底部中心）
var _is_cleared: bool = false
## 上次跳转发生的物理帧号：用于屏蔽"幽灵双击"——传送玩家+重建门区在同一帧完成时，
## 物理服务器可能按传送前的旧位置再报一次门区重叠，导致同一扇门连跳两关
##（先进商人房、紧接着被新随机选项覆盖成 6 怪战斗房）。跳转后 2 个物理帧内的门事件一律忽略。
var _last_advance_frame: int = -100

func _ready() -> void:
	_build_room()
	if not EventBus.room_cleared.is_connected(_on_room_cleared):
		EventBus.room_cleared.connect(_on_room_cleared)
	if not EventBus.enemy_died.is_connected(_on_enemy_died):
		EventBus.enemy_died.connect(_on_enemy_died)
	## 首波敌人走动态生成（不再依赖 main.tscn 静态敌人），与换房同一条链路
	call_deferred("_spawn_initial_wave")
	## 场景切换（如存档房→战斗房）后，确保玩家出现在入口内侧而非房间中心
	call_deferred("_place_player_at_entrance")

## 首波敌人生成：房间 1（以及从 Boss 房返回 main.tscn 重建场景时）按当前 RunState.room_index
## 的难度曲线出怪，无精英（精英只出现在玩家主动选择的精英门里）。
## 必须延迟到所有 _ready 之后执行：此时 RoomDirector 已入组可查询难度；
## 它在 _ready 时按 get_nodes_in_group("enemy") 统计为 0，生成后由 register_enemies 同步计数，
## 与 _do_advance 换房路径的处理方式一致。
func _spawn_initial_wave() -> void:
	var rd := get_tree().get_first_node_in_group("room_director")
	var room_index := 1
	if rd != null and rd.has_method("get_room_index"):
		room_index = rd.get_room_index()
	var enemy_count := 3
	if rd != null and rd.has_method("wave_count_for"):
		enemy_count = rd.wave_count_for(room_index)
	_spawn_for_spec(null, enemy_count, room_index)
	if rd != null and rd.has_method("register_enemies"):
		rd.register_enemies(enemy_count)

## 实时取玩家节点（避免 _ready 时序：本节点 _ready 早于 Player 入组）
func _get_player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D

func _opposite(dir: Dir) -> Dir:
	match dir:
		Dir.TOP: return Dir.BOTTOM
		Dir.BOTTOM: return Dir.TOP
		Dir.LEFT: return Dir.RIGHT
		Dir.RIGHT: return Dir.LEFT
	return Dir.BOTTOM

func _dir_name(dir: Dir) -> String:
	match dir:
		Dir.TOP: return "Top"
		Dir.BOTTOM: return "Bottom"
		Dir.LEFT: return "Left"
		Dir.RIGHT: return "Right"
	return "Unknown"

## 清除当前房间所有动态墙/门/检测区/徽章
func _clear_room() -> void:
	for wall in _walls:
		if is_instance_valid(wall):
			wall.queue_free()
	_walls.clear()
	for door in _doors.values():
		if is_instance_valid(door):
			door.queue_free()
	_doors.clear()
	for area in _exit_areas.values():
		if is_instance_valid(area):
			area.queue_free()
	_exit_areas.clear()
	for badge in _exit_badges.values():
		if is_instance_valid(badge):
			badge.queue_free()
	_exit_badges.clear()
	# 顺带清掉可能残留的掉落物 / 商人（玩家未拾取/未交互就出门重进时会出现）
	for child in get_children():
		if is_instance_valid(child) and (child is DropItemScript or child is PickupItemScript or child.is_in_group("merchant")):
			child.queue_free()

## 固定镜头内容矩形（世界空间）：含地板 + 整圈墙（墙半厚在地板外、门在墙体缺口内）。
## 战斗房用这个矩形让相机自适应缩放，确保四边墙和门都完整显示。
func _room_camera_rect() -> Rect2:
	var half := room_size * 0.5
	var top_left := global_position - half - Vector2.ONE * wall_thickness
	var size := room_size + Vector2.ONE * wall_thickness * 2.0
	return Rect2(top_left, size)

func _build_room() -> void:
	var half := room_size * 0.5
	var cx := 0.0
	var cy := 0.0
	var left := cx - half.x
	var right := cx + half.x
	var top := cy - half.y
	var bottom := cy + half.y

	var door_half := door_width * 0.5
	## 水平墙段：外端延伸到墙角外侧（多 wall_thickness），与垂直墙段在角落重叠，填满四角
	var horiz_segment_width := (room_size.x - door_width) * 0.5 + wall_thickness
	_create_wall_segment(Vector2(left - wall_thickness + horiz_segment_width * 0.5, top - wall_thickness * 0.5), Vector2(horiz_segment_width, wall_thickness))
	_create_wall_segment(Vector2(right + wall_thickness - horiz_segment_width * 0.5, top - wall_thickness * 0.5), Vector2(horiz_segment_width, wall_thickness))
	_create_wall_segment(Vector2(left - wall_thickness + horiz_segment_width * 0.5, bottom + wall_thickness * 0.5), Vector2(horiz_segment_width, wall_thickness))
	_create_wall_segment(Vector2(right + wall_thickness - horiz_segment_width * 0.5, bottom + wall_thickness * 0.5), Vector2(horiz_segment_width, wall_thickness))

	var vert_segment_height := (room_size.y - door_width) * 0.5 + wall_thickness
	_create_wall_segment(Vector2(left - wall_thickness * 0.5, top - wall_thickness + vert_segment_height * 0.5), Vector2(wall_thickness, vert_segment_height))
	_create_wall_segment(Vector2(left - wall_thickness * 0.5, bottom + wall_thickness - vert_segment_height * 0.5), Vector2(wall_thickness, vert_segment_height))
	_create_wall_segment(Vector2(right + wall_thickness * 0.5, top - wall_thickness + vert_segment_height * 0.5), Vector2(wall_thickness, vert_segment_height))
	_create_wall_segment(Vector2(right + wall_thickness * 0.5, bottom + wall_thickness - vert_segment_height * 0.5), Vector2(wall_thickness, vert_segment_height))

	## 门居中于墙中线：墙厚 = 门贴图边长 32，门体正好填满整段墙厚、与墙内外表面齐平，
	## 不再向房间内凸出，也不越出墙外，视觉上像嵌在砖墙里的拱门（贴合参考图）。
	_create_door(Dir.TOP, Vector2(cx, top - wall_thickness * 0.5), Vector2(door_width, wall_thickness))
	_create_door(Dir.BOTTOM, Vector2(cx, bottom + wall_thickness * 0.5), Vector2(door_width, wall_thickness))
	_create_door(Dir.LEFT, Vector2(left - wall_thickness * 0.5, cy), Vector2(wall_thickness, door_width))
	_create_door(Dir.RIGHT, Vector2(right + wall_thickness * 0.5, cy), Vector2(wall_thickness, door_width))

func _create_wall_segment(pos: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.position = pos
	wall.add_to_group("wall")
	add_child(wall)
	var shape := RectangleShape2D.new()
	shape.size = size
	var col := CollisionShape2D.new()
	col.shape = shape
	wall.add_child(col)
	wall.add_child(_make_tiled_rect(size, WALL_TEX))
	_walls.append(wall)

## 平铺贴图矩形（墙体视觉）：TextureRect TILE 模式 + NEAREST，替代原色块 Polygon2D
## modulate 压暗：浅蓝灰砖原色太亮，乘冷灰调后与地板拉开层次、贴合地牢氛围
func _make_tiled_rect(size: Vector2, tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.modulate = Color(0.6, 0.6, 0.7, 1.0)
	r.stretch_mode = TextureRect.STRETCH_TILE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = -size * 0.5
	r.size = size
	return r

## 出口触发矩形（本地坐标）：覆盖门洞并在两侧放宽、向室内延伸，让玩家“走到门口附近”即可触发进入。
func _exit_trigger_rect(dir: Dir) -> Rect2:
	var half_gap := door_width * 0.5 + EXIT_TRIGGER_SLACK
	var depth := wall_thickness + EXIT_TRIGGER_INSET
	var half := room_size * 0.5
	match dir:
		Dir.TOP: return Rect2(-half_gap, -half.y - wall_thickness, half_gap * 2.0, depth)
		Dir.BOTTOM: return Rect2(-half_gap, half.y - EXIT_TRIGGER_INSET, half_gap * 2.0, depth)
		Dir.LEFT: return Rect2(-half.x - wall_thickness, -half_gap, depth, half_gap * 2.0)
		Dir.RIGHT: return Rect2(half.x - EXIT_TRIGGER_INSET, -half_gap, depth, half_gap * 2.0)
	return Rect2()

func _create_door(dir: Dir, pos: Vector2, size: Vector2) -> void:
	var is_entrance := (dir == _entrance_dir)
	var door := StaticBody2D.new()
	door.name = "Door" + _dir_name(dir)
	door.position = pos
	door.add_to_group("wall")
	add_child(door)
	var shape := RectangleShape2D.new()
	shape.size = size
	var col := CollisionShape2D.new()
	col.shape = shape
	door.add_child(col)
	door.add_child(_make_door_sprite(size))   ## 视觉子节点下标 1：_open_exits 开门时换 door_open 贴图
	_doors[dir] = door

	if is_entrance:
		return

	## 出口：挂检测区（触发矩形比门洞更宽、并向室内延伸，走到门口附近即触发）
	var area := Area2D.new()
	area.name = "ExitArea" + _dir_name(dir)
	var trig := _exit_trigger_rect(dir)
	area.position = trig.get_center()
	var ashape := RectangleShape2D.new()
	ashape.size = trig.size
	var acol := CollisionShape2D.new()
	acol.shape = ashape
	area.add_child(acol)
	area.monitoring = false
	area.body_entered.connect(_on_exit_body_entered.bind(dir))
	add_child(area)
	_exit_areas[dir] = area

	## 出口门上的下一关徽章（清场后填充）
	var badge := Node2D.new()
	badge.name = "Badge" + _dir_name(dir)
	badge.position = pos
	badge.z_index = 5   ## 徽章画在门贴图(z=1)之上，避免文字被门挡住
	add_child(badge)
	_exit_badges[dir] = badge

## 门视觉：单个 32×32 门贴图按门洞尺寸拉伸（横向门拉宽 x、纵向门拉高 y），关门/开门都贴合门洞、无侧缝；
## 初始一律 door_closed，入口常闭、出口清场后由 _open_exits 换 door_open
func _make_door_sprite(size: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = "DoorSprite"
	s.texture = DOOR_CLOSED_TEX
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.z_index = 1
	## 门贴图按门洞宽度拉伸到与门洞同宽（横向门拉宽 x、纵向门拉高 y），关门/开门都不漏缝
	if size.x >= size.y:
		s.scale = Vector2(size.x / 32.0, 1.0)
	else:
		s.scale = Vector2(1.0, size.y / 32.0)
	return s

func _on_exit_body_entered(body: Node, dir: Dir) -> void:
	if not _is_cleared or not body.is_in_group("player"):
		return
	# 幽灵事件屏蔽：见 _last_advance_frame 注释
	if Engine.get_physics_frames() - _last_advance_frame <= 2:
		return
	# 必须延迟执行：body_entered 处于 physics flushing 阶段，不能立即增删 collision body。
	call_deferred("_do_advance", dir)

func _on_room_cleared(_room_index: int, _is_elite: bool) -> void:
	_is_cleared = true
	_open_exits()

## 清场后给每个出口门戴上徽章：显示该门通往房间的类型/敌人数/奖励偏斜
func _update_badges() -> void:
	var rd := get_tree().get_first_node_in_group("room_director")
	if rd == null:
		return
	for dir in _exit_badges.keys():
		var spec: RoomSpecScript = null
		if rd.has_method("get_option"):
			spec = rd.get_option(int(dir))
		for c in _exit_badges[dir].get_children():
			c.queue_free()
		if spec == null:
			continue
		var box := ColorRect.new()
		box.size = Vector2(16.0, 16.0)
		box.position = Vector2(-8.0, -8.0)
		match spec.type:
			RoomSpecScript.Type.ELITE:
				box.color = exit_badge_elite
			RoomSpecScript.Type.MERCHANT:
				box.color = exit_badge_merchant
			RoomSpecScript.Type.BOSS:
				box.color = exit_badge_boss
			_:
				box.color = exit_badge_normal
		_exit_badges[dir].add_child(box)
		var label := Label.new()
		label.text = spec.badge_text()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 11)
		label.position = Vector2(-22.0, -8.0)
		label.size = Vector2(44.0, 16.0)
		_exit_badges[dir].add_child(label)

## 玩家踏入出口 [dir]：按该门对应的 RoomSpec 进入下一关。
## BOSS 门 → 切换独立 Boss 场景；其余 → 重建本房间并按规格生成。
func _do_advance(exit_dir: Dir) -> void:
	_last_advance_frame = Engine.get_physics_frames()
	var rd: Node = get_tree().get_first_node_in_group("room_director")
	var spec: RoomSpecScript = null
	if rd != null and rd.has_method("get_option"):
		spec = rd.get_option(int(exit_dir))

	## 先推进进度（生成下一关选项），再判断门类型。
	## 这样 BOSS 门也能正常推进房间序号，且徽章显示的"当前选项"与玩家实际进入的完全一致。
	if rd != null and rd.has_method("advance"):
		rd.advance()

	## BOSS 门：进入独立 Boss 关（延迟切换，避开 physics callback）
	if spec != null and spec.type == RoomSpecScript.Type.BOSS:
		call_deferred("_go_boss_scene")
		return

	var room_index := 1
	if rd != null and rd.has_method("get_room_index"):
		room_index = rd.get_room_index()

	## 新入口 = 出口对侧（例如从上出去 → 下关入口在下）
	_entrance_dir = _opposite(exit_dir)

	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	# 顺带清掉滞空的投射物（敌方/我方），避免带进下一关
	for g in [&"enemy_projectile", &"player_projectile"]:
		for p in get_tree().get_nodes_in_group(g):
			if is_instance_valid(p):
				p.queue_free()

	_clear_room()
	_build_room()

	var enemy_count := 0
	if spec != null and spec.type == RoomSpecScript.Type.MERCHANT:
		## 商人房：无敌人，直接放入商人并开门
		_spawn_merchant()
		_is_cleared = true
		_open_exits()
	else:
		## 战斗/精英房：重置清场标记（修状态残留：之前 _is_cleared 一真永真）
		_is_cleared = false
		## spec 为准；spec 缺失时按难度曲线兜底
		if spec != null:
			enemy_count = spec.enemy_count
		elif rd != null and rd.has_method("wave_count_for"):
			enemy_count = rd.wave_count_for(room_index)
		else:
			enemy_count = 3
		_spawn_for_spec(spec, enemy_count, room_index)

	var player := _get_player()
	if player != null:
		player.global_position = global_position + _entrance_inner_offset()

	if rd != null and rd.has_method("register_enemies"):
		rd.register_enemies(enemy_count)

func _go_boss_scene() -> void:
	get_tree().change_scene_to_file("res://boss_room.tscn")

func _entrance_inner_offset() -> Vector2:
	var half := room_size * 0.5
	var inset := 40.0
	match _entrance_dir:
		Dir.TOP: return Vector2(0.0, -half.y + inset)
		Dir.BOTTOM: return Vector2(0.0, half.y - inset)
		Dir.LEFT: return Vector2(-half.x + inset, 0.0)
		Dir.RIGHT: return Vector2(half.x - inset, 0.0)
	return Vector2(0.0, half.y - inset)

## 把玩家放置到当前入口内侧；用于场景切换后的初始出生点
func _place_player_at_entrance() -> void:
	var player := _get_player()
	if player != null:
		player.global_position = global_position + _entrance_inner_offset()

## 按 RoomSpec 生成敌人波次；战斗/精英房应用金币/经验倍率。
## 敌型混合：前两房基本纯追击者，3 房起按权重混入冲锋/射手/坦克。
func _spawn_for_spec(spec: RoomSpecScript, count: int, room_index: int = 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var gold_mult := 1.0
	var xp_mult := 1.0
	if spec != null:
		gold_mult = spec.gold_mult
		xp_mult = spec.xp_mult
	var spawn_elite: bool = (spec != null and spec.type == RoomSpecScript.Type.ELITE)
	for i in range(count):
		var e := EnemyScript.new()
		if spawn_elite and i == 0:
			e.is_elite = true
			e.kind = Enemy.Kind.CHASER   ## 精英固定位给追击者（数值怪）
		else:
			e.is_elite = false
			e.kind = _roll_kind(rng, room_index)
		## 敌人视觉由 enemy.gd 按敌型/精英自建贴图精灵（不再外挂色块）
		var ang := float(i) / float(max(count, 1)) * TAU + rng.randf_range(-0.35, 0.35)
		var radius := 70.0 + rng.randf_range(0.0, 90.0)
		e.position = Vector2(cos(ang), sin(ang)) * radius
		add_child(e)
		## 奖励偏斜：在 _ready 应用敌型数值之后再乘倍率，避免被覆盖
		##（字段为 float，与 EventBus.xp_gained/currency_gained 的信号声明一致，勿取整）
		e.xp_drop = e.xp_drop * xp_mult
		e.currency_drop = e.currency_drop * gold_mult

## 按房号 roll 敌型：前期纯追击者教学，之后逐步混入新敌型
func _roll_kind(rng: RandomNumberGenerator, room_index: int) -> int:
	var roll := rng.randf()
	if room_index < 3:
		return Enemy.Kind.CHARGER if roll < 0.15 else Enemy.Kind.CHASER
	if roll < 0.45:
		return Enemy.Kind.CHASER
	if roll < 0.70:
		return Enemy.Kind.CHARGER
	if roll < 0.90:
		return Enemy.Kind.SHOOTER
	return Enemy.Kind.TANK

## 商人房：房间中央放置一个商人交互物（无敌人）
func _spawn_merchant() -> void:
	var m: Node2D = MerchantScript.new()
	m.position = Vector2(0.0, 0.0)
	add_child(m)

## 清场后打开所有出口（门换 door_open 贴图、碰撞取消、检测区启用），并刷新徽章
func _open_exits() -> void:
	for dir in _exit_areas.keys():
		var area := _exit_areas[dir] as Area2D
		area.set_deferred("monitoring", true)
		var door := _doors[dir] as StaticBody2D
		var col := door.get_child(0) as CollisionShape2D
		if col != null:
			col.set_deferred("disabled", true)
		var sprite := door.get_child(1) as Sprite2D
		if sprite != null:
			sprite.texture = DOOR_OPEN_TEX
		door.remove_from_group("wall")
	_update_badges()

## 监听敌人死亡：精英死亡掉赐福宝石 + 必掉血瓶；普通怪 15% 概率掉血瓶（F 拾取入背包）
func _on_enemy_died(enemy: Node) -> void:
	if not (enemy is Node2D):
		return
	var pos := (enemy as Node2D).global_position
	if enemy is Enemy and (enemy as Enemy).is_elite:
		call_deferred("_spawn_drop_at", pos)
		call_deferred("_spawn_pickup_at", pos + Vector2(28.0, 0.0), &"potion", 1)
	elif enemy is Enemy and randf() < 0.15:
		call_deferred("_spawn_pickup_at", pos, &"potion", 1)

## 在指定世界坐标生成消耗品掉落物（先入树再设世界坐标，同 _spawn_drop_at 的顺序教训）
func _spawn_pickup_at(pos: Vector2, id: StringName, count: int) -> void:
	var p := PickupItemScript.new()
	p.item_id = id
	p.amount = count
	add_child(p)
	p.global_position = pos

## 在指定世界坐标生成赐福掉落物
func _spawn_drop_at(pos: Vector2) -> void:
	# 保险：先清掉可能已存在的掉落物，避免重叠
	for child in get_children():
		if child is DropItemScript and is_instance_valid(child):
			child.queue_free()
	var drop := DropItemScript.new()
	add_child(drop)            ## 先入树：此时 drop.global_position == Room.global_position
	drop.global_position = pos ## 再设世界坐标，Godot 自动换算回正确的 local 位置
