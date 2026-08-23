extends Node

## RunState（autoload）：一次 run 的持久状态，跨场景（存档房/战斗房/Boss房）保留。
## 修复前这些数值存在 Player 节点上，change_scene_to_file 后全部重置，进度系统形同虚设。
## 现在：Player 只负责读写这里，HUD 直接监听这里的信号，RoomDirector 的房间序号也持久化。

## 血量
signal health_changed(new_health: float, max_health: float)
## 进度（等级/经验/货币）
signal stats_changed(level: int, xp: float, xp_to_next: float, currency: float)
## 玩家死亡（DeathUI 监听，弹死亡面板）
signal player_died

var max_health: float = 100.0
var current_health: float = 100.0

var level: int = 1
var xp: float = 0.0
var xp_to_next: float = 20.0
var currency: float = 0.0

## 基础血量上限（不含局外永久加成）。apply_meta_bonuses 从它重算，保证加成幂等不叠加
const BASE_MAX_HEALTH: float = 100.0

## 房间进度（RoomDirector 读写，跨场景不丢）
var room_index: int = 1

## 本局 Boss 击杀数（局外成长死亡结算用），reset_run 归零
var boss_kills: int = 0

## Boss 击杀奖励标记：回到 main 场景后由 BoonSelectUI 消费，自动弹出赐福选择
var pending_boon_offer: bool = false

## 背包（消耗品）：物品 id -> 数量。跨场景保留，死亡重开清空。
signal inventory_changed
var inventory: Dictionary = {}

## 当前武器下标（对应 Player.WEAPONS）。跨场景保留，死亡重开归零。
signal weapon_changed(idx: int)
var weapon_idx: int = 0

func set_weapon(idx: int) -> void:
	weapon_idx = idx
	weapon_changed.emit(weapon_idx)

func add_item(id: StringName, count: int = 1) -> void:
	inventory[id] = inventory.get(id, 0) + count
	inventory_changed.emit()

func item_count(id: StringName) -> int:
	return inventory.get(id, 0)

## 使用一件背包物品（效果由 Items.apply 结算）。没货或无效返回 false。
func use_item(id: StringName, player: Node = null) -> bool:
	if item_count(id) <= 0:
		return false
	if not Items.apply(id, player):
		return false
	inventory[id] -= 1
	if inventory[id] <= 0:
		inventory.erase(id)
	inventory_changed.emit()
	return true

func _ready() -> void:
	# 经验/货币由 RunState 直接累积，不再依赖 Player 节点在场
	EventBus.xp_gained.connect(_on_xp_gained)
	EventBus.currency_gained.connect(_on_currency_gained)

## 受到伤害（由 Player.take_damage 在无敌帧判定后调用）
func apply_damage(amount: float) -> void:
	current_health = maxf(current_health - amount, 0.0)
	health_changed.emit(current_health, max_health)

## 恢复生命，封顶到 max_health
func heal(amount: float) -> void:
	current_health = minf(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)

## 尝试花费金币。余额足够则扣除并刷新 HUD，返回 true；不足返回 false
func spend_currency(amount: float) -> bool:
	if currency < amount:
		return false
	currency -= amount
	_emit_stats()
	return true

func _on_xp_gained(amount: float) -> void:
	xp += amount
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = roundf(xp_to_next * 1.3)
		max_health += 10.0
		current_health = minf(current_health + 25.0, max_health)
		health_changed.emit(current_health, max_health)
	_emit_stats()

func _on_currency_gained(amount: float) -> void:
	currency += amount
	_emit_stats()

func _emit_stats() -> void:
	stats_changed.emit(level, xp, xp_to_next, currency)

## 局外成长永久加成（MetaState 解锁的 bonus_hp / bonus_gold）：
## 从基础值重算而非累加，因此首次启动（MetaState 读档后调用）与死亡重开（reset_run 调用）
## 走同一条路径都不会重复叠加。
func apply_meta_bonuses() -> void:
	max_health = BASE_MAX_HEALTH
	if MetaState.is_unlocked(&"bonus_hp"):
		max_health += 25.0
	current_health = max_health
	currency = 0.0
	if MetaState.is_unlocked(&"bonus_gold"):
		currency += 15.0

## 死亡重开：全部 run 状态归零（祝福由 BoonManager.reset() 另行清理）
func reset_run() -> void:
	apply_meta_bonuses()   ## 血量/金币基础值 + 永久加成
	boss_kills = 0
	level = 1
	xp = 0.0
	xp_to_next = 20.0
	room_index = 1
	pending_boon_offer = false
	inventory.clear()
	inventory_changed.emit()
	weapon_idx = 0
	weapon_changed.emit(weapon_idx)
	health_changed.emit(current_health, max_health)
	_emit_stats()
