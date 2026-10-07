-- Gamba Forever widget kit: the stone-and-gold window, tab bar, paged list, minimap button and
-- colors both addons build their windows from (design: Gamba Forever Addon). Loaded after
-- Protocol.lua into each addon's own namespace, so the two addons never share state.
-- Runs on the client's Lua 5.1 and the harness's Lua 5.4: no //, bitwise operators or goto.
-- Only long-standing widget APIs are used (no ScrollBox or DataProvider): lists page instead of scroll.
local _, ns = ...
local W = {}
ns.Widgets = W

-- Chat and text colors (design: chat colors). Close every colored run with |r.
W.colors = {
  system = '|cffff8000',
  whisper = '|cffff80ff',
  confirm = '|cffffff00',
  win = '|cff1eff00',
  muted = '|cff9d9d9d',
  gold = '|cffffd100',
  silver = '|cffc7c7cf',
  copper = '|cffeda55f',
}

function W.color(kind, text)
  return (W.colors[kind] or '') .. tostring(text) .. '|r'
end

local COIN = { g = 'gold', s = 'silver', c = 'copper' }

-- "125g 3c" with each unit letter in its coin color.
function W.money(copper)
  local text = ns.Protocol.formatCopper(copper)
  return (string.gsub(text, '(%d+)([gsc])', function(n, unit) return n .. W.colors[COIN[unit]] .. unit .. '|r' end))
end

local BACKDROP = {
  bgFile = 'Interface\\DialogFrame\\UI-DialogBox-Background-Dark',
  edgeFile = 'Interface\\DialogFrame\\UI-DialogBox-Gold-Border',
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

-- A movable dialog window with a title plaque and a close button, hidden until shown. Escape
-- closes it (UISpecialFrames). Returns the frame; `frame.title` and `frame.close` are its parts.
function W.window(opts)
  local f = CreateFrame('Frame', opts.name, UIParent, 'BackdropTemplate')
  f:SetSize(opts.width or 480, opts.height or 420)
  f:SetPoint('CENTER')
  f:SetFrameStrata('DIALOG')
  if f.SetBackdrop then f:SetBackdrop(BACKDROP) end
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag('LeftButton')
  f:SetScript('OnDragStart', function(self) self:StartMoving() end)
  f:SetScript('OnDragStop', function(self) self:StopMovingOrSizing() end)

  local plaque = f:CreateTexture(nil, 'ARTWORK')
  plaque:SetTexture('Interface\\DialogFrame\\UI-DialogBox-Header')
  plaque:SetSize(300, 64)
  plaque:SetPoint('TOP', 0, 12)
  local title = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
  title:SetPoint('TOP', plaque, 'TOP', 0, -14)
  title:SetText(opts.title or '')
  f.title = title

  local close = CreateFrame('Button', opts.name and (opts.name .. 'Close') or nil, f, 'UIPanelCloseButton')
  close:SetPoint('TOPRIGHT', -4, -4)
  close:SetScript('OnClick', function() f:Hide() end)
  f.close = close

  if opts.name then table.insert(UISpecialFrames, opts.name) end
  f:Hide()
  return f
end

-- A row of tab buttons under the title, each with its own page frame; exactly one page shows.
-- Returns { buttons, pages, selected, select(i) }. `onSelect(i)` runs after each switch.
function W.tabs(win, labels, onSelect)
  local bar = { buttons = {}, pages = {}, selected = nil }
  local x = 16
  for i, label in ipairs(labels) do
    local b = CreateFrame('Button', nil, win, 'UIPanelButtonTemplate')
    b:SetText(label)
    local width = 24 + 7 * #label
    b:SetSize(width, 22)
    b:SetPoint('TOPLEFT', x, -32)
    x = x + width + 4
    b:SetScript('OnClick', function() bar.select(i) end)
    bar.buttons[i] = b

    local page = CreateFrame('Frame', nil, win)
    page:SetPoint('TOPLEFT', 16, -60)
    page:SetPoint('BOTTOMRIGHT', -16, 16)
    bar.pages[i] = page
  end

  function bar.select(i)
    bar.selected = i
    for j, page in ipairs(bar.pages) do
      if j == i then
        page:Show()
        bar.buttons[j]:LockHighlight()
      else
        page:Hide()
        bar.buttons[j]:UnlockHighlight()
      end
    end
    if onSelect then onSelect(i) end
  end

  bar.select(1)
  return bar
end

-- A list of fixed rows with Prev / Next and "Page x of y". `opts.render(row, item, index)`
-- fills a row (each has a `text` FontString); `opts.onClick(item)` runs when a row is clicked.
function W.pagedList(parent, opts)
  local size = opts.rows or 10
  local height = opts.rowHeight or 20
  -- What each row shows is kept here, not on the row frames.
  local list = { rows = {}, items = {}, page = 1, shown = {} }

  for i = 1, size do
    local row = CreateFrame('Button', nil, parent)
    row:SetHeight(height)
    row:SetPoint('TOPLEFT', 0, -(i - 1) * height)
    row:SetPoint('RIGHT', parent, 'RIGHT', 0, 0)
    local text = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    text:SetPoint('LEFT', 4, 0)
    text:SetPoint('RIGHT', -4, 0)
    text:SetJustifyH('LEFT')
    row.text = text
    row:SetScript('OnClick', function()
      if opts.onClick and list.shown[i] ~= nil then opts.onClick(list.shown[i]) end
    end)
    list.rows[i] = row
  end

  local footerY = -size * height - 6
  local prev = CreateFrame('Button', nil, parent, 'UIPanelButtonTemplate')
  prev:SetSize(64, 20)
  prev:SetPoint('TOPLEFT', 0, footerY)
  prev:SetText('Prev')
  prev:SetScript('OnClick', function() list:setPage(list.page - 1) end)
  list.prev = prev

  local nextButton = CreateFrame('Button', nil, parent, 'UIPanelButtonTemplate')
  nextButton:SetSize(64, 20)
  nextButton:SetPoint('TOPRIGHT', parent, 'TOPRIGHT', 0, footerY)
  nextButton:SetText('Next')
  nextButton:SetScript('OnClick', function() list:setPage(list.page + 1) end)
  list.next = nextButton

  local label = parent:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
  label:SetPoint('TOP', parent, 'TOP', 0, footerY - 4)
  list.label = label

  function list:pageCount()
    return math.max(1, math.ceil(#self.items / size))
  end

  function list:setPage(n)
    self.page = math.max(1, math.min(n, self:pageCount()))
    local first = (self.page - 1) * size
    for i, row in ipairs(self.rows) do
      local item = self.items[first + i]
      self.shown[i] = item
      if item ~= nil then
        opts.render(row, item, first + i)
        row:Show()
      else
        row:Hide()
      end
    end
    self.prev:SetEnabled(self.page > 1)
    self.next:SetEnabled(self.page < self:pageCount())
    self.label:SetText(string.format('Page %d of %d', self.page, self:pageCount()))
  end

  -- New items keep the current page when it still exists.
  function list:setItems(items)
    self.items = items or {}
    self:setPage(self.page)
  end

  list:setItems({})
  return list
end

-- A one-line box holding an address the player can select and copy (Ctrl+C / Cmd+C): addons
-- cannot open a browser or touch the clipboard. Typing into it puts the address back.
function W.linkBox(parent, url, width)
  local box = CreateFrame('EditBox', nil, parent, 'InputBoxTemplate')
  box:SetSize(width or 300, 20)
  box:SetAutoFocus(false)
  box:SetText(url)
  box:SetCursorPosition(0)
  box:SetScript('OnEditFocusGained', function(self) self:HighlightText() end)
  box:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
  box:SetScript('OnTextChanged', function(self, userInput)
    if userInput then
      self:SetText(url)
      self:HighlightText()
    end
  end)
  return box
end

local atan2 = math.atan2 or math.atan

-- A round button on the minimap's edge. It shows `opts.tooltip` lines on hover, runs
-- `opts.onClick` on a left click, and can be dragged around the edge; the angle (degrees,
-- 0 = right, 90 = up, whole degrees) is kept in `opts.db.minimapAngle` (a SavedVariables table).
function W.minimapButton(opts)
  local b = CreateFrame('Button', opts.name, Minimap)
  b:SetSize(32, 32)
  b:SetFrameStrata('MEDIUM')
  b:SetFrameLevel(8)
  b:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
  b:RegisterForDrag('LeftButton')
  local icon = b:CreateTexture(nil, 'ARTWORK')
  icon:SetTexture(opts.icon or 'Interface\\Icons\\INV_Misc_Coin_02')
  icon:SetSize(20, 20)
  icon:SetPoint('CENTER')
  local border = b:CreateTexture(nil, 'OVERLAY')
  border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
  border:SetSize(54, 54)
  border:SetPoint('TOPLEFT')

  local function place(angle)
    b.angle = angle
    local radius = Minimap:GetWidth() / 2 + 10
    local rad = math.rad(angle)
    b:ClearAllPoints()
    b:SetPoint('CENTER', Minimap, 'CENTER', math.cos(rad) * radius, math.sin(rad) * radius)
  end

  local function follow()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    -- A whole number of degrees, 0-359: the table may be a synced file the server parses.
    local angle = math.floor(math.deg(atan2(cy / scale - my, cx / scale - mx)) + 0.5) % 360
    opts.db.minimapAngle = angle
    place(angle)
  end

  b:SetScript('OnDragStart', function(self)
    self:SetScript('OnUpdate', follow)
  end)
  b:SetScript('OnDragStop', function(self)
    self:SetScript('OnUpdate', nil)
    follow()
  end)
  b:SetScript('OnEnter', function(self)
    GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
    for _, line in ipairs(opts.tooltip or {}) do GameTooltip:AddLine(line) end
    GameTooltip:Show()
  end)
  b:SetScript('OnLeave', function() GameTooltip:Hide() end)
  b:SetScript('OnClick', function(_, button)
    if button == 'LeftButton' and opts.onClick then opts.onClick() end
    if button == 'RightButton' and opts.onRightClick then opts.onRightClick() end
  end)

  place(tonumber(opts.db.minimapAngle) or 225)
  return b
end
