local component = require("component")
local robot = component.robot
local invControl = component.inventory_controller
local modem = component.modem
local robotUtil = {}
robotUtil.port = 3000
robotUtil.computerPort = 3001
function robotUtil.check(_)
    print("正在回报状态。")
    modem.broadcast(robotUtil.computerPort, true)
end

function robotUtil.place(block)
    local item = nil
    local placed = false
    for i=1, robot.inventorySize() do
        item =  invControl.getStackInInternalSlot(i)
        if item ~= nil then
            if item.label == block and (not placed) then
                print("已找到 " .. block)
                robot.select(i)
                robot.swing(3) --3 is front of the robot
                if not robot.place(3) then
                    print("机器人前方有障碍，或选中的物品不是方块。")
                else
                    print("已放置 " .. block)
                    placed = true
                end
            end
        end
    end
    print(placed and "放置成功。" or "放置失败。")
    modem.broadcast(robotUtil.computerPort, placed)
end


return robotUtil
