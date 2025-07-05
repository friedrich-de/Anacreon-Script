------------- Instructions -------------
-- -- Video Demonstration: https://www.youtube.com/watch?v=M4t7HYS73ZQ
-- IF USING WEBSOCKET (RECOMMENDED)
-- -- Install the mpv_webscoket extension: https://github.com/kuroahna/mpv_websocket
-- -- Open a LOCAL copy of https://github.com/Renji-XD/texthooker-ui
-- -- Configure the script (if you're not using the Lapis note format)
-- IF USING CLIPBOARD INSERTER (NOT RECOMMENDED)
-- -- Install the clipboard inserter plugin: https://github.com/laplus-sadness/lap-clipboard-inserter
-- -- Open the texthooker UI, enable the plugin and enable clipboard pasting: https://github.com/Renji-XD/texthooker-ui
-- BOTH
-- -- Wait for an unknown word and create the card with Yomichan.
-- -- Select all the subtitle lines you wish to add to the card and copy with Ctrl + c.
-- -- Press Ctrl + v in MPV to add the lines, their Audio and the currently paused image to the back of the card.
---------------------------------------

------------- Credits -------------
-- Credits and copyright go to Anacreon DJT: https://anacreondjt.gitlab.io/
------------------------------------

------------- Original Credits (Outdated) -------------
-- This script was made by users of 4chan's Daily Japanese Thread (DJT) on /jp/
-- More information can be found here http://animecards.site/
-- Message @Anacreon with bug reports and feature requests on Discord (https://animecards.site/discord/) or 4chan (https://boards.4channel.org/jp/#s=djt)
--
-- If you like this work please consider subscribing on Patreon!
-- https://www.patreon.com/Quizmaster
------------------------------------

local mp_options = require 'mp.options'
local msg = require 'mp.msg'

local anki = require 'anki'                 -- Everything related to Anki
local builder = require 'card_builder'      -- Constructs Anki card
local clip = require 'clipboard'            -- Clipboard handling, platform detection
local enc = require 'encoder'               -- Media creation (audio, image, filenames)
local opts = require 'script_options'       -- Default script options
local sub_obs = require 'subtitle_observer' -- Stores subtitle information

-- 'input' doesn't exist in mpv version < v0.39
local has_input, input = pcall(require, 'mp.input')

if unpack ~= nil then table.unpack = unpack end

mp_options.read_options(opts, "animecards") -- loads user's animecards.conf
mp.register_event("file-loaded", enc.verify_libmp3lame)
clip.detect_platform()

-- Core functions
---------------------------------------
local function process_cards(note_ids)
  local current_time = mp.get_property_number('time-pos')

  -- Defines subs range from clipboard content
  local lines = clip.read()

  if lines == nil then
    mp.osd_message('Failed to access clipboard', 5)
    msg.error('Failed to access clipboard: the value is nil.')
    return
  end

  local range_start, range_end = sub_obs.specify_range(lines)

  if range_start == nil and range_end == nil then
    return -- Error handlers are already in specify_range() function
  end

  -- Creating media
  local media_name = enc.gen_name(range_start, range_end)
  enc.create_audio(media_name, range_start, range_end)
  enc.create_image(media_name, current_time)

  -- Updating anki cards
  for _, noteid in ipairs(note_ids) do
    local word = anki.get_field_value(noteid, opts.FRONT_FIELD)
    local fields = builder.construct(lines, noteid, range_start, media_name)

    -- Ensures the card is not focused before updating
    -- Otherwise, for some reasons, it will not be updated
    anki.unfocus_card(noteid)
    anki.update_note(noteid, fields)

    mp.osd_message('Updated note: ' .. word, 3)
    msg.info('Updated note: ' .. word)
  end

  if #note_ids > 1 then
    mp.osd_message(#note_ids .. " cards were overwritten.", 3)
    msg.info(#note_ids .. " cards were overwritten.")
  end

  -- Autoplay audio if required
  enc.autoplay(media_name)
end

local function handle_last_card() -- ctrl+v
  local noteid = anki.get_last_added()

  if noteid == nil then
    mp.osd_message("ERR! Last added card not found.", 3)
    return
  end

  process_cards({ noteid })
end

local function confirm_overwrite() -- ctrl+r
  local selected_notes = anki.get_selected_notes()

  if #selected_notes == 0 then
    mp.osd_message("ERR! Nothing selected for overwrite.", 3)
    msg.error("Nothing selected for overwrite.")
    return
  elseif #selected_notes > opts.OVERWRITE_LIMIT and opts.OVERWRITE_LIMIT ~= -1 then
    mp.osd_message("ERR! The number of selected notes exceeds the overwrite limit (" .. opts.OVERWRITE_LIMIT .. ")", 3)
    msg.error("The number of selected notes exceeds the overwrite limit (" .. opts.OVERWRITE_LIMIT .. ")")
    return
  end

  if opts.ASK_TO_OVERWRITE ~= true then
    process_cards(selected_notes)
    return
  end

  if not has_input or input.select == nil then
    mp.osd_message(
      "Error: input.select not found. Cannot ask for overwrite confirmation.\nYour MPV version may be below 0.39?",
      10)
    msg.error("Error: input.select not found. Cannot ask for overwrite confirmation.")
    return
  end

  input.select({
    prompt = 'Do you want to overwrite ' .. #selected_notes .. " cards?",
    items = { "No", "Yes" },
    submit = function(answer_id)
      if answer_id == 2 then
        process_cards(selected_notes)
      end
    end,
  })
end

-- saferun_* functions: wrap in pcall when debug mode is enabled
-- (DEBUG_MODE is defined in script_options.lua)
---------------------------------------
local function saferun_last_card() -- ctrl+v
  anki.set_media_dir()

  if not opts.DEBUG_MODE then
    handle_last_card()
  else
    local success, error_msg = pcall(handle_last_card)

    if not success then
      mp.osd_message('Error: ' .. tostring(error_msg), 5)
      msg.error('Failed to update a card: ' .. tostring(error_msg))
    end
  end
end

local function saferun_selected() -- ctrl+r
  anki.set_media_dir()

  if not opts.DEBUG_MODE then
    confirm_overwrite()
  else
    local success, error_msg = pcall(confirm_overwrite)
    if not success then
      mp.osd_message("Error: " .. tostring(error_msg), 5)
      msg.error("Failed to overwrite cards: " .. tostring(error_msg))
    end
  end
end

local function saferun_record(...)
  if not opts.DEBUG_MODE then
    sub_obs.record(...)
  else
    local success, error_msg = pcall(sub_obs.record, ...)

    if not success then
      msg.error('Failed to record subtitle: ' .. tostring(error_msg))
    end
  end
end

-- Set up key bindings
---------------------------------------
mp.add_key_binding("ctrl+v", "update-anki-card", saferun_last_card)
mp.add_key_binding("ctrl+r", "overwrite-anki-cards", saferun_selected)
mp.add_key_binding("ctrl+t", "toggle-clipboard-insertion", opts.toggle_sub_to_clipboard)

mp.add_key_binding("ctrl+V", saferun_last_card)
mp.add_key_binding("ctrl+R", saferun_selected)
mp.add_key_binding("ctrl+T", opts.toggle_sub_to_clipboard)

-- Set up mpv observers
---------------------------------------
mp.observe_property('sub-text', 'string', saferun_record)
mp.observe_property('filename', 'string', sub_obs.clear)
-----------------------------------------------------------------
