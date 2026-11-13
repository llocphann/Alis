--- alis.nvim file watcher
--- Monitors Alis generated JSON files and live-reloads the colorscheme.
local M = {}

---@param config alis.Config
function M.start(config)
  -- Only start once per session
  if vim.g.alis_watcher_started then
    return
  end

  local uv = vim.uv or vim.loop
  if not uv then
    return
  end

  local dir = config.generated_dir
  local watched = {
    ["palette.json"] = true,
    ["terminal.json"] = true,
    ["colors.json"] = true,
  }

  local handle = uv.new_fs_event()
  if not handle then
    return
  end

  local pending = false

  handle:start(dir, {}, vim.schedule_wrap(function(err, fname)
    if err or pending then
      return
    end
    if fname and not watched[fname] then
      return
    end

    pending = true
    vim.defer_fn(function()
      pending = false
      if vim.g.colors_name == "alis" or vim.g.colors_name == "inir" then
        -- Re-load the colorscheme (re-reads JSON, re-applies highlights)
        require("alis").load()
      end
    end, 150)
  end))

  vim.g.alis_watcher_started = true
end

return M
