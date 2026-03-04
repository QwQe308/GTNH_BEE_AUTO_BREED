local util = require("lib.utility")
local component = require("component")
local config = require("lib.config")
local shell = require("shell")
local args,flags = shell.parse(...)
local event = require("event")

local programMode = args[1]
local targetBee = args[2]
local convertCount = args[3]
function printUsage()
    print("Usage: BreederTron3000 ProgramMode TargetBee [Flags]|用法：BreederTron3000 程序模式 目标蜜蜂 [标志]")
    print("TargetBee needed in ProgramMode \"breed\" and \"convert\". Imprint mode accepts it as an optional argument|在程序模式\"breed\"和\"convert\"中需要目标蜜蜂。基因压印模式接受它作为可选参数")
    print("Available Modes: breed, imprint, convert|可用模式：breed（育种模式）, imprint（基因压印模式）, convert（（公主蜂）转换模式）")
    print("Supported flags:|支持的标志：")
    print("--noFinalImprint || If used in breed mode the final bee won't have its genes imprinted (in case you want a gene from this bee)|--noFinalImprint || 如果在育种模式下使用，最终的蜜蜂不会进行基因压印（以防你想要这只蜜蜂的基因）")
    print("--swarm || If used in convert mode the conversion will happen to every princess.|--swarm || 如果在（公主蜂）转换模式下使用，转换将对每个公主蜜蜂进行")
    print("--mutatron || If used in breed mode the breeding will utilize mutatron and imprinter. (Setup is complex, refer to the tutorial)|--mutatron || 如果在育种模式下使用，繁殖将使用变异器和基因压印器。（设置复杂，请参考教程）")
end
if programMode == nil then
    print("PROGRAM MODE NOT PROVIDED! TERMINATING!|未提供程序模式！终止程序！")
    printUsage()
    os.exit()
end
if targetBee == nil and programMode:lower() == "breed" then
    print("TARGET BEE NOT PROVIDED! TERMINATING!|未提供目标蜜蜂！终止程序！")
    printUsage()
    os.exit()
end
local breeder = nil
-- The program assumes only one adapter and one transposer is present in the network
local transposer = component.transposer
local modem = nil
if next(component.list("modem")) ~= nil then
    modem = component.modem
end
local robotMode = false
local sideConfig = util.getOrCreateSideConfig()
local acclimatiserConfig = util.getOrCreateAcclimatiserConfig()

if (next(component.list("for_alveary_0")) ~= nil) then
    print("Alveary found!|系统已找到蜂房！")
    breeder = component.for_alveary_0
elseif (next(component.list("tile_for_apiculture_0_name")) ~= nil) then
    print("Apiary found!|系统已找到蜂箱！")
    breeder = component.tile_for_apiculture_0_name
else
    print("Can't find breeder block! Terminating.|找不到可用的蜂箱（或蜂箱组）！终止程序。")
    os.exit()
end


for i=0,5 do
    local size = transposer.getInventorySize(i)
    if size == 9 or size == 12 then
        sideConfig.breeder = i
    end
end

if flags["noFinalImprint"] == true then
    print("------------------------------|------------------------------")
    print(string.format("The program will skip imprinting of the %s bee|程序将跳过 %s 蜜蜂的基因压印", targetBee, targetBee))
    print("------------------------------|------------------------------")
end

if flags["mutatron"] == true then
    if (next(component.list("tile_for_apiculture_0_name")) == nil) then
        print("------------------------------|------------------------------")
        print("Mutatron mode is exclusive to apiary! Terminating.|变异器模式仅限于蜂箱使用！终止程序。")
        print("------------------------------|------------------------------")
        os.exit()
    end
    print("------------------------------|------------------------------")
    print("The program will use the mutatron for breeding.|程序将使用变异器进行育种。")
    print("------------------------------|------------------------------")
end

print("Checking storage for existing bees...|检查存储箱中的现有蜜蜂...")
local beeCount = util.listBeesInStorage(sideConfig)
print("Done!|扫描完成")
if beeCount == nil then
    print("THERE ARE NO BEES! TERMINATING PROGRAM!|存储箱没有蜜蜂！终止程序！")
    os.exit()
end


local princessCount = 0
for _,data in pairs(beeCount) do
    if data["Princess"] ~= nil then
        princessCount = princessCount + data["Princess"]
    end
end
if princessCount == 0 then
    print("There are 0 princesses in storage! Terminating.|存储箱中有没有公主蜂！终止程序。")
    os.exit()
end
print(string.format("Located %d princesses in the storage chest.|在存储箱中找到 %d 个公主蜂。", princessCount, princessCount))

if programMode:lower() == "breed" or programMode:lower() == "imprint" then
    
    print("Populating underpopulated bee pairs...|正在补充蜜蜂配对数量不足的情况...")
    for name,data in pairs(beeCount) do
        if data["Princess"] ~= nil and data["Drone"] ~= nil then
            if data["Drone"] < 16 then
                util.populateBee(name, sideConfig, 16)
            end
        end
    end
end

if programMode:lower() == "breed" then
    local storageSize = transposer.getInventorySize(sideConfig.storage)
    local hasTemplates = transposer.getStackInSlot(sideConfig.storage, storageSize) ~= nil

    if modem == nil or (not modem.isWireless()) then
        print("WARNING: No network card or card isn't wireless!|警告：没有网络卡或网络卡不是无线的！（不使用robot模式可以忽略）")
    else
        print("Wireless network card detected!")
        modem.open(config.port)
        print("Opened port " .. config.port)
        print("Searching for a robot...")
        modem.broadcast(config.robotPort, "check")
        local _, _, _, _, _, message = event.pull(5,"modem_message")
        if message then
            print("Found a robot! Enabling robot mode...")
            robotMode = true
        else
            print("Can't locate any robots! Robot mode will stay disabled.")
        end
    end

    local breedingChain = util.createBreedingChain(targetBee, breeder, sideConfig, beeCount) 
    print("The breeding list:|计划育种列表：")
    for beeName,breedData in pairs(breedingChain) do
        print(beeName)
    end

    while breedingChain[targetBee] ~= nil do
        local bredBee = false
        for beeName,breedData in pairs(breedingChain) do
            if breedData ~= nil then
                local parent1 = breedData.allele1.name
                local parent2 = breedData.allele2.name
                if beeCount[parent1] == nil or beeCount[parent2] == nil then
                    print("Cannot breed " .. beeName .. ". Skipping.|现有蜜蜂无法育种 " .. beeName .. "。跳过并尝试育种其父代种")
                elseif beeCount[parent1].Drone ~= nil and beeCount[parent2].Drone ~= nil then
                    ::retryMutation::
                    if beeCount[parent1].Princess then
                        if beeCount[parent1].Drone < 32 then
                            util.populateBee(parent1, sideConfig, 16)
                        end
                    elseif beeCount[parent2].Princess then
                        if beeCount[parent2].Drone < 32 then
                            util.populateBee(parent2, sideConfig, 16)
                        end
                    else
                            util.convertPrincess(parent1, sideConfig, nil, breeder, acclimatiserConfig)
                            if beeCount[parent1].Drone < 32 then
                                util.populateBee(parent1, sideConfig, 16)
                            end
                    end
                    if flags["mutatron"] == true then
                        local success = util.breedByMutatron(beeName, breedData, sideConfig, breeder, acclimatiserConfig)
                        if not success then
                            print("Failed to breed " .. beeName .. " with the mutatron! Retrying...|使用变异器育种 " .. beeName .. " 失败！重试中...")
                            beeCount = util.listBeesInStorage(sideConfig) -- princess & drone killed, refresh beeCount
                            goto retryMutation
                        end
                    else
                        util.breed(beeName, breedData, sideConfig, robotMode)
                    end
                    if flags["completionist"] == true then
                        print("Your " .. beeName .. " bee is ready! Complete your quest, put the bee back then type ok to proceed!|你的 " .. beeName .. " 蜜蜂已准备就绪！完成你的任务，将蜜蜂放回后输入ok继续！")
                            local ans = io.read()
                            while type(ans) ~= "string" or ans ~= "ok" do
                                print("YOUR " .. beeName .. " bee is ready! Complete your quest, put the bee back then type ok to proceed!|你的 " .. beeName .. " 蜜蜂已准备就绪！完成你的任务，将蜜蜂放回后输入ok继续！")
                                ans = io.read()
                            end
                    end
                    if hasTemplates and (not (beeName == targetBee and flags["noFinalImprint"] == true) and not (beeName ~= targetBee and flags["onlyFinalImprint"] == true)) then
                        while (transposer.getStackInSlot(sideConfig.storage, storageSize) == nil) do
                            print("YOU RAN OUT OF TEMPLATE DRONES! PLEASE PROVIDE MORE!|模板雄蜂用完了！请提供更多！")
                            os.sleep(5)
                        end
                        util.populateBee(beeName, sideConfig, 8)
                        util.imprintFromTemplate(beeName, sideConfig)
                    end
                    util.populateBee(beeName, sideConfig, 32)
                    breedingChain[beeName] = nil
                    bredBee = true
                    print("Updating bee list...|更新蜜蜂列表...")
                    beeCount = util.listBeesInStorage(sideConfig)
                end
            end
        end
        if not bredBee then
            print("Cannot breed any required bee with bees in storage! Aborting.|无法使用存储中的蜜蜂育种任何所需的蜜蜂！中止程序。请尝试先培养其父代种排查原因，可能需要使用如僧侣蜂水生蜂等无法繁殖突变的蜜蜂。")
            os.exit()
        end
    end
elseif programMode:lower() == "imprint" then
    local size = transposer.getInventorySize(sideConfig.storage)
    local templateDrone = transposer.getStackInSlot(sideConfig.storage, size)
    if templateDrone == nil then
        print("PROGRAM IS IN IMPRINT MODE BUT NO TEMPLATE DRONES ARE PRESENT! TERMINATING!")
        os.exit()
    end
    local templateSpecies,_ = util.getItemName(templateDrone)
    if targetBee ~= nil then
        if beeCount[targetBee].Princess == nil then
            util.convertPrincess(targetBee, sideConfig)
        else
            if beeCount[targetBee].Drone < 8 then
                util.populateBee(targetBee, sideConfig, 8)
            end
            if (util.imprintFromTemplate(targetBee, sideConfig, templateDrone.individual.active) == true) then
                util.populateBee(targetBee, sideConfig, 32)
            end
        end
    else
        for name,count in pairs(beeCount) do
            if name == templateSpecies then
                goto continue
            end
            if count.Princess ~= nil and count.Drone ~= nil then
                if count.Drone < 8 then
                    util.populateBee(name, sideConfig, 8)
                end
                if (util.imprintFromTemplate(name, sideConfig, templateDrone.individual.active) == true) then
                    util.populateBee(name, sideConfig, 32)
                end
                beeCount[name] = nil
            end
            ::continue::
        end
        for name,count in pairs(beeCount) do
            if name == templateSpecies then
                goto continue
            end
            if(count.Drone == nil or count.Drone < 16) then
                print(string.format("THERE ARE LESS THAN 16 %s DRONES IN STORAGE. SKIPPING IMPRINT.", name))
                goto continue
            end
            local droneSlot = util.findBeeWithType(name, "Drone", sideConfig)
            local drone = transposer.getStackInSlot(sideConfig.storage, droneSlot)
            if not (util.isGeneticallyEquivalent(drone, templateDrone, templateDrone.individual.active, true)) then
                util.convertPrincess(name, sideConfig)
                util.populateBee(name, sideConfig, 8)
                if (util.imprintFromTemplate(name, sideConfig, templateDrone.individual.active) == true) then
                    util.populateBee(name, sideConfig, 32)
                end
            else
                print(string.format("%s bee already has template genes. skipping.", name))
            end
            ::continue::
        end
    end
    
elseif programMode:lower() == "convert" then
    if convertCount == nil then
        convertCount = 1
    else
        convertCount = math.min(princessCount, tonumber(convertCount))
    end
    if flags["swarm"] == true then
        convertCount = princessCount
    end
    for i=1,convertCount do
        if beeCount[targetBee] == nil or beeCount[targetBee].Drone == nil then
            print(string.format("You don't have the drones to convert a princess to %s!",targetBee))
            os.exit()
        elseif beeCount[targetBee].Drone < config.convertDroneReq then
            print(string.format("You only have %d %s drones. Would you like to proceed anyway? (This could crash the program) Y/N", beeCount[targetBee].Drone, targetBee))
            local ans = io.read()
            if ans ~= nil and ans:upper() == "Y" then
                util.convertPrincess(targetBee, sideConfig, 0, breeder, acclimatiserConfig)
            end
        else
            util.convertPrincess(targetBee, sideConfig, nil, breeder, acclimatiserConfig)
        end
        if beeCount[targetBee].Drone < config.convertDroneReq * 2 then
            util.populateBee(targetBee, sideConfig, 16)
        end
        print("Updating bee count...")
        beeCount = util.listBeesInStorage(sideConfig)
    end
else
    printUsage()
end
