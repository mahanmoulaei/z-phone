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
        local garageCaseSQL = "CASE v.`garage`"
        for key, data in pairs(garages) do
            local safeKey = key:gsub("'", "\\'")
            local safeLabel = tostring(data.Label):gsub("'", "\\'")
            garageCaseSQL = garageCaseSQL .. string.format(" WHEN '%s' THEN '%s'", safeKey, safeLabel)
        end
        garageCaseSQL = garageCaseSQL .. " ELSE v.`garage` END"

        -- Inject into query
        local query = string.format([[
            SELECT
                v.`model` AS vehicle,
                COALESCE(NULLIF(JSON_VALUE(v.`vehicle`, '$.plate'), ''), v.`plate`) AS plate,
                %s AS garage,
                CONCAT('https://cfx-nui-es_extended/files/vehicle-images/', v.`model`, '.jpg') AS image,
                COALESCE(NULLIF(JSON_VALUE(v.`vehicle`, '$.fuelLevel'), ''), 100) AS fuel,
                COALESCE(NULLIF(JSON_VALUE(v.`vehicle`, '$.engineHealth'), ''), 100) AS engine,
                COALESCE(NULLIF(JSON_VALUE(v.`vehicle`, '$.bodyHealth'), ''), 100) AS body,
                CASE
                    WHEN v.`stored` = 1 THEN 1
                    WHEN v.`stored` = 0 THEN (
                        CASE
                            WHEN EXISTS (SELECT 1 FROM `impounded_vehicles` iv WHERE iv.`id` = v.`id`) THEN 2
                            ELSE 3
                        END
                    )
                END AS state,
                DATE_FORMAT(NOW(), '%%d %%b %%Y %%H:%%i') AS created_at
            FROM `owned_vehicles` v
            WHERE v.`owner` = (
                SELECT u.`identifier`
                FROM `users` u
                WHERE u.`cid` = ?
                LIMIT 1
            )
            ORDER BY v.`plate` ASC
        ]], garageCaseSQL)

        return query
    end

    xCore.queryPlayerHouses = function()
        -- ADJUST QUERY FROM YOUR TABLE HOUSING
        local query = [[
        SELECT
                hl.id,
                hl.name,
                0 as tier,
                null as coords,
                0 as is_has_garage,
                1 AS is_house_locked,
                1 AS is_garage_locked,
                1 AS is_stash_locked,
                '[]' as keyholders
            FROM
                datastore_data hl
            WHERE hl.owner = ? and hl.name = 'property'
            ORDER BY hl.id DESC
        ]]

        return query
    end

    xCore.bankHistories = function(citizenid)
        -- type = withdraw or deposit (lowercase)
        local query = [[
            select
                lower(bs.type) as type,
                bs.type as label,
                bs.amount as total,
                DATE_FORMAT(now(), '%d/%m/%Y %H:%i') as created_at
            from banking as bs
            where bs.identifier = ? order by bs.id desc
        ]]

        local histories = MySQL.query.await(query, { citizenid })
        if not histories then
            histories = {}
        end

        return histories
    end

    xCore.bankInvoices = function(citizenid)
        local query = [[
            select
                pi.id,
                pi.target as society,
                pi.label as reason,
                pi.amount,
                pi.sender as sendercitizenid,
                DATE_FORMAT(now(), '%d/%m/%Y %H:%i') as created_at
            from billing as pi
            where pi.identifier = ? order by pi.id desc
        ]]

        local bills = MySQL.query.await(query, { citizenid })
        if not bills then
            bills = {}
        end

        return bills
    end

    xCore.bankInvoiceByCitizenID = function(id, citizenid)
        local query = [[
            select pi.id, pi.amount, pi.label as reason, pi.target as society, pi.amount from billing pi WHERE pi.id = ? and pi.identifier = ? LIMIT 1
        ]]

        return MySQL.single.await(query, { id, citizenid })
    end

    xCore.deleteBankInvoiceByID = function(id)
        local query = [[
            DELETE FROM billing WHERE id = ?
        ]]

        MySQL.query(query, { id })
    end
end
