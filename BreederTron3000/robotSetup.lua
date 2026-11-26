local shell = require("shell")
local filesystem = require("filesystem")
local args = shell.parse(...)
local scripts = {"lib/robotUtil.lua", "robot.lua"}

local paths = {"lib"}

local function exists(filename)
    return filesystem.exists(shell.getWorkingDirectory() .. "/" .. filename)
end

local repo = "https://gh-proxy.org/https://raw.githubusercontent.com/QwQe308/GTNH_BEE_AUTO_BREED/";
local branch = args[1] or "main"
if #args > 1 or not branch:match("^[%w_][%w._-]*$") then
    io.stderr:write("用法：robotSetup [分支名]，例如 robotSetup test。\n")
    return 1
end

for i = 1, #paths do
    if not filesystem.exists(shell.getWorkingDirectory() .. "/" .. paths[i]) then
        filesystem.makeDirectory(shell.getWorkingDirectory() .. "/" .. paths[i]);
    end
end

for i = 1, #scripts do
    if exists(scripts[i]) then
        filesystem.remove(shell.getWorkingDirectory() .. "/" .. scripts[i]);
    end

    shell.execute(string.format("wget %s%s/BreederTron3000/%s %s", repo, branch, scripts[i], scripts[i]));
end

shell.execute("reboot");
