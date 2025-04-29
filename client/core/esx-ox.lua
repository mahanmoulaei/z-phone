---@diagnostic disable: duplicate-set-field
if Config.Core == "ESX-OX" then
    lib.load "@es_extended/imports"

    xCore = {}

    local function reloadVehicleData()
        for model, data in pairs(ESX.GetVehicleData()) do
            Config.Vehicles[model] = {
                model = model,
                name = data.name,
                brand = data.make,
                category = "Unknown",
                type = data.type,
                image = data.image
            }
        end
    end

    do reloadVehicleData() end
    AddStateBagChangeHandler("esx:vehicleData", "global", reloadVehicleData)

    xCore.GetPlayerData = function()
        return ESX.PlayerLoaded and {
            citizenid = ESX.PlayerData.cid
        }
    end

    xCore.Notify = function(text, textType, duration)
        ESX.ShowNotification({ "Phone", text }, textType, duration)
    end

    xCore.HasItemByName = function(item)
        return exports["ox_inventory"]:GetItemCount(item, nil, false) >= 1
    end

    xCore.GetClosestPlayer = function()
        return lib.getClosestPlayer(cache.coords, 2.0, false)
    end
end
