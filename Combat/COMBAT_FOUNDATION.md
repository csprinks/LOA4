# Combat Foundation (LOA4)

Turn-based, first-person combat in the tradition of Wizardry, early Might &
Magic, and Dragon Quest — rebuilt as a modern tactical take. This document
records the design decisions and the code architecture of the **logic core**
(headless, testable; no battle scene yet).

## Design decisions

| Area | Decision |
|------|----------|
| Turn model | **Sequential initiative.** One queue of all combatants; each acts on its own turn, heroes and enemies interleaved. |
| Initiative | `Finesse + Awareness + random roll`, **re-rolled at the start of every round.** |
| Action economy | **AP budget.** Actions cost AP; AP **refreshes each turn but unspent AP banks** (overflow) up to `2× max`. |
| Battlefield | **Heroes have no rows** (flat party). **Monsters have rows.** Melee (either side) reaches only the **front monster row**; clearing it promotes the next. Ranged/spells hit **any** monster row. Enemy melee always reaches heroes. |
| Enemy model | **`Combatant` wrapper** over a **`MonsterDefinition` Resource** (`.tres`-authorable), sharing the initiative queue with hero `Character`s. |
| Attack resolution | **To-hit roll → damage roll → minus flat `Armor`.** |
| Accuracy / Evasion | `Accuracy = Might + Finesse`; `Evasion = Finesse + Awareness`. |
| Crits / luck | **Fate → passive crit chance**; **Fortune Points → spendable rerolls** (ally misses can be rerolled by spending 1 FP). |
| Commands (v1) | **Attack, Defend, Item, Flee.** `Cast`/spells extend the same `Action` base later. |
| Status effects | Small **`StatusEffect`** system (durational, ticks per turn). Defend is a 1-turn damage-reduction buff. |
| Hero at 0 HP | **Downed / revivable** (KO). Party loses only when **all** are down. Permanent death can layer on later. |
| Outcomes | `WIN` / `LOSE` / `FLED`. WIN awards **XP** (`reward_xp`), **crowns** (`Crowns`), and **loot** (backpack). LOSE = party wipe. FLED = no rewards. |
| Enemy AI | **Simple** (attack a random living hero; Defend when out of AP) behind a **pluggable `AIStrategy`** seam. |

## Architecture

```
Combat/
├─ combat_constants.gd     All tunable numbers (hit %, damage, crit, AP, defend, flee, initiative)
├─ combat_rng.gd           Seedable, injectable RNG (deterministic tests)
├─ status_effect.gd        Base durational condition (hooks: apply / turn_start / modify_incoming_damage / expire)
│  └─ defend_effect.gd      Defend = incoming-damage reduction for 1 turn
├─ monster_definition.gd   Resource: one monster type's stats + attack profile + rewards + loot
├─ monster_library.gd      Code-built sample monsters (Kobold, Orc, Kobold Archer) for bootstrapping/tests
├─ combatant.gd            The shared fighter: wraps a hero Character OR a MonsterDefinition
├─ encounter.gd            Board state: allies, enemy rows, reach/targeting queries, WIN/LOSE/FLED
├─ combat_resolver.gd      Pure math: hit chance, damage, crits
├─ combat_controller.gd    Turn engine: per-round initiative, turn loop, AP banking, reward payout
├─ ai_strategy.gd          Enemy decision seam (base)
│  └─ basic_ai_strategy.gd  v1 enemy behavior
├─ actions/
│  ├─ combat_action.gd      Base command (ap_cost_for / can_perform / execute) — spells extend this
│  ├─ attack_action.gd      Weapon attack + row reach + Fortune-reroll seam
│  ├─ defend_action.gd      Apply DefendEffect
│  ├─ item_action.gd        Use a potion (HEALTH/ACTION_POINTS mapped; MANA/ENERGY no-op for now)
│  └─ flee_action.gd        Chance to end the encounter as FLED
└─ tests/
   └─ combat_test.gd        Headless smoke test (seeded, deterministic)
```

### Key seams (left open on purpose)

- **`CombatAction` base** — spell/ability actions extend it; the engine only ever
  talks to `CombatAction`, so magic drops in without touching the loop.
- **`CombatController.ally_action_provider`** (`Callable`) — the battle UI supplies
  the player's chosen action; tests supply a scripted policy. The controller also
  exposes `build_initiative()` / `begin_turn()` / `apply_action()` so a
  turn-by-turn UI can drive the fight instead of `run_to_completion()`.
- **`CombatController.reroll_decider`** (`Callable`) — interactive Fortune-Point
  reroll in-game; never in tests.
- **`AIStrategy`** — swap in smarter/per-monster enemy behavior.
- **Weapon damage** — `Combatant.get_attack_profile()` reads an equipped primary
  weapon's damage if present, else unarmed defaults. The exact
  `EquipmentSerializer` weapon keys still need confirming (marked `TODO`).
- **Item consumption** — `ItemAction` applies real potion effects; removing the
  used potion from the backpack waits on an `InventoryManager.remove_item()` that
  doesn't exist yet (marked `TODO`).

## Combat math (all constants in `combat_constants.gd`)

- **Hit %** = `75 + (Accuracy − Evasion) × 3`, clamped to `[5, 95]`.
- **Damage** = `weapon_roll + floor(Might × 0.5)`, `×2` on a crit, then `− Armor`,
  floored at `1` (before Defend/status mitigation).
- **Crit %** = `round(Fate × 0.5)`, capped at `50`.
- **Initiative** = `Finesse + Awareness + randi(0..20)`, re-rolled each round.
- **AP** refresh = `min(2 × max, current + max)` each turn. Attack 3 / Defend 1 /
  Item 2 / Flee 2 (attack cost may be overridden by weapon/monster).

## Running the test

The test is headless and deterministic (seeded RNG):

```bash
# From wherever your Godot 4.x editor binary lives, e.g. Godot_v4.7.exe:
Godot_v4.7.exe --headless --path "E:/Godot Projects/loa-4" --script res://Combat/tests/combat_test.gd
```

If Godot can't resolve the new `class_name`s (fresh files not yet in the global
class cache), rebuild the cache once, then re-run:

```bash
Godot_v4.7.exe --headless --editor --quit --path "E:/Godot Projects/loa-4"
```

It exercises: a full fight to completion + reward payout, monster-row reach and
front-row promotion, downed/revive and the LOSE condition, Defend mitigation, and
AP banking. Exit code = number of failed checks (0 = all pass).

## Not yet built (next steps)

1. **Spells/abilities** — an `AbilityAction` (+ resource cost, target rules,
   effects) extending `CombatAction`; a spellbook per class.
2. **Battle scene/UI** — first-person enemy display, action menu, combat log
   (the existing `Rolling_Battle_Text` scene can show damage numbers).
3. **Weapon-damage + item-consume hookups** (the two `TODO` seams above).
4. **Row-swap / Move** command and ranged hero weapons.
5. **Encounter authoring** — `.tres` `MonsterDefinition`s and an encounter table.
6. **Permanent death**, surprise/ambush rounds, morale, richer AI.
