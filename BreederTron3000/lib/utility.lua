local component = require("component")
local config = require("config")
local filesystem = require("filesystem")
local event = require("event")
local os = require("os")
local serialization = require("serialization")
local utility = {}
local transposer = component.transposer
local modem = nil
if next(component.list("modem")) ~= nil then
    modem = component.modem
end

function utility.createBreedingChain(beeName, breeder, sideConfig, existingBees)
    local startingParents = utility.processBee(beeName, breeder, "TARGET BEE!")
    if(startingParents == nil) then
        print("Bee has no parents!")
        return {}
    end
    if(existingBees[beeName]) then
        print("You already have the " .. beeName .. " bee!")
        return {}
    end
    local breedingChain = {[beeName] = startingParents}
    local queue = {[beeName] = startingParents}
    local current = {}

    while next(queue) ~= nil do
        for child,parentPair in pairs(queue) do
            local leftName = parentPair.allele1.name
            local rightName = parentPair.allele2.name
            print("Processing parents of " .. child .. ": " .. leftName .. " and " .. rightName .. "|正在处理杂交的迭代种群 " .. child .. "，其父代种群为: " .. leftName .. " 和 " .. rightName)

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

    print("Detected conflict! Please choose one of the following parents for the " .. beeName .. " bee (Breeds into " .. child .. " bee): |发现杂交路径分歧，你可以选择该蜂种的杂交父代： " .. beeName .. "  (关于" .. child .. " 种群的繁育路线):")
    for i,pair in pairs(parentPairs) do
        print(i .. ": " .. pair.allele1.name .. " + " .. pair.allele2.name)
    end

    while(choice == nil or choice < 1 or choice > #parentPairs) do
        print("Please type the number of the correct pair|请选择适合你的繁育路线方案")
        choice = io.read("*n")
    end

    print("Selected: " .. parentPairs[choice].allele1.name .. " + " .. parentPairs[choice].allele2.name)
    return parentPairs[choice]
end

function utility.listBeesInStorage(sideConfig)
    local size = transposer.getInventorySize(sideConfig.storage)
    local bees = {}

    for i=1,size do
        local bee = transposer.getStackInSlot(sideConfig.storage, i)
        if bee ~= nil then
            if bee.individual ~= nil and bee.individual.active == nil then
                print(string.format("Bee in slot %d is unscanned! Sending to scanner.", i))
                safeTransfer(sideConfig.storage, sideConfig.scanner, 64, i, "storage", "scanner")
                while (transposer.getStackInSlot(sideConfig.output, 1) == nil) do
                    os.sleep(1)
                end
                bee = transposer.getStackInSlot(sideConfig.output, 1)
                print("Sending back to storage.")
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
    print("Converting princess to " .. beeName .. "|正在将公主蜂转换为 " .. beeName)
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
        print(string.format("Can't find drone or you don't have the required amount of drones (%d)! Aborting.", droneReq))
        return
    end
    if targetGenes == nil or targetGenes.active == nil then
        print("Drone not scanned! Aborting.")
        return
    end
    if princess == nil then
        print("Can't find princess! Aborting.")
        return
    end
    --Insert bees into the apiary
    print("Converting " .. princessName .. " princess to " .. beeName .. "|正在将 " .. princessName .. " 公主蜂转换为 " .. beeName)
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
                        print("Scanning princess...")
                        princessConverted = utility.checkPrincess(sideConfig) --This call will move the princess to sideConfig.output
                        if (not princessConverted) then
                            print("Princess is not a perfect copy! Continuing.")
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
        elseif acclimatiserConfig ~= nil then
            if acclimatiserConfig.useAcclimatiser and breeder ~= nil then
                utility.adjustToleranceIfNeeded(breeder, sideConfig, acclimatiserConfig)
            end
        end
        os.sleep(1)
    end
    print("Conversion complete!")
    for i=3,9 do --clean up the drones
        local item = transposer.getStackInSlot(sideConfig.breeder, i)
        if item ~= nil then
            safeTransfer(sideConfig.breeder, sideConfig.garbage, item.size, i, "breeder", "garbage")
        end
    end
    safeTransfer(sideConfig.output,sideConfig.storage, 1, 1, "output", "storage")
    print(beeName .. " princess moved to storage.|" .. beeName .. " 公主蜂已移至存储箱。")
end

function utility.populateBee(beeName, sideConfig, targetCount)
    local droneOutput = nil
    print("Populating " .. beeName .. " bee.|正在繁殖 " .. beeName .. " 的雄蜂，保证种群不会断代.")
    local princessSlot, droneSlot = utility.findPairString(beeName, beeName, sideConfig)
    if(princessSlot == -1 or droneSlot == -1) then
        print("Couldn't find princess or drone! Aborting.")
        return
    end
    local princess = transposer.getStackInSlot(sideConfig.storage, princessSlot)
    local genes = princess.individual.active
    if genes.fertility == 1 then
        print("This bee has 1 fertility! I can't populate this! Aborting.")
        return
    end
    print(beeName .. " bees found!")
    --Because the drones in storage are scanned you can only insert 1. the rest will be taken from output of the following cycles
    safeTransfer(sideConfig.storage, sideConfig.breeder, 1, princessSlot, "storage", "breeder")
    safeTransfer(sideConfig.storage, sideConfig.breeder, 1, droneSlot, "storage", "breeder")
    local item = nil
    while(item == nil or item.size < targetCount) do
        while(not cycleIsDone(sideConfig)) do
            os.sleep(1)
        end
        if droneOutput == nil then
            for i=3,9 do
                local candidate = transposer.getStackInSlot(sideConfig.breeder,i)
                if candidate ~= nil then
                    local _,type = utility.getItemName(candidate)
                    if type == "Drone" then
                        print("Drones located in slot: " .. i .. "已定位雄蜂在蜂箱的第" .. i .. "格")
                        if droneOutput ~= nil then
                            print("HEY! YOU'RE NOT SUPPOSED TO MAKE MORE THAN 2 DRONE STACKS WHEN POPULATING! TERMINATING PROGRAM.|程序运行繁育过程中，不应该有蜜蜂已经在蜂箱中，程序终止（请先清空蜂箱再启动程序）")
                            os.exit()
                        end
                        droneOutput = i
                    end
                end
            end
        else
            item = transposer.getStackInSlot(sideConfig.breeder, droneOutput)
            print("Populating progress: " .. item.size .. "/" .. targetCount .. "繁殖进度: " .. item.size .. "/" .. targetCount)
            if (item.size < targetCount) then
                safeTransfer(sideConfig.breeder,sideConfig.breeder, 1, droneOutput, "breeder", "breeder") --Move a single drone back to the breeding slot
                for i=3,9 do
                    local candidate = transposer.getStackInSlot(sideConfig.breeder,i)
                    if candidate ~= nil then
                        local _,type = utility.getItemName(candidate)
                        if type == "Princess" then
                            safeTransfer(sideConfig.breeder,sideConfig.breeder,1, i, "breeder", "breeder") --Move princess back to breeding slot
                        end
                    end
                end
            end
        end
    end
    print("Populating complete! Sending " .. beeName .. " bees to scanner.|繁殖雄蜂完成，正在发送 " .. beeName .. " 种的雄蜂进行扫描.")
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

    print("Scanned! " .. beeName .. " bees sent to storage.|扫描完成， " .. beeName .. " 种群的蜜蜂已被送回存储箱")
end


function utility.breed(beeName, breedData, sideConfig, robotMode)
    print("Breeding " .. beeName .. " bee.|正在尝试杂交 " .. beeName .. " bee.")
    local basePrincessSlot, baseDroneSlot = utility.findPair(breedData, sideConfig)
    if basePrincessSlot == -1 or baseDroneSlot == -1 then
        print("Couldn't find the parents of " .. beeName .. " bee! Aborting.")
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
        print("Mutation altering frames detected!")
    end
    
    print("Base chance: " .. breedData.chance .. "%|本次杂交突变概率：".. breedData.chance .. "%")
    if breederSize == 12 then
        print("Actual chance: " .. chance .. "%. MIGHT PRODUCE OTHER MUTATIONS!|实际突变概率: " .. chance .. "%，有概率产生其它非目标种群的突变")
    else
        print("Actual chance unknown (using alveary). MIGHT PRODUCE OTHER MUTATIONS!")
    end
    local requirements = breedData.specialConditions
    local botPlaced = false
    if next(requirements) ~= nil then
        print("This bee has the following special requirements: |该目标种群的突变有如下特殊要求：")
        for _, req in pairs(requirements) do
            print(req)
            local foundationBlock = req:match("Requires ([a-zA-Z ]+) as a foundation")
            if robotMode and foundationBlock ~= nil then
                print("Telling the robot to place: " .. foundationBlock)
                modem.broadcast(config.robotPort, "place " .. foundationBlock)
                os.sleep(0.5)
                local _, _, _, _, _, actionTaken = event.pull("modem_message")
                if actionTaken  == true then
                    print("Robot successfuly placed: " .. foundationBlock)
                    botPlaced = true
                else
                    print("Robot could not place " .. foundationBlock .. ". Please do it yourself.")
                end
            end
        end
        if #requirements == 1 and botPlaced then
            print("The robot dealt with all of the requirements! Proceeding.")
        else
            print("Type \"ok\" when you've made sure the conditions are met or type \"skip\" to skip this breed (You made this bee somewhere else).|请输入ok以代表你已经确认其满足上述条件，或者输入skip跳过本次育种（然后你自己去其它地方完成该育种）")
            local ans = io.read()
            while type(ans) ~= "string" or ans == "" do
                print("Type \"ok\" when you've made sure the conditions are met or type \"skip\" to skip this breed (You made this bee somewhere else).|请输入ok以代表你已经确认其满足上述条件，或者输入skip跳过本次育种（然后你自己去其它地方完成该育种）")
                ans = io.read()
            end
            if ans == "skip" then
                print("Updating the bee list...")
                utility.listBeesInStorage(sideConfig)
                goto skip
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
        print("Scanning bees...|扫描蜜蜂中")
        scanCount = utility.dumpBreeder(sideConfig, true)
        if scanCount == 0 then
            print("HEY! YOU TOOK OUT THE BEE! PUT A PRINCESS + DRONE IN THE BREEDER!")
            while(not cycleIsDone(sideConfig)) do
                os.sleep(1)
            end
            print("Continuing...")
            goto continue
        end
        while(transposer.getStackInSlot(sideConfig.output, scanCount) == nil) do
            os.sleep(1)
        end

        print("Assessing...|分析中")
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
            print("Target bee is pure!|目标蜜蜂的种群信息为纯合子")
            isPure = true
            isGeneticallyPerfect = utility.ensureGeneticEquivalence(princessSlot, bestDroneSlot, sideConfig) --Makes sure all genes are equal. will move genetically equivalent bee to storage
            if not isGeneticallyPerfect then
                print("Target bee is not genetically consistent! continuing|目标蜜蜂的其它等位基因为杂合子，需要继续繁育提纯")
                safeTransfer(sideConfig.output, sideConfig.breeder, 1, princessSlot, "output", "breeder") --Send princess to breeding slot
                safeTransfer(sideConfig.output, sideConfig.breeder, 1, bestDroneSlot, "output", "breeder") --Send drone to breeding slot
                dumpOutput(sideConfig, scanCount)
            end
        elseif (princessPureness + bestDronePureness) > 0 then
            if (not messageSent) then
                messageSent = true
                print("Target species present!|目标种群已出现")
                print("IT IS RECOMMENDED THAT YOU TAKE OUT ANY MUTATION ALTERING FRAMES TO REDUCE THE RISK OF UNWANTED MUTATIONS.|我们强烈建议您此时拿出带有突变效果的框架，以防该基因消失")
                os.sleep(5)
            end
            local princessSpecies = princess.individual.active.species.name .. "/" .. princess.individual.inactive.species.name
            local droneSpecies = bestDrone.individual.active.species.name .. "/" .. bestDrone.individual.inactive.species.name
            print("Breeding " .. princessSpecies .. " princess with " .. droneSpecies .. " drone.")
            safeTransfer(sideConfig.output, sideConfig.breeder, 1, princessSlot, "output", "breeder") --Send princess to breeding slot
            safeTransfer(sideConfig.output, sideConfig.breeder, 1, bestDroneSlot, "output", "breeder") --Send drone to breeding slot
            for i=1,scanCount do --Move the other drones to the garbage container
                safeTransfer(sideConfig.output, sideConfig.garbage, 64, i, "output", "garbage")
            end
        else
            print("TARGET SPECIES LOST!|目标种群未找到（杂交失败）")
            print("Looking for reserve drone...|正在搜索备用的雄蜂")
            bestReserveDrone = nil
            bestReserveScore, bestReserveSlot = getBestBreedReserve(beeName, sideConfig)
            if bestReserveSlot ~= nil then
                bestReserveDrone = transposer.getStackInSlot(sideConfig.garbage, bestReserveSlot)
            end
            if bestReserveDrone ~= nil then
                print("Found reserve drone with pureness: " .. bestReserveScore .. "/" .. "2")
                safeTransfer(sideConfig.garbage, sideConfig.breeder, 1, bestReserveSlot, "garbage", "breeder")
                safeTransfer(sideConfig.output, sideConfig.breeder, 1, princessSlot, "output", "breeder")
                dumpOutput(sideConfig, scanCount)
            else
                print("Couldn't find a good reserve drone! converting back to base species.|找不到一个好的备用雄蜂！准备重新从父代种开始杂交。")
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
    print("Breeding finished. " .. beeName .. " princess and its drones moved to storage.|育种完成。" .. beeName .. " 公主蜂及其雄蜂已移至存储。")
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
    assert(breeder ~= nil, "breeder should not be nil.")
    print("Breeding " .. beeName .. " bee by Mutatron.")
    local basePrincessSlot, baseDroneSlot = utility.findPair(breedData, sideConfig)
    if basePrincessSlot == -1 or baseDroneSlot == -1 then
        print("Couldn't find the parents of " .. beeName .. " bee! Aborting.")
        return true
    end

    if utility.isBeeSpeciesBlacklistedInMutatron(beeName) then
        print("This bee is blacklisted in the Mutatron!")
        print("type \"skip\" to skip this breed (You made this bee somewhere else).")
        local ans = io.read()
        while type(ans) ~= "string" or ans ~= "skip" do
            print("type \"skip\" to skip this breed (You made this bee somewhere else).")
            ans = io.read()
        end
        print("Updating the bee list...")
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
        print("Mutatron failed! Princess and drone killed by mutatron. We may have a retry.")
        safeTransfer(sideConfig.output, sideConfig.garbage, 64, 1, "output", "garbage")
        return false
    end
    -- successfuly mutated
    -- still need to check if the bee's gene is dangerous, force to imprint it if so
    -- queen in output#1
    local killed = utility.forceImprintIfNeeded(sideConfig.output, 1, sideConfig)
    if killed then
        print("Queen killed by imprinter! We may have a retry.")
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
        if IsBeeCycleStarted(sideConfig) and acclimatiserConfig.useAcclimatiser then
            utility.adjustToleranceIfNeeded(breeder, sideConfig, acclimatiserConfig)
        end
        while(not cycleIsDone(sideConfig)) do
            os.sleep(1)
        end
        print("Scanning bees...|扫描蜜蜂中")
        scanCount = utility.dumpBreeder(sideConfig, true)
        if scanCount == 0 then
            print("HEY! YOU TOOK OUT THE BEE! PUT A PRINCESS + DRONE IN THE BREEDER!")
            while(not cycleIsDone(sideConfig)) do
                os.sleep(1)
            end
            print("Continuing...")
            goto continueMutatron
        end
        while(transposer.getStackInSlot(sideConfig.output, scanCount) == nil) do
            os.sleep(1)
        end

        print("Assessing...|分析中")
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

        assert(bestDroneSlot ~= nil, "With mutatron we should not get impure bees, something went wrong")
        assert(princessSlot ~= nil, "With mutatron we should not get impure bees, something went wrong")

        -- princess may still have dangerous genes, check it
        killed = utility.forceImprintIfNeeded(sideConfig.output, princessSlot, sideConfig)
        if killed then
            print("Princess killed by imprinter! We may have a retry.")
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
            print("Target bee is pure!|目标蜜蜂的种群信息为纯合子")
            isPure = true
            isGeneticallyPerfect = utility.ensureGeneticEquivalence(princessSlot, bestDroneSlot, sideConfig) --Makes sure all genes are equal. will move genetically equivalent bee to storage
            if not isGeneticallyPerfect then
                print("Target bee is not genetically consistent! continuing|目标蜜蜂的其它等位基因为杂合子，需要继续繁育提纯")
                safeTransfer(sideConfig.output, sideConfig.breeder, 1, princessSlot, "output", "breeder") --Send princess to breeding slot
                safeTransfer(sideConfig.output, sideConfig.breeder, 1, bestDroneSlot, "output", "breeder") --Send drone to breeding slot
                dumpOutput(sideConfig, scanCount, bestDroneSlot)
            end
        else
            assert(false, "With mutatron we should not get impure bees, something went wrong")
        end
        ::continueMutatron::
    end
    for i=1,scanCount do
        if i ~= bestDroneSlot and i ~= princessSlot then
            safeTransfer(sideConfig.output,sideConfig.garbage, 64, i, "output", "garbage") --Move irrelevant drones to garbage
        end
    end
    print("Breeding finished. " .. beeName .. " princess and its drones moved to storage.|育种完成。" .. beeName .. " 公主蜂及其雄蜂已移至存储。")

    return true
end

function utility.ensureGeneticEquivalence(princessSlot, droneSlot, sideConfig)
    local princess = transposer.getStackInSlot(sideConfig.output,princessSlot)
    local drone = transposer.getStackInSlot(sideConfig.output,droneSlot)
    local targetGenes = princess.individual.active
    local isEquivalent = utility.isGeneticallyEquivalent(princess, drone, princess.individual.active, false)
    if isEquivalent then
        print("Target bee is genetically consistent!|目标蜜蜂的所有基因都是纯合子了！")
        safeTransfer(sideConfig.output, sideConfig.storage, 1, princessSlot, "output", "storage")
        safeTransfer(sideConfig.output, sideConfig.storage, 64, droneSlot, "output", "storage")
        return true
    end
    return false
end

function utility.imprintFromTemplate(beeName, sideConfig, templateGenes)
    print("Imprinting template genes onto " .. beeName .. " bee.")
    local size = transposer.getInventorySize(sideConfig.storage)

    local templateDrone = transposer.getStackInSlot(sideConfig.storage, size)
    if templateDrone == nil then
        print("You don't have a template drone (It goes in the last slot of your storage container)! Aborting.")
        return false
    end

    local basePrincessSlot, baseDroneSlot = utility.findPairString(beeName, beeName, sideConfig)
    if basePrincessSlot == nil or baseDroneSlot == nil then
        print("This species doesn't have both drones and a princess in your storage container! Aborting.")
        return false
    end

    local basePrincess = transposer.getStackInSlot(sideConfig.storage, basePrincessSlot)
    local baseDrone = transposer.getStackInSlot(sideConfig.storage, baseDroneSlot)
    if templateGenes == nil then
        templateGenes = templateDrone.individual.active
    end

    if utility.isGeneticallyEquivalent(basePrincess, templateDrone, templateGenes, true) then
        print("This bee already has template genes! Aborting.")
        return false
    end


    safeTransfer(sideConfig.storage, sideConfig.breeder, 1, basePrincessSlot, "storage", "breeder")
    safeTransfer(sideConfig.storage, sideConfig.breeder, 1, size, "storage", "breeder") -- Last slot in storage is reserved for template bees.

    
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
        princessScore = 0
        princessPureness = 0
        princessSlot = nil
        bestDroneScore = -1
        bestDronePureness = 0
        bestDroneSlot = nil
        scanCount = 0
        while(not cycleIsDone(sideConfig)) do
            os.sleep(1)
        end
        scanCount = utility.dumpBreeder(sideConfig, true)
        if scanCount == 0 then
            print("HEY! YOU TOOK OUT THE BEE! PUT A PRINCESS + DRONE IN THE BREEDER!")
            while(not cycleIsDone(sideConfig)) do
                os.sleep(1)
            end
            print("Continuing...")
            goto continue
        end
        print("Scanning...")
        while transposer.getStackInSlot(sideConfig.output, scanCount) == nil do --Wait for scan finish
            os.sleep(1)
        end
        print("Grading...")
        for i=1,scanCount do
            local bee = transposer.getStackInSlot(sideConfig.output, i) --scanCount guarantees there are bees in these slots
            local _,type = utility.getItemName(bee)
            if type == "Princess" then
                princess = bee
                princessScore = utility.getGeneticScore(bee, templateGenes, basePrincess.individual.active.species, config.geneWeights)
                princessPureness = utility.getBeePureness(beeName, bee)
                princessSlot = i
            else
                local droneScore = utility.getGeneticScore(bee, templateGenes, basePrincess.individual.active.species, config.geneWeights)
                if droneScore > bestDroneScore then
                    bestDrone = bee
                    bestDroneScore = droneScore
                    bestDronePureness = utility.getBeePureness(beeName, bee)
                    bestDroneSlot = i
                end
            end
        end

        local geneticSum = princessScore + bestDroneScore
        print("Genetic score: " .. geneticSum .. "/" .. config.targetSum*2)
        if (tostring(geneticSum) == tostring(config.targetSum*2)) then --Avoids floating point arithmetic errors
            print("Genetic imprint succeeded!")
            print("Dumping original drones...")
            utility.dumpDrones(beeName, sideConfig)
            safeTransfer(sideConfig.output, sideConfig.storage, 1, princessSlot, "output", "storage")
            safeTransfer(sideConfig.output, sideConfig.storage, 64, bestDroneSlot, "output", "storage")
            print("Imprinted bee moved to storage.|基因压印蜜蜂已移至存储箱。")
            dumpOutput(sideConfig, scanCount)
            return true
        end

        if (princessPureness + bestDronePureness) == 4 then
            print("PRINCESS AND DRONE ARE PURELY ORIGINAL SPECIES!")
            if utility.hasTargetGenes(princess, bestDrone, templateGenes) then
                print("Target gene pool reachable. Continuing.")
                continueImprinting(sideConfig, princessSlot, bestDroneSlot, scanCount)
            else
                print("Target gene pool unreachable. substituting drone for template drone.")
                while (transposer.getStackInSlot(sideConfig.storage, size) == nil) do
                    print("YOU RAN OUT OF TEMPLATE DRONES! PLEASE PROVIDE MORE!")
                    os.sleep(5)
                end
                safeTransfer(sideConfig.output, sideConfig.breeder, 1, princessSlot, "output", "breeder")
                safeTransfer(sideConfig.storage, sideConfig.breeder, 1, size, "storage", "breeder") -- Last slot in storage is reserved for template bees.
                for i=1,scanCount do
                    safeTransfer(sideConfig.output, sideConfig.garbage, 64, i, "output", "garbage")
                end
            end

        elseif (princessPureness + bestDronePureness) == 0 then
            print("ORIGINAL SPECIES LOST!")
            print("Looking for reserve drone...")
            local bestReserveDrone = nil
            local bestReserveScore = -1
            local bestReserveSlot = nil
            bestReserveScore, bestReserveSlot = getBestReserve(beeName, sideConfig, templateGenes, config.geneWeights)
            if bestReserveSlot ~= nil then
                bestReserveDrone = transposer.getStackInSlot(sideConfig.garbage, bestReserveSlot)
            end
            if bestReserveDrone ~= nil then
                print("Found reserve drone with genetic score " .. bestReserveScore .. "/" .. config.targetSum)
                safeTransfer(sideConfig.garbage, sideConfig.breeder, 1, bestReserveSlot, "garbage", "breeder")
                safeTransfer(sideConfig.output, sideConfig.breeder, 1, princessSlot, "output", "breeder")
                dumpOutput(sideConfig, scanCount)
            else
                print("Couldn't find reserve drone! Substituting base drone")
                safeTransfer(sideConfig.output, sideConfig.breeder, 1, princessSlot, "output", "breeder")
                if (safeTransfer(sideConfig.storage, sideConfig.breeder, 1, baseDroneSlot, "storage", "breeder") == 0) then
                    print("OUT OF BASE DRONES! TERMINATING.")
                    os.exit()
                end
                dumpOutput(sideConfig, scanCount)
            end
        elseif (princessPureness + bestDronePureness) == 1 then
            print("BEE AT RISK OF LOSING ORIGINAL SPECIES!")
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
        print("BEST RESERVE DRONE DISAPPEARED! TRYING AGAIN...")
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
        print("BEST RESERVE DRONE DISAPPEARED! TRYING AGAIN...")
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
function utility.hasTargetGenes(princess, drone, targetGenes)
    for gene, value in pairs(targetGenes) do
        if gene == "species" then
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


function utility.getOrCreateSideConfig()
    if filesystem.exists("/home/sideConfig.lua") then
        local sideConfig = require("sideConfig")
        return sideConfig
    end
    local directions = {"down","up","north","south","west","east"}
    local remainingDirections = {"down","up","north","south","west","east"}
    local configOrder = {"storage","scanner","output","garbage"}
    local newConfig = {}

    print("It looks like this might be your first time running this program. Let's set up your containers!")
    print("All directions are relative to the transposer.")

    for _,container in pairs(configOrder) do
        print(string.format("Which side is the: %s? Select one of the following:", container))
        for i,direction in pairs(directions) do
            if indexInTable(remainingDirections, direction) ~= 0 then
                print(string.format("%d. %s", i, direction))
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
                print("I can't process this answer! Try again.")
            end
        end
    end

    remainingDirections = {"down","up","north","south","west","east"}
    configOrder = {"apiaryBreaker","acclimatiserBreaker"}
    print("Let's set up the redstone I/O! If you don't need it, configure it randomly.")
    print("All directions are relative to the redstone I/O.")
    for _,container in pairs(configOrder) do
        print(string.format("Which side is the: %s? Select one of the following:", container))
        for i,direction in pairs(directions) do
            if indexInTable(remainingDirections, direction) ~= 0 then
                print(string.format("%d. %s", i, direction))
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
                print("I can't process this answer! Try again.")
            end
        end
    end

    print("Creating sideConfig.lua...")
    local file = filesystem.open("/home/sideConfig.lua", "w")
    file:write("local sideConfig = {\n")
    for container,side in pairs(newConfig) do
        file:write(string.format("[\"%s\"] = %d, \n", container, side))
    end
    file:write("}\n")
    file:write("return sideConfig")
    file:close()
    print("Done! Setup Complete!")
    return newConfig
end

function utility.getOrCreateAcclimatiserConfig()
    if filesystem.exists("/home/acclimatiserConfig.lua") then
        local acclimatiserConfig = require("acclimatiserConfig")
        return acclimatiserConfig
    end
    local newConfig = {}

    print("It looks like this might be your first time running this program. Let's set up your acclimatiser!")
    print("Do you want to use acclimatiser to adjust humidity/temperature? (y/n)")
    local getUseAcclimatiser = function ()
        local answer = nil
        while answer == nil do
            answer = io.read("*l")
            if string.lower(answer) ~= "y" and string.lower(answer) ~= "n" then
                print("Invalid input. Please enter y or n.")
                answer = nil
            end
        end
        return string.lower(answer) == "y"
    end

    newConfig.useAcclimatiser = getUseAcclimatiser()

    print("Check your apiary to get humidity/temperature info, and enter the number below.")
    -- humidity
    local function getHumidity()
        local answer = nil
        while answer == nil do
            print("Please enter the apiary humidity:")
            print("arid: -1")
            print("normal: 0")
            print("damp: 1")
            answer = io.read("*n")
            if answer < -1 or answer > 1 then
                print("Invalid input.")
                answer = nil
            end
        end
        return answer
    end
    
    local function getTemperature()
        local answer = nil
        while answer == nil do
            print("Please enter the apiary temperature:")
            print("icy: -2")
            print("cold: -1")
            print("none: 0")
            print("normal: 0")
            print("warm: 1")
            print("hot: 2")
            print("hellish: 3")
            answer = io.read("*n")
            if answer < -2 or answer > 3 then
                print("Invalid input.")
                answer = nil
            end
        end
        return answer
    end

    local function getTimeout()
        local answer = nil
        while answer == nil do
            print("Please enter the acclimatiser timeout in seconds:")
            print("(Acclimatiser will be break to retrieve Queen bee back when timed out):")
            answer = io.read("*n")
            if answer < 0 then
                print("Invalid input.")
                answer = nil
            end
        end
        return answer
    end

    newConfig.humidity = getHumidity()
    newConfig.temperature = getTemperature()
    newConfig.timeout = getTimeout()

    print("Creating acclimatiserConfig.lua...")
    local file = filesystem.open("/home/acclimatiserConfig.lua", "w")
    file:write("local acclimatiserConfig = {\n")
    file:write(string.format("[\"%s\"] = %s, \n", "useAcclimatiser", newConfig.useAcclimatiser))
    file:write(string.format("[\"%s\"] = %d, \n", "temperature", newConfig.temperature))
    file:write(string.format("[\"%s\"] = %d, \n", "humidity", newConfig.humidity))
    file:write(string.format("[\"%s\"] = %d, \n", "timeout", newConfig.timeout))
    file:write("}\n")
    file:write("return acclimatiserConfig")
    file:close()
    print("Done! Setup Complete!")
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

    -- print(string.format("humidity: %s, temperature: %s", queen.active.species.humidity, queen.active.species.temperature))

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

--- Adjust the tolerance of the queen bee if needed. 
---@param breeder any
---@param sideConfig any
---@param acclimatiserConfig any
function utility.adjustToleranceIfNeeded(breeder, sideConfig, acclimatiserConfig)
    -- wait until queen created
    local queenStack = transposer.getStackInSlot(sideConfig.breeder, 1)
    while queenStack ~= nil do
        local name, type = utility.getItemName(queenStack)
        if type == "Queen" then
            break
        end
        os.sleep(1)
    end

    -- queenStack may be nil if the breeder's work is done

    -- no need to adjust tolerance if the breeder can breed
    if breeder.canBreed() or transposer.getStackInSlot(sideConfig.breeder, 1) == nil then
        return
    end

    -- from here, queenStack must not be nil
    -- and we may have to adjust tolerance
    assert(queenStack ~= nil, "queenStack must not be nil")
    print("Cannot breed. Adjusting tolerance...")

    print(string.format("Breaking apiary to get the queen."))
    component.redstone.setOutput(sideConfig.apiaryBreaker, 15)
    os.sleep(config.blockBreakerRedstoneInterval)
    component.redstone.setOutput(sideConfig.apiaryBreaker, 0)
    os.sleep(config.blockBreakerRedstoneInterval)
    while (transposer.getStackInSlot(sideConfig.output, 1) == nil) do
        os.sleep(1)
    end
    -- after breaking, queen appears in the output slot 1
    safeTransfer(sideConfig.output, sideConfig.scanner, 64, 1, "output", "ToBeAcc", config.slot.scanner.ToBeAcc)
    while (transposer.getStackInSlot(sideConfig.scanner, config.slot.scanner.ToBeAcc) == nil) do
        os.sleep(1)
    end
    -- queen transferred to scanner#21

    local bee = transposer.getStackInSlot(sideConfig.scanner, config.slot.scanner.ToBeAcc)
    if bee.individual ~= nil and bee.individual.active == nil then
        print(string.format("Queen is unscanned! Sending to scanner."))
        safeTransfer(sideConfig.scanner, sideConfig.scanner, 64, config.slot.scanner.ToBeAcc, "output", "scanner", 1)
        while (transposer.getStackInSlot(sideConfig.output, 1) == nil) do
            os.sleep(1)
        end
        safeTransfer(sideConfig.output, sideConfig.scanner, 64, 1, "output", "ToBeAcc", config.slot.scanner.ToBeAcc)
    end
    bee = transposer.getStackInSlot(sideConfig.scanner, config.slot.scanner.ToBeAcc)

    local temperatureOK = false
    local humidityOK = false
    local humidityRange, temperatureRange = nil, nil
    local elaspedSeconds = 0
    local acclimatiserTimeout = acclimatiserConfig.timeout
    local sideAcclimatiserBreaker = sideConfig.acclimatiserBreaker

    while not (temperatureOK and humidityOK) do
        -- temperature
        while (transposer.getStackInSlot(sideConfig.scanner, config.slot.scanner.ToBeAcc) == nil) do
            os.sleep(1)
        end

        bee = transposer.getStackInSlot(sideConfig.scanner, config.slot.scanner.ToBeAcc)
        humidityRange, temperatureRange = utility.getQueenHumidityAndTemperatureRange(bee)
        assert(humidityRange ~= nil, "humidityRange must not be nil")
        assert(temperatureRange ~= nil, "temperatureRange must not be nil")
        if temperatureRange.max < acclimatiserConfig.temperature or acclimatiserConfig.temperature < temperatureRange.min then
            print("adjusting temperature tolerance.")
            safeTransfer(sideConfig.scanner, sideConfig.scanner, 64, config.slot.scanner.ToBeAcc, "scanner", "T+-Acc", config.slot.scanner.TempAcc)
            elaspedSeconds = 0
            while (transposer.getStackInSlot(sideConfig.output, 1) == nil and elaspedSeconds < acclimatiserTimeout) do
                os.sleep(1)
                elaspedSeconds = elaspedSeconds + 1
            end
            if elaspedSeconds >= acclimatiserTimeout then
                print("Timeout while waiting for acclimatiser, break it.")
                component.redstone.setOutput(sideAcclimatiserBreaker, 15)
                os.sleep(config.blockBreakerRedstoneInterval)
                component.redstone.setOutput(sideAcclimatiserBreaker, 0)
                os.sleep(config.blockBreakerRedstoneInterval)
            end
            safeTransfer(sideConfig.output, sideConfig.scanner, 64, 1, "output", "ToBeAcc", config.slot.scanner.ToBeAcc)
        else
            temperatureOK = true
        end

        -- humidity
        while (transposer.getStackInSlot(sideConfig.scanner, config.slot.scanner.ToBeAcc) == nil) do
            os.sleep(1)
        end
        bee = transposer.getStackInSlot(sideConfig.scanner, config.slot.scanner.ToBeAcc)
        humidityRange, temperatureRange = utility.getQueenHumidityAndTemperatureRange(bee)
        assert(humidityRange ~= nil, "humidityRange must not be nil")
        assert(temperatureRange ~= nil, "temperatureRange must not be nil")
        if humidityRange.max < acclimatiserConfig.humidity or acclimatiserConfig.humidity < humidityRange.min then
            print("adjusting humidity tolerance.")
            safeTransfer(sideConfig.scanner, sideConfig.scanner, 64, config.slot.scanner.ToBeAcc, "scanner", "H+-Acc", config.slot.scanner.HumAcc)
            elaspedSeconds = 0
            while (transposer.getStackInSlot(sideConfig.output, 1) == nil) and elaspedSeconds < acclimatiserTimeout do
                os.sleep(1)
                elaspedSeconds = elaspedSeconds + 1
            end
            if elaspedSeconds >= acclimatiserTimeout then
                print("Timeout while waiting for acclimatiser, break it.")
                component.redstone.setOutput(sideAcclimatiserBreaker, 15)
                os.sleep(config.blockBreakerRedstoneInterval)
                component.redstone.setOutput(sideAcclimatiserBreaker, 0)
                os.sleep(config.blockBreakerRedstoneInterval)
            end
            safeTransfer(sideConfig.output, sideConfig.scanner, 64, 1, "output", "ToBeAcc", config.slot.scanner.ToBeAcc)
        else
            humidityOK = true
        end
    end

    -- finally we put the queen back to the breeder
    print("Adjusted queen moved to breeder.|调整后的蜂后已移至蜂箱。")
    safeTransfer(sideConfig.scanner, sideConfig.breeder, 1, config.slot.scanner.ToBeAcc, "scanner", "breeder")

    if (not breeder.canBreed()) and transposer.getStackInSlot(sideConfig.breeder, 1) ~= nil then
        print("Warning: Queen exists but cannot breed, even after tolerance adjustment. Please check the queen bee.")
    end

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
        print(string.format("Bee is unscanned! Sending to scanner."))
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

    print("Detected forced imprint genes. Imprint the bee now...")

    print(string.format("Sending bee to imprinter."))
    safeTransfer(sideConfig.scanner, sideConfig.scanner, 64, config.slot.scanner.cache, "cache", "imprinter", config.slot.scanner.Imprinter)
    while (transposer.getStackInSlot(sideConfig.output, config.slot.output.imprinted) == nil) do
        os.sleep(1)
    end
    -- imprinted bee/waste in output#imprinted

    bee = transposer.getStackInSlot(sideConfig.output, config.slot.output.imprinted)
    if bee.name == "gendustry:Waste" then
        print("Imprinter killed the bee.")
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
            print(string.format("TRANSFER FROM SLOT %d OF CONTAINER: %s TO CONTAINER: %s FAILED! PLEASE DO IT MANUALLY OR CLEAN THE %s CONTAINER!", slot, sideInName:upper(), sideOutName:upper(), sideOutName:upper()))
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