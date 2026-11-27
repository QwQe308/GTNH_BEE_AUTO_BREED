local component = require("component")
local config = require("config")
local filesystem = require("filesystem")
local event = require("event")
local os = require("os")
local serialization = require("serialization")
local utility = {}
local transposer = component.transposer
local modem = nil
local lastRequirements = nil
if next(component.list("modem")) ~= nil then
    modem = component.modem
end

function utility.createBreedingChain(beeName, breeder, sideConfig, existingBees)
    local startingParents = utility.processBee(beeName, breeder, "目标蜂种")
    if(startingParents == nil) then
        print("找不到该蜂种的亲本！")
        return {}
    end
    if(existingBees[beeName]) then
        print("仓库中已有 " .. beeName .. " 蜂！")
        return {}
    end
    local breedingChain = {[beeName] = startingParents}
    local queue = {[beeName] = startingParents}
    local current = {}

    while next(queue) ~= nil do
        for child,parentPair in pairs(queue) do
            local leftName = parentPair.allele1.name
            local rightName = parentPair.allele2.name
            print("正在处理杂交的迭代种群 " .. child .. "，其父代种群为: " .. leftName .. " 和 " .. rightName)

            local leftParents = utility.processBee(leftName, breeder, child)
            local rightParents = utility.processBee(rightName, breeder, child)

            if leftParents ~= nil then
                print(leftName .. ": " .. leftParents.allele1.name .. " + " .. leftParents.allele2.name)
                current[leftName] = leftParents
            end
            if rightParents ~= nil then
                print(rightName .. ": " .. rightParents.allele1.name .. " + " .. rightParents.allele2.name)
                current[rightName] = rightParents
            end
        end
        queue = {}
        for child,parents in pairs(current) do
            --Skip the bee if it's already present in the breeding chain, the queue or in storage
            if breedingChain[child] == nil and queue[child] == nil and existingBees[child] == nil then
                queue[child] = parents
            end
            if breedingChain[child] == nil and existingBees[child] == nil then
                breedingChain[child] = parents
            end
        end
        current = {}
    end
    return table.unpack({breedingChain,existingBees})
end

function utility.processBee(beeName, breeder, child)
    local parentPairs = breeder.getBeeParents(beeName)
    if #parentPairs == 0 then
        return nil
    elseif #parentPairs == 1 then
        return table.unpack(parentPairs)
    else
        local preference = config.preference[beeName]
        if preference == nil then
            return utility.resolveConflict(beeName, parentPairs, child)
        end
        for _,pair in pairs(parentPairs) do
            if (pair.allele1.name == preference[1] and pair.allele2.name == preference[2]) then
                return pair 
            end
        end
    end
    return nil
end

function utility.resolveConflict(beeName, parentPairs, child)
    local choice = nil

    print("发现蜜蜂重名，请检查NEI确定是蜜蜂种 " .. beeName .. "是以下哪个路线培育上来的  (关于后续" .. child .. " 子代的突变):")
    for i,pair in pairs(parentPairs) do
        print(i .. ": " .. pair.allele1.name .. " + " .. pair.allele2.name)
    end

    while(choice == nil or choice < 1 or choice > #parentPairs) do
        print("请选择正确的突变路线方案")
        choice = io.read("*n")
    end

    print("已选择：" .. parentPairs[choice].allele1.name .. " + " .. parentPairs[choice].allele2.name)
    return parentPairs[choice]
end

function utility.listBeesInStorage(sideConfig)
    local size = transposer.getInventorySize(sideConfig.storage)
    local bees = {}

    for i=1,size do
        local bee = transposer.getStackInSlot(sideConfig.storage, i)
        if bee ~= nil then
            if bee.individual ~= nil and bee.individual.active == nil then
                print(string.format("在第%d个栏位的蜜蜂还没有扫描，正在送去扫描", i))
                safeTransfer(sideConfig.storage, sideConfig.scanner, 64, i, "storage", "scanner")
                while (transposer.getStackInSlot(sideConfig.output, 1) == nil) do
                    os.sleep(1)
                end
                bee = transposer.getStackInSlot(sideConfig.output, 1)
                print("送回存储箱")
                safeTransfer(sideConfig.output, sideConfig.storage, 64, 1, "output", "storage")
            end
            local species,type = utility.getItemName(bee)


            if bees[species] == nil then
                bees[species] = {[type] = bee.size}
            elseif bees[species][type] == nil then
                bees[species][type] = bee.size
            else
                bees[species][type] = bees[species][type] + bee.size
            end
        end
    end
    return bees
end

--Converts a princess to the given bee type
--Assumes bee is scanned (Only scanned bees expose genes)
function utility.convertPrincess(beeName, sideConfig, droneReq, breeder, acclimatiserConfig)
    print("正在将公主蜂转换为 " .. beeName)
    local droneSlot = nil
    local targetGenes = nil
    local princess = transposer.getStackInSlot(sideConfig.breeder, 1)
    local princessSlot = nil
    local princessName = nil
    if princess ~= nil then
        local species,_ = utility.getItemName(princess)
        princessName = species
    end
    if droneReq == nil then
        droneReq = config.convertDroneReq
    end
    local size = transposer.getInventorySize(sideConfig.storage)
    --Since frame slots are slots 10,11,12 for the apiary there is no need to make any offsets

    for i=1,size do
        if droneSlot == nil or princess == nil then
            local bee = transposer.getStackInSlot(sideConfig.storage,i)
            if bee ~= nil then
                local species,type = utility.getItemName(bee)
                if species == beeName and type == "Drone" and bee.size >= droneReq and droneSlot == nil then
                    droneSlot = i
                    targetGenes = bee.individual
                elseif type == "Princess" and princess == nil and species ~= beeName then
                    princess = bee
                    princessSlot = i
                    princessName = species
                end
            end
        end
    end
    if droneSlot == nil then
        print(string.format("找不到雄蜂，或雄蜂数量不足（需要 %d 只）。停止转换。", droneReq))
        return
    end
    if targetGenes == nil or targetGenes.active == nil then
        print("雄蜂尚未扫描，停止转换。")
        return
    end
    if princess == nil then
        print("找不到公主蜂，停止转换。")
        return
    end
    --Insert bees into the apiary
    print("正在将 " .. princessName .. " 公主蜂转换为 " .. beeName)
    --First number is the amount of items transferred, the second is the slot number of the container items are transferred to
    --Move only 1 drone at a time to leave the apiary empty after the cycling is complete (you can't extract from input slots)
    safeTransfer(sideConfig.storage,sideConfig.breeder, 1, droneSlot, "storage", "breeder")
    if princessSlot ~= nil then
        safeTransfer(sideConfig.storage,sideConfig.breeder, 1, princessSlot, "storage", "breeder")
    end

    local princessConverted = false
    while(not princessConverted) do
        --Cycle finished if slot 1 is empty
        if transposer.getStackInSlot(sideConfig.breeder, 1) == nil then
            for i=3,9 do
                local item = transposer.getStackInSlot(sideConfig.breeder,i)
                if item ~= nil then
                    local species,type = utility.getItemName(item)
                    if type == "Drone" and item.size == targetGenes.active.fertility and species == beeName then
                        print("正在扫描公主蜂")
                        princessConverted = utility.checkPrincess(sideConfig) --This call will move the princess to sideConfig.output
                        if (not princessConverted) then
                            print("被转换的公主蜂还不是纯合子，继续压印基因")
                            safeTransfer(sideConfig.output,sideConfig.breeder, 1, 1, "output", "breeder") --Move princess back to input
                            safeTransfer(sideConfig.storage, sideConfig.breeder, 1, droneSlot, "storage", "breeder") --Move drone from storage to breed slot
                        end
                    end
                end
            end
            if(not princessConverted) then
                for i=3,9 do
                    local item = transposer.getStackInSlot(sideConfig.breeder,i)
                    if item ~= nil then
                        local species,type = utility.getItemName(item)
                        if type == "Princess" then
                            safeTransfer(sideConfig.breeder, sideConfig.breeder, 1, i, "breeder", "breeder") --Move princess back to input slot
                            safeTransfer(sideConfig.storage, sideConfig.breeder, 1, droneSlot, "storage", "breeder") --Move drone from storage to breed slot
                        else
                            safeTransfer(sideConfig.breeder, sideConfig.garbage, item.size, i, "breeder", "garbage")
                        end
                    end
                end
            end
        elseif breeder and acclimatiserConfig and acclimatiserConfig.useAcclimatiser then
            utility.adjustToleranceIfNeeded(breeder, sideConfig, acclimatiserConfig)
        end
        os.sleep(1)
    end
    print("完成公主蜂的目标种群转换工作")
    for i=3,9 do --clean up the drones
        local item = transposer.getStackInSlot(sideConfig.breeder, i)
        if item ~= nil then
            safeTransfer(sideConfig.breeder, sideConfig.garbage, item.size, i, "breeder", "garbage")
        end
    end
    safeTransfer(sideConfig.output,sideConfig.storage, 1, 1, "output", "storage")
    print(beeName .. " 公主蜂已移至存储箱。")
    return true
end

local function waitForBeeCycle(sideConfig, breeder, acclimatiserConfig, maximiseTolerance)
    local checkTolerance = breeder and acclimatiserConfig and acclimatiserConfig.useAcclimatiser
    local recoveredDrones
    while not cycleIsDone(sideConfig) do
        if checkTolerance and IsBeeCycleStarted(sideConfig) then
            recoveredDrones = utility.adjustToleranceIfNeeded(breeder, sideConfig, acclimatiserConfig, maximiseTolerance)
            checkTolerance = false
        else
            os.sleep(checkTolerance and maximiseTolerance and 0.05 or 1)
        end
    end
    return recoveredDrones
end

function utility.populateBee(beeName, sideConfig, targetCount, breeder, acclimatiserConfig)
    print("正在繁殖 " .. beeName .. " 的雄蜂，保证种群不会断代.")
    local princessSlot, droneSlot = utility.findPairString(beeName, beeName, sideConfig)
    if(princessSlot == -1 or droneSlot == -1) then
        print("繁殖失败，无法找到纯合子的公主蜂和雄蜂")
        return
    end
    local princess = transposer.getStackInSlot(sideConfig.storage, princessSlot)
    local genes = princess.individual.active
    if genes.fertility == 1 then
        print("该蜂种的繁殖力为 1，无法补充雄蜂。")
        return
    end
    print(beeName .. " 种群的纯合子蜜蜂对已找到")
    --Because the drones in storage are scanned you can only insert 1. the rest will be taken from output of the following cycles
    safeTransfer(sideConfig.storage, sideConfig.breeder, 1, princessSlot, "storage", "breeder")
    safeTransfer(sideConfig.storage, sideConfig.breeder, 1, droneSlot, "storage", "breeder")
    local recoveredCount = 0
    while true do
        local recoveredDrones = waitForBeeCycle(sideConfig, breeder, acclimatiserConfig)
        recoveredCount = recoveredCount + (recoveredDrones and recoveredDrones[beeName] or 0)
        local droneOutput, princessOutput, droneCount
        for i = 3, 9 do
            local candidate = transposer.getStackInSlot(sideConfig.breeder, i)
            local _, beeType = utility.getItemName(candidate)
            if beeType == "Drone" then
                if droneOutput ~= nil then
                    print("程序运行繁育过程中，不应该有蜜蜂已经在蜂箱中，程序终止（请先清空蜂箱，并保证存储箱中没有杂合子再启动程序）")
                    os.exit()
                end
                droneOutput, droneCount = i, candidate.size
            elseif beeType == "Princess" then
                princessOutput = i
            end
        end
        assert(droneOutput ~= nil and princessOutput ~= nil, "未找到繁育产出的公主蜂或雄蜂。")
        local total = recoveredCount + droneCount
        print("繁殖进度: " .. total .. "/" .. targetCount)
        if total >= targetCount then
            break
        end
        safeTransfer(sideConfig.breeder, sideConfig.breeder, 1, droneOutput, "breeder", "breeder")
        safeTransfer(sideConfig.breeder, sideConfig.breeder, 1, princessOutput, "breeder", "breeder")
    end
    print("繁殖雄蜂完成，正在发送 " .. beeName .. " 种的雄蜂进行扫描.")
    for i=3,9 do
        local item = transposer.getStackInSlot(sideConfig.breeder,i)
        if item ~= nil then
            local _,type = utility.getItemName(item)
            if type ~= "Princess" and type ~= "Drone" then
                safeTransfer(sideConfig.breeder,sideConfig.garbage,64,i, "breeder", "garbage")
            else
                safeTransfer(sideConfig.breeder,sideConfig.scanner,64,i, "breeder", "scanner")
            end
        end
    end
    while transposer.getStackInSlot(sideConfig.output, 2) == nil do
        os.sleep(1)
    end
    safeTransfer(sideConfig.output,sideConfig.storage,64,1, "output", "storage")
    safeTransfer(sideConfig.output,sideConfig.storage,64,2, "output", "storage")

    print("扫描完成， " .. beeName .. " 种群的蜜蜂已被送回存储箱")
end


function utility.breed(beeName, breedData, sideConfig, robotMode)
    print("正在尝试杂交 " .. beeName .. " 的蜜蜂.")
    local basePrincessSlot, baseDroneSlot = utility.findPair(breedData, sideConfig)
    if basePrincessSlot == -1 or baseDroneSlot == -1 then
        print("找不到 " .. beeName .. " 蜂的亲本，停止育种。")
        return
    end
    local basePrincess = transposer.getStackInSlot(sideConfig.storage, basePrincessSlot) --In case princess needs to be converted
    local basePrincessSpecies,_ = utility.getItemName(basePrincess)
    local chance = breedData.chance

    local breederSize = transposer.getInventorySize(sideConfig.breeder)
    if(breederSize == 12) then --Apiary exclusive.
        for i=10,12 do
            local frame = transposer.getStackInSlot(sideConfig.breeder,i)
            if frame ~= nil and frame.name == "MagicBees:item.frenziedFrame"then
                chance = math.min(100, chance*10)
            end
        end
    end
    if chance ~= breedData.chance then
        print("检测到会改变突变概率的框架。")
    end
    
    print("本次杂交突变概率：".. breedData.chance .. "%")
    if breederSize == 12 then
        print("实际突变概率: " .. chance .. "%，有概率产生其它非目标种群的突变")
    else
        print("使用蜂箱组时无法确定实际突变概率，可能产生其他品种。")
    end
    local requirements = breedData.specialConditions
    local botPlaced = false
    if next(requirements) ~= nil then
        print("该目标种群的突变有如下特殊要求：")
        for _, req in pairs(requirements) do
            local foundationBlock = req:match("Requires ([a-zA-Z ]+) as a foundation")
            if foundationBlock and req:match("^Requires [a-zA-Z ]+ as a foundation%.?$") then
                print("突变条件：蜂箱下方需要放置 " .. foundationBlock .. " 作为基底。")
            else
                print("突变条件：" .. req)
            end
            if robotMode and foundationBlock ~= nil then
                print("正在让机器人放置：" .. foundationBlock)
                modem.broadcast(config.robotPort, "place " .. foundationBlock)
                os.sleep(0.5)
                local _, _, _, _, _, actionTaken = event.pull("modem_message")
                if actionTaken  == true then
                    print("机器人已放置：" .. foundationBlock)
                    botPlaced = true
                else
                    print("机器人无法放置 " .. foundationBlock .. "，请手动放置。")
                end
            end
        end
        if #requirements == 1 and botPlaced then
            print("机器人已处理全部突变条件，继续育种。")
        else
            --询问用户是否满足条件
            if lastRequirements ~= requirements then
                print("请输入ok以代表你已经确认其满足上述条件，或者输入skip跳过本次育种（然后你自己去其它地方完成该育种）")
                local ans = io.read()
                while type(ans) ~= "string" or ans == "" do
                    print("请输入ok以代表你已经确认其满足上述条件，或者输入skip跳过本次育种（然后你自己去其它地方完成该育种）")
                    ans = io.read()
                end
                if ans == "skip" then
                    print("正在更新蜜蜂列表……")
                    utility.listBeesInStorage(sideConfig)
                    goto skip
                end
                lastRequirements = requirements
            else
                print("你上次已经确认过相同的突变条件，不再向你确认")
            end
        end
    end

    safeTransfer(sideConfig.storage,sideConfig.breeder, 1, basePrincessSlot, "storage", "breeder")
    safeTransfer(sideConfig.storage,sideConfig.breeder, 1, baseDroneSlot, "storage", "breeder")
    local isPure = false
    local isGeneticallyPerfect = false --In this case genetic perfection refers to the bee having the same active and inactive genes
    local messageSent = false --About mutation frames

    local princess = nil
    local princessPureness = 0
    local princessSlot = nil
    local bestDrone = nil
    local bestDronePureness = -1
    local bestDroneSlot = nil
    local scanCount = 0

    while(not isPure) or (not isGeneticallyPerfect) do
        while(not cycleIsDone(sideConfig)) do
            os.sleep(1)
        end
        print("扫描蜜蜂中")
        scanCount = utility.dumpBreeder(sideConfig, true)
        if scanCount == 0 then
            print("蜂箱中的蜜蜂已被取出，请放回一只公主蜂和一只雄蜂。")
            while(not cycleIsDone(sideConfig)) do
                os.sleep(1)
            end
            print("正在继续育种……")
            goto continue
        end
        while(transposer.getStackInSlot(sideConfig.output, scanCount) == nil) do
            os.sleep(1)
        end

        print("分析中")
        princess = nil
        princessPureness = 0
        princessSlot = nil
        bestDrone = nil
        bestDronePureness = -1
        bestDroneSlot = nil
        for i=1,scanCount do
            local item = transposer.getStackInSlot(sideConfig.output, i) --Previous loop ensures the slots aren't empty
            local _,type = utility.getItemName(item)
            if type == "Princess" then
                princessSlot = i
                princess = item
                if item.individual.active.species.name == beeName then
                    princessPureness = princessPureness + 1
                end
                if item.individual.inactive.species.name == beeName then
                    princessPureness = princessPureness + 1
                end
            else
                local dronePureness = 0
                if item.individual.active.species.name == beeName then
                    dronePureness = dronePureness + 1
                end
                if item.individual.inactive.species.name == beeName then
                    dronePureness = dronePureness + 1
                end
                if dronePureness > bestDronePureness then
                    bestDronePureness = dronePureness
                    bestDroneSlot = i
                    bestDrone = item
                end
            end
        end

        if (princessPureness + bestDronePureness) == 4 then
            print("目标蜜蜂的种群信息为纯合子")
            isPure = true
            isGeneticallyPerfect = utility.ensureGeneticEquivalence(princessSlot, bestDroneSlot, sideConfig) --Makes sure all genes are equal. will move genetically equivalent bee to storage
            if not isGeneticallyPerfect then
                print("目标蜜蜂的其它等位基因为杂合子，需要继续繁育提纯")
                safeTransfer(sideConfig.output, sideConfig.breeder, 1, princessSlot, "output", "breeder") --Send princess to breeding slot
                safeTransfer(sideConfig.output, sideConfig.breeder, 1, bestDroneSlot, "output", "breeder") --Send drone to breeding slot
                dumpOutput(sideConfig, scanCount)
            end
        elseif (princessPureness + bestDronePureness) > 0 then
            if (not messageSent) then
                messageSent = true
                print("目标种群已出现")
                print("我们强烈建议您此时拿出带有突变效果的框架，以防该基因消失")
                os.sleep(5)
            end
            local princessSpecies = princess.individual.active.species.name .. "/" .. princess.individual.inactive.species.name
            local droneSpecies = bestDrone.individual.active.species.name .. "/" .. bestDrone.individual.inactive.species.name
            print("正在将" .. princessSpecies .. " 公主蜂和" .. droneSpecies .. " 雄蜂进行杂交")
            safeTransfer(sideConfig.output, sideConfig.breeder, 1, princessSlot, "output", "breeder") --Send princess to breeding slot
            safeTransfer(sideConfig.output, sideConfig.breeder, 1, bestDroneSlot, "output", "breeder") --Send drone to breeding slot
            for i=1,scanCount do --Move the other drones to the garbage container
                safeTransfer(sideConfig.output, sideConfig.garbage, 64, i, "output", "garbage")
            end
        else
            print("目标种群未找到（杂交失败）")
            print("正在搜索备用的雄蜂")
            bestReserveDrone = nil
            bestReserveScore, bestReserveSlot = getBestBreedReserve(beeName, sideConfig)
            if bestReserveSlot ~= nil then
                bestReserveDrone = transposer.getStackInSlot(sideConfig.garbage, bestReserveSlot)
            end
            if bestReserveDrone ~= nil then
                print("已找到备用雄蜂，蜂种纯度：" .. bestReserveScore .. "/" .. "2")
                safeTransfer(sideConfig.garbage, sideConfig.breeder, 1, bestReserveSlot, "garbage", "breeder")
                safeTransfer(sideConfig.output, sideConfig.breeder, 1, princessSlot, "output", "breeder")
                dumpOutput(sideConfig, scanCount)
            else
                print("找不到一个好的备用雄蜂！准备重新从父代种开始杂交。")
                safeTransfer(sideConfig.output,sideConfig.breeder, 1, princessSlot, "output", "breeder") -- Move to breeder for conversion
                for i=1,scanCount do --Get rid of the useless bees
                    safeTransfer(sideConfig.output, sideConfig.garbage, 64, i, "output", "garbage")
                end
                utility.convertPrincess(basePrincessSpecies, sideConfig)
                local otherDroneSlot = utility.findBeeWithType(basePrincessSpecies, "Drone", sideConfig) --other drone species is the same as the base princess species
                local otherDrone = transposer.getStackInSlot(sideConfig.storage, otherDroneSlot)
                if otherDrone.size < 32 then
                    utility.populateBee(basePrincessSpecies, sideConfig, 16)
                end
                messageSent = false
                return utility.breed(beeName, breedData, sideConfig)
            end
        end
        ::continue::
    end
    for i=1,scanCount do
        if i ~= bestDroneSlot and i ~= princessSlot then
            safeTransfer(sideConfig.output,sideConfig.garbage, 64, i, "output", "garbage") --Move irrelevant drones to garbage
        end
    end
    print("育种完成。" .. beeName .. " 公主蜂及其雄蜂已移至存储。")
    ::skip::
end

---breed with mutatron and imprinter
---@param beeName string bee name.
---@param breedData table breedData object.
---@param sideConfig table config object.
---@param breeder table breeder object.
---@param acclimatiserConfig table acclimatiserConfig object.
---@return boolean success true if breeding succeeded or aborted, false means we need a retry
function utility.breedByMutatron(beeName, breedData, sideConfig, breeder, acclimatiserConfig)
    assert(breeder ~= nil, "未检测到蜂箱组件。")
    print("正在使用诱变机培育 " .. beeName .. " 蜂。")
    local basePrincessSlot, baseDroneSlot = utility.findPair(breedData, sideConfig)
    if basePrincessSlot == -1 or baseDroneSlot == -1 then
        print("找不到 " .. beeName .. " 蜂的亲本，停止育种。")
        return true
    end

    if utility.isBeeSpeciesBlacklistedInMutatron(beeName) then
        print("该蜂种无法通过诱变机培育。")
        print("请在其他地方培育该蜂种，再输入 skip 跳过本次育种。")
        local ans = io.read()
        while type(ans) ~= "string" or ans ~= "skip" do
            print("请在其他地方培育该蜂种，再输入 skip 跳过本次育种。")
            ans = io.read()
        end
        print("正在更新蜜蜂列表……")
        utility.listBeesInStorage(sideConfig)

        return true
    end

    safeTransfer(sideConfig.storage,sideConfig.scanner, 1, basePrincessSlot, "storage", "mutatron", config.slot.scanner.Mutatron, true)
    safeTransfer(sideConfig.storage,sideConfig.scanner, 1, baseDroneSlot, "storage", "mutatron", config.slot.scanner.Mutatron, true)
    -- princess and drone transferred to mutatron

    -- wait until mutatron done, transfer queen to breeder
    while transposer.getStackInSlot(sideConfig.output, 1) == nil do
        os.sleep(1)
    end
    if transposer.getStackInSlot(sideConfig.output, 1).name == "gendustry:Waste" then
        print("诱变失败，公主蜂和雄蜂已死亡，可以重试。")
        safeTransfer(sideConfig.output, sideConfig.garbage, 64, 1, "output", "garbage")
        return false
    end
    -- successfuly mutated
    -- still need to check if the bee's gene is dangerous, force to imprint it if so
    -- queen in output#1
    local killed = utility.forceImprintIfNeeded(sideConfig.output, 1, sideConfig)
    if killed then
        print("蜂后在压印时死亡，可以重试。")
        return false
    end

    -- mutation work done, move queen to breeder
    safeTransfer(sideConfig.output, sideConfig.breeder, 64, 1, "output", "breeder")


    local isPure = false
    local isGeneticallyPerfect = false --In this case genetic perfection refers to the bee having the same active and inactive genes

    local princessPureness = 0
    local princessSlot = nil
    local bestDronePureness = -1
    local bestDroneSlot = nil
    local scanCount = 0

    while(not isPure) or (not isGeneticallyPerfect) do
        waitForBeeCycle(sideConfig, breeder, acclimatiserConfig)
        print("扫描蜜蜂中")
        scanCount = utility.dumpBreeder(sideConfig, true)
        if scanCount == 0 then
            print("蜂箱中的蜜蜂已被取出，请放回一只公主蜂和一只雄蜂。")
            waitForBeeCycle(sideConfig, breeder, acclimatiserConfig)
            print("正在继续育种……")
            goto continueMutatron
        end
        while(transposer.getStackInSlot(sideConfig.output, scanCount) == nil) do
            os.sleep(1)
        end

        print("分析中")
        princessPureness = 0
        princessSlot = nil
        bestDronePureness = -1
        bestDroneSlot = nil
        for i=1,scanCount do
            local item = transposer.getStackInSlot(sideConfig.output, i) --Previous loop ensures the slots aren't empty
            local _,type = utility.getItemName(item)
            if type == "Princess" then
                princessSlot = i
                if item.individual.active.species.name == beeName then
                    princessPureness = princessPureness + 1
                end
                if item.individual.inactive.species.name == beeName then
                    princessPureness = princessPureness + 1
                end
            else
                local dronePureness = 0
                if item.individual.active.species.name == beeName then
                    dronePureness = dronePureness + 1
                end
                if item.individual.inactive.species.name == beeName then
                    dronePureness = dronePureness + 1
                end
                if dronePureness > bestDronePureness then
                    bestDronePureness = dronePureness
                    bestDroneSlot = i
                end
            end
        end

        assert(bestDroneSlot ~= nil, "诱变结果异常，未找到预期的纯种蜜蜂。")
        assert(princessSlot ~= nil, "诱变结果异常，未找到预期的纯种蜜蜂。")

        -- princess may still have dangerous genes, check it
        killed = utility.forceImprintIfNeeded(sideConfig.output, princessSlot, sideConfig)
        if killed then
            print("公主蜂在压印时死亡，可以重试。")
            for i=1,scanCount do
                safeTransfer(sideConfig.output,sideConfig.garbage, 64, i, "output", "garbage") --Move all bees to garbage
            end
            return false
        end

        -- get a pure drone, imprint it
        safeTransfer(sideConfig.output, sideConfig.scanner, 64, bestDroneSlot, "output", "imprinter", config.slot.scanner.Imprinter)
        bestDroneSlot = config.slot.output.imprinted
        -- we always output imprinted drones to this slot to prevent some stacking issues
        while transposer.getStackInSlot(sideConfig.output, bestDroneSlot) == nil do
            os.sleep(1)
        end

        if (princessPureness + bestDronePureness) == 4 then
            print("目标蜜蜂的种群信息为纯合子")
            isPure = true
            isGeneticallyPerfect = utility.ensureGeneticEquivalence(princessSlot, bestDroneSlot, sideConfig) --Makes sure all genes are equal. will move genetically equivalent bee to storage
            if not isGeneticallyPerfect then
                print("目标蜜蜂的其它等位基因为杂合子，需要继续繁育提纯")
                safeTransfer(sideConfig.output, sideConfig.breeder, 1, princessSlot, "output", "breeder") --Send princess to breeding slot
                safeTransfer(sideConfig.output, sideConfig.breeder, 1, bestDroneSlot, "output", "breeder") --Send drone to breeding slot
                dumpOutput(sideConfig, scanCount, bestDroneSlot)
            end
        else
            assert(false, "诱变结果异常，未找到预期的纯种蜜蜂。")
        end
        ::continueMutatron::
    end
    for i=1,scanCount do
        if i ~= bestDroneSlot and i ~= princessSlot then
            safeTransfer(sideConfig.output,sideConfig.garbage, 64, i, "output", "garbage") --Move irrelevant drones to garbage
        end
    end
    print("育种完成。" .. beeName .. " 公主蜂及其雄蜂已移至存储。")

    return true
end

function utility.ensureGeneticEquivalence(princessSlot, droneSlot, sideConfig)
    local princess = transposer.getStackInSlot(sideConfig.output,princessSlot)
    local drone = transposer.getStackInSlot(sideConfig.output,droneSlot)
    local targetGenes = princess.individual.active
    local isEquivalent = utility.isGeneticallyEquivalent(princess, drone, princess.individual.active, false)
    if isEquivalent then
        print("目标蜜蜂的所有基因都是纯合子了！")
        safeTransfer(sideConfig.output, sideConfig.storage, 1, princessSlot, "output", "storage")
        safeTransfer(sideConfig.output, sideConfig.storage, 64, droneSlot, "output", "storage")
        return true
    end
    return false
end

local maxTolerance = "BOTH_5"

local function countMaxTolerance(bee)
    if bee == nil then
        return 0
    end
    local count = 0
    for _, genes in ipairs({bee.individual.active, bee.individual.inactive}) do
        if genes.temperatureTolerance == maxTolerance then
            count = count + 1
        end
        if genes.humidityTolerance == maxTolerance then
            count = count + 1
        end
    end
    return count
end

function utility.getImprintTargetGenes(templateGenes, acclimatiserConfig)
    if not (acclimatiserConfig and acclimatiserConfig.useAcclimatiser) then
        return templateGenes
    end
    local target = {}
    for gene, value in pairs(templateGenes) do
        target[gene] = value
    end
    target.temperatureTolerance = maxTolerance
    target.humidityTolerance = maxTolerance
    return target
end

function utility.imprintFromTemplate(beeName, sideConfig, templateGenes, breeder, acclimatiserConfig)
    print("正在将模板基因压印到 " .. beeName .. " 蜂。")
    local size = transposer.getInventorySize(sideConfig.storage)

    local templateDrone = transposer.getStackInSlot(sideConfig.storage, size)
    if templateDrone == nil then
        print("找不到模板雄蜂。请将模板雄蜂放入存储箱最后一格。")
        return false
    end

    local basePrincessSlot, baseDroneSlot = utility.findPairString(beeName, beeName, sideConfig)
    if basePrincessSlot == -1 or baseDroneSlot == -1 then
        print("存储箱缺少该蜂种的公主蜂或雄蜂，停止压印。")
        return false
    end

    local basePrincess = transposer.getStackInSlot(sideConfig.storage, basePrincessSlot)
    local baseDrone = transposer.getStackInSlot(sideConfig.storage, baseDroneSlot)
    if templateGenes == nil then
        templateGenes = templateDrone.individual.active
    end
    local targetGenes = utility.getImprintTargetGenes(templateGenes, acclimatiserConfig)
    local stabiliseTolerance = targetGenes ~= templateGenes
    local pairHasMaxTolerance = stabiliseTolerance and countMaxTolerance(basePrincess) == 4 and countMaxTolerance(baseDrone) == 4
    local stabilisingTolerance = stabiliseTolerance and not pairHasMaxTolerance
    local toleranceCycles = 0

    if (not stabiliseTolerance or pairHasMaxTolerance)
        and utility.isGeneticallyEquivalent(basePrincess, stabiliseTolerance and baseDrone or templateDrone, targetGenes, true) then
        print("该蜂种已有模板基因，跳过压印。")
        return false
    end


    safeTransfer(sideConfig.storage, sideConfig.breeder, 1, basePrincessSlot, "storage", "breeder")
    local useBaseDrone = stabilisingTolerance or (pairHasMaxTolerance and utility.hasTargetGenes(basePrincess, baseDrone, targetGenes))
    safeTransfer(sideConfig.storage, sideConfig.breeder, 1, useBaseDrone and baseDroneSlot or size, "storage", "breeder")
    if not useBaseDrone then
        pairHasMaxTolerance = pairHasMaxTolerance and countMaxTolerance(templateDrone) == 4
    end
    
    local isImprinted = false
    local princess = nil
    local princessScore = 0
    local PrincessSlot = nil
    local bestDrone = nil
    local bestDroneScore = -1
    local bestDroneSlot = nil
    local scanCount = 0

    local bestReserveDrone = nil
    local bestReserveScore = -1
    local bestReserveSlot = nil
    while not isImprinted do
        local scanCount = 0
        local bestDroneTolerance = -1
        princessScore = 0
        princessPureness = 0
        princessSlot = nil
        bestDroneScore = -1
        bestDronePureness = 0
        bestDroneSlot = nil
        scanCount = 0
        waitForBeeCycle(sideConfig, breeder, acclimatiserConfig, stabiliseTolerance and not pairHasMaxTolerance)
        scanCount = utility.dumpBreeder(sideConfig, true)
        if scanCount == 0 then
            print("蜂箱中的蜜蜂已被取出，请放回一只公主蜂和一只雄蜂。")
            print("正在继续育种……")
            goto continue
        end
        print("正在扫描……")
        while transposer.getStackInSlot(sideConfig.output, scanCount) == nil do --Wait for scan finish
            os.sleep(1)
        end
        print("正在评估基因……")
        for i=1,scanCount do
            local bee = transposer.getStackInSlot(sideConfig.output, i) --scanCount guarantees there are bees in these slots
            local _,type = utility.getItemName(bee)
            if type == "Princess" then
                princess = bee
                princessScore = utility.getGeneticScore(bee, targetGenes, basePrincess.individual.active.species, config.geneWeights)
                princessPureness = utility.getBeePureness(beeName, bee)
                princessSlot = i
            else
                local droneScore = utility.getGeneticScore(bee, targetGenes, basePrincess.individual.active.species, config.geneWeights)
                local pureness = utility.getBeePureness(beeName, bee)
                -- Prefer drones of the original species before ranking their four tolerance alleles.
                local droneTolerance = stabilisingTolerance and (pureness * 5 + countMaxTolerance(bee)) or 0
                if droneTolerance > bestDroneTolerance or (droneTolerance == bestDroneTolerance and droneScore > bestDroneScore) then
                    bestDrone = bee
                    bestDroneScore = droneScore
                    bestDroneTolerance = droneTolerance
                    bestDronePureness = pureness
                    bestDroneSlot = i
                end
            end
        end

        pairHasMaxTolerance = stabiliseTolerance and countMaxTolerance(princess) == 4 and countMaxTolerance(bestDrone) == 4
        if stabilisingTolerance and (not pairHasMaxTolerance or princessPureness + bestDronePureness < 4) then
            toleranceCycles = toleranceCycles + 1
            if toleranceCycles >= config.imprintToleranceCycleLimit then
                print("多轮自交后仍未固定温湿度耐受性，已将本轮后代送回存储箱。")
                for i = 1, scanCount do
                    safeTransfer(sideConfig.output, sideConfig.storage, 64, i, "output", "storage")
                end
                return false
            end
            print("正在选配同种后代，继续固定温湿度耐受性。")
            continueImprinting(sideConfig, princessSlot, bestDroneSlot, scanCount)
            goto continue
        end
        if stabilisingTolerance then
            print("温度和湿度耐受性均已固定为全 5，继续压印其余基因。")
            stabilisingTolerance = false
        end

        local geneticSum = princessScore + bestDroneScore
        print("基因评分：" .. geneticSum .. "/" .. config.targetSum*2)
        if (not stabiliseTolerance or pairHasMaxTolerance) and tostring(geneticSum) == tostring(config.targetSum*2) then
            print("基因压印成功。")
            print("正在将原有雄蜂移入杂物箱……")
            utility.dumpDrones(beeName, sideConfig)
            safeTransfer(sideConfig.output, sideConfig.storage, 1, princessSlot, "output", "storage")
            safeTransfer(sideConfig.output, sideConfig.storage, 64, bestDroneSlot, "output", "storage")
            print("基因压印蜜蜂已移至存储箱。")
            dumpOutput(sideConfig, scanCount)
            return true
        end

        if (princessPureness + bestDronePureness) == 4 then
            print("公主蜂和雄蜂均为原品种的纯合子。")
            if utility.hasTargetGenes(princess, bestDrone, targetGenes, stabiliseTolerance) then
                print("现有亲本可繁育出目标基因，继续繁育。")
                continueImprinting(sideConfig, princessSlot, bestDroneSlot, scanCount)
            else
                pairHasMaxTolerance = false
                print("现有亲本无法繁育出目标基因，改用模板雄蜂。")
                while (transposer.getStackInSlot(sideConfig.storage, size) == nil) do
                    print("模板雄蜂已用完，请补充。")
                    os.sleep(5)
                end
                safeTransfer(sideConfig.output, sideConfig.breeder, 1, princessSlot, "output", "breeder")
                safeTransfer(sideConfig.storage, sideConfig.breeder, 1, size, "storage", "breeder") -- Last slot in storage is reserved for template bees.
                for i=1,scanCount do
                    safeTransfer(sideConfig.output, sideConfig.garbage, 64, i, "output", "garbage")
                end
            end

        elseif (princessPureness + bestDronePureness) == 0 then
            pairHasMaxTolerance = false
            print("后代已失去原品种。")
            print("正在查找备用雄蜂……")
            local bestReserveDrone = nil
            local bestReserveScore = -1
            local bestReserveSlot = nil
            bestReserveScore, bestReserveSlot = getBestReserve(beeName, sideConfig, targetGenes)
            if bestReserveSlot ~= nil then
                bestReserveDrone = transposer.getStackInSlot(sideConfig.garbage, bestReserveSlot)
            end
            if bestReserveDrone ~= nil then
                print("已找到备用雄蜂，基因评分：" .. bestReserveScore .. "/" .. config.targetSum)
                safeTransfer(sideConfig.garbage, sideConfig.breeder, 1, bestReserveSlot, "garbage", "breeder")
                safeTransfer(sideConfig.output, sideConfig.breeder, 1, princessSlot, "output", "breeder")
                dumpOutput(sideConfig, scanCount)
            else
                print("找不到备用雄蜂，改用原品种的雄蜂。")
                safeTransfer(sideConfig.output, sideConfig.breeder, 1, princessSlot, "output", "breeder")
                if (safeTransfer(sideConfig.storage, sideConfig.breeder, 1, baseDroneSlot, "storage", "breeder") == 0) then
                    print("原品种的雄蜂已用完，程序终止。")
                    os.exit()
                end
                dumpOutput(sideConfig, scanCount)
            end
        elseif (princessPureness + bestDronePureness) == 1 then
            print("后代可能失去原品种。")
            continueImprinting(sideConfig, princessSlot, bestDroneSlot, scanCount)
        else
            continueImprinting(sideConfig, princessSlot, bestDroneSlot, scanCount)
        end
        ::continue::
    end
    return true
end

function getBestReserve(beeName, sideConfig, targetGenes)
    local reserveSize = transposer.getInventorySize(sideConfig.garbage)
    local bestReserveScore = -1
    local bestReserveSlot = nil
    local nilCounter = 0
    for i=1,reserveSize do
        local bee = transposer.getStackInSlot(sideConfig.garbage, i)
        if bee == nil then
            nilCounter = nilCounter + 1
            if nilCounter > 10 then
                return table.unpack({bestReserveScore, bestReserveSlot})
            end
        else
            if bee.individual == nil or bee.individual.active == nil then
                goto continue
            end
            if bee.individual.active ~= nil then
                local score = -1
                if bee.individual.active.species.name == beeName then
                    score = utility.getGeneticScore(bee, targetGenes, bee.individual.active.species, config.geneWeights)
                elseif bee.individual.inactive.species.name == beeName then
                    score = utility.getGeneticScore(bee, targetGenes, bee.individual.inactive.species, config.geneWeights)
                end
                if score > bestReserveScore then
                    bestReserveScore = score
                    bestReserveSlot = i
                end
            end
        end
        ::continue::
    end
    if bestReserveSlot ~= nil and transposer.getStackInSlot(sideConfig.garbage, bestReserveSlot) == nil then
        print("选中的备用雄蜂已被移走，正在重新查找……")
        return getBestReserve(beeName, sideConfig, targetGenes, config.geneWeights)
    end
    return table.unpack({bestReserveScore, bestReserveSlot})
end

function getBestBreedReserve(beeName, sideConfig)
    local bestReserveScore = 0
    local bestReserveSlot = nil
    local nilCounter = 0
    local reserveSize = transposer.getInventorySize(sideConfig.garbage)

    for i=1,reserveSize do
        local bee = transposer.getStackInSlot(sideConfig.garbage, i)
        if bee == nil then
            nilCounter = nilCounter + 1
            if nilCounter > 10 then
                return table.unpack({bestReserveScore, bestReserveSlot})
            end
        else
            if bee.individual == nil or bee.individual.active == nil then
                goto continue
            end
            if bee.individual.active ~= nil then
                local score = 0
                if bee.individual.active.species.name == beeName then
                    score = score + 1
                end
                if bee.individual.inactive.species.name == beeName then
                    score = score + 1
                end
                if score > bestReserveScore then
                    bestReserveScore = score
                    bestReserveSlot = i
                end
            end
        end
        ::continue::
    end
    if bestReserveSlot ~= nil and transposer.getStackInSlot(sideConfig.garbage, bestReserveSlot) == nil then
        print("选中的备用雄蜂已被移走，正在重新查找……")
        return getBestReserve(beeName, sideConfig, targetGenes, config.geneWeights)
    end
    return table.unpack({bestReserveScore, bestReserveSlot})
end

function utility.dumpDrones(beeName, sideConfig)
    local storageSize = transposer.getInventorySize(sideConfig.storage)
    for i=1,storageSize do
        local bee = transposer.getStackInSlot(sideConfig.storage, i)
        if bee ~= nil then
            local species = utility.getItemName(bee)
            if species == beeName then
                safeTransfer(sideConfig.storage, sideConfig.garbage, 64, i, "storage", "garbage")
            end
        end
    end
end
function continueImprinting(sideConfig, princessSlot, droneSlot, scanCount)
    safeTransfer(sideConfig.output, sideConfig.breeder, 1, princessSlot, "output", "breeder")
    safeTransfer(sideConfig.output, sideConfig.breeder, 1, droneSlot, "output", "breeder")
    dumpOutput(sideConfig, scanCount)
end

function dumpOutput(sideConfig, scanCount, additionalSlot)
    for i=1,scanCount do
        safeTransfer(sideConfig.output, sideConfig.garbage, 64, i, "output", "garbage")
    end
    if additionalSlot then
        safeTransfer(sideConfig.output, sideConfig.garbage, 64, additionalSlot, "output", "garbage")
    end
end
function utility.hasTargetGenes(princess, drone, targetGenes, adjustTolerance)
    for gene, value in pairs(targetGenes) do
        if gene == "species" or (adjustTolerance and (gene == "temperatureTolerance" or gene == "humidityTolerance")) then
        elseif type(value) == "table" then
            for tName, tValue in pairs(value) do
                if princess.individual.active[gene][tName] ~= tValue and drone.individual.active[gene][tName] ~= tValue and 
                    princess.individual.inactive[gene][tName] ~= tValue and drone.individual.inactive[gene][tName] ~= tValue then
                    return false
                end
            end
        else
            if princess.individual.active[gene] ~= value and princess.individual.inactive[gene] ~= value and
                drone.individual.active[gene] ~= value and drone.individual.inactive[gene] ~= value then
                return false
            end
        end
    end
    return true
end
function utility.getBeePureness(beeName, bee)
    local pureness = 0
    if bee.individual.active.species.name == beeName then
        pureness = pureness + 1
    end
    if bee.individual.inactive.species.name == beeName then
        pureness = pureness + 1
    end
    return pureness
end
function utility.getGeneticScore(bee, targetGenes, speciesTarget, weightTable)
    local geneticScore = 0
    for gene, value in pairs(targetGenes) do
        local weight = weightTable[gene]
        local bonusExp = 1
        if gene == "species" then
            bonusExp = 0
            value = speciesTarget
        end
        if weight ~= nil then
            if type(value) == "table" then
                local matchesActive = true
                local matchesInactive = true
                for tName, tValue in pairs(value) do
                    if bee.individual.active[gene][tName] ~= tValue then
                        matchesActive = false
                    end
                    if bee.individual.inactive[gene][tName] ~= tValue then
                        matchesInactive = false
                    end
                end
                if matchesActive then
                    geneticScore = geneticScore + weight*(config.activeBonus^bonusExp)
                end
                if matchesInactive then
                    geneticScore = geneticScore + weight
                end
            else
                if bee.individual.active[gene] == value then
                    geneticScore = geneticScore + weight*(config.activeBonus^bonusExp)
                end
                if bee.individual.inactive[gene] == value then
                    geneticScore = geneticScore + weight
                end
            end
        end
    end
    return geneticScore
end
function utility.dumpBreeder(sideConfig, scanDrones)
    local dumpedBees = 0
    for i=3,9 do
        local item = transposer.getStackInSlot(sideConfig.breeder, i)
        if item ~= nil then
            local name,type = utility.getItemName(item)
            if type ~= "Princess" and type ~= "Drone" then
                safeTransfer(sideConfig.breeder, sideConfig.garbage, 64, i, "breeder", "garbage")
            else
                if scanDrones or type == "Princess" then
                    dumpedBees = dumpedBees + 1
                    safeTransfer(sideConfig.breeder, sideConfig.scanner, 64, i, "breeder", "scanner")
                else
                    safeTransfer(sideConfig.breeder, sideConfig.garbage, 64, i, "breeder", "garbage")
                end
            end
        end
    end
    return dumpedBees
end
function utility.isGeneticallyEquivalent(princess, drone, targetGenes, omitSpecies)
    for gene, value in pairs(targetGenes) do
        if gene == "species" and omitSpecies then
        elseif type(value) == "table" then
            for tName, tValue in pairs(value) do
                if princess.individual.active[gene][tName] ~= tValue then
                    return false
                end
                if princess.individual.inactive[gene][tName] ~= tValue then
                    return false
                end
                if drone.individual.active[gene][tName] ~= tValue then
                    return false
                end
                if drone.individual.inactive[gene][tName] ~= tValue then
                    return false
                end
            end
        else
            if princess.individual.active[gene] ~= value then
                return false
            end
            if princess.individual.inactive[gene] ~= value then
                return false
            end
            if drone.individual.active[gene] ~= value then
                return false
            end
            if drone.individual.inactive[gene] ~= value then
                return false
            end
        end
    end
    return true
end

function utility.findBeeWithType(targetName, targetType, sideConfig)
    local size = transposer.getInventorySize(sideConfig.storage)
    for i=1,size do
        local item = transposer.getStackInSlot(sideConfig.storage,i)
        if item ~= nil then
            local species, type = utility.getItemName(item)
            if type == targetType and species == targetName then
                return i
            end
        end
    end
    return -1
end

--Takes the table from getBeeParents() 
function utility.findPair(pair, sideConfig)
    local size = transposer.getInventorySize(sideConfig.storage)
    local princess1 = nil
    local princess2 = nil
    local drone1 = nil
    local drone2 = nil

    for i=1,size do
        local item = transposer.getStackInSlot(sideConfig.storage,i)
        if item ~= nil then
            local species, type = utility.getItemName(item)
            if type == "Drone" then
                if species == pair.allele1.name then
                    drone1 = i
                end
                if species == pair.allele2.name then
                    drone2 = i
                end
            end
            if type == "Princess" then
                if species == pair.allele1.name then
                    princess1 = i
                end
                if species == pair.allele2.name then
                    princess2 = i
                end
            end
        end
        if princess1 and drone2 then
            return table.unpack({princess1, drone2})
        end
        if princess2 and drone1 then
            return table.unpack({princess2, drone1})
        end
    end
    return table.unpack({-1,-1})
end

function utility.findPairString(bee1, bee2, sideConfig)
    local size = transposer.getInventorySize(sideConfig.storage)
    local princess1 = nil
    local princess2 = nil
    local drone1 = nil
    local drone2 = nil

    for i=1,size do
        local item = transposer.getStackInSlot(sideConfig.storage,i)
        if item ~= nil then
            local species, type = utility.getItemName(item)
            if type == "Drone" then
                if species == bee1 then
                    drone1 = i
                end
                if species == bee2 then
                    drone2 = i
                end
            end
            if type == "Princess" then
                if species == bee1 then
                    princess1 = i
                end
                if species == bee2 then
                    princess2 = i
                end
            end
        end
        if princess1 and drone2 then
            return table.unpack({princess1, drone2})
        end
        if princess2 and drone1 then
            return table.unpack({princess2, drone1})
        end
    end
    return table.unpack({-1,-1})
end

---get bee name and type from ItemStack; returns (nil, nil) if the item is not a bee
---@param bee ItemStack the bee
---@return string|nil species, string|nil type type could be "Princess", "Drone", or "Queen"
function utility.getItemName(bee)
--TODO: 
    -- it is better to return bee uid, but this breaks info display

    -- not a bee
    if bee == nil or bee.individual == nil then
        return nil, nil
    end

    local species = bee.individual.displayName

    local type = nil
    if bee.name == "Forestry:beeQueenGE" then
        type = "Queen"
    elseif bee.name == "Forestry:beePrincessGE" then
        type = "Princess"
    elseif bee.name == "Forestry:beeDroneGE" then
        type = "Drone"
    end

    return species, type
end

function utility.checkPrincess(sideConfig)
    for i=3,9 do
        local item = transposer.getStackInSlot(sideConfig.breeder,i)
        if item ~= nil then
            local species,type = utility.getItemName(item)
            if type == "Princess" then
                safeTransfer(sideConfig.breeder,sideConfig.scanner, 1, i, "breeder", "scanner")
                while transposer.getStackInSlot(sideConfig.output, 1) == nil do
                    os.sleep(1)
                end
                local princess = transposer.getStackInSlot(sideConfig.output, 1)
                return utility.areGenesEqual(princess.individual)
            end
        end
    end
    return false
end

function utility.areGenesEqual(geneTable)
    for gene,value in pairs(geneTable.active) do
        if type(value) == "table" then
            for name,tValue in pairs(value) do
                if geneTable.inactive[gene][name] ~= tValue then
                    return false
                end
            end
        elseif value ~= geneTable.inactive[gene] then
            return false
        end
    end
    return true
end


local containerNames = {
    ["storage"] = "存储箱",
    ["scanner"] = "扫描仪输入箱",
    ["output"] = "输出箱",
    ["garbage"] = "杂物箱",
    ["apiaryBreaker"] = "蜂箱拆除装置",
    ["acclimatiserBreaker"] = "调整器拆除装置",
}

function utility.getOrCreateSideConfig()
    if filesystem.exists("/home/sideConfig.lua") then
        local sideConfig = require("sideConfig")
        return sideConfig
    end
    local directionNames = {"下", "上", "北", "南", "西", "东"}
    local directions = {"down","up","north","south","west","east"}
    local remainingDirections = {"down","up","north","south","west","east"}
    local configOrder = {"storage","scanner","output","garbage"}
    local newConfig = {}

    print("首次运行，请配置容器方向。")
    print("以下方向均以转运器为基准。")

    for _,container in pairs(configOrder) do
        print(string.format("请输入%s所在方向的编号：", containerNames[container]))
        for i,direction in pairs(directions) do
            if indexInTable(remainingDirections, direction) ~= 0 then
                print(string.format("%d. %s", i, directionNames[i]))
            end
        end
        local answeredCorrectly = false
        while not answeredCorrectly do
            local answer = io.read("*n")
            if tonumber(answer) ~= nil then
                answer = tonumber(answer)
                if answer >= 1 and answer <= #directions then --Check if answer within bounds
                    newConfig[container] = answer - 1
                    table.remove(remainingDirections, indexInTable(remainingDirections, directions[answer]))
                    answeredCorrectly = true
                end
            else
                local index = indexInTable(directions, string.lower(answer))
                if index ~= 0 then
                    newConfig[container] = index - 1
                    table.remove(remainingDirections, indexInTable(remainingDirections, answer))
                    answeredCorrectly = true
                end
            end
            if not answeredCorrectly then
                print("无法识别输入，请重试。")
            end
        end
    end

    remainingDirections = {"down","up","north","south","west","east"}
    configOrder = {"apiaryBreaker","acclimatiserBreaker"}
    print("请配置红石 I/O 的输出方向。无需使用红石控制时可任选方向。")
    print("以下方向均以红石 I/O 为基准。")
    for _,container in pairs(configOrder) do
        print(string.format("请输入%s所在方向的编号：", containerNames[container]))
        for i,direction in pairs(directions) do
            if indexInTable(remainingDirections, direction) ~= 0 then
                print(string.format("%d. %s", i, directionNames[i]))
            end
        end
        local answeredCorrectly = false
        while not answeredCorrectly do
            local answer = io.read("*n")
            if tonumber(answer) ~= nil then
                answer = tonumber(answer)
                if answer >= 1 and answer <= #directions then --Check if answer within bounds
                    newConfig[container] = answer - 1
                    table.remove(remainingDirections, indexInTable(remainingDirections, directions[answer]))
                    answeredCorrectly = true
                end
            else
                local index = indexInTable(directions, string.lower(answer))
                if index ~= 0 then
                    newConfig[container] = index - 1
                    table.remove(remainingDirections, indexInTable(remainingDirections, answer))
                    answeredCorrectly = true
                end
            end
            if not answeredCorrectly then
                print("无法识别输入，请重试。")
            end
        end
    end

    print("正在创建 sideConfig.lua……")
    local file = filesystem.open("/home/sideConfig.lua", "w")
    file:write("local sideConfig = {\n")
    for container,side in pairs(newConfig) do
        file:write(string.format("[\"%s\"] = %d, \n", container, side))
    end
    file:write("}\n")
    file:write("return sideConfig")
    file:close()
    print("配置完成。")
    return newConfig
end

function utility.getOrCreateAcclimatiserConfig()
    if filesystem.exists("/home/acclimatiserConfig.lua") then
        local acclimatiserConfig = require("acclimatiserConfig")
        return acclimatiserConfig
    end
    local newConfig = {}

    print("首次运行，请配置适应性调整器。")
    print("是否使用适应性调整器调整湿度和温度耐受性？输入 y 确认或 n 取消。")
    local getUseAcclimatiser = function ()
        local answer = nil
        while answer == nil do
            answer = io.read("*l")
            if string.lower(answer) ~= "y" and string.lower(answer) ~= "n" then
                print("输入无效，请输入 y 或 n。")
                answer = nil
            end
        end
        return string.lower(answer) == "y"
    end

    newConfig.useAcclimatiser = getUseAcclimatiser()

    print("请查看蜂箱所处环境的湿度和温度，再输入对应的数字。")
    -- humidity
    local function getHumidity()
        local answer = nil
        while answer == nil do
            print("请选择蜂箱环境湿度：")
            print("干燥：-1")
            print("普通：0")
            print("潮湿：1")
            answer = io.read("*n")
            if answer < -1 or answer > 1 then
                print("输入无效。")
                answer = nil
            end
        end
        return answer
    end
    
    local function getTemperature()
        local answer = nil
        while answer == nil do
            print("请选择蜂箱环境温度：")
            print("冰冷：-2")
            print("寒冷：-1")
            print("无：0")
            print("普通：0")
            print("温暖：1")
            print("炎热：2")
            print("地狱：3")
            answer = io.read("*n")
            if answer < -2 or answer > 3 then
                print("输入无效。")
                answer = nil
            end
        end
        return answer
    end

    local function getTimeout()
        local answer = nil
        while answer == nil do
            print("请输入适应性调整器的超时秒数：")
            print("超时后将拆除调整器以取回蜂后。")
            answer = io.read("*n")
            if answer < 0 then
                print("输入无效。")
                answer = nil
            end
        end
        return answer
    end

    newConfig.humidity = getHumidity()
    newConfig.temperature = getTemperature()
    newConfig.timeout = getTimeout()

    print("正在创建 acclimatiserConfig.lua……")
    local file = filesystem.open("/home/acclimatiserConfig.lua", "w")
    file:write("local acclimatiserConfig = {\n")
    file:write(string.format("[\"%s\"] = %s, \n", "useAcclimatiser", newConfig.useAcclimatiser))
    file:write(string.format("[\"%s\"] = %d, \n", "temperature", newConfig.temperature))
    file:write(string.format("[\"%s\"] = %d, \n", "humidity", newConfig.humidity))
    file:write(string.format("[\"%s\"] = %d, \n", "timeout", newConfig.timeout))
    file:write("}\n")
    file:write("return acclimatiserConfig")
    file:close()
    print("配置完成。")
    return newConfig
end
function utility.isBeeSpeciesBlacklistedInMutatron(beeName)
    local blacklist = {
        ["Leporine"] = true,
        ["Merry"] = true,
        ["Tipsy"] = true,
        ["Tricky"] = true,
        ["Chad"] = true,
        ["Cosmic Neutronium"] = true,
        ["Infinity Catalyst"] = true,
        ["Infinity"] = true,
        ["Americium"] = true,
        ["Europium"] = true,
        ["Kevlar"] = true,
        ["Drake"] = true
    }

    return blacklist[beeName] or false
end

--- Get the humidity and temperature range of the queen bee
--- @param queen table The queen object
--- @return table|nil humidityRange The humidity range, containing min and max fields
--- @return table|nil temperatureRange The temperature range, containing min and max fields
function utility.getQueenHumidityAndTemperatureRange(queen)
    if not queen.individual then
        return nil, nil
    end
    queen = queen.individual
    if not queen or not queen.active then
        return nil, nil
    end

    local function parseTolerance(tolerance)
        local upValue = 0
        local downValue = 0
        if tolerance:find("UP") then
            upValue = tonumber(tolerance:match("UP_(%d+)")) or 0
        elseif tolerance:find("DOWN") then
            downValue = tonumber(tolerance:match("DOWN_(%d+)")) or 0
        elseif tolerance:find("BOTH") then
            local bothValue = tonumber(tolerance:match("BOTH_(%d+)")) or 0
            upValue = bothValue
            downValue = bothValue
        end
        return upValue, downValue
    end

    local function parseTemperature(temperature)
        local tempMap = {
            ICY = -2,
            COLD = -1,
            NONE = 0,
            NORMAL = 0,
            WARM = 1,
            HOT = 2,
            HELLISH = 3
        }
        return tempMap[temperature:upper()] or 0
    end

    local function parseHumidity(humidity)
        local humidityMap = {
            ARID = -1,
            NORMAL = 0,
            DAMP = 1
        }
        return humidityMap[humidity:upper()] or 0
    end

    local humidityUp, humidityDown = parseTolerance(queen.active.humidityTolerance)
    local temperatureUp, temperatureDown = parseTolerance(queen.active.temperatureTolerance)
    local baseHumidity = parseHumidity(queen.active.species.humidity)
    local baseTemperature = parseTemperature(queen.active.species.temperature)

    local humidityRange = {
        min = baseHumidity - humidityDown,
        max = baseHumidity + humidityUp
    }

    local temperatureRange = {
        min = baseTemperature - temperatureDown,
        max = baseTemperature + temperatureUp
    }

    return humidityRange, temperatureRange
end

local function storeRecoveredBee(sideConfig, outputSlot, count)
    local templateSlot = transposer.getInventorySize(sideConfig.storage)
    while count > 0 do
        for slot = 1, templateSlot - 1 do
            count = count - transposer.transferItem(sideConfig.output, sideConfig.storage, count, outputSlot, slot)
            if count == 0 then
                return
            end
        end
        if transposer.getStackInSlot(sideConfig.output, outputSlot) == nil then
            return
        end
        print("存储箱没有足够空间收回留种蜜蜂，请腾出空位。")
        os.sleep(1)
    end
end

local function findRecoveredQueen(sideConfig, recovery)
    local queenSlot
    local pendingScan = false
    for slot = 1, transposer.getInventorySize(sideConfig.output) do
        local item = transposer.getStackInSlot(sideConfig.output, slot)
        if item then
            local species, beeType = utility.getItemName(item)
            if beeType == "Queen" then
                queenSlot = queenSlot or slot
            elseif (beeType == "Drone" or beeType == "Princess") and (not item.individual.active or not item.individual.inactive) then
                local key = item.name .. (species or "")
                local moved = transposer.transferItem(sideConfig.output, sideConfig.scanner, item.size, slot, 1)
                if moved > 0 then
                    recovery.scans[key] = (recovery.scans[key] or 0) + moved
                end
                pendingScan = true
            else
                if beeType == "Drone" or beeType == "Princess" then
                    local key = item.name .. (species or "")
                    local pending = recovery.scans[key]
                    if pending then
                        recovery.scans[key] = pending > item.size and pending - item.size or nil
                    end
                end
                local keep = beeType == "Princess" or (beeType == "Drone" and utility.areGenesEqual(item.individual))
                if keep then
                    local count = item.size
                    storeRecoveredBee(sideConfig, slot, count)
                    if beeType == "Drone" and species then
                        recovery.drones[species] = (recovery.drones[species] or 0) + count
                    end
                else
                    repeat
                        safeTransfer(sideConfig.output, sideConfig.garbage, item.size, slot, "output", "garbage")
                        item = transposer.getStackInSlot(sideConfig.output, slot)
                    until item == nil
                end
            end
        end
    end
    return queenSlot, pendingScan or next(recovery.scans) ~= nil
end

local function waitForQueenOutput(sideConfig, recovery, timeout)
    local elapsedSeconds = 0
    while true do
        local slot, pendingScan = findRecoveredQueen(sideConfig, recovery)
        if slot and not pendingScan then
            return slot
        end
        if not slot and timeout and elapsedSeconds >= timeout then
            print("等待适应性调整器超时，正在触发拆除装置以取回蜂后。")
            component.redstone.setOutput(sideConfig.acclimatiserBreaker, 15)
            os.sleep(config.blockBreakerRedstoneInterval)
            component.redstone.setOutput(sideConfig.acclimatiserBreaker, 0)
            timeout = nil
        end
        os.sleep(1)
        elapsedSeconds = elapsedSeconds + 1
    end
end

local function adjustQueenTolerance(sideConfig, acclimatiserConfig, gene, machineSlot, machineName, isReady, maximiseTolerance, recovery)
    local pendingSlot = config.slot.scanner.ToBeAcc
    local attempts = 0
    while true do
        local queen = transposer.getStackInSlot(sideConfig.scanner, pendingSlot)
        if maximiseTolerance then
            if queen.individual.active[gene] == maxTolerance then
                return true
            end
            if attempts >= config.imprintToleranceAdjustmentLimit then
                return false
            end
        elseif isReady(queen) then
            return true
        end

        safeTransfer(sideConfig.scanner, sideConfig.scanner, 1, pendingSlot, "scanner", machineName, machineSlot)
        local queenSlot = waitForQueenOutput(sideConfig, recovery, acclimatiserConfig.timeout)
        safeTransfer(sideConfig.output, sideConfig.scanner, 1, queenSlot, "output", "ToBeAcc", pendingSlot)
        attempts = attempts + 1
    end
end

function utility.adjustToleranceIfNeeded(breeder, sideConfig, acclimatiserConfig, maximiseTolerance)
    if not IsBeeCycleStarted(sideConfig) or (not maximiseTolerance and breeder.canBreed()) then
        return
    end
    local recovery = {drones = {}, scans = {}}
    local pendingSlot = config.slot.scanner.ToBeAcc
    if maximiseTolerance then
        print("正在检查蜂后的温湿度全 5 耐受基因……")
    else
        print("蜂后无法繁育，正在检查温湿度耐受性……")
    end

    print("正在触发拆除装置，从蜂箱取回蜂后。")
    component.redstone.setOutput(sideConfig.apiaryBreaker, 15)
    os.sleep(config.blockBreakerRedstoneInterval)
    component.redstone.setOutput(sideConfig.apiaryBreaker, 0)
    os.sleep(config.blockBreakerRedstoneInterval)
    local queenSlot = waitForQueenOutput(sideConfig, recovery)
    safeTransfer(sideConfig.output, sideConfig.scanner, 1, queenSlot, "output", "ToBeAcc", pendingSlot)

    local bee = transposer.getStackInSlot(sideConfig.scanner, pendingSlot)
    if bee.individual ~= nil and bee.individual.active == nil then
        print("蜂后尚未扫描，正在送往扫描仪。")
        safeTransfer(sideConfig.scanner, sideConfig.scanner, 1, pendingSlot, "ToBeAcc", "scanner", 1)
        queenSlot = waitForQueenOutput(sideConfig, recovery)
        safeTransfer(sideConfig.output, sideConfig.scanner, 1, queenSlot, "output", "ToBeAcc", pendingSlot)
    end
    local temperatureOK = adjustQueenTolerance(sideConfig, acclimatiserConfig, "temperatureTolerance",
        config.slot.scanner.TempAcc, "T+-Acc", function(queen)
            local _, range = utility.getQueenHumidityAndTemperatureRange(queen)
            assert(range ~= nil, "无法读取蜂后的温度耐受范围。")
            return range.min <= acclimatiserConfig.temperature and acclimatiserConfig.temperature <= range.max
        end, maximiseTolerance, recovery)
    local humidityOK = adjustQueenTolerance(sideConfig, acclimatiserConfig, "humidityTolerance",
        config.slot.scanner.HumAcc, "H+-Acc", function(queen)
            local range = utility.getQueenHumidityAndTemperatureRange(queen)
            assert(range ~= nil, "无法读取蜂后的湿度耐受范围。")
            return range.min <= acclimatiserConfig.humidity and acclimatiserConfig.humidity <= range.max
        end, maximiseTolerance, recovery)

    -- finally we put the queen back to the breeder
    print("调整后的蜂后已移至蜂箱。")
    local _, pendingScan = findRecoveredQueen(sideConfig, recovery)
    while pendingScan do
        os.sleep(1)
        _, pendingScan = findRecoveredQueen(sideConfig, recovery)
    end
    safeTransfer(sideConfig.scanner, sideConfig.breeder, 1, pendingSlot, "scanner", "breeder")

    if not (temperatureOK and humidityOK) then
        error("调整器未能将温湿度耐受性提升到全 5。蜂后已放回蜂箱，请检查双向耗材和超时设置。", 0)
    end
    if (not breeder.canBreed()) and transposer.getStackInSlot(sideConfig.breeder, 1) ~= nil then
        print("警告：蜂后调整耐受性后仍无法繁育，请检查蜂后和蜂箱环境。")
    end
    return recovery.drones
end

---check if we should imprint the bee immediately.
---assumes bee in the side#slot. if success, the bee will still be in side#slot. otherwise waste in garbage.
---@param containerSide integer container side
---@param containerSlot integer slot number
---@param sideConfig table sideConfig object
---@return boolean killed true if the bee killed by imprinter
function utility.forceImprintIfNeeded(containerSide, containerSlot, sideConfig)
    safeTransfer(containerSide, sideConfig.scanner, 64, containerSlot, "output", "cache", config.slot.scanner.cache)
    while (transposer.getStackInSlot(sideConfig.scanner, config.slot.scanner.cache) == nil) do
        os.sleep(1)
    end
    local bee = transposer.getStackInSlot(sideConfig.scanner, config.slot.scanner.cache)

    if bee.individual ~= nil and bee.individual.active == nil then
        print("蜜蜂尚未扫描，正在送往扫描仪。")
        safeTransfer(sideConfig.scanner, sideConfig.scanner, 64, config.slot.scanner.cache, "cache", "scanner", 1)
        while (transposer.getStackInSlot(sideConfig.output, 1) == nil) do
            os.sleep(1)
        end
        safeTransfer(sideConfig.output, sideConfig.scanner, 64, 1, "output", "cache", config.slot.scanner.cache)
    end
    bee = transposer.getStackInSlot(sideConfig.scanner, config.slot.scanner.cache)

    local shouldImprint = utility.hasForcedImprintGenes(bee)
    -- no need to imprint
    if not shouldImprint then
        safeTransfer(sideConfig.scanner, containerSide, 1, config.slot.scanner.cache, "scanner", "output", containerSlot)
        return false
    end

    print("检测到需强制压印的基因，正在压印……")

    print("正在将蜜蜂送往压印机。")
    safeTransfer(sideConfig.scanner, sideConfig.scanner, 64, config.slot.scanner.cache, "cache", "imprinter", config.slot.scanner.Imprinter)
    while (transposer.getStackInSlot(sideConfig.output, config.slot.output.imprinted) == nil) do
        os.sleep(1)
    end
    -- imprinted bee/waste in output#imprinted

    bee = transposer.getStackInSlot(sideConfig.output, config.slot.output.imprinted)
    if bee.name == "gendustry:Waste" then
        print("蜜蜂在压印时死亡。")
        -- move waste to garbage
        safeTransfer(sideConfig.output, sideConfig.garbage, 64, config.slot.output.imprinted, "output", "garbage")
        return true
    end
    
    -- bee still alive, move it back to initial place
    safeTransfer(sideConfig.output, containerSide, 1, config.slot.output.imprinted, "output", "output", containerSlot)
    return false
end

--- Check if the bee has some genes that should be erased/imprinted forcibly
---@param bee table bee itemstack
---@return boolean hasForcedImprintGenes true if the bee has some genes that should be erased/imprinted forcibly
function utility.hasForcedImprintGenes(bee)
    if not bee or not bee.individual or not bee.individual.active then
        return false
    end

    for geneName, forcedMap in pairs(config.forceImprintGenes) do
        local currentVal
        -- species need special treatment
        if geneName == "species" then
            currentVal = (bee.individual.active.species or {}).uid
        else
            currentVal = bee.individual.active[geneName]
        end

        if currentVal and forcedMap[currentVal] then
            return true
        end

        currentVal = bee.individual.inactive[geneName]
        if currentVal and forcedMap[currentVal] then
            return true
        end
    end

    return false
end

function safeTransfer(sideIn, sideOut, amount, slot, sideInName, sideOutName, slotOut, noWarn)
    noWarn = noWarn or false
    local transferSuccess
    if slotOut then
        transferSuccess = transposer.transferItem(sideIn, sideOut, amount, slot, slotOut)
    else
        transferSuccess = transposer.transferItem(sideIn, sideOut, amount, slot)
    end

    if transferSuccess == 0 and transposer.getStackInSlot(sideIn, slot) ~= nil then
        if not noWarn then
            print("转移物品失败，是不是箱子满了或者有杂物没拿出来")
        end
        while transposer.getStackInSlot(sideIn, slot) ~= nil do
            os.sleep(1)
            if slotOut then
                transposer.transferItem(sideIn, sideOut, amount, slot, slotOut)
            else
                transposer.transferItem(sideIn, sideOut, amount, slot)
            end
        end
    end
end

function indexInTable(tbl, target)
    for i,value in pairs(tbl) do
        if value == target then
            return i
        end
    end
    return 0
end

function cycleIsDone(sideConfig)
    for i=3,9 do
        local item = transposer.getStackInSlot(sideConfig.breeder, i)
        if item ~= nil then
            local _,type = utility.getItemName(item)
            if type == "Princess" then
                return true
            end
        end
    end 
    return false
end

function IsBeeCycleStarted(sideConfig)
    local item = transposer.getStackInSlot(sideConfig.breeder, 1)
    if item ~= nil then
        local _,type = utility.getItemName(item)
        if type == "Queen" then
            return true
        end
    end

    return false
end

return utility
