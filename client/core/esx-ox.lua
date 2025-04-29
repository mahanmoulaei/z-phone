---@diagnostic disable: duplicate-set-field
if Config.Core == "ESX-OX" then
    lib.load "@es_extended/imports"

    xCore = {}

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
