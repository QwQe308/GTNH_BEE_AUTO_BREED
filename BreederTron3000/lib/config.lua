local config = {}
config.preference = {
    ["Common"]= {"Forest","Meadows"},
    ["Oily"]= {"Ocean","Primeval"},
    ["Corroded"]= {"Wintry","Resilient"},
    ["Ruby"]= {"Redstone","Diamond"},
    ["Sinister"]= {"Cultivated","Modest"},
    ["Tarnished"]= {"Marshy", "Resilient"},
    ["Lustered"]= {"Forest","Resilient"},
    ["Glittering"]= {"Majestic","Rusty"},
    ["Diamond"]= {"Certus","Coal"},
    ["Galvanized"]= {"Wintry","Resilient"},
    ["Frugal"]= {"Modest","Sinister"},
    ["Leaden"]= {"Meadows","Resilient"},
    ["Shining"]= {"Majestic","Galvanized"},
    ["Spirit"]= {"Ethereal","Aware"},
    ["Nuclear"]= {"Unstable","Rusty"},
    ["Cultivated"]= {"Common","Forest"},
    ["Arid"]= {"Meadows","Frugal"},
    ["Indium"]= {"Lead","Osmium"},
    ["Sapphire"]= {"Certus","Lapis"},
    ["Fossilised"]= {"Primeval","Growing"},
    ["Fungal"]= {"Boggy","Miry"},
    ["Scummy"]= {"Agrarian","Exotic"},
    ["Fiendish"]= {"Sinister","Cultivated"},
    ["Emerald"]= {"Olivine","Diamond"},
    ["Rusty"]= {"Meadows","Resilient"},
    ["Vengeful"]= {"Demonic","Vindictive"},
    ["Eldritch"]= {"Mystical","Cultivated"},


}
config.geneWeights = {
    ["species"] = 7,
    ["lifespan"] = 1,
    ["speed"] = 1,
    ["flowering"] = 1,
    ["flowerProvider"] = 1,
    ["fertility"] = 13,
    ["territory"] = 1,
    ["effect"] = 1,

    ["temperatureTolerance"] = 4,
    ["humidityTolerance"] = 4,
    ["nocturnal"] = 2,
    ["tolerantFlyer"] = 2,
    ["caveDwelling"] = 2,
}
config.breedWeights = {
    ["species"] = 5,
}
config.activeBonus = 1.3

config.weightSum = 0
for _,value in pairs(config.geneWeights) do
    config.weightSum = config.weightSum + value
end
config.targetSum = config.weightSum + config.weightSum * config.activeBonus - (config.geneWeights.species * (config.activeBonus - 1))

config.devConfig = {
    ["storage"] = 4,
    ["breeder"] = 5,
    ["scanner"] = 2,
    ["garbage"] = 1,
    ["output"] = 3,
}

config.convertDroneReq = 16

config.port = 3001
config.robotPort = 3000

-- 1-indexed slots config
-- Assumes we use a 27-slot ender chest
-- we extends the "scanner" chest to process everything, each slot for a different purpose
config.slot = {
    ["scanner"] = {
        -- slot 1-5 for old scanner
        ["TempAcc"] = 26, -- TemperatureAcclimatiser,
        ["HumAcc"] = 24, -- HumidityAcclimatiser,
        ["Imprinter"] = 23,
        ["Mutatron"] = 22,
        ["ToBeAcc"] = 21, -- bees that need to be acclimatised
        ["cache"] = 20, -- cache random stuff
    },
    ["output"] = {
        -- slot 1 the first output slot, for general-purpose usage
        ["imprinted"] = 27, -- imprinted bees
    }
}

-- time between block breaker redstone high->low
config.blockBreakerRedstoneInterval = 0.2

config.imprintToleranceCycleLimit = 32
config.imprintToleranceAdjustmentLimit = 12 -- Per tolerance trait and queen.

-- With mutatron and imprinter, when we get a bee that has a gene in this list, 
-- we immediately send it to the imprinter
config.forceImprintGenes = {
    -- species = { -- do not use this, it will kill all the princesses
    --     ["gregtech.bee.speciesEnergy"] = true, -- for testing
    -- },
    effect = {
        ["extrabees.effect.lightning"] = true,
        ["extrabees.effect.meteor"] = true,
        ["forestry.allele.effect.radioactive"] = true,
    },
    -- flowerProvider = {
    --     ["flowersEnd"] = true, -- Dragon Egg
    -- },
}

return config
