--- Lualine theme for alis.nvim
--- Reads colours from current highlight groups for a fully transparent statusline.
local function fg(group)
  local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
  return hl and hl.fg and string.format("#%06x", hl.fg) or nil
end

local function theme()
  local accent  = fg("Function") or "#7b8dab"
  local green   = fg("String")   or "#88a480"
  local yellow  = fg("Type")     or "#9b9e73"
  local red     = fg("Error")    or "#d99f9f"
  local purple  = fg("Keyword")  or "#a28798"
  local dim     = fg("Comment")  or "#6e6e74"

  local s = function(c)
    return {
      a = { fg = c, bg = "NONE", gui = "bold" },
      b = { fg = c, bg = "NONE" },
      c = { fg = dim, bg = "NONE" },
    }
  end

  return {
    normal   = s(accent),
    insert   = s(green),
    visual   = s(purple),
    replace  = s(red),
    command  = s(yellow),
    inactive = s(dim),
  }
end

return theme()
