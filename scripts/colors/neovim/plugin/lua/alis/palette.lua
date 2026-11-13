--- alis.nvim palette loader
--- Reads palette.json + terminal.json from the Alis generated directory
--- and produces a normalised colour table.
---@class alis.Palette
---@field bg string
---@field dark_bg string
---@field darker_bg string
---@field lighter_bg string
---@field fg string
---@field dark_fg string
---@field muted string
---@field red string
---@field yellow string
---@field orange string
---@field green string
---@field cyan string
---@field blue string
---@field purple string
---@field brown string
---@field bright_red string
---@field bright_yellow string
---@field bright_green string
---@field bright_cyan string
---@field bright_blue string
---@field bright_purple string
---@field selection string
---@field accent string

local M = {}

--- Read and decode a JSON file, returning {} on failure.
---@param path string
---@return table
local function read_json(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines or #lines == 0 then
    return {}
  end
  local ok2, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
  return (ok2 and type(decoded) == "table") and decoded or {}
end

--- Pick a value from a table, falling back to a default.
---@param tbl table
---@param key string
---@param fallback string
---@return string
local function pick(tbl, key, fallback)
  local v = tbl[key]
  return (type(v) == "string" and v ~= "") and v or fallback
end

--- Load the full palette from Alis generated JSON files.
---@param config alis.Config
---@return alis.Palette
function M.load(config)
  local dir = config.generated_dir
  local pal = read_json(dir .. "/palette.json")
  if vim.tbl_isempty(pal) then
    pal = read_json(dir .. "/colors.json")
  end
  local term = read_json(dir .. "/terminal.json")

  local fg = pick(pal, "on_background", "#DAC1C5")

  local colors = {
    bg         = pick(pal,  "background",                "#1E1D2E"),
    dark_bg    = pick(pal,  "surface_container_low",     "#171623"),
    darker_bg  = pick(pal,  "surface_container_lowest",  "#0f0f17"),
    lighter_bg = pick(pal,  "surface_container_highest", "#353443"),
    fg         = fg,
    dark_fg    = pick(pal,  "on_surface_variant",        "#a49194"),
    muted      = pick(pal,  "outline",                   "#6e6e74"),
    red        = pick(term, "term1",                     "#D99F9F"),
    yellow     = pick(term, "term11",                    "#9b9e73"),
    orange     = pick(pal,  "primary",                   "#dfadad"),
    green      = pick(term, "term2",                     "#88a480"),
    cyan       = pick(term, "term6",                     "#99B3CE"),
    blue       = pick(term, "term4",                     "#7B8DAB"),
    purple     = pick(term, "term5",                     "#a28798"),
    brown      = pick(pal,  "secondary_container",       "#866868"),
    bright_red    = pick(term, "term9",  "#febcbc"),
    bright_yellow = pick(term, "term11", "#c0c58c"),
    bright_green  = pick(term, "term10", "#aacc9c"),
    bright_cyan   = pick(term, "term14", "#b6d2f4"),
    bright_blue   = pick(term, "term12", "#9eb1d8"),
    bright_purple = pick(term, "term13", "#caaac0"),
    selection   = pick(pal, "surface_container_high",    "#353443"),
    accent      = pick(pal, "primary",                   "#7B8DAB"),
  }

  -- Let the user modify colours before highlights are applied
  if config.on_colors then
    config.on_colors(colors)
  end

  return colors
end

return M
