extends Node

## 局外成长（meta progression，autoload）：
## 跨局持久化「英灵碎片」与雕像解锁状态（user://meta.save，JSON）。
## 循环：死亡按本局表现结算碎片 → 存档房雕像处消费碎片解锁新卡/永久加成 → 下一局生效。

## 碎片余额变化（存档房余额显示监听）
signal shards_changed(total: int)
## 某雕像被解锁（存档房监听：局中解锁的雕像若玩家已选完卡则直接锁定，下一局才可用）
signal statue_unlocked(key: StringName)
## 死亡结算完成（DeathUI 监听显示 "+X 英灵碎片（共 Y）"，避免依赖 autoload 连接顺序）
signal run_banked(earned: int, total: int)

const SAVE_PATH := "user://meta.save"

## 解锁价格表：key 即 Boon 的 card_id（boon.gd CARD_IDS），两个永久加成用 bonus_hp / bonus_gold
const UNLOCK_COSTS: Dictionary = {
	&"hermes_move": 10,
	&"hermes_roll": 10,
	&"hermes_haste": 10,
	&"hermes_dash": 20,
	&"poseidon_wrath": 20,
	&"ares_lifesteal": 10,
	&"ares_ramp": 20,
	&"bonus_hp": 15,
	&"bonus_gold": 15,
	# 武器解锁（短剑免费，其余英灵碎片逐步解锁）
	&"weapon_greatsword": 20,
	&"weapon_staff": 25,
	&"weapon_bow": 25,
	&"weapon_shield": 30,
}

## 武器解锁映射：下标对应 Player.WEAPONS（短剑为空，表示常驻可用）
const WEAPON_KEYS: Array[StringName] = [
	&"",
	&"weapon_greatsword",
	&"weapon_staff",
	&"weapon_bow",
	&"weapon_shield",
]

var shards: int = 0                ## 英灵碎片（持久化货币）
var unlocks: Dictionary = {}       ## StringName -> true
var last_earned: int = 0           ## 上一局结算所得（DeathUI 之外的查询兜底）

func _ready() -> void:
	load_game()
	## 首次启动的永久加成在此落地：RunState._ready 早于本节点（autoload 顺序），
	## 那时存档还没读，所以由这里在读档后统一重算（apply_meta_bonuses 幂等，重开时 reset_run 会再调）
	RunState.apply_meta_bonuses()
	RunState.player_died.connect(_on_player_died)

## 死亡结算：房间进度 + 剩余金币折算 + Boss 击杀，入账并持久化
func _on_player_died() -> void:
	var earned := RunState.room_index * 5 + int(RunState.currency * 0.5) + RunState.boss_kills * 20
	last_earned = earned
	shards += earned
	save_game()
	run_banked.emit(earned, shards)

## 尝试花碎片解锁。已解锁直接成功（不重复扣费）；碎片不足返回 false 且不动余额
func try_unlock(key: StringName) -> bool:
	if is_unlocked(key):
		return true
	var cost: int = UNLOCK_COSTS.get(key, 0)
	if shards < cost:
		return false
	shards -= cost
	unlocks[key] = true
	save_game()
	statue_unlocked.emit(key)
	shards_changed.emit(shards)
	return true

func is_unlocked(key: StringName) -> bool:
	return unlocks.get(key, false)

## 查武器下标是否已解锁（短剑常锁）
func is_weapon_unlocked(idx: int) -> bool:
	if idx < 0 or idx >= WEAPON_KEYS.size():
		return false
	var key := WEAPON_KEYS[idx]
	if key == &"":
		return true
	return is_unlocked(key)

## 花英灵碎片解锁武器：已解锁直接成功；碎片不足返回 false（不动余额）
func try_unlock_weapon(idx: int) -> bool:
	if idx < 0 or idx >= WEAPON_KEYS.size():
		return false
	var key := WEAPON_KEYS[idx]
	if key == &"":
		return true
	return try_unlock(key)

func save_game() -> void:
	var unlocks_str: Dictionary = {}
	for k in unlocks:
		if unlocks[k]:
			unlocks_str[String(k)] = true
	var data := {"shards": shards, "unlocks": unlocks_str}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))

func load_game() -> void:
	shards = 0
	unlocks.clear()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return   ## 存档损坏：按全新进度处理，不崩溃
	shards = int(parsed.get("shards", 0))
	var u: Variant = parsed.get("unlocks", {})
	if u is Dictionary:
		for k in u:
			if u[k]:
				unlocks[StringName(k)] = true
