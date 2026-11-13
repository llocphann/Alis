--- alis.nvim — Alis Material You colorscheme for Neovim
--- Reads palette.json + terminal.json from the Alis theming pipeline
--- and applies a fully dynamic, transparent colorscheme.
---@class alis
---@field config alis.Config
local M = {}

--- Load and apply the colorscheme
function M.load()
  local config = require("alis.config").resolve()
  local palette = require("alis.palette").load(config)
  require("alis.highlights").apply(palette, config)
  require("alis.terminal").apply(palette)

  vim.g.colors_name = "alis"

  -- Start the file watcher for live reloading (if not already started)
  if config.live_reload then
    require("alis.watcher").start(config)
  end
end

--- Configure the plugin.  Call this from your lazy plugin spec's opts.
---@param opts? alis.Config
function M.setup(opts)
  require("alis.config").setup(opts)
end

return M
