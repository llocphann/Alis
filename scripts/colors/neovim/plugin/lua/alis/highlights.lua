--- alis.nvim highlight definitions
--- Applies all highlight groups from the palette.
local M = {}

---@param c alis.Palette
---@param config alis.Config
function M.apply(c, config)
  vim.cmd.highlight("clear")
  if vim.fn.exists("syntax_on") == 1 then
    vim.cmd.syntax("reset")
  end

  local bg = config.transparent and "NONE" or c.bg
  local bg_sidebar = config.transparent and "NONE" or c.dark_bg
  local bg_float = config.transparent and "NONE" or c.dark_bg

  local h = function(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
  end

  -- Collect all highlights into a table so on_highlights can modify them
  local hl = {}

  -- ── Editor ────────────────────────────────────────────────────────────────
  hl["Normal"]       = { fg = c.fg, bg = bg }
  hl["NormalNC"]     = { fg = c.fg, bg = bg }
  hl["NormalSB"]     = { fg = c.fg, bg = bg_sidebar }
  hl["NormalFloat"]  = { fg = c.fg, bg = bg_float }
  hl["FloatBorder"]  = { fg = c.lighter_bg, bg = bg_float }
  hl["FloatTitle"]   = { fg = c.accent, bg = bg_float, bold = true }
  hl["EndOfBuffer"]  = { fg = c.muted, bg = bg }
  hl["Cursor"]       = { fg = c.bg, bg = c.fg }
  hl["CursorLine"]   = { bg = c.dark_bg }
  hl["CursorColumn"] = { bg = c.dark_bg }
  hl["CursorLineNr"] = { fg = c.accent, bold = true }
  hl["LineNr"]       = { fg = c.muted }
  hl["SignColumn"]   = { fg = c.muted, bg = bg }
  hl["ColorColumn"]  = { bg = c.dark_bg }
  hl["Folded"]       = { fg = c.muted, bg = c.dark_bg }
  hl["FoldColumn"]   = { fg = c.muted, bg = bg }
  hl["Visual"]       = { bg = c.selection }
  hl["VisualNOS"]    = { bg = c.selection }
  hl["Search"]       = { fg = c.bg, bg = c.yellow }
  hl["IncSearch"]    = { fg = c.bg, bg = c.orange }
  hl["CurSearch"]    = { fg = c.bg, bg = c.orange }
  hl["MatchParen"]   = { fg = c.orange, bold = true, underline = true }
  hl["Pmenu"]        = { fg = c.fg, bg = c.dark_bg }
  hl["PmenuSel"]     = { fg = c.bg, bg = c.accent }
  hl["PmenuSbar"]    = { bg = c.darker_bg }
  hl["PmenuThumb"]   = { bg = c.lighter_bg }
  hl["WildMenu"]     = { fg = c.bg, bg = c.accent }
  hl["VertSplit"]    = { fg = c.lighter_bg, bg = bg }
  hl["WinSeparator"] = { fg = c.lighter_bg, bg = bg }
  hl["StatusLine"]   = { fg = c.fg, bg = bg }
  hl["StatusLineNC"] = { fg = c.muted, bg = bg }
  hl["TabLine"]      = { fg = c.dark_fg, bg = bg }
  hl["TabLineFill"]  = { bg = bg }
  hl["TabLineSel"]   = { fg = c.fg, bg = bg, bold = true }
  hl["Title"]        = { fg = c.blue, bold = true }
  hl["Directory"]    = { fg = c.blue }
  hl["NonText"]      = { fg = c.muted }
  hl["SpecialKey"]   = { fg = c.muted }
  hl["Whitespace"]   = { fg = c.muted }
  hl["Conceal"]      = { fg = c.muted }
  hl["QuickFixLine"] = { bg = c.selection }
  hl["MsgArea"]      = { fg = c.fg }
  hl["ModeMsg"]      = { fg = c.accent, bold = true }
  hl["MoreMsg"]      = { fg = c.green }
  hl["WarningMsg"]   = { fg = c.yellow }
  hl["ErrorMsg"]     = { fg = c.red }
  hl["Question"]     = { fg = c.green }
  hl["SpellBad"]     = { undercurl = true, sp = c.red }
  hl["SpellCap"]     = { undercurl = true, sp = c.blue }
  hl["SpellRare"]    = { undercurl = true, sp = c.purple }
  hl["SpellLocal"]   = { undercurl = true, sp = c.cyan }

  -- ── Syntax ────────────────────────────────────────────────────────────────
  hl["Comment"]      = vim.tbl_extend("force", { fg = c.muted }, config.styles.comments or {})
  hl["Constant"]     = { fg = c.orange }
  hl["String"]       = { fg = c.green }
  hl["Character"]    = { fg = c.green }
  hl["Number"]       = { fg = c.orange }
  hl["Boolean"]      = { fg = c.orange }
  hl["Float"]        = { fg = c.orange }
  hl["Identifier"]   = vim.tbl_extend("force", { fg = c.fg }, config.styles.variables or {})
  hl["Function"]     = vim.tbl_extend("force", { fg = c.blue }, config.styles.functions or {})
  hl["Statement"]    = { fg = c.purple }
  hl["Conditional"]  = { fg = c.purple }
  hl["Repeat"]       = { fg = c.purple }
  hl["Label"]        = { fg = c.purple }
  hl["Operator"]     = { fg = c.cyan }
  hl["Keyword"]      = vim.tbl_extend("force", { fg = c.purple }, config.styles.keywords or {})
  hl["Exception"]    = { fg = c.red }
  hl["PreProc"]      = { fg = c.cyan }
  hl["Include"]      = { fg = c.purple }
  hl["Define"]       = { fg = c.purple }
  hl["Macro"]        = { fg = c.cyan }
  hl["PreCondit"]    = { fg = c.cyan }
  hl["Type"]         = { fg = c.yellow }
  hl["StorageClass"] = { fg = c.purple }
  hl["Structure"]    = { fg = c.yellow }
  hl["Typedef"]      = { fg = c.yellow }
  hl["Special"]      = { fg = c.cyan }
  hl["SpecialChar"]  = { fg = c.orange }
  hl["Tag"]          = { fg = c.red }
  hl["Delimiter"]    = { fg = c.dark_fg }
  hl["SpecialComment"] = { fg = c.muted, italic = true }
  hl["Debug"]        = { fg = c.red }
  hl["Underlined"]   = { underline = true }
  hl["Ignore"]       = { fg = c.muted }
  hl["Error"]        = { fg = c.red }
  hl["Todo"]         = { fg = c.bg, bg = c.yellow, bold = true }

  -- ── Treesitter ────────────────────────────────────────────────────────────
  hl["@comment"]               = { link = "Comment" }
  hl["@punctuation.bracket"]   = { fg = c.dark_fg }
  hl["@punctuation.delimiter"] = { fg = c.dark_fg }
  hl["@punctuation.special"]   = { fg = c.cyan }
  hl["@string"]                = { link = "String" }
  hl["@string.escape"]         = { fg = c.orange }
  hl["@string.special"]        = { fg = c.cyan }
  hl["@character"]             = { link = "Character" }
  hl["@boolean"]               = { link = "Boolean" }
  hl["@number"]                = { link = "Number" }
  hl["@float"]                 = { link = "Float" }
  hl["@function"]              = { link = "Function" }
  hl["@function.builtin"]      = { fg = c.cyan }
  hl["@function.macro"]        = { fg = c.cyan }
  hl["@function.call"]         = { fg = c.blue }
  hl["@method"]                = { fg = c.blue }
  hl["@method.call"]           = { fg = c.blue }
  hl["@constructor"]           = { fg = c.yellow }
  hl["@parameter"]             = { fg = c.fg }
  hl["@keyword"]               = { link = "Keyword" }
  hl["@keyword.function"]      = { fg = c.purple, italic = true }
  hl["@keyword.operator"]      = { fg = c.cyan }
  hl["@keyword.return"]        = { fg = c.purple, italic = true }
  hl["@conditional"]           = { link = "Conditional" }
  hl["@repeat"]                = { link = "Repeat" }
  hl["@label"]                 = { fg = c.blue }
  hl["@operator"]              = { link = "Operator" }
  hl["@exception"]             = { link = "Exception" }
  hl["@type"]                  = { link = "Type" }
  hl["@type.builtin"]          = { fg = c.yellow, italic = true }
  hl["@variable"]              = { link = "Identifier" }
  hl["@variable.builtin"]      = { fg = c.red, italic = true }
  hl["@constant"]              = { link = "Constant" }
  hl["@constant.builtin"]      = { fg = c.orange, italic = true }
  hl["@namespace"]             = { fg = c.yellow }
  hl["@field"]                 = { fg = c.cyan }
  hl["@property"]              = { fg = c.cyan }
  hl["@attribute"]             = { fg = c.yellow }
  hl["@tag"]                   = { fg = c.red }
  hl["@tag.attribute"]         = { fg = c.yellow }
  hl["@tag.delimiter"]         = { fg = c.dark_fg }
  hl["@text.title"]            = { fg = c.blue, bold = true }
  hl["@text.literal"]          = { fg = c.green }
  hl["@text.uri"]              = { fg = c.cyan, underline = true }
  hl["@text.emphasis"]         = { italic = true }
  hl["@text.strong"]           = { bold = true }
  hl["@text.reference"]        = { fg = c.orange }

  -- ── Diagnostics ───────────────────────────────────────────────────────────
  hl["DiagnosticError"]            = { fg = c.red }
  hl["DiagnosticWarn"]             = { fg = c.yellow }
  hl["DiagnosticInfo"]             = { fg = c.blue }
  hl["DiagnosticHint"]             = { fg = c.cyan }
  hl["DiagnosticUnderlineError"]   = { undercurl = true, sp = c.red }
  hl["DiagnosticUnderlineWarn"]    = { undercurl = true, sp = c.yellow }
  hl["DiagnosticUnderlineInfo"]    = { undercurl = true, sp = c.blue }
  hl["DiagnosticUnderlineHint"]    = { undercurl = true, sp = c.cyan }
  hl["DiagnosticVirtualTextError"] = { fg = c.red,    bg = bg, italic = true }
  hl["DiagnosticVirtualTextWarn"]  = { fg = c.yellow, bg = bg, italic = true }
  hl["DiagnosticVirtualTextInfo"]  = { fg = c.blue,   bg = bg, italic = true }
  hl["DiagnosticVirtualTextHint"]  = { fg = c.cyan,   bg = bg, italic = true }

  -- ── LSP ───────────────────────────────────────────────────────────────────
  hl["LspReferenceText"]  = { bg = c.lighter_bg }
  hl["LspReferenceRead"]  = { bg = c.lighter_bg }
  hl["LspReferenceWrite"] = { bg = c.lighter_bg, bold = true }

  -- ── Gitsigns / Diff ───────────────────────────────────────────────────────
  hl["GitSignsAdd"]    = { fg = c.green,  bg = bg }
  hl["GitSignsChange"] = { fg = c.yellow, bg = bg }
  hl["GitSignsDelete"] = { fg = c.red,    bg = bg }
  hl["DiffAdd"]    = { fg = c.green,  bg = c.darker_bg }
  hl["DiffChange"] = { fg = c.yellow, bg = c.darker_bg }
  hl["DiffDelete"] = { fg = c.red,    bg = c.darker_bg }
  hl["DiffText"]   = { fg = c.orange, bg = c.darker_bg }

  -- ── Telescope ─────────────────────────────────────────────────────────────
  hl["TelescopeNormal"]       = { fg = c.fg, bg = bg }
  hl["TelescopeBorder"]       = { fg = c.lighter_bg, bg = bg }
  hl["TelescopePromptNormal"] = { fg = c.fg, bg = c.dark_bg }
  hl["TelescopePromptBorder"] = { fg = c.dark_bg, bg = c.dark_bg }
  hl["TelescopePromptTitle"]  = { fg = c.bg, bg = c.accent }
  hl["TelescopePreviewTitle"] = { fg = c.bg, bg = c.green }
  hl["TelescopeResultsTitle"] = { fg = c.dark_bg, bg = c.dark_bg }
  hl["TelescopeSelection"]    = { bg = c.selection }
  hl["TelescopeMatching"]     = { fg = c.orange, bold = true }

  -- ── Snacks.nvim (explorer / picker) ───────────────────────────────────────
  hl["SnacksNormal"]       = { fg = c.fg, bg = bg }
  hl["SnacksNormalNC"]     = { fg = c.fg, bg = bg }
  hl["SnacksWinBar"]       = { fg = c.dark_fg, bg = bg }
  hl["SnacksWinBarNC"]     = { fg = c.muted, bg = bg }
  hl["SnacksWinSeparator"] = { fg = c.lighter_bg, bg = bg }
  hl["SnacksTitle"]        = { fg = c.accent, bold = true }
  hl["SnacksFooter"]       = { fg = c.muted, bg = bg }
  hl["SnacksBackdrop"]     = { bg = bg }

  -- ── NeoTree ───────────────────────────────────────────────────────────────
  hl["NeoTreeNormal"]       = { fg = c.fg, bg = bg_sidebar }
  hl["NeoTreeNormalNC"]     = { fg = c.fg, bg = bg_sidebar }
  hl["NeoTreeEndOfBuffer"]  = { fg = c.darker_bg, bg = bg_sidebar }
  hl["NeoTreeRootName"]     = { fg = c.accent, bold = true }
  hl["NeoTreeDirectoryName"]= { fg = c.blue }
  hl["NeoTreeDirectoryIcon"]= { fg = c.blue }
  hl["NeoTreeFileName"]     = { fg = c.fg }
  hl["NeoTreeGitAdded"]     = { fg = c.green }
  hl["NeoTreeGitModified"]  = { fg = c.yellow }
  hl["NeoTreeGitDeleted"]   = { fg = c.red }
  hl["NeoTreeGitUntracked"] = { fg = c.orange }
  hl["NeoTreeGitIgnored"]   = { fg = c.muted }
  hl["NeoTreeIndentMarker"] = { fg = c.lighter_bg }
  hl["NeoTreeWinSeparator"] = { fg = c.lighter_bg, bg = bg }
  hl["NeoTreeFloatBorder"]  = { fg = c.lighter_bg, bg = bg_float }

  -- ── NvimTree ──────────────────────────────────────────────────────────────
  hl["NvimTreeNormal"]      = { fg = c.fg, bg = bg_sidebar }
  hl["NvimTreeNormalNC"]    = { fg = c.fg, bg = bg_sidebar }
  hl["NvimTreeEndOfBuffer"] = { fg = c.darker_bg, bg = bg_sidebar }
  hl["NvimTreeRootFolder"]  = { fg = c.accent, bold = true }
  hl["NvimTreeFolderName"]  = { fg = c.blue }
  hl["NvimTreeFolderIcon"]  = { fg = c.blue }
  hl["NvimTreeGitNew"]      = { fg = c.green }
  hl["NvimTreeGitDirty"]    = { fg = c.yellow }
  hl["NvimTreeGitDeleted"]  = { fg = c.red }
  hl["NvimTreeIndentMarker"]= { fg = c.lighter_bg }

  -- ── Which-key ─────────────────────────────────────────────────────────────
  hl["WhichKey"]          = { fg = c.cyan }
  hl["WhichKeyGroup"]     = { fg = c.purple }
  hl["WhichKeyDesc"]      = { fg = c.blue }
  hl["WhichKeySeparator"] = { fg = c.muted }
  hl["WhichKeyFloat"]     = { bg = c.dark_bg }

  -- ── Indent-blankline ──────────────────────────────────────────────────────
  hl["IblIndent"] = { fg = c.lighter_bg }
  hl["IblScope"]  = { fg = c.accent }

  -- ── nvim-cmp / blink.cmp ──────────────────────────────────────────────────
  hl["CmpItemAbbr"]           = { fg = c.fg }
  hl["CmpItemAbbrDeprecated"] = { fg = c.muted, strikethrough = true }
  hl["CmpItemAbbrMatch"]      = { fg = c.orange, bold = true }
  hl["CmpItemAbbrMatchFuzzy"] = { fg = c.orange }
  hl["CmpItemMenu"]           = { fg = c.muted }
  hl["CmpItemKindFunction"]   = { fg = c.blue }
  hl["CmpItemKindVariable"]   = { fg = c.fg }
  hl["CmpItemKindKeyword"]    = { fg = c.purple }
  hl["CmpItemKindText"]       = { fg = c.green }
  hl["CmpItemKindDefault"]    = { fg = c.dark_fg }

  -- Let user modify / add highlights
  if config.on_highlights then
    config.on_highlights(hl, c)
  end

  -- Apply all highlights
  for group, opts in pairs(hl) do
    h(group, opts)
  end
end

return M
