-- The Campfire Dad Jokes window: a Campfire tab with one big button (Tell a joke, then Punch
-- line!) and a My jokes tab to add, edit, delete and restore jokes, plus a minimap button and a
-- compact view (just the one button, movable). The buttons call ns.tell() from their own click,
-- the hardware event /say needs.
local _, ns = ...
local W = ns.Widgets

local ui = {}
ns.ui = ui
-- The editor's selection lives here, not on frames: the joke being edited (a position) or nil
-- for a new joke.
local editor = { selected = nil }

local win = W.window({ name = 'DadJokesFrame', title = 'Campfire Dad Jokes', width = 460, height = 380 })
ui.window = win
ui.tabs = W.tabs(win, { 'Campfire', 'My jokes' }, function() if ui.refresh then ui.refresh() end end)

-- Campfire tab -----------------------------------------------------------------------------------

local camp = ui.tabs.pages[1]

local hint = camp:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
hint:SetPoint('TOP', 0, -4)
hint:SetText('Gather everyone round. Click once for the setup, again for the punch line.')

local tellButton = CreateFrame('Button', 'DadJokesTellButton', camp, 'UIPanelButtonTemplate')
tellButton:SetSize(220, 60)
tellButton:SetPoint('CENTER', 0, 30)
tellButton:SetScript('OnClick', function() ns.tell() end)
ui.tellButton = tellButton

local setupText = camp:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
setupText:SetPoint('TOP', tellButton, 'BOTTOM', 0, -16)
setupText:SetPoint('LEFT', camp, 'LEFT', 10, 0)
setupText:SetPoint('RIGHT', camp, 'RIGHT', -10, 0)
setupText:SetJustifyH('CENTER')
ui.setupText = setupText

local skipButton = CreateFrame('Button', nil, camp, 'UIPanelButtonTemplate')
skipButton:SetSize(80, 22)
skipButton:SetPoint('BOTTOM', 0, 4)
skipButton:SetText('Skip')
skipButton:SetScript('OnClick', function() ns.skip() end)
ui.skipButton = skipButton

-- Says the download link in /say, from its own click (a hardware event, which /say needs).
local shareButton = CreateFrame('Button', nil, camp, 'UIPanelButtonTemplate')
shareButton:SetSize(140, 22)
shareButton:SetPoint('BOTTOMLEFT', 0, 4)
shareButton:SetText('Share addon link')
shareButton:SetScript('OnClick', function() ns.share() end)
ui.shareButton = shareButton

local compactButton = CreateFrame('Button', nil, camp, 'UIPanelButtonTemplate')
compactButton:SetSize(110, 22)
compactButton:SetPoint('BOTTOMRIGHT', 0, 4)
compactButton:SetText('Compact view')
compactButton:SetScript('OnClick', function()
  win:Hide()
  ui.showMini(true)
end)
ui.compactButton = compactButton

-- Auto-tell: jokes keep coming on their own, as speech-style emotes, until stopped.
local function toggleAuto()
  if ns.autoRunning() then ns.stopAuto() else ns.startAuto() end
end

local autoButton = CreateFrame('Button', nil, camp, 'UIPanelButtonTemplate')
autoButton:SetSize(130, 22)
autoButton:SetPoint('BOTTOM', 0, 30)
autoButton:SetScript('OnClick', toggleAuto)
ui.autoButton = autoButton

-- Auto-tell pauses, in seconds: before the punch line, and before the next joke. A value is saved
-- on Enter or when the box loses focus; one out of range is refused and the box shows the current one.
local function paceBox(label, key, x)
  local l = camp:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
  l:SetPoint('BOTTOMLEFT', x, 62)
  l:SetText(label)
  local b = CreateFrame('EditBox', nil, camp, 'InputBoxTemplate')
  b:SetSize(36, 20)
  b:SetPoint('LEFT', l, 'RIGHT', 8, 0)
  b:SetAutoFocus(false)
  b:SetMaxLetters(4)
  local unit = camp:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
  unit:SetPoint('LEFT', b, 'RIGHT', 2, 0)
  unit:SetText('s')
  local function save(self)
    local n = tonumber(self:GetText())
    local ok, why
    if n then
      ok, why = ns.setPace(key == 'punch' and n or nil, key == 'next' and n or nil)
    else
      ok, why = false, ns.PACE_RANGE_MESSAGE
    end
    if not ok then ns.print(why) end
    self:SetText(tostring(ns.pace()[key]))
  end
  b:SetScript('OnEnterPressed', function(self) save(self); self:ClearFocus() end)
  b:SetScript('OnEditFocusLost', save)
  b:SetScript('OnEscapePressed', function(self)
    self:SetText(tostring(ns.pace()[key]))
    self:ClearFocus()
  end)
  return b
end
ui.punchDelayBox = paceBox('Punch line after', 'punch', 70)
ui.nextDelayBox = paceBox('Next joke after', 'next', 250)

-- Compact view ----------------------------------------------------------------------------------
-- Just the tell button in a small frame you drag anywhere. Its position and whether it is open
-- are kept in DadJokesDB.mini. Right-click opens the full window.

local mini = CreateFrame('Frame', 'DadJokesMiniFrame', UIParent, 'BackdropTemplate')
mini:SetSize(256, 56)
mini:SetPoint('CENTER', UIParent, 'CENTER', 0, -200)
mini:SetFrameStrata('MEDIUM')
if mini.SetBackdrop then
  mini:SetBackdrop({
    bgFile = 'Interface\\DialogFrame\\UI-DialogBox-Background',
    edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
end
mini:SetMovable(true)
mini:SetClampedToScreen(true)
mini:EnableMouse(true)
mini:RegisterForDrag('LeftButton')
mini:Hide()
ui.mini = mini

local function savePosition()
  local point, _, relativePoint, x, y = mini:GetPoint()
  if point and DadJokesDB then
    DadJokesDB.mini = DadJokesDB.mini or {}
    DadJokesDB.mini.point, DadJokesDB.mini.relativePoint, DadJokesDB.mini.x, DadJokesDB.mini.y = point, relativePoint, x, y
  end
end
mini:SetScript('OnDragStart', function(self) self:StartMoving() end)
mini:SetScript('OnDragStop', function(self)
  self:StopMovingOrSizing()
  savePosition()
end)

local miniButton = CreateFrame('Button', 'DadJokesMiniButton', mini, 'UIPanelButtonTemplate')
miniButton:SetSize(164, 40)
miniButton:SetPoint('LEFT', 8, 0)
miniButton:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
-- Dragging the button moves the frame too, so the whole thing is easy to grab.
miniButton:RegisterForDrag('LeftButton')
miniButton:SetScript('OnDragStart', function() mini:StartMoving() end)
miniButton:SetScript('OnDragStop', function()
  mini:StopMovingOrSizing()
  savePosition()
end)
miniButton:SetScript('OnClick', function(_, button)
  if button == 'RightButton' then ui.open(1) else ns.tell() end
end)
miniButton:SetScript('OnEnter', function(self)
  GameTooltip:SetOwner(self, 'ANCHOR_TOP')
  GameTooltip:AddLine('Campfire Dad Jokes')
  GameTooltip:AddLine(W.color('muted', 'Click: setup, then punch line. Auto: keep telling jokes. Right-click: full window. Drag to move.'))
  GameTooltip:Show()
end)
miniButton:SetScript('OnLeave', function() GameTooltip:Hide() end)
ui.miniButton = miniButton

local miniAutoButton = CreateFrame('Button', nil, mini, 'UIPanelButtonTemplate')
miniAutoButton:SetSize(52, 40)
miniAutoButton:SetPoint('LEFT', miniButton, 'RIGHT', 4, 0)
miniAutoButton:SetScript('OnClick', toggleAuto)
ui.miniAutoButton = miniAutoButton

local miniClose = CreateFrame('Button', nil, mini, 'UIPanelCloseButton')
miniClose:SetSize(24, 24)
miniClose:SetPoint('TOPRIGHT', 2, 2)
miniClose:SetScript('OnClick', function() ui.showMini(false) end)
mini.close = miniClose

-- Show or hide the compact view, and remember which for the next login.
function ui.showMini(show)
  if DadJokesDB then
    DadJokesDB.mini = DadJokesDB.mini or {}
    DadJokesDB.mini.shown = show and true or false
  end
  if show then
    mini:Show()
    ui.refresh()
  else
    mini:Hide()
  end
end

-- My jokes tab -----------------------------------------------------------------------------------

local mine = ui.tabs.pages[2]

local listArea = CreateFrame('Frame', nil, mine)
listArea:SetPoint('TOPLEFT', 0, 0)
listArea:SetPoint('RIGHT', mine, 'RIGHT', 0, 0)
listArea:SetHeight(150)

local function loadEditor()
  local j = editor.selected and DadJokesDB.jokes[editor.selected]
  ui.setupBox:SetText(j and j.setup or '')
  ui.punchBox:SetText(j and j.punch or '')
end

ui.list = W.pagedList(listArea, {
  rows = 7,
  rowHeight = 18,
  render = function(row, j, index)
    row.text:SetText((index == editor.selected and '> ' or '  ') .. j.setup)
  end,
  onClick = function(j)
    for i, x in ipairs(DadJokesDB.jokes) do
      if x == j then editor.selected = i end
    end
    ui.editorMessage:SetText('')
    loadEditor()
    ui.refresh()
  end,
})

local function box(label, y)
  local l = mine:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
  l:SetPoint('TOPLEFT', 0, y)
  l:SetText(label)
  local b = CreateFrame('EditBox', nil, mine, 'InputBoxTemplate')
  b:SetSize(330, 20)
  b:SetPoint('TOPLEFT', 80, y + 4)
  b:SetAutoFocus(false)
  -- One chat line is 255 bytes; capping bytes (not letters) matches the validation exactly.
  b:SetMaxBytes(ns.MAX_BYTES)
  b:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
  return b
end
ui.setupBox = box('Setup', -186)
ui.punchBox = box('Punch line', -212)

local function button(label, x, onClick)
  local b = CreateFrame('Button', nil, mine, 'UIPanelButtonTemplate')
  b:SetSize(80, 22)
  b:SetPoint('TOPLEFT', x, -240)
  b:SetText(label)
  b:SetScript('OnClick', onClick)
  return b
end

ui.newButton = button('New', 0, function()
  editor.selected = nil
  ui.editorMessage:SetText('')
  loadEditor()
  ui.refresh()
end)

ui.saveButton = button('Save', 84, function()
  local ok, why
  if editor.selected then
    ok, why = ns.editJoke(editor.selected, ui.setupBox:GetText(), ui.punchBox:GetText())
  else
    ok, why = ns.addJoke(ui.setupBox:GetText(), ui.punchBox:GetText())
    if ok then editor.selected = #DadJokesDB.jokes end
  end
  ui.editorMessage:SetText(ok and W.color('win', 'Saved.') or W.color('system', ns.REASONS[why] or why))
  ui.refresh()
end)

ui.deleteButton = button('Delete', 168, function()
  if editor.selected and ns.deleteJoke(editor.selected) then
    editor.selected = nil
    loadEditor()
    ui.editorMessage:SetText('Deleted.')
  end
  ui.refresh()
end)

ui.restoreButton = CreateFrame('Button', nil, mine, 'UIPanelButtonTemplate')
ui.restoreButton:SetSize(150, 22)
ui.restoreButton:SetPoint('TOPRIGHT', mine, 'TOPRIGHT', 0, -240)
ui.restoreButton:SetText('Restore starter jokes')
ui.restoreButton:SetScript('OnClick', function()
  local n = ns.restoreStarters()
  ui.editorMessage:SetText(n > 0 and (n .. ' starter jokes restored.') or 'All starter jokes are already in your list.')
  ui.refresh()
end)

local editorMessage = mine:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
editorMessage:SetPoint('TOPLEFT', 0, -268)
editorMessage:SetPoint('RIGHT', mine, 'RIGHT', 0, 0)
editorMessage:SetJustifyH('LEFT')
ui.editorMessage = editorMessage

-- Refresh and open -------------------------------------------------------------------------------

function ui.refresh()
  if not DadJokesDB then return end
  local asked = ns.tellerState() == 'asked'
  local auto = ns.autoRunning()
  -- While auto-tell runs, a click on the big buttons stops it (ns.tell does that).
  tellButton:SetText(auto and 'Stop' or asked and 'Punch line!' or 'Tell a joke')
  tellButton:SetEnabled(auto or asked or #DadJokesDB.jokes > 0)
  miniButton:SetText(tellButton:GetText())
  miniButton:SetEnabled(tellButton:IsEnabled())
  autoButton:SetText(auto and 'Stop auto-tell' or 'Auto-tell')
  autoButton:SetEnabled(auto or #DadJokesDB.jokes > 0)
  miniAutoButton:SetText(auto and 'Stop' or 'Auto')
  miniAutoButton:SetEnabled(autoButton:IsEnabled())
  local pace = ns.pace()
  -- Leave a box alone while the player is typing in it (auto-tell refreshes every line).
  if not ui.punchDelayBox:HasFocus() then ui.punchDelayBox:SetText(tostring(pace.punch)) end
  if not ui.nextDelayBox:HasFocus() then ui.nextDelayBox:SetText(tostring(pace.next)) end
  local j = ns.currentJoke()
  setupText:SetText(asked and j and j.setup or (#DadJokesDB.jokes == 0 and 'Add a joke on My jokes first.' or ''))
  skipButton:SetEnabled(asked)
  ui.list:setItems(DadJokesDB.jokes)
  ui.deleteButton:SetEnabled(editor.selected ~= nil)
end

function ui.open(tab)
  win:Show()
  if tab then ui.tabs.select(tab) end
  ui.refresh()
end

function ui.toggle()
  if win:IsShown() then win:Hide() else ui.open() end
end

win:SetScript('OnShow', function() ui.refresh() end)

-- The minimap button keeps its angle in DadJokesDB, so it is made once that is loaded.
ns.on('ADDON_LOADED', function(name)
  if name ~= 'DadJokes' or ui.minimap then return end
  ui.minimap = W.minimapButton({
    name = 'DadJokesMinimapButton',
    db = DadJokesDB,
    icon = 'Interface\\Icons\\Spell_Fire_Fire',
    onClick = ui.toggle,
    tooltip = {},
  })
  local saved = DadJokesDB.mini
  if type(saved) == 'table' then
    if saved.point and saved.relativePoint and tonumber(saved.x) and tonumber(saved.y) then
      mini:ClearAllPoints()
      mini:SetPoint(saved.point, UIParent, saved.relativePoint, tonumber(saved.x), tonumber(saved.y))
    end
    if saved.shown then mini:Show() end
  end
  ui.minimap:SetScript('OnEnter', function(self)
    GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
    GameTooltip:AddLine('Campfire Dad Jokes')
    GameTooltip:AddLine(#DadJokesDB.jokes .. ' jokes in your list')
    GameTooltip:AddLine(W.color('muted', 'Click to open. Drag to move.'))
    GameTooltip:Show()
  end)
  ui.refresh()
end)
