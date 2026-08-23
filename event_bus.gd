extends Node

## 跨场景事件总线（autoload）。
## 只承载可缺失、多监听的“玩家攻击命中敌人”这类事件，
## 供祝福系统（BoonManager）hook，避免玩家直接耦合具体机制。
## 可靠 1:1 交互（玩家调敌人 take_damage）不走这里。

signal hit_landed(enemy: Node, damage: float)

## 敌人死亡（由 enemy._die 上报），供房间控制器统计清房进度
signal enemy_died(enemy: Node)

## 房间清空（房间序号 + 是否精英房），触发遇神/掉落等前置条件逻辑
signal room_cleared(room_index: int, is_elite: bool)

## 敌人死亡掉落经验（amount 为数值，供玩家成长系统累加）
signal xp_gained(amount: float)

## 敌人死亡掉落货币（amount 为数值，供玩家货币系统累加）
signal currency_gained(amount: float)

## 请求打开赐福选择界面。[param god_filter] 为空=任意神；指定神名=只在该神卡池抽。
## [param card_id] 非空时只出这一张卡（雕像用：雕像代表卡池里的一张具体机制卡）。
## 由掉落物 / 雕像的 interact 触发，解耦具体来源。
signal boon_offer_requested(god_filter: StringName, card_id: StringName)

## 选卡界面被 ESC 跳过（未选卡）。存档房雕像监听此信号恢复原样，防止软锁。
signal boon_offer_skipped

## 请求打开商店界面。由商人 interact 触发，解耦商人节点与商店 UI（ShopUI）。
## 商店内按金币扣费购买治疗/赐福，逻辑全部收敛在 ShopUI，不污染商人节点。
signal shop_opened
