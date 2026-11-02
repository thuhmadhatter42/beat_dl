-- Beat Key Listener for REAPER.
-- Installed by Beat Key as <REAPER resource path>/Scripts/Beat Key Listener.lua.
-- Run it once per REAPER session (Actions > Show action list > New action > Load ReaScript,
-- then Run); it keeps running in the background (reaper.defer) until REAPER quits.
--
-- Mailbox: Beat Key writes  ~/Library/Application Support/Beat Key/DAW/REAPER/request.txt
--   id=<n>  cmd=ping|set|selection  [bpm=<number>]      (one key=value per line)
-- and this script answers in reply.txt with the same id:
--   id=<n>  ok=1|0  [bpm=<tempo now>] [file=<selected item's source file>] [error=<text>]
-- REAPER has no project key: only the tempo is set (SetCurrentBPM, or tempo marker 0 when the
-- project has tempo markers, so the marker is changed instead of being overridden).

local VERSION = "1"
local home = os.getenv("HOME") or ""
local dir = home .. "/Library/Application Support/Beat Key/DAW/REAPER/"
local last_id = nil

local function parse(text)
  local t = {}
  for k, v in string.gmatch(text or "", "([%w_]+)=([^\n]*)") do t[k] = v end
  return t
end

local function serialize(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. tostring(t[k]):gsub("\n", " ") end
  return table.concat(out, "\n") .. "\n"
end

local function set_tempo(bpm)
  if reaper.CountTempoTimeSigMarkers(0) > 0 then
    local ok, timepos, measurepos, beatpos, _, num, den, linear = reaper.GetTempoTimeSigMarker(0, 0)
    if ok then
      reaper.SetTempoTimeSigMarker(0, 0, timepos, measurepos, beatpos, bpm, num, den, linear)
      reaper.UpdateTimeline()
      reaper.Undo_OnStateChange("Beat Key: tempo " .. bpm)
      return
    end
  end
  reaper.SetCurrentBPM(0, bpm, true)
end

local function selection()
  local item = reaper.GetSelectedMediaItem(0, 0)
  if not item then return nil, "Select an audio item in REAPER first." end
  local take = reaper.GetActiveTake(item)
  if not take then return nil, "The selected item has no take." end
  if reaper.TakeIsMIDI(take) then return nil, "The selected item is MIDI. Select an audio item." end
  local src = reaper.GetMediaItemTake_Source(take)
  local parent = reaper.GetMediaSourceParent(src)
  while parent do src = parent; parent = reaper.GetMediaSourceParent(src) end
  local file = reaper.GetMediaSourceFileName(src)
  if not file or file == "" then return nil, "REAPER gave no file for this item." end
  return file
end

-- One request in, one reply table out.
function BeatKeyHandle(req)
  local r = { id = req.id, ok = 1, version = VERSION }
  if req.cmd == "set" then
    local bpm = tonumber(req.bpm or "")
    if bpm and bpm > 0 then set_tempo(math.max(1, math.min(960, bpm))) end
    r.bpm = string.format("%.4f", reaper.Master_GetTempo())
  elseif req.cmd == "selection" then
    local file, err = selection()
    if file then r.file = file else r.ok = 0; r.error = err end
  elseif req.cmd == "ping" then
    r.bpm = string.format("%.4f", reaper.Master_GetTempo())
  else
    r.ok = 0; r.error = "unknown request " .. tostring(req.cmd)
  end
  return r
end

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a"); f:close()
  return s
end

local function write(path, text)
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then return end
  f:write(text); f:close()
  os.rename(tmp, path)
end

local function poll()
  local req = parse(read(dir .. "request.txt"))
  if req.id and req.id ~= last_id then
    last_id = req.id
    write(dir .. "reply.txt", serialize(BeatKeyHandle(req)))
  end
  reaper.defer(poll)
end

BeatKeySerialize, BeatKeyParse = serialize, parse
if not BEATKEY_TEST then
  os.execute('mkdir -p "' .. dir .. '"')
  -- answer only requests made after this start, not a stale one left in the mailbox
  last_id = parse(read(dir .. "request.txt")).id
  poll()
end
