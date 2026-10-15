local scheme = vim.fn.hostname() == "fedora" and "kanagawa-lotus" or "kanagawa"
local status, _ = pcall(vim.cmd, "colorscheme " .. scheme)
if not status then
	print("Colorscheme not found!")
	return
end
