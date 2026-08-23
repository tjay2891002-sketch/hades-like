class_name RoomSpec
extends RefCounted

## 一个出口门通往的下一关房间规格（Phase 4 房间多样性）。
## RoomDirector 在清场后为每个出口门生成一份独立的 RoomSpec，
## 门上徽章据此显示类型/敌人数/奖励偏斜，玩家据此选择走哪扇门。

enum Type { COMBAT, ELITE, MERCHANT, BOSS }

var type: int = Type.COMBAT
var enemy_count: int = 3
var reward_bias: StringName = &""      ## &"gold" = 金币房, &"xp" = 经验房, &"" = 无偏斜
var gold_mult: float = 1.0
var xp_mult: float = 1.0

func type_label() -> String:
	match type:
		Type.COMBAT: return "战斗"
		Type.ELITE: return "精英"
		Type.MERCHANT: return "商人"
		Type.BOSS: return "BOSS"
		_: return "?"

## 徽章文字：类型 + 敌人数（商人/BOSS 不显示敌人数）+ 奖励图标
func badge_text() -> String:
	if type == Type.MERCHANT or type == Type.BOSS:
		return type_label()
	var rw := ""
	if reward_bias == &"gold":
		rw = " 💰"
	elif reward_bias == &"xp":
		rw = " ✦"
	return type_label() + rw
