-- Trainer scanner: builds normalized entries from Blizzard trainer API
local _, wt = ...

wt.debug = wt.debug or false

-- Filter changes fire TRAINER_UPDATE. Ignore those while we are the ones changing them
-- or the restore step will re-enter forever and freeze the client.
local applyingFilters = false

local function dprint(...)
  if not wt.debug then return end
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[WT:Epoch]|r " .. table.concat({tostringall(...)}, " "))
end

local tip = CreateFrame("GameTooltip", "WT_EpochTrainerTip", UIParent, "GameTooltipTemplate")
tip:SetOwner(UIParent, "ANCHOR_NONE")
tip:SetClampedToScreen(false)
tip:ClearAllPoints()
tip:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -128, 0)
tip:Hide()

local function StripReq(text)
  if not text or text == "" then return nil end
  if text:match("^Requires") then return nil end
  if text:match("^Cost") then return nil end
  if text:match("^You must") then return nil end
  if text:match("^Already known") then return nil end
  return text
end

local function DescriptionFromTip()
  local out = {}
  for i = 3, tip:NumLines() do
    local fs = _G["WT_EpochTrainerTipTextLeft" .. i]
    local txt = StripReq(fs and fs:GetText())
    if txt then table.insert(out, txt) end
  end
  return table.concat(out, "\n")
end

local function SpellIDFromTip()
  if not (tip and tip.GetSpell) then return nil end
  local _, _, spellID = tip:GetSpell()
  return tonumber(spellID)
end

local function SpellIDFromLink(name, rank)
  if not (name and name ~= "" and GetSpellLink) then return nil end
  local query = name
  if rank and rank ~= "" then
    query = name .. " (" .. rank .. ")"
  end
  local link = GetSpellLink(query)
  if not link then return nil end
  return tonumber(link:match("Hspell:(%d+)"))
end

-- One SetTrainerService per row: tooltip:GetSpell() plus description from the same tip.
local function ResolveSpellIDAndDescription(index, name, rank)
  local desc = GetTrainerServiceDescription and GetTrainerServiceDescription(index) or ""
  local id
  if tip and tip.SetTrainerService then
    tip:Hide()
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:ClearAllPoints()
    tip:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -128, 0)
    tip:ClearLines()
    tip:SetTrainerService(index)
    id = SpellIDFromTip()
    if not desc or desc == "" then
      desc = DescriptionFromTip()
    end
    tip:Hide()
  end
  if not id then
    id = SpellIDFromLink(name, rank)
  end
  return id, desc or ""
end

local function ResolveIcon(name, rank, index, spellID)
  if spellID and type(GetSpellTexture) == "function" then
    local tex = GetSpellTexture(spellID)
    if tex then return tex end
  end
  if type(GetTrainerServiceIcon) == "function" then
    local tex = GetTrainerServiceIcon(index)
    if tex then return tex end
  end
  if name and name ~= "" then
    local _, _, tex = GetSpellInfo(name)
    if tex then return tex end
    if rank and rank ~= "" then
      local _, _, tex2 = GetSpellInfo(name .. " (" .. rank .. ")")
      if tex2 then return tex2 end
      local _, _, tex3 = GetSpellInfo(name .. "(" .. rank .. ")")
      if tex3 then return tex3 end
    end
  end
  return wt.GetBestIconFor and wt.GetBestIconFor(name, rank) or nil
end

local function toint(v) return (v == 1 or v == true) and 1 or 0 end

local function GetTrainerSelectionIndexCompat()
  if type(GetTrainerSelectionIndex) == "function" then return GetTrainerSelectionIndex() end
  if type(GetTrainerSelection) == "function" then return GetTrainerSelection() end
  return nil
end
local function SetTrainerSelectionCompat(i)
  if type(SetTrainerSelection) == "function" and i then
    pcall(SetTrainerSelection, i)
  end
end
local function GetTrainerScrollFrame()
  return _G.ClassTrainerListScrollFrame or _G.TrainerFrameScrollFrame
end
local function SaveTrainerUIState()
  local sel = GetTrainerSelectionIndexCompat()
  local sf = GetTrainerScrollFrame()
  local off = sf and FauxScrollFrame_GetOffset(sf) or nil
  return sel, off
end
local function RefreshTrainerFrame()
  if type(ClassTrainerFrame_Update) == "function" then
    ClassTrainerFrame_Update()
  elseif type(TrainerFrame_Update) == "function" then
    TrainerFrame_Update()
  end
end

local function RestoreTrainerUIState(sel, off)
  applyingFilters = true
  SetTrainerSelectionCompat(sel)
  local sf = GetTrainerScrollFrame()
  if sf and off then
    FauxScrollFrame_SetOffset(sf, off)
  end
  RefreshTrainerFrame()
  applyingFilters = false
end

local function ReadFilterState()
  local avail, unavl, used = 1, 1, 0
  if GetTrainerServiceTypeFilter then
    avail = toint(GetTrainerServiceTypeFilter("available"))
    unavl = toint(GetTrainerServiceTypeFilter("unavailable"))
    used  = toint(GetTrainerServiceTypeFilter("used"))
  end
  -- Checkboxes are the visible player state on this client.
  if ClassTrainerAvailableButton then avail = toint(ClassTrainerAvailableButton:GetChecked()) end
  if ClassTrainerUnavailableButton then unavl = toint(ClassTrainerUnavailableButton:GetChecked()) end
  if ClassTrainerUsedButton then used = toint(ClassTrainerUsedButton:GetChecked()) end
  return avail, unavl, used
end

local function ApplyServiceFilters(avail, unavl, used)
  applyingFilters = true
  if SetTrainerServiceTypeFilter then
    SetTrainerServiceTypeFilter("available", avail)
    SetTrainerServiceTypeFilter("unavailable", unavl)
    SetTrainerServiceTypeFilter("used", used)
  end
  if ClassTrainerAvailableButton then ClassTrainerAvailableButton:SetChecked(avail == 1 and 1 or nil) end
  if ClassTrainerUnavailableButton then ClassTrainerUnavailableButton:SetChecked(unavl == 1 and 1 or nil) end
  if ClassTrainerUsedButton then ClassTrainerUsedButton:SetChecked(used == 1 and 1 or nil) end
  applyingFilters = false
end

local function IsProfessionTrainer()
  if not IsTradeskillTrainer then return false end
  local ok = IsTradeskillTrainer()
  return ok == true or ok == 1
end

-- Riding-related spells to exclude (IDs are stable across locales)
local RIDING_SPELL_IDS = {
  [33388] = true, -- Apprentice Riding
  [33391] = true, -- Journeyman Riding
  [34090] = true, -- Expert Riding
  [34091] = true, -- Artisan Riding
  [54197] = true, -- Cold Weather Flying
  -- Some private servers/Cata+ backports might expose these:
  [90265] = true, -- Master Riding
  [90267] = true, -- Flight Master's License
}

local function IsRidingService(name, spellID)
  if spellID and RIDING_SPELL_IDS[spellID] then return true end
  -- Conservative English-only fallback if we couldn't resolve an ID
  if not spellID and type(name) == "string" then
    local n = string.lower(name)
    if n:find("riding") or n:find("flying") or n:find("cold weather") then
      return true
    end
  end
  return false
end

local function CollectTrainerEntries()
  local results = {}
  local n = (GetNumTrainerServices and GetNumTrainerServices()) or 0
  dprint("Scanning trainer (one-time), services:", n)
  for i = 1, n do
    local name, rank, serviceType = GetTrainerServiceInfo(i)
    if name and name ~= "" and serviceType ~= "header" then
        local id, description = ResolveSpellIDAndDescription(i, name, rank)
      if IsRidingService(name, id) then
        dprint("Filtered riding service:", name, id or "nil")
      else
        local reqLevel = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 0
        local moneyCost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0

        local abilityReqs = {}
        local numReqs = GetTrainerServiceNumAbilityReq and (GetTrainerServiceNumAbilityReq(i) or 0) or 0
        for r = 1, numReqs do
          if GetTrainerServiceAbilityReq then
            local ability, has = GetTrainerServiceAbilityReq(i, r)
            abilityReqs[#abilityReqs + 1] = { ability = ability, has = has and true or false }
          end
        end

        results[#results + 1] = {
          id = id,
          name = name,
          rank = rank,
          description = description,
          requiredLevel = reqLevel,
          cost = moneyCost,
          abilityReqs = abilityReqs,
          trainerState = serviceType,
          icon = (ResolveIcon and ResolveIcon(name, rank, i, id)) or nil,
        }
      end
    end
  end
  dprint("Scan complete, rows:", #results)
  if tip then
    tip:Hide()
  end
  return results
end

local function StoreScan(entries)
  if wt.DB_StoreScan then wt.DB_StoreScan(entries) end
  if type(wt.RebuildData) == "function" then
    wt.RebuildData()
    if wt.MainFrame and wt.MainFrame:IsVisible() and type(wt.Update) == "function" then
      wt.Update(wt.MainFrame, true)
    end
  end
end

-- phase: idle, waitopen, flip, restore
local scan = { phase = "idle", avail = 1, unavl = 1, used = 0, sel = nil, off = nil }

local wait = CreateFrame("Frame")
wait:Hide()
local waitLeft, waitFn = 0, nil
wait:SetScript("OnUpdate", function(self, elapsed)
  waitLeft = waitLeft - elapsed
  if waitLeft > 0 then return end
  self:Hide()
  local fn = waitFn
  waitFn = nil
  if fn then fn() end
end)

local function CancelWait()
  wait:Hide()
  waitFn = nil
end

local function AfterTrainerSettles(sec, fn)
  waitLeft, waitFn = sec or 0.25, fn
  wait:Show()
end

local function RestoreSavedFilters()
  dprint("Restoring trainer filters:", scan.avail, scan.unavl, scan.used)
  ApplyServiceFilters(scan.avail, scan.unavl, scan.used)
  RestoreTrainerUIState(scan.sel, scan.off)
end

local function FinishAndRestore()
  if scan.phase ~= "flip" and scan.phase ~= "waitopen" then return end
  local ok, entries = pcall(CollectTrainerEntries)
  if tip then
    tip:Hide()
  end
  wt._trainerScannedThisSession = true
  if ok then
    StoreScan(entries)
  else
    dprint("Scan failed:", entries)
  end
  scan.phase = "restore"
  RestoreSavedFilters()
  AfterTrainerSettles(0.3, function()
    if scan.phase ~= "restore" then return end
    scan.phase = "idle"
  end)
end

local function BeginScan()
  if not wt._trainerOpen or wt._trainerScannedThisSession then return end
  if scan.phase ~= "idle" and scan.phase ~= "waitopen" then return end
  if IsProfessionTrainer() then
    dprint("Skipping profession trainer scan (profession trainer detected).")
    wt._trainerScannedThisSession = true
    scan.phase = "idle"
    StoreScan({})
    return
  end

  scan.avail, scan.unavl, scan.used = ReadFilterState()
  scan.sel, scan.off = SaveTrainerUIState()
  dprint("Saved trainer filters:", scan.avail, scan.unavl, scan.used)

  if scan.avail == 1 and scan.unavl == 1 and scan.used == 1 then
    scan.phase = "flip"
    FinishAndRestore()
    return
  end

  -- Show Available + Unavailable + Already Known so the scan sees every rank.
  -- Do not scan on the TRAINER_UPDATE this filter flip causes; wait a tick so
  -- the list is complete, then restore the player's filters once.
  scan.phase = "flip"
  ApplyServiceFilters(1, 1, 1)
  AfterTrainerSettles(0.25, FinishAndRestore)
end

function wt.ScanTrainerOnceNow()
  wt._trainerScannedThisSession = false
  scan.phase = "waitopen"
  BeginScan()
end

wt._trainerOpen = wt._trainerOpen or false
wt._trainerScannedThisSession = wt._trainerScannedThisSession or false

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("TRAINER_SHOW")
f:RegisterEvent("TRAINER_UPDATE")
f:RegisterEvent("TRAINER_CLOSED")
f:SetScript("OnEvent", function(_, event)
  dprint("Event:", event)
  if applyingFilters then
    return
  end
  if event == "TRAINER_SHOW" then
    CancelWait()
    wt._trainerOpen = true
    wt._trainerScannedThisSession = false
    scan.phase = "waitopen"
    AfterTrainerSettles(0.35, BeginScan)
  elseif event == "TRAINER_UPDATE" then
    -- flip: wait for AfterTrainerSettles; scanning on this event races an incomplete list
    -- and RestoreSavedFilters used to run here every update, which re-fired TRAINER_UPDATE.
    if scan.phase == "restore" then
      return
    elseif wt._trainerOpen and not wt._trainerScannedThisSession and scan.phase == "waitopen" then
      AfterTrainerSettles(0.25, BeginScan)
    end
  elseif event == "TRAINER_CLOSED" then
    CancelWait()
    if scan.phase == "flip" or scan.phase == "restore" then
      RestoreSavedFilters()
    end
    wt._trainerOpen = false
    wt._trainerScannedThisSession = false
    scan.phase = "idle"
  end
end)
