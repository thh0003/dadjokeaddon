-- Telling a joke takes two clicks: the first says a random joke's setup, the second its punch
-- line. Jokes go out as speech-style emotes ("Bo says: ..."), which reach the same nearby players
-- as /say. Auto-tell runs on timers, and the game only takes addon /say from a click or keypress
-- outside instances, so clicks emote too, to match. During chat lockdown (combat, a match) nothing
-- is sent and the same line waits for the next click.
--
-- Auto-tell: setup, pace().punch seconds, punch line, pace().next seconds, next joke, until stopped.
-- The pauses are player settings (DadJokesDB.pace), set with /joke pace or on the Campfire tab.
local _, ns = ...

ns.DEFAULT_PACE = { punch = 4, next = 3 }
ns.PACE_MIN, ns.PACE_MAX = 0.5, 60

local function validPace(n)
  return type(n) == 'number' and n >= ns.PACE_MIN and n <= ns.PACE_MAX
end

-- The pauses in seconds: { punch = before the punch line, next = before the next joke }.
function ns.pace()
  local p = type(DadJokesDB) == 'table' and type(DadJokesDB.pace) == 'table' and DadJokesDB.pace or {}
  return {
    punch = validPace(p.punch) and p.punch or ns.DEFAULT_PACE.punch,
    next = validPace(p.next) and p.next or ns.DEFAULT_PACE.next,
  }
end

-- Set one or both pauses (nil keeps the current value). Returns true, or false and a reason.
function ns.setPace(punch, nextJoke)
  local cur = ns.pace()
  punch, nextJoke = punch or cur.punch, nextJoke or cur.next
  if not validPace(punch) or not validPace(nextJoke) then
    return false, 'Pauses must be between ' .. ns.PACE_MIN .. ' and ' .. ns.PACE_MAX .. ' seconds.'
  end
  DadJokesDB.pace = { punch = punch, next = nextJoke }
  return true
end

-- `run` numbers each auto-tell start: C_Timer.After cannot be cancelled, so a callback whose run
-- is no longer current does nothing.
local state = { phase = 'idle', joke = nil, pending = nil, auto = false, run = 0 }

function ns.tellerState() return state.phase end
function ns.currentJoke() return state.joke end
function ns.autoRunning() return state.auto end

local function refresh()
  if ns.ui and ns.ui.refresh then ns.ui.refresh() end
end

local EMOTE_PREFIX = 'says: '

local function locked()
  return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

-- A speech-style emote. A line too long for the prefix within one chat line (255 bytes) goes bare.
local function emote(text)
  if #EMOTE_PREFIX + #text <= 255 then text = EMOTE_PREFIX .. text end
  SendChatMessage(text, 'EMOTE')
end

-- Send a line from a click: as a joke emote, or in /say for the share link.
local function send(text, chatType)
  if locked() then
    ns.print('Chat is locked during combat or a match. Click again afterwards.')
    return false
  end
  if chatType == 'SAY' then SendChatMessage(text, 'SAY') else emote(text) end
  return true
end

local function stop(reason)
  state.auto, state.run = false, state.run + 1
  state.phase, state.joke, state.pending = 'idle', nil, nil
  if reason then ns.print(reason) end
  refresh()
end

function ns.stopAuto() stop() end

-- One auto-tell step: the punch line when a joke is waiting for it, otherwise the next setup.
local function autoStep(run)
  if run ~= state.run or not state.auto then return end
  if locked() then
    return stop('Chat is locked during combat or a match. Auto-tell stopped.')
  end
  if state.phase == 'asked' then
    emote(state.joke.punch)
    state.joke, state.phase = nil, 'idle'
    refresh()
    C_Timer.After(ns.pace().next, function() autoStep(run) end)
    return
  end
  local j = state.pending or ns.nextJoke()
  if not j then
    return stop('Add a joke first: open the window with /joke, or /joke add <setup> || <punch line>.')
  end
  emote(j.setup)
  state.pending, state.joke, state.phase = nil, j, 'asked'
  refresh()
  C_Timer.After(ns.pace().punch, function() autoStep(run) end)
end

-- Start auto-tell. A joke waiting for its punch line is finished first.
function ns.startAuto()
  state.run = state.run + 1
  state.auto = true
  autoStep(state.run)
end

-- Say the next line. Returns true when something was said. While auto-tell runs, a tell (a click
-- or /joke tell) stops it instead.
function ns.tell()
  if state.auto then
    stop()
    return false
  end
  if state.phase == 'idle' then
    local j = state.pending or ns.nextJoke()
    if not j then
      ns.print('Add a joke first: open the window with /joke, or /joke add <setup> || <punch line>.')
      return false
    end
    if not send(j.setup) then
      state.pending = j
      return false
    end
    state.pending, state.joke, state.phase = nil, j, 'asked'
  else
    if not send(state.joke.punch) then return false end
    state.joke, state.phase = nil, 'idle'
  end
  refresh()
  return true
end

ns.ADDON_URL = 'https://gamba-forever.com/addons'

-- Say where to get the addon, for anyone at the campfire who wants it. A joke in progress keeps
-- waiting for its punch line.
function ns.share()
  return send('Get Campfire Dad Jokes at ' .. ns.ADDON_URL, 'SAY')
end

-- Drop the joke in progress without saying anything (and stop auto-tell).
function ns.skip()
  if state.auto then return stop() end
  state.phase, state.joke, state.pending = 'idle', nil, nil
  refresh()
end

SLASH_DADJOKES1 = '/joke'
SLASH_DADJOKES2 = '/dadjoke'
SlashCmdList.DADJOKES = function(msg)
  msg = msg or ''
  local cmd, rest = string.match(msg, '^%s*(%S*)%s*(.-)%s*$')
  cmd = string.lower(cmd or '')
  if cmd == 'tell' then
    ns.tell()
  elseif cmd == 'skip' then
    ns.skip()
  elseif cmd == 'share' then
    ns.share()
  elseif cmd == 'auto' then
    if state.auto then ns.stopAuto() else ns.startAuto() end
  elseif cmd == 'stop' then
    ns.stopAuto()
  elseif cmd == 'pace' then
    if rest == '' then
      local p = ns.pace()
      ns.print('Auto-tell pace: punch line after ' .. p.punch .. ' s, next joke after ' .. p.next .. ' s.')
      return
    end
    local a, b = string.match(rest, '^(%S+)%s+(%S+)$')
    local punch, nextJoke = tonumber(a or ''), tonumber(b or '')
    if not punch or not nextJoke then
      ns.print('Usage: /joke pace <seconds before the punch line> <seconds between jokes>, e.g. /joke pace 4 3')
      return
    end
    local ok, why = ns.setPace(punch, nextJoke)
    ns.print(ok and ('Auto-tell pace set: punch line after ' .. punch .. ' s, next joke after ' .. nextJoke .. ' s.') or why)
    refresh()
  elseif cmd == 'mini' or cmd == 'compact' then
    if ns.ui then ns.ui.showMini(not ns.ui.mini:IsShown()) end
  elseif cmd == 'add' then
    local at = string.find(rest, '||', 1, true)
    if not at then
      ns.print('Usage: /joke add <setup> || <punch line>')
      return
    end
    local ok, why = ns.addJoke(string.sub(rest, 1, at - 1), string.sub(rest, at + 2))
    ns.print(ok and 'Joke added.' or ns.REASONS[why] or why)
  elseif cmd == 'list' then
    ns.print(#DadJokesDB.jokes .. ' jokes in your list.')
  elseif cmd == 'help' then
    ns.print('/joke opens the window. /joke tell says the next line (bind it to a key with a macro). /joke skip drops the joke in progress. /joke auto keeps telling jokes on its own until /joke stop. /joke pace <punch> <next> sets its pauses in seconds (now 4 and 3 by default). /joke share says where to get this addon. /joke mini shows or hides the compact view (just the button). /joke add <setup> || <punch line> adds a joke. /joke list counts your jokes.')
  elseif ns.ui and ns.ui.toggle then
    ns.ui.toggle()
  end
end
