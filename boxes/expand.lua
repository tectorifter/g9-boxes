-- g9-boxes / boxes/expand.lua -- the CONTENT half: raise every generation's
-- box count to 50 and make the storage constructors hand back a 50-entry,
-- well-typed box table no matter what shape the save was written in.
--
-- Every reader in the engine sizes itself from one of the constants patched
-- below, so raising them is what makes the whole game offer 50 boxes:
--   * src/pokemon/Boxes.lua            Gen 1  Boxes.COUNT
--   * src/core/gen2/Save.lua           Gen 2  Save.NUM_BOXES
--   * src/core/gen2/Boxes.lua          Gen 2  Boxes.NUM_BOXES
--   * src/core/game3/storage.lua       Gen 3  Storage.TOTAL_BOXES_COUNT
--     (ui/BoxMenu.lua, ui/gen2/PcMenu.lua, ui/gen2/BoxMenu.lua,
--      ui/game3/box_storage_ui.lua and scripting/natives_queries.lua all read
--      the constant rather than a literal.)
--
-- A constant alone is NOT safe on Gen 1: Boxes.ensure only builds save.boxes
-- when it is nil, so a save that already carries the vanilla 12 keeps 12 while
-- Boxes.deposit walks 1..COUNT and does `#boxes[i]` -- a nil -> crash.  The
-- ensure wrapper materialises the missing boxes and repairs non-table entries,
-- and clamps currentBox, so the engine can never index a nil box.
--
-- Each generation is patched under its own pcall: a module this install cannot
-- load (a cartridge the player does not have) never stops the others.
return function(mod)
  local BOX_COUNT = tonumber(mod.exports.boxCount) or 50
  if BOX_COUNT < 1 then BOX_COUNT = 50 end
  -- Every box is a fixed 30-slot array (6 columns x 5 rows), the modern PC's
  -- own shape.  Gen 3 already holds 30 per box; Gen 1 (20) and Gen 2 (20) are
  -- raised to match, so a slot grid has 30 usable cells on every generation.
  local SLOT_COUNT = tonumber(mod.exports.slotCount) or 30
  if SLOT_COUNT < 1 then SLOT_COUNT = 30 end

  local function clampIndex(n, hi)
    n = tonumber(n)
    if n == nil or n ~= n then return 1 end
    n = math.floor(n)
    if n < 1 then return 1 end
    if n > hi then return hi end
    return n
  end

  local installed = {}

  -- --------------------------------------------------------------- Gen 1 ---
  local ok1, Boxes1 = pcall(require, "src.pokemon.Boxes")
  if ok1 and type(Boxes1) == "table" then
    Boxes1.COUNT = BOX_COUNT
    Boxes1.CAPACITY = SLOT_COUNT
    local realEnsure = Boxes1.ensure
    if type(realEnsure) == "function" and not Boxes1.__g9boxes then
      Boxes1.__g9boxes = true
      Boxes1.ensure = function(save)
        if type(save) ~= "table" then return realEnsure(save) end
        local boxes = realEnsure(save)
        if type(boxes) ~= "table" then
          boxes = {}
          save.boxes = boxes
        end
        -- materialise 1..COUNT so #boxes[i] is never a nil-length error
        for i = 1, Boxes1.COUNT do
          if type(boxes[i]) ~= "table" then boxes[i] = {} end
        end
        save.currentBox = clampIndex(save.currentBox or 1, Boxes1.COUNT)
        return boxes
      end
    end
    installed[#installed + 1] = "gen1"
  else
    mod.log:warn("g9-boxes: gen1 Boxes module unreachable (" .. tostring(Boxes1) .. ")")
  end

  -- Gen 1's native CHANGE BOX menu (ui/BoxMenu.lua changeBoxMenu) sizes a Menu
  -- with an explicit th = 14 and no maxVisible, so with 50 items Menu.new
  -- computes visible = #items and draws rows past the bottom of the screen --
  -- boxes beyond ~17 would be unreachable.  Ask Menu to scroll that menu (and
  -- only that one): #items equals the box count and every label is "BOXnn".
  -- Gen 2's CHANGE BOX already scrolls a six-row window and Gen 3 switches
  -- boxes with LEFT/RIGHT, so this is Gen 1 only.
  local okm, Menu = pcall(require, "src.ui.Menu")
  if okm and type(Menu) == "table"
      and type(Menu.new) == "function" and not Menu.__g9boxes then
    Menu.__g9boxes = true
    local realNew = Menu.new
    Menu.new = function(game, items, opts)
      if opts and opts.maxVisible == nil and type(items) == "table"
          and #items == BOX_COUNT and #items > 1 then
        local allBoxes = true
        for _, it in ipairs(items) do
          if type(it) ~= "table" or type(it.label) ~= "string"
              or not it.label:match("^BOX%s*%d+$") then
            allBoxes = false
            break
          end
        end
        if allBoxes then
          local merged = {}
          for k, v in pairs(opts) do merged[k] = v end
          -- rows that fit above the bottom border: itemY + (row-1)*rowStep <= th-2
          merged.maxVisible = math.max(2,
            math.floor(((opts.th or 16) - 2 - (opts.itemY or 2)) / (opts.rowStep or 2)) + 1)
          return realNew(game, items, merged)
        end
      end
      return realNew(game, items, opts)
    end
  end

  -- --------------------------------------------------------------- Gen 2 ---
  local ok2s, Save2 = pcall(require, "src.core.gen2.Save")
  if ok2s and type(Save2) == "table" then
    Save2.NUM_BOXES = BOX_COUNT
    Save2.MONS_PER_BOX = SLOT_COUNT
  end
  local ok2b, Boxes2 = pcall(require, "src.core.gen2.Boxes")
  if ok2b and type(Boxes2) == "table" then
    Boxes2.NUM_BOXES = BOX_COUNT
    Boxes2.MONS_PER_BOX = SLOT_COUNT
    -- Boxes.box already answers an out-of-range index with a throwaway {} --
    -- but it writes save.boxes[index] without first checking save.boxes is a
    -- table, so make that write structural.
    local realBox = Boxes2.box
    if type(realBox) == "function" and not Boxes2.__g9boxes then
      Boxes2.__g9boxes = true
      Boxes2.box = function(save, index)
        if type(save) ~= "table" then return {} end
        if type(save.boxes) ~= "table" then save.boxes = {} end
        return realBox(save, index)
      end
    end
    installed[#installed + 1] = "gen2"
  end

  -- --------------------------------------------------------------- Gen 3 ---
  local ok3, Storage = pcall(require, "src.core.game3.storage")
  if ok3 and type(Storage) == "table" then
    Storage.TOTAL_BOXES_COUNT = BOX_COUNT
    Storage.IN_BOX_COUNT = SLOT_COUNT
    Storage.TOTAL_BOX_MONS = BOX_COUNT * SLOT_COUNT
    local realEnsure = Storage.ensure
    if type(realEnsure) == "function" and not Storage.__g9boxes then
      Storage.__g9boxes = true
      Storage.ensure = function(session)
        if type(session) ~= "table" then return realEnsure(session) end
        -- Storage.ensure itself does `#session.storage.boxes`, which a
        -- non-table value would turn into an error before it can rebuild.
        if session.storage ~= nil and type(session.storage) ~= "table" then
          session.storage = nil
        elseif type(session.storage) == "table"
            and session.storage.boxes ~= nil
            and type(session.storage.boxes) ~= "table" then
          session.storage.boxes = nil
        end
        local st = realEnsure(session)
        if type(st) ~= "table" then return st end
        if type(st.boxes) ~= "table" then st.boxes = {} end
        for b = 1, Storage.TOTAL_BOXES_COUNT do
          local box = st.boxes[b]
          if type(box) ~= "table" then
            st.boxes[b] = {
              name = string.format("BOX %d", b),
              wallpaper = ((b - 1) % 16) + 1,
              mons = {},
            }
          else
            if type(box.mons) ~= "table" then box.mons = {} end
            if box.name == nil then box.name = string.format("BOX %d", b) end
            if box.wallpaper == nil then box.wallpaper = ((b - 1) % 16) + 1 end
          end
        end
        st.currentBox = clampIndex(st.currentBox or 1, Storage.TOTAL_BOXES_COUNT)
        return st
      end
    end
    installed[#installed + 1] = "gen3"
  end

  -- ------------------------------------------------- the rule-table mirror ---
  -- Nothing in the engine reads data.constants.boxCount today -- every reader
  -- uses Boxes.COUNT / Save.NUM_BOXES / Storage.TOTAL_BOXES_COUNT -- but a UI
  -- mod is free to size a grid off the rule table, and 12 there beside a
  -- 50-box save is exactly the "bad data" this mod exists to prevent.  Patch
  -- it best-effort; a registry without the key simply logs and moves on.
  local okc, constants = pcall(function() return mod.content.constants end)
  if okc and constants and type(constants.patch) == "function" then
    local okp, err = pcall(function() constants:patch("boxCount", BOX_COUNT) end)
    if not okp then
      mod.log:warn("g9-boxes: constants.boxCount patch skipped (" .. tostring(err) .. ")")
    end
  end

  mod.log:info("g9-boxes: box count set to " .. tostring(BOX_COUNT) .. " ["
    .. (#installed > 0 and table.concat(installed, "/") or "no engine module reached")
    .. "]")
end
