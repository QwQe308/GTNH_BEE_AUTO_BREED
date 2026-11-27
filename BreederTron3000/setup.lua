-- BreederTron3000 versioned installer
local shell = require("shell")
local filesystem = require("filesystem")
local args, flags = shell.parse(...)
local branch, revision = args[1] or "main", args[2]
local robot = flags.robot
local installer = robot and "robotSetup" or "setup"
if #args > 2 or not branch:match("^[%w_][%w._-]*$")
    or (revision and (#revision ~= 40 or not revision:match("^%x+$"))) then
    io.stderr:write("用法：" .. installer .. " [分支名] [40 位提交 SHA]\n")
    return 1
end

local wget = assert(loadfile("/bin/wget.lua"))
local repo = "QwQe308/GTNH_BEE_AUTO_BREED"
local proxy = "https://gh-proxy.org/"
local root = shell.getWorkingDirectory()
local stage = filesystem.concat(root, ".breedertron-install")
local function staged(path)
    return filesystem.concat(stage, path)
end
local function readFile(path)
    local file = assert(io.open(path, "r"))
    local contents = file:read("*a")
    file:close()
    return contents
end

if filesystem.exists(stage) then
    io.stderr:write("发现未清理的安装目录 " .. stage .. "。请先检查其中的旧脚本备份。\n")
    return 1
end
local made, reason = filesystem.makeDirectory(stage)
if not made then
    io.stderr:write("无法创建安装目录：" .. tostring(reason) .. "\n")
    return 1
end

local versionFile = robot and ".breedertron-robot-version" or ".breedertron-version"
local scripts = robot and {"lib/robotUtil.lua", "robot.lua"} or {"lib/config.lua", "lib/utility.lua", "BreederTron3000.lua"}
local changes = {}
local function install()
    if not revision then
        local url = "https://api.github.com/repos/" .. repo .. "/git/ref/heads/" .. branch
        local response = staged("branch.json")
        assert(wget("-fq", url, response) or wget("-fq", proxy .. url, response),
            "无法查询分支版本。可传入该分支的完整提交 SHA。")
        local ref = readFile(response)
        local resolvedRef = ref:match('"ref"%s*:%s*"([^"]+)"')
        revision = ref:match('"sha"%s*:%s*"(%x+)"')
        assert(resolvedRef == "refs/heads/" .. branch and revision and #revision == 40, "无法确认请求的分支版本。")
    end

    print("正在安装 " .. branch .. "，版本 " .. revision)
    local raw = proxy .. "https://raw.githubusercontent.com/" .. repo .. "/" .. revision .. "/BreederTron3000/"
    for index, path in ipairs(scripts) do
        local pathInStage = staged("new-" .. index)
        assert(wget("-q", raw .. path, pathInStage), "下载失败：" .. path)
        assert(readFile(pathInStage):find("%S") and loadfile(pathInStage), "下载的脚本无效：" .. path)
    end
    local version = assert(io.open(staged("new-" .. (#scripts + 1)), "w"))
    local written, writeError = version:write(branch .. " " .. revision .. "\n")
    local closed, closeError = version:close()
    assert(written and closed, writeError or closeError)

    local lib = filesystem.concat(root, "lib")
    if not filesystem.exists(lib) then
        assert(filesystem.makeDirectory(lib))
    end
    for _, path in ipairs(scripts) do
        changes[#changes + 1] = {path = filesystem.concat(root, path)}
    end
    changes[#changes + 1] = {path = filesystem.concat(root, versionFile)}
    for index, change in ipairs(changes) do
        change.backup = staged("old-" .. index)
        if filesystem.exists(change.path) then
            assert(not filesystem.isDirectory(change.path), "脚本路径是目录：" .. change.path)
            assert(filesystem.rename(change.path, change.backup))
            change.saved = true
        end
        assert(filesystem.rename(staged("new-" .. index), change.path))
        change.installed = true
    end

    local oldConfig = changes[1]
    if not robot and oldConfig.saved and readFile(oldConfig.backup) ~= readFile(oldConfig.path) then
        local backup = oldConfig.path .. ".previous"
        local suffix = 1
        while filesystem.exists(backup) do
            backup = oldConfig.path .. ".previous." .. suffix
            suffix = suffix + 1
        end
        assert(filesystem.rename(oldConfig.backup, backup))
        oldConfig.saved = false
        print("上一版脚本配置已备份到 " .. backup)
    end
end

local ok, failure = pcall(install)
local rollbackOK = true
if not ok then
    io.stderr:write("安装失败：" .. tostring(failure) .. "\n")
    for index = #changes, 1, -1 do
        local change = changes[index]
        if change.installed and not filesystem.remove(change.path) then
            rollbackOK = false
        end
        if change.saved and not filesystem.rename(change.backup, change.path) then
            rollbackOK = false
        end
    end
end
if rollbackOK then
    for index = 1, #scripts + 1 do
        filesystem.remove(staged("new-" .. index))
        filesystem.remove(staged("old-" .. index))
    end
    filesystem.remove(staged("branch.json"))
    if not filesystem.remove(stage) then
        io.stderr:write("无法清理安装暂存目录 " .. stage .. "。\n")
    end
else
    io.stderr:write("旧脚本恢复不完整，备份仍在 " .. stage .. "。\n")
end
if not ok then
    return 1
end

print("安装完成。分支 " .. branch .. "，版本 " .. revision)
shell.execute("reboot")
