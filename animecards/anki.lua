local msg = require 'mp.msg'
local utils = require 'mp.utils'

local tools = require 'tools'

local anki = {}
local media_dir = ""

function anki.request(action, params)
  local request = utils.format_json({ action = action, params = params, version = 6 })
  -- Avoid "localhost" on Windows, it causes latency. Use 127.0.0.1 instead
  local args = { 'curl', '-s', '127.0.0.1:8765', '-X', 'POST', '-d', request }

  tools.dlog("AnkiConnect request: " .. request)

  local result = utils.subprocess({ args = args, cancellable = false, capture_stderr = true })

  if result.status ~= 0 then
    msg.error("Curl command failed with status: " .. tostring(result.status))
    msg.error("Stderr: " .. (result.stderr or "none"))
    return nil
  end

  if not result.stdout or result.stdout == "" then
    msg.error("Empty response from AnkiConnect")
    return nil
  end

  tools.dlog("AnkiConnect response: " .. result.stdout)

  local success, parsed_result = pcall(function() return utils.parse_json(result.stdout) end)
  if not success or not parsed_result then
    msg.error("Failed to parse JSON response: " .. (result.stdout or "empty"))
    return nil
  end

  return parsed_result
end

function anki.set_media_dir()
  if media_dir ~= '' then
    return
  end

  local media_dir_response = anki.request('getMediaDirPath')

  if not media_dir_response then
    msg.error("Failed to communicate with AnkiConnect. Is Anki running and do you have AnkiConnect installed?")
    mp.osd_message(
      "Error: Failed to communicate with AnkiConnect. Is Anki running and do you have AnkiConnect installed?", 5)
    return
  elseif media_dir_response["error"] then
    msg.error("AnkiConnect error: " .. tostring(media_dir_response["error"]))
    mp.osd_message("AnkiConnect error: " .. tostring(media_dir_response["error"]), 5)
    return
  elseif media_dir_response["result"] then
    media_dir = media_dir_response["result"]
    tools.dlog("Got media directory path from AnkiConnect: " .. media_dir)
  else
    msg.error("Unexpected response format from AnkiConnect")
    mp.osd_message("Error: Unexpected response from AnkiConnect", 5)
    return
  end
end

function anki.get_media_dir()
  return media_dir
end

function anki.get_selected_notes()
  local result = anki.request("guiSelectedNotes")
  return result["result"]
end

-- If a card is curently selected, unfocus it
-- Otherwise, it will interfere with card update
function anki.unfocus_card(noteid)
  local selected_notes = anki.get_selected_notes()

  if #selected_notes == 1 and selected_notes[1] == noteid then
    return anki.request('guiSelectCard', { card = 0 })
  end
end

function anki.update_note(noteid, fields)
  return anki.request('updateNoteFields', {
    note = { id = noteid, fields = fields }
  })
end

function anki.get_field_value(noteid, field)
  local note = anki.request('notesInfo', { notes = { noteid } })
  return note['result'][1]['fields'][field]['value']
end

function anki.get_last_added()
  local added_notes = anki.request('findNotes', { query = 'added:1' })["result"]
  table.sort(added_notes)
  return added_notes[#added_notes]
end

return anki
