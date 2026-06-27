-- Resolve qbx PlayerData via the official qbx_core export so this bridge does
-- not depend on the global `QBX` table (which required hard-including
-- @qbx_core/modules/playerdata.lua in the manifest and broke non-qbx servers).
local function getQbxPlayerData()
    if exports.qbx_core then
        return exports.qbx_core:GetPlayerData()
    end
    return QBX and QBX.PlayerData or {}
end

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    local pd = getQbxPlayerData()
    ps.ped = PlayerPedId()
    ps.charinfo = pd.charinfo
    ps.citizenid = pd.citizenid
    ps.name = pd.charinfo and (pd.charinfo.firstname .. " " .. pd.charinfo.lastname) or nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        ps.ped = nil
        ps.charinfo = nil
        ps.citizenid = nil
        ps.name = nil
    end
end)
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if PlayerPedId() then
            local pd = getQbxPlayerData()
            ps.ped = PlayerPedId()
            ps.charinfo = pd.charinfo
            ps.citizenid = pd.citizenid
            ps.name = pd.charinfo and (pd.charinfo.firstname .. " " .. pd.charinfo.lastname) or nil
        end
    end
end)

function ps.getPlayerData()
    return getQbxPlayerData()
end

function ps.getIdentifier()
    return ps.getPlayerData().citizenid
end
ps.getCid = ps.getIdentifier

function ps.getMetadata(meta)
    return ps.getPlayerData().metadata[meta]
end

function ps.getCharInfo(info)
    return ps.getPlayerData().charinfo[info]
end

function ps.getPlayerName()
    return ps.getPlayerData().charinfo.firstname .. " " .. ps.getPlayerData().charinfo.lastname
end
ps.getName = ps.getPlayerName

function ps.getPlayer()
    return PlayerPedId()
end

function ps.getVehicleLabel(model)
    if not IsPedInAnyVehicle(ps.getPlayer(), false) then
        return false
    end

    model = GetEntityModel(model)
    local vehicle = exports.qbx_core:GetVehiclesByName(model)

    if vehicle then
        return vehicle.name
    else
        return GetDisplayNameFromVehicleModel(model)
    end
end

function ps.isDead()
    local isDead = exports.qbx_medical:IsDead()
    local inLaststand = exports.qbx_medical:IsLaststand()

    if isDead or inLaststand then return true end
    return false
end

function ps.getJob()
    local player = ps.getPlayerData()
    return player.job
end

function ps.getJobName()
    local job = ps.getJob()
    return job.name
end

function ps.getJobType()
    local job = ps.getJob()
    return job.type or false
end

function ps.isBoss()
    local job = ps.getJob()
    return job.isboss
end

function ps.getJobDuty()
    local job = ps.getJob()
    return job.onduty
end

function ps.getJobData(data)
    local job = ps.getJob()
    return job[data]
end

function ps.getGang()
    local player = ps.getPlayerData()
    return player.gang
end

function ps.getGangName()
    local gang = ps.getGang()
    return gang.name
end

function ps.isLeader()
    local Gang = ps.getGang()
    return Gang.isboss or false
end

function ps.getGangData(data)
    local Gang = ps.getGang()
    return Gang[data]
end

function ps.getCoords()
    return GetEntityCoords(ps.ped)
end

function ps.getMoneyData()
    local money = getQbxPlayerData().money
    return money
end
function ps.getMoney(type)
    local money = getQbxPlayerData().money
    return money[type] or 0
end

function ps.getAllMoney()
    local money = getQbxPlayerData().money
    local moneyData = {}
    for k, v in pairs(money) do
       table.insert(moneyData, {
            amount = v,
            name = k
        })
    end
    return moneyData
end

exports('getPlayerData', ps.getPlayerData)
exports('getIdentifier', ps.getIdentifier)
exports('getCid', ps.getCid)
exports('getMetadata', ps.getMetadata)
exports('getCharInfo', ps.getCharInfo)
exports('getPlayerName', ps.getPlayerName)
exports('getName', ps.getName)
exports('getPlayer', ps.getPlayer)
exports('getVehicleLabel', ps.getVehicleLabel)
exports('isDead', ps.isDead)
exports('getJob', ps.getJob)
exports('getJobName', ps.getJobName)
exports('getJobType', ps.getJobType)
exports('isBoss', ps.isBoss)
exports('getJobDuty', ps.getJobDuty)
exports('getJobData', ps.getJobData)
exports('getGang', ps.getGang)
exports('getGangName', ps.getGangName)
exports('isLeader', ps.isLeader)
exports('getGangData', ps.getGangData)
exports('getCoords', ps.getCoords)
exports('getMoneyData', ps.getMoneyData)
exports('getMoney', ps.getMoney)
exports('getAllMoney', ps.getAllMoney)