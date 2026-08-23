# 角色帧动画素材说明（ANIMATIONS）

本目录为逐帧 PNG（`<角色>_<动作>[_<朝向>]_<帧号>.png`，帧号从 0 开始），全部由
Calciumtrice 的 spritesheet 按等宽网格裁出（裁帧脚本为一次性脚本，未保留；原始
spritesheet 保留在 `C:\Users\admin\Downloads\ca_*_spritesheet.png`）。**所有帧均保留
原始尺寸，未做缩放**；游戏内请用最近邻（NEAREST）缩放。

游戏内目标尺寸：普通角色 32×32，Boss 64×64。

## 覆盖关系（对应游戏角色）

| 游戏角色 | 动画前缀 | 原始帧尺寸 | 推荐缩放 | 来源 |
|---|---|---|---|---|
| 玩家战士 | `player_*` | 64×64 | 0.5×（→32×32） | Animated Warrior（CC-BY 4.0） |
| 近战小怪 | `goblin_*`（小刀哥布林） | 32×32 | 1× | Animated Goblins（CC-BY 3.0） |
| 近战小怪（备选/重装变体） | `goblinhammer_*`（盔甲锤哥布林） | 32×32 | 1× | Animated Goblins（CC-BY 3.0） |
| 近战小怪（备选） | `slime_*`（绿色史莱姆） | 32×32 | 1× | Animated Slime（CC-BY 3.0） |
| 冲撞型野兽 | `minotaur_*` | 48×48 | 0.67× 或直接 1× 当中型怪 | Animated Minotaur（CC-BY 3.0） |
| 远程法师 | `mage_*` | 32×32 | 1× | Animated Mage（CC-BY 3.0） |
| 重装大型怪 / Boss | `statue_*` | 64×64 | Boss 1×（→64×64）；普通大怪 0.5× | Animated Statue（CC-BY 3.0） |

## 各动画帧清单

### player_*（Animated Warrior，64×64/帧，带剑版本；另有空手版未裁）
- `player_idle_front/back/left/right`：各 12 帧
- `player_run_front/back/left/right`：各 8 帧
- `player_attack_front/back/left/right`：各 6 帧
- `player_death`：14 帧（无朝向）
- 原表 `ca_warrior_spritesheet.png`（896×1600，64×64 格，14 列×25 行）；行布局见
  `Downloads\ca_warrior_labelled_reference.png`：每个动作分 FRONT/BACK/LEFT/RIGHT ×
  UNARMED/SWORD 两行，本次只裁了 SWORD 行 + DEATH 行（第 24 行）。
- 朝向说明：left/right 为侧向，front 朝下（面向镜头），back 朝上。

### goblin_* / goblinhammer_*（Animated Goblins，32×32/帧，各 10 帧）
- `_idle`、`_gesture`（挑衅/警觉，可当受击或警戒）、`_run`、`_attack`、`_death`
- 原表 `ca_goblin_spritesheet.png`（320×320，32×32 格，10×10）：行 0–4 小刀哥布林
  （idle/gesture/walk/attack/death），行 5–9 盔甲锤哥布林同序。

### slime_*（Animated Slime，32×32/帧，各 10 帧）
- 同上 5 个动作；本次只裁绿色（行 0–4）。原表 320×640 共 20 行，行 5–9 蓝、
  10–14 红、15–19 黄，需要换色可自行补裁。

### minotaur_*（Animated Minotaur，48×48/帧，各 10 帧）
- `_idle`、`_gesture`、`_run`（冲撞跑姿）、`_attack`（带挥击弧光）、`_death`
- 原表 `ca_minotaur_spritesheet.png`（480×240，48×48 格，10 列×5 行）。

### mage_*（Animated Mage，32×32/帧，各 10 帧）
- `_idle`、`_gesture`（抬手咏唱，可当施法前摇）、`_run`、`_attack`（法杖挥出，
  可当施法帧）、`_death`
- 原表 `ca_mage_spritesheet.png`（320×160，32×32 格，10 列×5 行）。

### statue_*（Animated Statue，64×64/帧）
- `statue_turn`：4 帧（从石像状态转身激活，可当 Boss 登场/苏醒）
- `statue_run`：8 帧（行走）
- `statue_attack`：5 帧（抡锤）
- `statue_death`：6 帧（崩碎）
- 原表 `ca_statue_spritesheet.png`（512×256，64×64 格，8 列×4 行，"no green" 无绿锈
  版本；另有 tan/grey × 有/无绿锈 4 个变体未下载，见 OGA 页面）。

## 备注

- 所有动画均为单向（侧向只有 left/right 之分由 warrior 提供；怪物无朝向区分，
  需要镜像时用引擎 flip_h）。
- 未缩放、未调色；如需命中特效帧，可用 `*_gesture` 或 attack 中段帧。
- 许可与署名要求见 `../ATTRIBUTION.md`「角色动画素材」一节。
