local shell = require("shell")
local filesystem = require("filesystem")
local args = shell.parse(...)
local branch, revision = args[1] or "main", args[2]
if #args > 2 or not branch:match("^[%w_][%w._-]*$")
    or (revision and (#revision ~= 40 or not revision:match("^%x+$"))) then
    io.stderr:write("用法：robotSetup [分支名] [40 位提交 SHA]\n")
    return 1
end

local wget = assert(loadfile("/bin/wget.lua"))
local temp = os.tmpname()
local url = "https://gh-proxy.org/https://raw.githubusercontent.com/QwQe308/GTNH_BEE_AUTO_BREED/"
    .. (revision or branch) .. "/BreederTron3000/setup.lua"
local installer
if wget("-fq", url, temp) then
    local file = io.open(temp, "r")
    if file then
        local header = file:read("*l")
        file:close()
        if header == "-- BreederTron3000 versioned installer" then
            installer = loadfile(temp)
        end
    end
end
filesystem.remove(temp)
if not installer then
    io.stderr:write("无法加载指定版本的机器人安装器。\n")
    return 1
end
return installer("--robot", branch, revision)
