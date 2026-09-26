-- g9-boxes / boxes/save_guard.lua -- the SAVE half: wrap each generation's
-- validate pass so a loaded save always comes out with the box shape the
-- 50-box engine expects, and the count change can never silently destroy
-- something.
--
-- Gen 1 (SaveData.validate, src/core/SaveData.lua:2513) already owns a real
-- quarantine: save.orphaned (the LOST box, walked by its own reclaim()).  So
-- Gen 1 overflow -- whole boxes past 50, mons past a box's 30 -- is MOVED
-- into save.orphaned, exactly the place the engine itself parks a mon whose
-- species became unknown.  Gen 2 / Gen 3 have no LOST box, so there the guard
-- only repairs the SHAPE (boxNames / boxes / currentBox well-typed) and
-- relocates any boxed mon past a box's capacity into a box with room; it
-- never drops one.
--
-- The wrapper calls the real validate FIRST (so all of the engine's own
-- scrubbing still runs exactly as before) and only then normalises the boxes.
-- Everything is pcall'd: a repair failure is logged and the untouched save is
-- returned.
return function(mod)
  local BOX_COUNT = tonumber(mod.exports.boxCount) or 50
  if BOX_COUNT < 1 then BOX_COUNT = 50 end

  local function isInt(n)
    return type(n) == "number" and n == n and n == math.floor(n)
  end

  local function clampIndex(n, hi)
    if not isInt(n) then return 1 end
    if n < 1 then return 1 end
    if n > hi then return hi end
    return n
  end

  -- Box positions ride the mons: `mon.boxSlot` is the mon's cell in a fixed
  -- SLOT_COUNT-cell box (1..30), the modern PC's own array.  The engine never
  -- reads it -- it exists so a slot grid can keep a mon at cell 20 with cells
  -- 1..19 empty, which a packed list cannot express.  A missing/invalid value
  -- is cleared (the grid assigns the first free cell), and duplicates inside
  -- one list keep the first and clear the rest, so a bad file self-heals.
  local SLOT_COUNT = tonumber(mod.exports.slotCount) or 30
  local function scrubSlots(list)
    if type(list) ~= "table" then return end
    local seen = {}
    for i = 1, #list do
      local mon = list[i]
      if type(mon) == "table" then
        local s = tonumber(mon.boxSlot)
        if s == nil or s ~= s then
          mon.boxSlot = nil
        else
          s = math.floor(s)
          if s < 1 or s > SLOT_COUNT or seen[s] then
            mon.boxSlot = nil
          else
            seen[s] = true
            mon.boxSlot = s
          end
        end
      end
    end
  end

  -- Rebuild one mon list as a dense 1..n array of tables, preserving numeric
  -- order.  Non-table entries are handed to `absorb` (the caller decides
  -- whether that means "quarantine" or "drop"); holes and stray keys are
  -- folded away.  Returns the list and whether anything actually changed.
  local function compactMons(list, where, absorb)
    if type(list) ~= "table" then return {}, true end
    local keys = {}
    for k in pairs(list) do
      if isInt(k) and k >= 1 then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local out, dirty = {}, false
    for idx, k in ipairs(keys) do
      local v = list[k]
      if type(v) == "table" then
        out[#out + 1] = v
      else
        absorb(v, where)
        dirty = true
      end
      if k ~= idx then dirty = true end
    end
    if #keys ~= #out then dirty = true end
    if (keys[#keys] or 0) ~= #out then dirty = true end
    return out, dirty
  end

  -- Count how far a sparse array actually reaches (pairs, not #, which a hole
  -- hides).
  local function maxIndex(t)
    local m = 0
    for k in pairs(t) do
      if isInt(k) and k > m then m = k end
    end
    return m
  end

  -- ==================================================================== Gen 1
  local okb, Boxes1 = pcall(require, "src.pokemon.Boxes")
  local CAP1 = (okb and type(Boxes1) == "table" and tonumber(Boxes1.CAPACITY)) or 20

  local function orphaned(save)
    if type(save.orphaned) ~= "table" then save.orphaned = { mons = {}, items = {} } end
    if type(save.orphaned.mons) ~= "table" then save.orphaned.mons = {} end
    if type(save.orphaned.items) ~= "table" then save.orphaned.items = {} end
    return save.orphaned
  end

  local function repairGen1(save, report)
    if type(save) ~= "table" then return 0 end
    local moved = 0
    local function quarantine(mon, where)
      if type(mon) ~= "table" then return end
      local o = orphaned(save)
      o.mons[#o.mons + 1] = mon
      if report and type(report.lostMons) == "table" then
        report.lostMons[#report.lostMons + 1] = { species = mon.species, from = where }
      end
      moved = moved + 1
    end
    local absorb = function(mon, where) quarantine(mon, where) end

    local boxes = save.boxes
    if type(boxes) ~= "table" then
      boxes = {}
      save.boxes = boxes
    end

    -- a save that kept the pre-12-box `box` key beside `boxes`: fold it in
    if type(save.box) == "table" then
      local b1 = boxes[1]
      if type(b1) ~= "table" then b1 = {}; boxes[1] = b1 end
      for _, mon in ipairs(save.box) do
        if #b1 < CAP1 and type(mon) == "table" then
          b1[#b1 + 1] = mon
        else
          quarantine(mon, "legacy box")
        end
      end
      save.box = nil
    end

    -- whole boxes past the cap: their mons go to the LOST box, not nowhere
    for i = BOX_COUNT + 1, maxIndex(boxes) do
      local box = boxes[i]
      if type(box) == "table" then
        for _, mon in ipairs(box) do quarantine(mon, "box " .. i .. " past box " .. BOX_COUNT) end
      end
      boxes[i] = nil
    end
    for k in pairs(boxes) do
      if not isInt(k) then boxes[k] = nil end
    end

    -- every box 1..BOX_COUNT present, dense, with nothing past its capacity
    for i = 1, BOX_COUNT do
      local box = boxes[i]
      if type(box) ~= "table" then
        box = {}
        boxes[i] = box
      end
      local compacted, dirty = compactMons(box, "box " .. i, absorb)
      if dirty then
        boxes[i] = compacted
        box = compacted
      end
      while #box > CAP1 do
        quarantine(table.remove(box), "box " .. i .. " over " .. CAP1)
      end
    end

    save.currentBox = clampIndex(save.currentBox, BOX_COUNT)
    for i = 1, BOX_COUNT do scrubSlots(boxes[i]) end
    -- the PARTY gets the same slot scrub Gen 2's gets: a party mon's boxSlot is
    -- never read (the party is a packed list, array 0), but the modern box page
    -- DEPOSITS it straight into a box with whatever cell it still carries -- so
    -- a stale or duplicated slot here would ride back out of the party, and
    -- this is where it is healed.  (The engine's own withdraw leaves the field
    -- set; nothing else on Gen 1 ever clears it.)
    scrubSlots(save.party)
    return moved
  end

  local okd, SaveData = pcall(require, "src.core.SaveData")
  if okd and type(SaveData) == "table"
      and type(SaveData.validate) == "function" and not SaveData.__g9boxesGuard then
    SaveData.__g9boxesGuard = true
    local realValidate = SaveData.validate
    SaveData.validate = function(save, data)
      local report = realValidate(save, data)
      local ok, moved = pcall(repairGen1, save, report)
      if not ok then
        mod.log:warn("g9-boxes: gen1 save repair failed (" .. tostring(moved) .. ")")
      elseif moved and moved > 0 then
        mod.log:warn("g9-boxes: gen1 save repaired -- " .. tostring(moved)
          .. " mon(s) moved to the LOST box (save.orphaned)")
      end
      return report
    end
  end

  -- ==================================================================== Gen 2
  local ok2, Save2 = pcall(require, "src.core.gen2.Save")
  if ok2 and type(Save2) == "table"
      and type(Save2.validate) == "function" and not Save2.__g9boxesGuard then
    Save2.__g9boxesGuard = true
    local realValidate2 = Save2.validate
    local NUM2 = math.max(BOX_COUNT, tonumber(Save2.NUM_BOXES) or BOX_COUNT)
    local CAP2 = tonumber(Save2.MONS_PER_BOX) or 20

    local function repairGen2(save)
      if type(save) ~= "table" then return 0 end
      local relocated, dropped = 0, 0
      if type(save.boxes) ~= "table" then save.boxes = {} end
      if type(save.boxNames) ~= "table" then save.boxNames = {} end
      local boxes = save.boxes

      -- a name is only meaningful for a box the UI can reach, and must be a
      -- string (Boxes.name indexes boxNames[index], so a non-table boxNames
      -- is a hard crash on the PC screen)
      for k, v in pairs(save.boxNames) do
        if not isInt(k) or type(v) ~= "string" then save.boxNames[k] = nil end
      end
      for i = NUM2 + 1, maxIndex(save.boxNames) do save.boxNames[i] = nil end

      for k in pairs(boxes) do
        if not isInt(k) then boxes[k] = nil end
      end
      local top = maxIndex(boxes)
      for i = 1, top do
        local box = boxes[i]
        if type(box) == "table" then
          local compacted, dirty = compactMons(box, "box " .. i, function() dropped = dropped + 1 end)
          if dirty then boxes[i] = compacted end
        end
      end

      -- a boxed mon past the capacity of every UI slot would be invisible and
      -- unrecoverable: move it into a box with room, never drop it.  Gen 2's
      -- own Boxes.box creates a box on demand, so a missing one counts as room.
      local function firstRoom()
        for b = 1, NUM2 do
          local bx = boxes[b]
          if type(bx) ~= "table" then
            bx = {}
            boxes[b] = bx
          end
          if #bx < CAP2 then return bx end
        end
        return nil
      end
      for i = NUM2 + 1, top do
        local box = boxes[i]
        if type(box) == "table" then
          for _, mon in ipairs(box) do
            local room = firstRoom()
            if room then
              room[#room + 1] = mon
              relocated = relocated + 1
            end
          end
        end
        boxes[i] = nil
      end
      for i = 1, NUM2 do
        local box = boxes[i]
        if type(box) == "table" then
          while #box > CAP2 do
            local room = firstRoom()
            if not room then break end
            room[#room + 1] = table.remove(box)
            relocated = relocated + 1
          end
        end
      end

      save.currentBox = clampIndex(save.currentBox, NUM2)
      for i = 1, NUM2 do scrubSlots(boxes[i]) end
      scrubSlots(save.party)
      return relocated, dropped
    end

    Save2.validate = function(save)
      local report = realValidate2(save)
      local ok, relocated, dropped = pcall(repairGen2, save)
      if not ok then
        mod.log:warn("g9-boxes: gen2 save repair failed (" .. tostring(relocated) .. ")")
      elseif (relocated or 0) > 0 or (dropped or 0) > 0 then
        mod.log:warn("g9-boxes: gen2 save repaired -- " .. tostring(relocated)
          .. " mon(s) relocated, " .. tostring(dropped) .. " junk entr(ies) dropped")
      end
      return report
    end
  end

  mod.log:info("g9-boxes: save guard installed (gen1 quarantine, gen2 shape repair)")
end
