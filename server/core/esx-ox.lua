---@diagnostic disable: duplicate-set-field
if Config.Core == "ESX-OX" then
    lib.load "@es_extended/imports"

    xCore = {}

    local function getPlayerDataFromXPlayer(xPlayer)
        return {
            source = xPlayer.source,
            citizenid = xPlayer.cid,
            name = xPlayer.name,
            job = {
                name = xPlayer.job.name,
                label = xPlayer.job.label
            },
            money = {
                cash = xPlayer.getAccount("money")?.money,
                bank = xPlayer.getAccount("bank")?.money,
            },
            removeCash = function(amount)
                xPlayer.removeMoney(amount)
            end,
            removeAccountMoney = function(account, amount, reason)
                xPlayer.removeAccountMoney(account, amount, reason)
            end,
            addAccountMoney = function(account, amount, reason)
                xPlayer.addAccountMoney(account, amount, reason)
            end
        }
    end

    xCore.GetPlayerBySource = function(source)
        local xPlayer = ESX.GetPlayerFromId(source)

        return xPlayer and getPlayerDataFromXPlayer(xPlayer)
    end

    xCore.GetPlayerByIdentifier = function(cid)
        local xPlayer = ESX.GetPlayerFromCid(cid)

        return xPlayer and getPlayerDataFromXPlayer(xPlayer)
    end

    xCore.HasItemByName = function(source, item)
        return exports["ox_inventory"]:GetItem(source, item, nil, false)?.count >= 1
    end

    xCore.AddMoneyBankSociety = function(societyName, amount, reason)
        local society = exports["esx_society"]:GetSociety(societyName)

        TriggerEvent("esx_addonaccount:getSharedAccount", society?.account, function(account)
            if account then account.addMoney(amount, reason) end
        end)
    end

    xCore.queryPlayerVehicles = function()
        -- state
        -- 1 = Garaged
        -- 2 = Impound
        -- 3 = Outside
        -- default = Outside

        local garages = exports["esx_garage"]:GetGarages()

        -- Dynamically build CASE clause from garages table
        local garageCaseSQL = "CASE ov.`garage`"
        for key, data in pairs(garages) do
            local safeKey = key:gsub("'", "\\'")
            local safeLabel = tostring(data.Label):gsub("'", "\\'")
            garageCaseSQL = garageCaseSQL .. string.format(" WHEN '%s' THEN '%s'", safeKey, safeLabel)
        end
        garageCaseSQL = garageCaseSQL .. " ELSE ov.`garage` END"

        -- Inject into query
        local query = string.format([[
            SELECT
                ov.`model` AS vehicle,
                COALESCE(NULLIF(JSON_VALUE(ov.`vehicle`, '$.plate'), ''), ov.`plate`) AS plate,
                %s AS garage,
                CONCAT('https://cfx-nui-es_extended/files/vehicle-images/', ov.`model`, '.jpg') AS image,
                COALESCE(NULLIF(JSON_VALUE(ov.`vehicle`, '$.fuelLevel'), ''), 100) AS fuel,
                COALESCE(NULLIF(JSON_VALUE(ov.`vehicle`, '$.engineHealth'), ''), 100) AS engine,
                COALESCE(NULLIF(JSON_VALUE(ov.`vehicle`, '$.bodyHealth'), ''), 100) AS body,
                CASE
                    WHEN ov.`stored` = 1 THEN 1
                    WHEN ov.`stored` = 0 THEN (
                        CASE
                            WHEN EXISTS (SELECT 1 FROM `impounded_vehicles` iv WHERE iv.`id` = ov.`id`) THEN 2
                            ELSE 3
                        END
                    )
                END AS state,
                DATE_FORMAT(NOW(), '%%d %%b %%Y %%H:%%i') AS created_at
            FROM `owned_vehicles` ov
            WHERE ov.`owner` COLLATE utf8mb4_unicode_ci = (
                SELECT u.`identifier` COLLATE utf8mb4_unicode_ci
                FROM `users` u
                WHERE u.`cid` = ?
                LIMIT 1
            )
            ORDER BY ov.`plate` ASC
        ]], garageCaseSQL)

        return query
    end

    xCore.queryPlayerHouses = function()
        -- ADJUST QUERY FROM YOUR TABLE HOUSING
        local query = [[
            SELECT
                d.`id`,
                d.`name`,
                0 AS tier,
                NULL AS coords,
                0 AS is_has_garage,
                1 AS is_house_locked,
                1 AS is_garage_locked,
                1 AS is_stash_locked,
                '[]' AS keyholders
            FROM
                `datastore_data` d
            WHERE d.`owner` COLLATE utf8mb4_unicode_ci = (
                SELECT u.`identifier` COLLATE utf8mb4_unicode_ci
                FROM `users` u
                WHERE u.`cid` = ?
                LIMIT 1
            ) AND d.`name` = 'property'
            ORDER BY d.`id` DESC
        ]]

        return query
    end

    xCore.bankHistories = function(citizenid)
        -- type = withdraw or deposit (lowercase)

        local query = [[
            SELECT
                LOWER(b.`type`) AS type,
                b.`type` AS label,
                b.`amount` AS total,
                DATE_FORMAT(FROM_UNIXTIME(b.`time` / 1000), '%d/%m/%Y %H:%i') AS created_at
            FROM `banking` AS b
            WHERE b.`identifier` COLLATE utf8mb4_unicode_ci = (
                SELECT u.`identifier` COLLATE utf8mb4_unicode_ci
                FROM `users` u
                WHERE u.`cid` = ?
                LIMIT 1
            )
            ORDER BY b.`id` DESC LIMIT 50
        ]]

        return MySQL.query.await(query, { citizenid }) or {}
    end

    xCore.bankInvoices = function(citizenid)
        local query = [[
            SELECT
                bill.`id`,
                bill.`target` AS society,
                bill.`label` AS reason,
                bill.`amount`,
                bill.`sender` AS sendercitizenid,
                DATE_FORMAT(NOW(), '%d/%m/%Y %H:%i') AS created_at
            FROM `billing` AS bill
            WHERE bill.`identifier` COLLATE utf8mb4_unicode_ci = (
                SELECT u.`identifier` COLLATE utf8mb4_unicode_ci
                FROM `users` u
                WHERE u.`cid` = ?
                LIMIT 1
            )
            ORDER BY bill.`id` DESC
        ]]

        return MySQL.query.await(query, { citizenid }) or {}
    end

    xCore.bankInvoiceByCitizenID = function(id, citizenid)
        local query = [[
            SELECT
                bill.`id`,
                bill.`amount`,
                bill.`label` AS reason,
                bill.`target` AS society,
                bill.`amount`
            FROM `billing` bill
            WHERE bill.`id` = ? and bill.`identifier` COLLATE utf8mb4_unicode_ci = (
                SELECT u.`identifier` COLLATE utf8mb4_unicode_ci
                FROM `users` u
                WHERE u.`cid` = ?
                LIMIT 1
            )
            LIMIT 1
        ]]

        return MySQL.single.await(query, { id, citizenid })
    end

    xCore.deleteBankInvoiceByID = function(id)
        local query = [[
            DELETE
            FROM `billing`
            WHERE `id` = ?
        ]]

        MySQL.query(query, { id })
    end
end
