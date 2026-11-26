local component = require("component")
local event = require("event")
local robot = component.robot
local modem = component.modem
local robotUtil = require("lib.robotUtil")
if robot == nil then
    print("当前设备不是机器人，程序终止。")
    os.exit()
end
if modem == nil then
    print("机器人没有安装无线网卡，程序终止。")
    os.exit()
end
if not modem.isWireless() then
    print("检测到有线网卡，请安装无线网卡。程序终止。")
    os.exit()
end
modem.open(robotUtil.port)
print("已打开端口 " .. robotUtil.port)
while true do
    print("正在等待消息……")
    local _, _, _, _, _, message = event.pull("modem_message")
    if message ~= nil then
        local command, arg = message:match("(%w+) ?([a-zA-Z0-9 ]*)")
        if robotUtil[command] ~= nil then
            print(string.format("正在执行指令 %s，参数为 %s。",command, arg))
            robotUtil[command](arg)
        end
    end
end


