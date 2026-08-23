class_name Items
extends RefCounted

## 消耗品注册表（静态数据，无需 autoload）。
## 加新物品：在 DEFS 加一条（action 填对应的 InputMap 动作）+ 在 player.gd 绑一个热键即可。

const DEFS: Dictionary = {
	&"potion": {
		"name": "血瓶",
		"desc": "恢复 30 点生命",
		"heal": 30.0,
		"action": &"item_1",
	},
	&"greater_potion": {
		"name": "大血瓶",
		"desc": "恢复 70 点生命",
		"heal": 70.0,
		"action": &"item_2",
	},
}

static func item_name(id: StringName) -> String:
	var def: Dictionary = DEFS.get(id, {})
	return def.get("name", String(id))

## 热键提示：键名随输入设备变化（键盘 1/2 ↔ 手柄 LB/RT）
static func hotkey_label(id: StringName) -> String:
	var def: Dictionary = DEFS.get(id, {})
	var action: StringName = def.get("action", &"")
	if action != &"":
		return InputDevice.hint(action)
	return "?"

## 使用物品效果。返回 true 表示生效（调用方负责扣库存）。
static func apply(id: StringName, player: Node) -> bool:
	var def: Dictionary = DEFS.get(id, {})
	if def.is_empty():
		return false
	if def.has("heal"):
		if player != null and player.has_method("heal"):
			player.heal(def["heal"])
			return true
		# 没有玩家节点在场时兜底直接加血（无飘字）
		RunState.heal(def["heal"])
		return true
	return false
