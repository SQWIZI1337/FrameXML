-- TalentImporter (FrameXML встроенная версия) для WoW 3.3.5a
-- Грузится через TalentImporter.xml (Script file="TalentImporter.lua")
-- Основано на TalentImporter 1.4g (рабочая версия)

local TI = {}
_G.TalentImporter = TI

-- ======================
-- CLASS ID (твоя схема)
-- ======================
TI.ClassIdToClassFile = {
  [1]  = "WARRIOR",
  [2]  = "PALADIN",
  [3]  = "HUNTER",
  [4]  = "ROGUE",
  [5]  = "PRIEST",
  [6]  = "DEATHKNIGHT",
  [7]  = "SHAMAN",
  [8]  = "MAGE",
  [9]  = "WARLOCK",
  [11] = "DRUID",
}

-- ======================
-- UI helpers (3.3.5)
-- ======================
local function ApplyBackdrop(frame)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
end

local function SetStatus(self, msg, ok)
  if not self.Frame or not self.Frame.Status then return end
  self.Frame.Status:SetText((ok and "|cff00ff00" or "|cffff3333") .. msg .. "|r")
end

function TI:TotalRemaining(queue)
  local n = 0
  for _, q in ipairs(queue or {}) do
    n = n + (q.need or 0)
  end
  return n
end


-- ======================
-- Кнопка-иконка в шапке окна талантов
-- ======================
local function CreateImportButton()
  if not PlayerTalentFrame or PlayerTalentFrame.TI_ImportButton then return end

  local btn = CreateFrame("Button", nil, PlayerTalentFrame)
  PlayerTalentFrame.TI_ImportButton = btn
  btn:SetSize(18, 18)
  btn:SetPoint("RIGHT", PlayerTalentFrameCloseButton, "LEFT", -6, 0)

  btn.Icon = btn:CreateTexture(nil, "ARTWORK")
  btn.Icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
  btn.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  btn.Icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
  btn.Icon:SetSize(16, 16)

  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Импорт талантов")
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  btn:SetScript("OnClick", function()
    TI:ShowImportWindow()
  end)

  -- Закрываем импорт, когда закрывают окно талантов
  PlayerTalentFrame:HookScript("OnHide", function()
    if TI.Frame then TI.Frame:Hide() end
    TI._queue = nil
    if TI._worker then TI._worker:Hide() end
  end)
end

-- ======================
-- Окно импорта (не двигается, рядом с TalentFrame)
-- ======================
function TI:ShowImportWindow()
  if self.Frame then
    if self.Frame:IsShown() then
      self.Frame:Hide()
      return
    end
    self.Frame:Show()
    self.Frame.EditBox:SetFocus()
    self.Frame.EditBox:HighlightText()
    return
  end

  local f = CreateFrame("Frame", "TI_ImportFrame", UIParent)
  self.Frame = f
  f:SetSize(400, 150)
  f:SetFrameStrata("DIALOG")
  f:EnableMouse(true)

  if PlayerTalentFrame then
    f:SetPoint("TOPLEFT", PlayerTalentFrame, "TOPRIGHT", 10, -60)
  else
    f:SetPoint("CENTER")
  end

  ApplyBackdrop(f)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", f, "TOP", 0, -14)
  title:SetText("Импорт талантов")

  local closeX = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  closeX:SetPoint("TOPRIGHT", -6, -6)

  local hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 18, -44)
  hint:SetText("Формат: 2-1435:1,1627:1,1748:1,2185:2")

  local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  f.EditBox = eb
  eb:SetSize(365, 20)
  eb:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
  eb:SetAutoFocus(true)
  eb:SetScript("OnEscapePressed", function() f:Hide() end)

  local applyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  applyBtn:SetSize(120, 22)
  applyBtn:SetPoint("BOTTOM", f, "BOTTOM", -60, 22)
  applyBtn:SetText("Применить")

  local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  closeBtn:SetSize(120, 22)
  closeBtn:SetPoint("BOTTOM", f, "BOTTOM", 60, 22)
  closeBtn:SetText("Закрыть")
  closeBtn:SetScript("OnClick", function() f:Hide() end)

  local status = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  f.Status = status
  status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 50)
  status:SetWidth(360)
  status:SetJustifyH("LEFT")
  status:SetText("")

  applyBtn:SetScript("OnClick", function()
    local ok, err = TI:ImportString(eb:GetText())
    if not ok then
      SetStatus(TI, "Ошибка: " .. (err or "неизвестно"), false)
    end
  end)

  f:Show()
  eb:SetFocus()
  eb:HighlightText()
end

-- ======================
-- Поиск таланта по TalentID (Talent.dbc ID из твоего CSV)
-- ======================
function TI:FindTalentPos(talentID)
  for tab = 1, 3 do
    local n = GetNumTalents(tab) or 0
    for index = 1, n do
      local link = GetTalentLink(tab, index)
      if link then
        local id = tonumber(link:match("Htalent:(%d+):"))
        if id == talentID then
          return tab, index
        end
      end
    end
  end
end

-- ======================
-- Парсер строки
-- ======================
local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function TI:Parse(str)
  str = trim(str)
  if str == "" then return nil, "пустая строка" end

  local classIdStr, body = str:match("^(%d+)%-(.+)$")
  if not classIdStr or not body then
    return nil, "ожидается формат classId-список"
  end

  local classId = tonumber(classIdStr)
  if not classId then return nil, "неверный classId" end

  local result = { classId = classId, list = {} }

  for token in body:gmatch("[^,]+") do
    token = trim(token)
    local idStr, ptsStr = token:match("^(%d+)%s*:%s*(%d+)$")
    if not idStr then
      return nil, "неверный элемент: " .. token
    end
    local id = tonumber(idStr)
    local pts = tonumber(ptsStr)
    if not id or not pts or pts < 0 then
      return nil, "неверные числа: " .. token
    end
    table.insert(result.list, { id = id, pts = pts })
  end

  return result
end

-- ======================
-- Умный импорт: сортировка по tier/column + round-robin по 1 очку
-- ======================

function TI:ImportString(str)
  if not PlayerTalentFrame then
    ToggleTalentFrame()
  end

  local data, perr = self:Parse(str)
  if not data then return false, perr end

  local _, playerClass = UnitClass("player")
  local expected = self.ClassIdToClassFile[data.classId]
  if expected and expected ~= playerClass then
    return false, "строка не для твоего класса"
  end

  local plan = {}
  local totalWanted = 0

  for _, t in ipairs(data.list) do
    local tab, index = self:FindTalentPos(t.id)
    if not tab then
      return false, "TalentID " .. t.id .. " не найден"
    end

    local _, _, tier, column = GetTalentInfo(tab, index)
    tier = tonumber(tier) or 0
    column = tonumber(column) or 0

    table.insert(plan, {
      id = t.id,
      tab = tab,
      index = index,
      tier = tier,
      column = column,
      desired = t.pts,
      need = 0,      -- посчитаем ниже из текущего rank
      lastRank = 0,
    })
    totalWanted = totalWanted + (t.pts or 0)
  end

  local unspent = UnitCharacterPoints("player") or 0
table.sort(plan, function(a, b)
    if a.tab ~= b.tab then return a.tab < b.tab end
    if a.tier ~= b.tier then return a.tier < b.tier end
    if a.column ~= b.column then return a.column < b.column end
    return a.id < b.id
  end)

  -- Стартуем асинхронный импорт

-- Приводим "need" к ДОКИДЫВАНИЮ: если в таланте уже есть очки, не пытаемся вложить заново
for _, p in ipairs(plan) do
  local _, _, _, _, rank, maxRank = GetTalentInfo(p.tab, p.index)
  rank = tonumber(rank) or 0
  maxRank = tonumber(maxRank) or 0
  p.lastRank = rank
  local desired = tonumber(p.desired) or 0
  if desired > maxRank then desired = maxRank end
  p.desired = desired
  p.need = math.max(0, desired - rank)
end

-- Удалим уже выполненные записи
for i = #plan, 1, -1 do
  if (plan[i].need or 0) <= 0 then
    table.remove(plan, i)
  end
end

if #plan == 0 then
  return true
end

  self:EnsureWorker()
  TI._queue = plan
  TI._cursor = 1
  TI._lastProgress = GetTime()
  SetStatus(TI, ("Осталось: %d"):format(self:TotalRemaining(plan)), true)
  self._worker:Show()

  return true
end

-- ======================
-- Хук на загрузку TalentUI
-- ======================

-- ======================
-- Async worker для стабильного докидывания рангов (3.3.5 клиент обновляет rank не мгновенно)
-- ======================
TI._queue = nil
TI._cursor = 1
TI._worker = nil
TI._lastProgress = 0

function TI:EnsureWorker()
  if self._worker then return end
  local w = CreateFrame("Frame", "TI_WorkerFrame", UIParent)
  self._worker = w
  w:Hide()

  local elapsed = 0
  w:SetScript("OnUpdate", function(_, dt)
    if not self._queue then
      w:Hide()
      return
    end

    elapsed = elapsed + dt
    if elapsed < 0.05 then return end
    elapsed = 0

    local queue = self._queue

-- Реконсиляция: иногда rank обновляется НЕ в тот же тик, поэтому фиксируем прогресс по факту изменения rank
local anyProgress = false
for i = #queue, 1, -1 do
  local q = queue[i]
  local rank = select(5, GetTalentInfo(q.tab, q.index))
  rank = tonumber(rank) or 0
  q.lastRank = tonumber(q.lastRank) or 0
  if rank > q.lastRank then
    local delta = rank - q.lastRank
    q.lastRank = rank
    q.need = math.max(0, (q.need or 0) - delta)
    anyProgress = true
  end
  if (q.need or 0) <= 0 then
    table.remove(queue, i)
    if self._cursor > #queue then self._cursor = 1 end
    anyProgress = true
  end
end
if anyProgress then
  self._lastProgress = GetTime()
  if #queue == 0 then
    SetStatus(self, "Готово", true)
    self._queue = nil
    w:Hide()
    return
  end
  SetStatus(self, ("Осталось: %d"):format(self:TotalRemaining(queue)), true)
end

    if #queue == 0 then
      SetStatus(self, "Готово", true)
      self._queue = nil
      w:Hide()
      return
    end

    -- Если долго нет прогресса — значит упёрлись в тиры/пререквизиты/очков нет
    if GetTime() - (self._lastProgress or 0) > 6 then
      SetStatus(self, "Ошибка: не удалось распределить все очки (тиры/пререквизиты/порядок)", false)
      self._queue = nil
      w:Hide()
      return
    end

    -- Round-robin: выбираем следующую подходящую запись
    local tries = #queue
    local chosenIndex = nil

    while tries > 0 do
      if self._cursor > #queue then self._cursor = 1 end
      local q = queue[self._cursor]
      if q and (q.need or 0) > 0 then
        -- Проверим, можно ли сейчас вложить
        local _, _, _, _, rank, maxRank, _, meetsPrereq = GetTalentInfo(q.tab, q.index)
        if rank and maxRank and rank < maxRank and meetsPrereq then
          chosenIndex = self._cursor
          break
        end
      end
      self._cursor = self._cursor + 1
      tries = tries - 1
    end

    if not chosenIndex then
      -- Сейчас ни один не доступен (ждём, может откроется после вложения в другой, но прогресса нет → сработает таймаут)
      return
    end

    local q = queue[chosenIndex]
    local before = select(5, GetTalentInfo(q.tab, q.index))
    LearnTalent(q.tab, q.index)

    -- В 3.3.5 rank может обновиться на следующий кадр, поэтому проверим сейчас и в следующем тике.
    local after = select(5, GetTalentInfo(q.tab, q.index))

    if after and before and after > before then
      local delta = after - before
      q.lastRank = after
      q.need = math.max(0, (q.need or 0) - delta)
      self._lastProgress = GetTime()
      SetStatus(self, ("Осталось: %d"):format(self:TotalRemaining(queue)), true)
      if (q.need or 0) <= 0 then
        table.remove(queue, chosenIndex)
        if self._cursor > #queue then self._cursor = 1 end
      else
        self._cursor = chosenIndex + 1
      end
    else
      -- Не получилось сейчас — пробуем следующий талант на следующем тике
      self._cursor = chosenIndex + 1
    end
  end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, addon)
  if event == "ADDON_LOADED" and addon == "Blizzard_TalentUI" then
    CreateImportButton()
  elseif event == "PLAYER_LOGIN" then
    if IsAddOnLoaded("Blizzard_TalentUI") then
      CreateImportButton()
    end
  end
end)
