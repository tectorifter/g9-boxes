# g9-boxes

Every PC in the game holds **50 boxes**. The vanilla counts are 12 (Gen 1
Red/Blue/Yellow), 14 (Gen 2 Gold/Silver/Crystal) and 14 (Gen 3
FireRed/LeafGreen); this mod raises all three to 50 and hardens the save loader
so the jump cannot crash or corrupt an existing playthrough.

It is deliberately **one small, additive mod** rather than a change buried in a
UI or engine pack: nothing else has to be installed, and disabling the mod is
the whole rollback.

## What it changes

The engine sizes its PC screens from a single constant per generation, and
every consumer reads that constant rather than a literal:

- **Gen 1** — `src/pokemon/Boxes.lua` → `Boxes.COUNT`
  (`ui/BoxMenu.lua`, the withdraw/deposit lists and the box picker).
- **Gen 2** — `src/core/gen2/Save.lua` → `Save.NUM_BOXES` and
  `src/core/gen2/Boxes.lua` → `Boxes.NUM_BOXES` (`ui/gen2/PcMenu.lua`,
  `ui/gen2/BoxMenu.lua`).
- **Gen 3** — `src/core/game3/storage.lua` → `Storage.TOTAL_BOXES_COUNT`
  (`ui/game3/box_storage_ui.lua`, `scripting/natives_queries.lua`).

`boxes/expand.lua` sets each of those to **50** and mirrors the value into the
`content.constants` rule table (`boxCount`) so a UI that sizes a grid off the
rule table agrees with the real storage.

Gen 1's native CHANGE BOX menu (`ui/BoxMenu.lua`) builds its `Menu` with a
fixed `th = 14` and no scrolling, so at 50 items the rows would run off the
bottom of the screen and the last boxes would be unreachable. `expand.lua`
narrows a single behaviour change onto that menu: when a `Menu` is built with
exactly the box count of items and every label is `BOXnn`, it is given a
`maxVisible` window (13 rows for the CHANGE BOX menu) so `Menu` scrolls it.
Every other menu is untouched. Gen 2's CHANGE BOX already scrolls a six-row
window and Gen 3 switches boxes with LEFT/RIGHT, so this is Gen 1 only.

Box **capacity is raised to 30** on all three generations — 20 mons per box is
the vanilla Gen 1/2 count and 30 the vanilla Gen 3 count, so a box is now the
same 30 slots everywhere, i.e. **1500 storage slots** (`50 x 30`). The constant
patched is `Boxes.CAPACITY` (Gen 1), `Save.MONS_PER_BOX` + `Boxes.MONS_PER_BOX`
(Gen 2, which are aliases of each other) and `Storage.IN_BOX_COUNT` (Gen 3,
already 30, pinned so a mod that shrank it cannot).

30 is also what g9-gui's modern box page draws as its six-by-five wall, so the
two mods agree on the shape of a box: a fixed grid of 30 always-visible cells
rather than a list that collapses to the number of mons in the box. The cell a
mon sits in rides the mon itself as `mon.boxSlot` (1..30) — the engine never
reads that field, so it survives save/load untouched, and a hole in the middle
of a box stays a hole instead of packing up.

## Why 50 needed a save guard

Raising a constant is easy; the danger is an **existing** save. Gen 1's
`Boxes.ensure` only builds `save.boxes` the first time (when it is `nil`), so a
save written under the 12-box engine keeps 12 entries. `Boxes.deposit` then
walks `for off = 0, Boxes.COUNT - 1` and does `#boxes[i]` on box 13 — a `nil`
length, which is a hard error. Worse, a save edited by hand or written by a
future version could carry an out-of-range `currentBox` or a box with far more
mons than a box holds, and nothing checked any of it.

`boxes/save_guard.lua` wraps each generation's validate pass
(`SaveData.validate` on Gen 1, `Save.validate` on Gen 2) and runs the engine's
own validate first, then:

- **materialises** boxes `1..50` as real tables (`expand.lua`'s `ensure`
  wrapper does this on every `Boxes.ensure`, so even the pre-validate migration
  path is safe);
- **clamps** `currentBox` into `1..50`;
- **quarantines** Gen 1 overflow into the engine's own LOST box
  (`save.orphaned`): whole boxes past 50 and any mon past a box's capacity are
  *moved*, never deleted;
- **relocates** Gen 2 overflow into a box with room (Gen 2 has no LOST box), so
  a mon in an unreachable slot is never silently stranded;
- **repairs the shape** — a non-table `save.boxes`, a non-table `boxNames`, a
  `#nil` hole or a junk entry is normalised before any reader can index it;
- **scrubs `mon.boxSlot`** — the field the modern box page stores a mon's cell
  in (g9-gui) is cleared when it is out of `1..capacity` or duplicated inside
  the same list (each box, and — since 1.1.1 — the Gen 1 party too), so a
  hand-edited or future save can never make two mons claim one cell. The page
  re-seats an unplaced mon on its next draw.

Every repair is logged. A vanilla save passes through untouched: the guard only
writes when something is actually malformed, so a clean 50-box save re-encodes
identically.

## Install

Unzip the export (`⬇ g9-boxes .zip`) into the engine's `mods/` folder so you end
up with

```
mods/g9-boxes/{manifest.json,main.lua,README.md,documentation.md,boxes/expand.lua,boxes/save_guard.lua}
```

then enable it in the Mod Manager. It targets `gen1`, `gen2` and `gen3` and
needs the `engine_internals` permission (it patch-wraps engine module tables —
the engine tree itself is never edited). It has no dependencies.

To roll back, disable it in the Mod Manager. Existing save files are not
changed on disk by this mod; a save that used boxes past the vanilla count will
simply have those boxes unreachable again (their mons stay in the file).

## A note on native `.sav` export

The engine's own save file (Lua table format) keeps all 50 boxes. The native
cartridge exporters, however, are fixed-count by design: `save_convert/GenSave.lua`
writes 12 boxes, `Gen2Save.lua` 14, and `Gen3Save.lua` uses the layout's own
box region. Exporting to a real `.sav` therefore carries only the native number
of boxes and the rest are left out — lossy, but never corrupt, because those
converters clamp to their own fixed size. Keep a Lua-format save if you care
about boxes 13+/15+.

## Version history

- **1.1.2** — the PC holds **50** boxes on all three generations (was 40), so
  total storage is 1500 slots (`50 x 30`). No code-path change beyond the
  `boxCount` export every reader already sizes itself from.
- **1.1.1** — the Gen 1 PARTY gets the same `mon.boxSlot` scrub as each box, so
  a stale or duplicated cell can never ride back into a box when g9-gui's
  modern page deposits a party mon. No capacity change.
- **1.1.0** — boxes hold **30** on all three generations (Gen 1/2 raised from
  20; Gen 3 pinned at its vanilla 30), and the save guard scrubs each boxed
  mon's `mon.boxSlot` cell (the field g9-gui's modern box page rides a mon
  between the 30 slots) so an out-of-range or duplicated cell is cleared.
- **1.0.0** — initial release: 40 boxes on Gen 1/2/3, the `ensure` materialiser,
  and the Gen 1 quarantine / Gen 2 shape repair save guard.

## Repository

<https://github.com/tectorifter/g9-boxes> — the home of this mod. The manifest
declares it as `"github"`, so the gen1recomp launcher can pull an update for an
installed copy straight from its own release.

## License

GNU General Public License v3.0 (GPL-3.0). Copyright (C) 2026
[tectorifter](https://github.com/tectorifter/). The full text ships as
`LICENSE` beside this file.

## Third-party notices

Pokemon and all related names, characters, creatures, moves, items, sprites and
other assets are the property of Nintendo, Creatures Inc., GAME FREAK inc. and
The Pokemon Company. This is an unofficial fan mod and is not affiliated with,
sponsored by or endorsed by them; it owns only its own Lua source (see
`LICENSE`). Third-party fonts, sprite packs, data and companion mods keep their
own licences. The full list ships in
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
