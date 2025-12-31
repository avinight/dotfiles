-- import lualine plugin safely
local status, lualine = pcall(require, "lualine")
if not status then
	return
end

-- get lualine palenight theme
local lualine_palenight = require("lualine.themes.palenight")

-- get lualine nightfly theme
local lualine_nightfly = require("lualine.themes.nightfly")

-- new colors for theme
local new_colors = {
	blue = "#65D1FF",
	green = "#3EFFDC",
	violet = "#FF61EF",
	yellow = "#FFDA7B",
	black = "#000000",
}

-- change palenight theme colors
lualine_palenight.normal.a.bg = new_colors.blue
lualine_palenight.insert.a.bg = new_colors.green
lualine_palenight.visual.a.bg = new_colors.violet
lualine_palenight.command = {
	a = {
		gui = "bold",
		bg = new_colors.yellow,
		fg = new_colors.black, -- black
	},
}

-- change nightfly theme colors
lualine_nightfly.normal.a.bg = new_colors.blue
lualine_nightfly.insert.a.bg = new_colors.green
lualine_nightfly.visual.a.bg = new_colors.violet
lualine_nightfly.command = {
	a = {
		gui = "bold",
		bg = new_colors.yellow,
		fg = new_colors.black, -- black
	},
}

-- configure lualine with modified theme
lualine.setup({
	options = {
		theme = "kanagawa",
		globalstatus = true,
	},
})
