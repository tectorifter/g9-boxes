-- g9-boxes -- raise every generation's PC to 50 boxes and make the save
-- loader prove the box table is well-formed before the game can index it.
--
-- The mod is two sibling files, loaded in order:
--
--   boxes/expand.lua      raises the three box-count constants (Gen 1
--                         Boxes.COUNT, Gen 2 Save.NUM_BOXES / Boxes.NUM_BOXES,
--                         Gen 3 Storage.TOTAL_BOXES_COUNT) and wraps the
--                         storage constructors so a SHORT or malformed
--                         save.boxes is materialised/typed before anything
--                         reads it.  This is the fix for the real crash:
--                         Gen 1's Boxes.ensure only builds save.boxes when it
--                         is nil, so a 12-box save left 12 entries while
--                         Boxes.deposit walked for off = 0, COUNT-1 and did
--                         `#boxes[i]` on a nil -> "attempt to get length of a
--                         nil value".  Every reader sizes itself from one of
--                         the constants, so raising them is enough for the
--                         game to offer all 50 boxes.
--
--   boxes/save_guard.lua  wraps each generation's validate pass
--                         (SaveData.validate for Gen 1, gen2 Save.validate for
--                         Gold/Silver/Crystal) so a loaded save comes out
--                         with exactly the right box shape, currentBox in
--                         range, and -- on Gen 1, which has a real quarantine
--                         (save.orphaned, the LOST box) -- overflow MOVED
--                         there rather than silently destroyed.  Gen 2/Gen 3
--                         have no LOST box, so there overflow is relocated to
--                         a box with room when one exists, never dropped.
--
-- A mod that a save was written under is disabled later (or the box count is
-- lowered back), the guard is what keeps the next load from crashing on the
-- boxes the engine no longer expects.  Everything engine-tree stays untouched:
-- both siblings only patch the MODULE TABLES the engine already holds.
-- =============================================================================
return function(mod)
  local function loadSibling(file)
    local body, readErr = mod:read(file)
    assert(body, "g9-boxes: missing sibling file: " .. tostring(file) .. " (" .. tostring(readErr) .. ")")
    local compile = loadstring or load
    local chunk, err = compile(body, "@" .. tostring(mod.path) .. "/" .. file)
    assert(chunk, "g9-boxes: " .. tostring(file) .. " failed to compile: " .. tostring(err))
    return chunk()
  end

  -- One broken sibling must not take the whole mod down; each is logged and
  -- skipped (the loader would otherwise roll back the entire entry chunk).
  local function boot(label, fn)
    local ok, res = pcall(fn)
    if not ok then
      mod.log:warn("g9-boxes: [" .. label .. "] failed to initialize: " .. tostring(res))
      return nil
    end
    return res
  end

  mod.exports.boxCount = 50
  mod.exports.slotCount = 30

  boot("expand", function() return loadSibling("boxes/expand.lua")(mod) end)
  boot("save_guard", function() return loadSibling("boxes/save_guard.lua")(mod) end)

  mod.log:info("g9-boxes: 50-box PC storage ready")
end
