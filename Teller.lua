-- Telling a joke takes two clicks: the first says a random joke's setup, the second its punch
-- line. Lines go to the player's chosen destination (DadJokesDB.dest, set with /joke to or on the
-- Campfire tab): a speech-style emote ("Bo says: ...") by default, or say, yell, party, raid,
-- instance, guild, officer, a whisper or a numbered channel. During chat lockdown (combat, a
-- match), or when the chosen chat isn't available, a click sends nothing and the same line waits
-- for the next click.
--
-- Auto-tell: setup, pace().punch seconds, punch line, pace().next seconds, next joke, until stopped.
-- The pauses are player settings (DadJokesDB.pace), set with /joke pace or on the Campfire tab.
-- It runs on timers, and the client only takes addon say, yell, emotes and channel lines from a
-- click or keypress (emotes too since WoW: Forever's October 2026 update). So auto-tell uses the
-- destination when it is a chat timers may use (TIMED_DESTS), and group chat otherwise. It stops
-- when its chat goes away, when its whisper target is offline, or when the game blocks a line.
local ADDON, ns = ...

ns.DEFAULT_PACE = { punch = 4, next = 3 }
ns.PACE_MIN, ns.PACE_MAX = 0.5, 60
ns.PACE_RANGE_MESSAGE = 'Pauses must be between ' .. ns.PACE_MIN .. ' and ' .. ns.PACE_MAX .. ' seconds.'

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
    return false, ns.PACE_RANGE_MESSAGE
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

-- Where jokes can go, in the order the Campfire tab's button cycles through them.
ns.DESTS = {
  { type = 'EMOTE', label = 'Emote', slash = '/e', aliases = { 'e', 'em', 'emote' } },
  { type = 'SAY', label = 'Say', slash = '/s', aliases = { 's', 'say' } },
  { type = 'YELL', label = 'Yell', slash = '/y', aliases = { 'y', 'yell' } },
  { type = 'PARTY', label = 'Party', slash = '/p', aliases = { 'p', 'party' } },
  { type = 'RAID', label = 'Raid', slash = '/raid', aliases = { 'ra', 'raid' } },
  { type = 'INSTANCE_CHAT', label = 'Instance', slash = '/i', aliases = { 'i', 'instance' } },
  { type = 'GUILD', label = 'Guild', slash = '/g', aliases = { 'g', 'guild' } },
  { type = 'OFFICER', label = 'Officer', slash = '/o', aliases = { 'o', 'officer' } },
  { type = 'WHISPER', label = 'Whisper', slash = '/w', aliases = { 'w', 't', 'whisper', 'tell' } },
  { type = 'CHANNEL', label = 'Channel', slash = '/#', aliases = { 'c', 'channel' } },
}
local DEST_BY_TYPE, DEST_BY_ALIAS = {}, {}
for _, d in ipairs(ns.DESTS) do
  DEST_BY_TYPE[d.type] = d
  for _, a in ipairs(d.aliases) do DEST_BY_ALIAS[a] = d end
end
-- Chats the game lets auto-tell's timers post in.
local TIMED_DESTS = { PARTY = true, RAID = true, INSTANCE_CHAT = true, GUILD = true, OFFICER = true, WHISPER = true }
local PICK_ANOTHER = ' Pick another place with /joke to, or on the Campfire tab.'

-- A character name ("thrall" -> "Thrall", optionally "-Realm"), or nil when it can't be one.
local function characterName(text)
  if type(text) ~= 'string' then return nil end
  text = string.gsub(text, '^%s+', '')
  text = string.gsub(text, '%s+$', '')
  local name, realm = string.match(text, '^([^%-]+)%-(.+)$')
  name = name or text
  if #name < 2 or #name > 24 or not string.find(name, '^[%a\128-\255]+$') then return nil end
  if realm and not string.find(realm, "^[%a\128-\255']+$") then return nil end
  name = string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
  return realm and (name .. '-' .. realm) or name
end

local function channelNumber(value)
  local n = tonumber(value)
  if n and n >= 1 and n == math.floor(n) then return n end
  return nil
end

local function targetFor(destType, value)
  if destType == 'WHISPER' then return characterName(value) end
  if destType == 'CHANNEL' then return channelNumber(value) end
  return nil
end

-- The saved destination { type, target }; anything unreadable is the default, an emote.
function ns.dest()
  local d = type(DadJokesDB) == 'table' and type(DadJokesDB.dest) == 'table' and DadJokesDB.dest or {}
  if not DEST_BY_TYPE[d.type] then return { type = 'EMOTE' } end
  return { type = d.type, target = targetFor(d.type, d.target) }
end

-- The last whisper name or channel number used, kept per type.
function ns.destTarget(destType)
  local t = type(DadJokesDB) == 'table' and type(DadJokesDB.destTargets) == 'table' and DadJokesDB.destTargets or {}
  return targetFor(destType, t[destType])
end

-- Choose where jokes go. `target` is the whisper name or channel number; nil keeps the last one
-- used for that type. Returns true, or false and a reason.
function ns.setDest(destType, target)
  if not DEST_BY_TYPE[destType] then return false, 'Unknown place.' end
  local value
  if destType == 'WHISPER' or destType == 'CHANNEL' then
    if target == nil then
      value = ns.destTarget(destType)
    else
      value = targetFor(destType, target)
      if not value then
        return false, destType == 'WHISPER' and 'That is not a character name.' or 'Channel numbers are whole numbers from 1.'
      end
    end
  end
  DadJokesDB.dest = { type = destType, target = value }
  if value ~= nil then
    DadJokesDB.destTargets = DadJokesDB.destTargets or {}
    DadJokesDB.destTargets[destType] = value
  end
  return true
end

-- "Guild (/g)", "Whisper Thrall (/w)", "Channel 2 (/2)".
function ns.destLabel(d)
  d = d or ns.dest()
  local info = DEST_BY_TYPE[d.type]
  if d.type == 'WHISPER' then return 'Whisper' .. (d.target and (' ' .. d.target) or '') .. ' (/w)' end
  if d.type == 'CHANNEL' then return 'Channel' .. (d.target and (' ' .. d.target .. ' (/' .. d.target .. ')') or '') end
  return info.label .. ' (' .. info.slash .. ')'
end

-- Whether `d` can take a line now: true, or false and why.
local function available(d)
  local t = d.type
  if t == 'PARTY' and not (IsInGroup and IsInGroup()) then return false, "You're not in a party." end
  if t == 'RAID' and not (IsInRaid and IsInRaid()) then return false, "You're not in a raid." end
  if t == 'INSTANCE_CHAT' and not (IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) then
    return false, "You're not in an instance group."
  end
  if (t == 'GUILD' or t == 'OFFICER') and not (IsInGuild and IsInGuild()) then return false, "You're not in a guild." end
  if t == 'WHISPER' and not d.target then return false, 'Type who to whisper.' end
  if t == 'CHANNEL' then
    if not d.target then return false, 'Type a channel number.' end
    if (GetChannelName(d.target) or 0) == 0 then return false, "You're not in channel " .. d.target .. '.' end
  end
  return true
end

local function locked()
  return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

-- A speech-style emote. A line too long for the prefix within one chat line (255 bytes) goes bare.
local function emote(text)
  if #EMOTE_PREFIX + #text <= 255 then text = EMOTE_PREFIX .. text end
  SendChatMessage(text, 'EMOTE')
end

local function sendTo(text, chatType, target)
  if chatType == 'EMOTE' then emote(text) else SendChatMessage(text, chatType, nil, target) end
end

-- Send a line from a click to the chosen destination, when it can take one.
local function send(text)
  if locked() then
    ns.print('Chat is locked during combat or a match. Click again afterwards.')
    return false
  end
  local d = ns.dest()
  local ok, why = available(d)
  if not ok then
    ns.print(why .. PICK_ANOTHER)
    return false
  end
  sendTo(text, d.type, d.target)
  return true
end

-- The group chat auto-tell posts in, or nil outside a group.
local function groupChannel()
  if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return 'INSTANCE_CHAT' end
  if IsInRaid and IsInRaid() then return 'RAID' end
  if IsInGroup and IsInGroup() then return 'PARTY' end
  return nil
end

-- The chat auto-tell posts in: the destination when timers may use it, else group chat. Returns
-- chatType, target; or nil and why.
local function autoChat()
  local d = ns.dest()
  if TIMED_DESTS[d.type] then
    local ok, why = available(d)
    if ok then return d.type, d.target end
    return nil, why
  end
  local group = groupChannel()
  if group then return group end
  return nil, 'Auto-tell posts in party or raid chat: join a group first, or pick Guild or Whisper with /joke to. (The game only lets addons use say, yell, emotes and channels from a click, so use Tell a joke there.)'
end

local function stop(reason)
  state.auto, state.run = false, state.run + 1
  state.autoWhisper = nil
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
  local chatType, target = autoChat()
  if not chatType then
    if not TIMED_DESTS[ns.dest().type] then return stop('You left the group. Auto-tell stopped.') end
    return stop(target .. ' Auto-tell stopped.')
  end
  state.autoWhisper = chatType == 'WHISPER' and target or nil
  if state.phase == 'asked' then
    sendTo(state.joke.punch, chatType, target)
    state.joke, state.phase = nil, 'idle'
    refresh()
    C_Timer.After(ns.pace().next, function() autoStep(run) end)
    return
  end
  local j = state.pending or ns.nextJoke()
  if not j then
    return stop('Add a joke first: open the window with /joke, or /joke add <setup> || <punch line>.')
  end
  sendTo(j.setup, chatType, target)
  state.pending, state.joke, state.phase = nil, j, 'asked'
  refresh()
  C_Timer.After(ns.pace().punch, function() autoStep(run) end)
end

-- Start auto-tell. A joke waiting for its punch line is finished first. Returns false when there is
-- no chat it may use.
function ns.startAuto()
  local chatType, why = autoChat()
  if not chatType then
    ns.print(why)
    return false
  end
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

-- A line the game refused (a protected call outside a click): stop rather than fail every few seconds.
local function onBlocked(addon)
  if addon == ADDON and state.auto then
    stop('The game blocked a Campfire Dad Jokes line. Auto-tell stopped.')
  end
end
ns.on('ADDON_ACTION_BLOCKED', onBlocked)
ns.on('ADDON_ACTION_FORBIDDEN', onBlocked)

-- Whispering someone offline gets "No player named ... is currently playing." Stop auto-tell then.
ns.on('CHAT_MSG_SYSTEM', function(msg)
  local name = state.auto and state.autoWhisper
  if name and ERR_CHAT_PLAYER_NOT_FOUND_S and msg == string.format(ERR_CHAT_PLAYER_NOT_FOUND_S, name) then
    stop(name .. " isn't online. Auto-tell stopped.")
  end
end)

ns.ADDON_URL = 'https://www.curseforge.com/wow/addons/campfire-dad-jokes'

-- Say where to get the addon, wherever the jokes go. A joke in progress keeps waiting for its
-- punch line.
function ns.share()
  return send('Get Campfire Dad Jokes at ' .. ns.ADDON_URL)
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
  elseif cmd == 'to' then
    if rest == '' then
      ns.print('Jokes go to: ' .. ns.destLabel() .. '.')
      return
    end
    local word, arg = string.match(rest, '^(%S+)%s*(.-)$')
    word = string.lower(word)
    local destType, target
    if tonumber(word) then
      destType, target = 'CHANNEL', word
    elseif DEST_BY_ALIAS[word] then
      destType = DEST_BY_ALIAS[word].type
      if destType == 'WHISPER' or destType == 'CHANNEL' then target = arg end
    end
    local ok, why
    if destType then ok, why = ns.setDest(destType, target) end
    if ok then
      ns.print('Jokes go to: ' .. ns.destLabel() .. '.')
      refresh()
    else
      if why then ns.print(why) end
      ns.print('Usage: /joke to <e|s|y|p|raid|i|g|o> or /joke to w <name> or /joke to <channel number>')
    end
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
    ns.print('/joke opens the window. /joke tell says the next line (bind it to a key with a macro). /joke skip drops the joke in progress. /joke to <e|s|y|p|raid|i|g|o>, /joke to w <name> or /joke to <channel number> chooses where jokes go. /joke auto keeps telling jokes on its own until /joke stop (in your party or raid unless you chose party, raid, guild, officer or a whisper). /joke pace <punch> <next> sets its pauses in seconds (now 4 and 3 by default). /joke share says where to get this addon, where the jokes go. /joke mini shows or hides the compact view (just the button). /joke add <setup> || <punch line> adds a joke. /joke list counts your jokes.')
  elseif ns.ui and ns.ui.toggle then
    ns.ui.toggle()
  end
end
