--- alis.nvim configuration
---@class alis.Config
---@field transparent? boolean  Make all backgrounds NONE (default: true)
---@field terminal_colors? boolean  Set terminal colour variables (default: true)
---@field live_reload? boolean  Watch JSON files and reload on change (default: true)
---@field generated_dir? string  Path to Alis generated dir
---@field styles? alis.Styles  Syntax styling options
---@field on_colors? fun(colors: alis.Palette)  Callback to modify palette
---@field on_highlights? fun(hl: table, colors: alis.Palette)  Callback to modify highlights
---@field lualine_bold? boolean  Bold lualine section headers (default: false)

---@class alis.Styles
---@field comments? vim.api.keyset.highlight
---@field keywords? vim.api.keyset.highlight
---@field functions? vim.api.keyset.highlight
---@field variables? vim.api.keyset.highlight

local M = {}

---@type alis.Config
M.defaults = {
  transparent = true,
  terminal_colors = true,
  live_reload = true,
  generated_dir = vim.fn.expand("~/.local/state/quickshell/user/generated"),
  styles = {
    comments = { italic = true },
    keywords = { italic = true },
    functions = {},
    variables = {},
  },
  on_colors = function() end,
  on_highlights = function() end,
  lualine_bold = false,
}

---@type alis.Config
M.options = nil

---@param opts? alis.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

--- Resolve current config (setup if needed)
---@return alis.Config
function M.resolve()
  if not M.options then
    M.setup()
  end
  return M.options
end

return M
