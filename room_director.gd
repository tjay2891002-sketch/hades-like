extends Node

## 房间进度控制器（2c-1/2c-3 + Phase 4 多样性）。
## 职责：统计当前房敌人数、归零触发 room_cleared、维护房间序号与精英节奏；
## 每次清场后为 4 个方向各生成一份独立的 RoomSpec（类型+奖励偏斜+敌人数），
## 供出口门徽章显示与“选择走哪扇门”使用。

const RoomSpecScript = preload("res://room_spec.gd")

@export var rooms_per_elite: int = 3
@export var wave_base_count: int = 3    ## 每波敌人基数
@export var wave_max_count: int = 6     ## 每波敌人上限

## 难度曲线唯一出处（room.gd 的兜底生成也调这里，不要再复制公式）
func wave_count_for(room_index: int) -> int:
	return mini(wave_base_count + int((room_index - 1) / 2.0), wave_max_count)

## 房间序号持久化在 RunState（autoload），Boss 房往返后进度不丢
var _is_elite_room: bool = false
var _enemies_remaining: int = 0
var _next_options: Dictionary = {}   ## Room.Dir(int) -> RoomSpec

func _ready() -> void:
	add_to_group("room_director")
	_enemies_remaining = get_tree().get_nodes_in_group("enemy").size()
	_is_elite_room = (RunState.room_index % rooms_per_elite == 0)
	if not EventBus.enemy_died.is_connected(_on_enemy_died):
		EventBus.enemy_died.connect(_on_enemy_died)
	prepare_next_options()

func _on_enemy_died(_enemy: Node) -> void:
	_enemies_remaining -= 1
	if _enemies_remaining <= 0:
		## 注意：此处【不要】prepare_next_options()！
		## 清场时徽章显示的必须是"当前房间"的 _next_options（_ready 或上次 advance 时已生成）；
		## 若在此重 roll，会出现"门上徽章 = 旧选项、实际进入 = 新选项"的不一致
		## （精英门进去没精英、普通门莫名进 Boss 房）。下一关选项交给 _do_advance 里的 advance() 处理。
		EventBus.room_cleared.emit(RunState.room_index, _is_elite_room)

## 玩家踏入出口时调用：进入下一关，房间号自增、重算精英节奏、刷新门选项
func advance() -> void:
	RunState.room_index += 1
	_is_elite_room = (RunState.room_index % rooms_per_elite == 0)
	prepare_next_options()

## 房间重刷一波敌人后调用，重置剩余计数。
func register_enemies(count: int) -> void:
	_enemies_remaining = count

func get_room_index() -> int:
	return RunState.room_index

func is_elite() -> bool:
	return _is_elite_room

## 取某方向的下一关规格（供出口门徽章 / 进入时构建房间）
func get_option(dir: int) -> RoomSpecScript:
	return _next_options.get(dir, null)

## 清场后生成 4 个独立规格（每个方向一份），保证门与门之间有差异
func prepare_next_options() -> void:
	_next_options = _roll_options()

func _roll_options() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var result: Dictionary = {}
	var dirs := [Room.Dir.TOP, Room.Dir.BOTTOM, Room.Dir.LEFT, Room.Dir.RIGHT]
	# 类型模板：至少 1 战斗 + 1 精英，其余随机注入商人 / BOSS 增加选择性
	var types := [
		RoomSpecScript.Type.COMBAT,
		RoomSpecScript.Type.ELITE,
		RoomSpecScript.Type.COMBAT,
		RoomSpecScript.Type.COMBAT,
	]
	if rng.randf() < 0.6:
		types[2] = RoomSpecScript.Type.MERCHANT
	if RunState.room_index >= 4 and rng.randf() < 0.4:
		types[3] = RoomSpecScript.Type.BOSS
	types.shuffle()
	# 选项描述的是【下一关】，难度基数按 room_index + 1 算（修复错配一关的问题）
	var base_count := wave_count_for(RunState.room_index + 1)
	for i in range(4):
		var spec := RoomSpecScript.new()
		spec.type = types[i]
		match types[i]:
			RoomSpecScript.Type.COMBAT:
				spec.enemy_count = base_count
			RoomSpecScript.Type.ELITE:
				spec.enemy_count = mini(base_count, 4)
			RoomSpecScript.Type.MERCHANT, RoomSpecScript.Type.BOSS:
				spec.enemy_count = 0
		# 奖励偏斜：战斗/精英房随机偏金币或经验
		if types[i] == RoomSpecScript.Type.COMBAT or types[i] == RoomSpecScript.Type.ELITE:
			if rng.randf() < 0.5:
				spec.reward_bias = &"gold"
				spec.gold_mult = 2.0
			else:
				spec.reward_bias = &"xp"
				spec.xp_mult = 2.0
		result[dirs[i]] = spec
	return result
