# g9-boxes — manifest description

This file records the full `description` for the **g9-boxes** mod
(`manifest.json`). The manifest's own `description` field is capped at
**80 characters** (a studio rule, so the Mod Manager row and the generator
listing stay readable), so the complete text lives here and the manifest
carries only a short summary.

## Current description (full)

Every PC in the game holds 50 boxes. The vanilla box counts are 12 for Gen 1
(Red/Blue/Yellow), 14 for Gen 2 (Gold/Silver/Crystal) and 14 for Gen 3
(FireRed/LeafGreen); this mod raises all three to 50 and hardens the save
loader so the change cannot crash or corrupt an existing playthrough. Box
capacity is raised to 30 on all three generations (Gen 1's `Boxes.CAPACITY`
and Gen 2's `Save.MONS_PER_BOX`/`Boxes.MONS_PER_BOX` go up from 20, Gen 3's
`Storage.IN_BOX_COUNT` is pinned at its vanilla 30), so every box is the same
30 slots and the total storage becomes 1500 slots. The save half also clears a
boxed mon's `mon.boxSlot` cell (the field the modern box page in g9-gui rides
a mon between the 30 slots) when it is out of range or duplicated. The count is
raised by patching
the single constant each generation's UI and storage code already reads:
Gen 1's `Boxes.COUNT`, Gen 2's `Save.NUM_BOXES` and `Boxes.NUM_BOXES`, and
Gen 3's `Storage.TOTAL_BOXES_COUNT`; the value is also mirrored into the
`content.constants` rule table as `boxCount`. The save half wraps each
generation's validate pass (SaveData.validate for Gen 1, Save.validate for
Gen 2), calls the engine's own validate first, and then guarantees the loaded
save has boxes 1..50 as real tables, a currentBox inside 1..50, and no reader
can index a nil box, a non-table box, or a non-table boxNames. Gen 1 overflow
(whole boxes past 50, or a mon past a box's 30) is moved into the engine's own
LOST box (`save.orphaned`), never deleted; Gen 2 overflow is relocated into a
box with room because that generation has no LOST box. Every repair is logged
and a clean save passes through untouched. Nothing in the engine tree is
edited — only the module tables the engine already holds.

## Manifest summary (<= 80 chars)

50 boxes of 30 slots, with save repair to stop overflows

## History

- **1.1.5** declares the mod's own repository in the manifest
  (`"github": "https://github.com/tectorifter/g9-boxes"`), so the gen1recomp
  launcher can pull updates for an installed copy from its own GitHub release.
  No code change.
- **1.1.4** adds a third-party-IP notice (`THIRD-PARTY-NOTICES.md`): Pokemon and
  related assets belong to Nintendo, Creatures Inc., GAME FREAK inc. and The
  Pokemon Company; this is an unofficial fan mod owning only its own Lua
  (GPL-3.0-or-later) and shipping no third-party assets. No code change.
- **1.1.3** places the mod under the **GNU GPLv3**: a `LICENSE` file (the full
  GNU General Public License, version 3, copyright **tectorifter**
  <https://github.com/tectorifter/>) now ships with it. No code change.
- **1.1.2** — the PC holds **50** boxes (was 40) on Gen 1/2/3, so total
  storage is 1500 slots (`50 x 30`). Only the `boxCount` export changes; every
  reader — and the `content.constants` `boxCount` mirror — already sizes itself
  from it, and the save guard materialises/clamps to the raised count unchanged.
- **1.1.1** — the Gen 1 PARTY gets the same `mon.boxSlot` scrub each box gets,
  so a stale or duplicated cell cannot ride back into a box when g9-gui's
  modern page deposits a party mon. No capacity change.
- **1.1.0** — box capacity raised to **30** on all three generations (Gen 1/2
  from 20; Gen 3 pinned at its vanilla 30), so a box is 30 slots everywhere and
  the total is 1200. `save_guard.lua` also scrubs each boxed mon's
  `mon.boxSlot` (cleared when out of `1..capacity` or duplicated in a box), the
  cell field g9-gui's modern box page stores a mon's position in.
- **1.0.0** — initial release. `boxes/expand.lua` raises the three generation
  box-count constants and wraps `Boxes.ensure` (Gen 1), `Boxes.box` (Gen 2) and
  `Storage.ensure` (Gen 3) so a short or malformed save is materialised and
  typed before anything reads it, which is the fix for the Gen 1
  `#nil`-on-box-13 crash a 12-box save hit under a 40-box engine.  It also
  gives Gen 1's native CHANGE BOX menu a `maxVisible` window (it is built with
  a fixed `th = 14` and no scrolling, so 40 rows would run off the screen) --
  scoped to a `Menu` built with exactly the box count of `BOXnn` labels, so no
  other menu changes.
  `boxes/save_guard.lua` wraps `SaveData.validate` (Gen 1) and
  `Save.validate` (Gen 2): the engine's validate runs first, then boxes are
  materialised to 40, `currentBox` clamped, Gen 1 overflow quarantined to
  `save.orphaned`, Gen 2 overflow relocated, and box/nickname table shapes
  repaired. Mod targets `gen1`, `gen2`, `gen3`; permission `engine_internals`.
