local utils = require 'mp.utils'

local opts = require 'script_options'
local tools = require 'tools'

local clipboard = {}
local platform
local display_server
local use_powershell_clipboard = nil

function clipboard.detect_platform()
  platform = mp.get_property_native("platform")

  if platform == "darwin" then
    platform = "macos"
  end

  if os.getenv("WAYLAND_DISPLAY") then
    display_server = 'wayland'
  elseif platform == 'linux' then
    display_server = 'xorg'
  else
    display_server = ""
  end

  tools.dlog("Detected Platform: " .. platform)
  tools.dlog("Detected display server: " .. display_server)
end

function clipboard.read()
  if opts.USE_MPV_CLIPBOARD_API == true then
    local api_response = mp.get_property_native('clipboard/text')
    return api_response
  end

  local res

  if platform == 'windows' then
    res = utils.subprocess({
      args = {
        'powershell', '-NoProfile', '-Command', [[& {
        Trap {
          Write-Error -ErrorRecord $_
          Exit 1
        }
        $clip = ""
        if (Get-Command "Get-Clipboard" -errorAction SilentlyContinue) {
          $clip = Get-Clipboard -Raw -Format Text -TextFormatType UnicodeText
        } else {
          Add-Type -AssemblyName PresentationCore
          $clip = [Windows.Clipboard]::GetText()
        }
        $clip = $clip -Replace "`r",""
        $u8clip = [System.Text.Encoding]::UTF8.GetBytes($clip)
        [Console]::OpenStandardOutput().Write($u8clip, 0, $u8clip.Length)
      }]]
      }
    })
  elseif platform == 'macos' then
    return io.popen('LANG=en_US.UTF-8 pbpaste'):read("*a")
  else -- platform == 'linux'
    if display_server == 'wayland' then
      res = utils.subprocess({
        args = {
          'wl-paste'
        }
      })
    else -- display_server == 'xorg'
      res = utils.subprocess({
        args = {
          'xclip', '-selection', 'clipboard', '-out'
        }
      })
    end
  end

  if not res.error then
    return res.stdout
  end
end

function clipboard.set(text)
  -- Remove newlines from text before sending it to clipboard.
  -- This way pressing control+v without copying from texthooker page
  -- will always give last line.
  text = string.gsub(text, "[\n\r]+", " ")

  if opts.USE_MPV_CLIPBOARD_API == true then
    mp.set_property("clipboard/text", text)
    return
  end

  if platform == 'windows' then
    -- Windows clipboard handling with automatic type detection
    if use_powershell_clipboard == nil then
      -- Test PowerShell clipboard functionality inline
      local test_text = [[Anacreon様]]
      utils.subprocess({
        args = {
          'powershell', '-NoProfile', '-Command', [[Set-Clipboard -Value @"]] ..
        "\n" .. test_text .. "\n" .. [["@]]
        }
      })
      use_powershell_clipboard = clipboard.read() == test_text
      tools.dlog("Using PowerShell clipboard: " .. (use_powershell_clipboard and "yes" or "no"))
    end

    -- Use determined clipboard method
    if use_powershell_clipboard then
      utils.subprocess({
        args = {
          'powershell', '-NoProfile', '-Command', [[Set-Clipboard -Value @"]] .. "\n" .. text .. "\n" .. [["@]]
        }
      })
    else
      local cmd = 'echo ' .. text .. ' | clip'
      mp.command("run cmd /D /C " .. cmd)
    end
  elseif platform == 'macos' then
    -- macOS clipboard handling
    os.execute('export LANG=en_US.UTF-8; cat <<EOF | pbcopy\n' .. text .. '\nEOF\n')
  else
    -- Linux clipboard handling
    if display_server == 'wayland' then
      os.execute('wl-copy <<EOF\n' .. text .. '\nEOF\n')
    else -- assume xorg
      os.execute('xclip -selection clipboard <<EOF\n' .. text .. '\nEOF\n')
    end
  end
end

return clipboard
