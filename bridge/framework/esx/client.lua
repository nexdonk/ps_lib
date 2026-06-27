
-- Resolve the ESX shared object defensively. Config.lua sets the global `ESX`
-- during shared-script load, but that can lose a startup race, and on a live
-- `restart ps_lib` we must re-grab it. Without a valid ESX every getter fails.
if not ESX then
    local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
    if ok and obj then ESX = obj end
end

local esxJOBCompat = {
    ['police'] = 'leo',
    ['unemployed'] = 'loser'
}

-- Config-driven job -> type resolver (mirrors the server bridge).
local function jobToType(jobName)
    if not jobName then return 'none' end
    if Config and Config.ESXJobTypes and Config.ESXJobTypes[jobName] then
        return Config.ESXJobTypes[jobName]
    end
    return esxJOBCompat[jobName] or 'none'
end


local esxMetadata = {
    health = 0,
    armor = 0,
    thirst = 0,
    hunger = 0,
    stress = 0,
}


AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        ps.ped = nil
        ps.charinfo = nil
        ps.name = nil
        ps.identifier = nil
    end
end)

AddEventHandler('esx:playerLoaded', function(playerData)
    if ESX then ESX.PlayerData = playerData end
    ps.ped = PlayerPedId()
    ps.charinfo = {
        firstname = playerData.firstName,
        lastname = playerData.lastName,
        age = playerData.dateofbirth,
        gender = playerData.sex
    }
    ps.name = playerData.firstName .. " " .. playerData.lastName
    ps.identifier = playerData.identifier
    ps.debug(ps.ped, ps.charinfo, ps.name, ps.identifier)
end)

AddEventHandler("esx_status:onTick", function(data)
    local hunger, thirst, stress 
    for i = 1, #data do
        if data[i].name == "thirst" then
            thirst = math.floor(data[i].percent)
        end
        if data[i].name == "hunger" then
            hunger = math.floor(data[i].percent)
        end
        if data[i].name == "stress" then
            stress = math.floor(data[i].percent)
        end
    end
    local ped = PlayerPedId()
    esxMetadata.health = math.floor((GetEntityHealth(ped) - 100) / 100 * 100)
    esxMetadata.armor = GetPedArmour(ped)
    esxMetadata.thirst = thirst
    esxMetadata.hunger = hunger
    esxMetadata.stress = stress
end)

RegisterNetEvent('esx:setJob', function(job)
    if not ESX then return end
    ESX.PlayerData = ESX.PlayerData or {}
    ESX.PlayerData.job = job
end)

-- Hydrate PlayerData on (re)start. If this bridge loads AFTER the player already
-- spawned (e.g. a live `restart ps_lib`), esx:playerLoaded never fires again, so
-- ESX.PlayerData.job would stay nil and crash job detection. Pull it directly.
CreateThread(function()
    local tries = 0
    while ESX and tries < 50 do
        if ESX.PlayerData and ESX.PlayerData.job then break end
        local pd = ESX.GetPlayerData and ESX.GetPlayerData() or nil
        if pd and pd.job then
            ESX.PlayerData = pd
            break
        end
        tries = tries + 1
        Wait(200)
    end
end)

---@return: table
---@DESCRIPTION: Returns the player's data, including job, gang, and metadata.
function ps.getPlayerData()
    -- MDT auth/dispatch consumers (dashboard.lua, dispatch.lua, nui.lua) read
    -- QB-shaped citizenid + charinfo off this table. ESX only exposes
    -- identifier/firstName/lastName/sex/dateofbirth, so map them here once so
    -- every consumer works unchanged. Idempotent and rebuilt each call.
    local pd = (ESX and ESX.GetPlayerData and ESX.GetPlayerData()) or {}
    pd.citizenid = pd.identifier
    pd.charinfo = {
        firstname = pd.firstName,
        lastname  = pd.lastName,
        birthdate = pd.dateofbirth,
        gender    = pd.sex,
    }
    return pd
end

--- @return: string
--- @DESCRIPTION: Returns the player's citizen ID.
--- @example: ps.getIdentifier()
function ps.getIdentifier()
    return ps.getPlayerData().identifier
end

--- @PARAM: meta: string
--- @return: any
--- @DESCRIPTION: Returns specific metadata for the player.
--- @example: ps.getMetadata('isdead')
function ps.getMetadata(meta)
    if esxMetadata[meta] ~= nil then
        return esxMetadata[meta]
    end
    if meta == 'isdead' then
        return (ESX and ESX.PlayerData and ESX.PlayerData.dead) or false
    end
    local pd = ps.getPlayerData()
    local md = pd and pd.metadata
    if md ~= nil then
        return md[meta]
    end
    -- ESX may not sync a metadata table to the client; return a safe shape.
    if meta == 'licences' then return {} end
    return nil
end

--- @PARAM: info: string
--- @return: any
--- @DESCRIPTION: Returns specific character information based on the provided key.
--- @example: ps.getCharInfo('age')
function ps.getCharInfo(info)
    local playerData = ps.getPlayerData()
    local charinfo = {
            firstname = playerData.firstName,
            lastname = playerData.lastName,
            age = playerData.dateofbirth,
            gender = playerData.sex
        }
    return charinfo[info]
end

--- @return: string
--- @DESCRIPTION: Returns the player's full name.
function ps.getPlayerName()
    local pd = (ESX and ESX.GetPlayerData and ESX.GetPlayerData()) or (ESX and ESX.PlayerData)
    if pd and (pd.firstName or pd.lastName) then
        local name = ((pd.firstName or '') .. ' ' .. (pd.lastName or '')):match('^%s*(.-)%s*$')
        if name and name ~= '' then return name end
    end
    return GetPlayerName(PlayerId())
end

--- @return: number
--- @DESCRIPTION: Returns the player's ped ID.
function ps.getPlayer()
    return PlayerPedId()
end

--- @PARAM: model: number | string
--- @RETURN: string
--- @DESCRIPTION: Returns the vehicle label for the given model.
function ps.getVehicleLabel(model)
    local vehicle = ps.callback('ps_lib:esx:getVehicleLabel', model)
    return vehicle or GetDisplayNameFromVehicleModel(model)
end
   

--- @DESCRIPTION: Checks if the player is dead or in last stand.
--- @return boolean
--- @example if ps.isDead() then Revive end
function ps.isDead()
   return (ESX and ESX.PlayerData and ESX.PlayerData.dead) or false
end

--- @return: table
--- @DESCRIPTION: Returns the player's job information, including name, type, and duty status.
function ps.getJob()
    if not ESX then return nil end
    local pd = (ESX.GetPlayerData and ESX.GetPlayerData()) or ESX.PlayerData
    return pd and pd.job or nil
end

--- @RETURN: string
--- @DESCRIPTION: Returns the name of the player's job.
--- @example: ps.getJobName()
function ps.getJobName()
    local job = ps.getJob()
    return job and job.name or nil
end

function ps.getJobDuty()
    local job = ps.getJob()
    if not job then return false end
    if job.onDuty ~= nil then return job.onDuty end
    return true
end
function ps.getJobLabel()
    local job = ps.getJob()
    return job and job.label or nil
end
--- @RETURN: string
--- @DESCRIPTION: Returns the type of the player's job.
--- @example: ps.getJobType()
function ps.getJobType()
    local job = ps.getJob()
    return jobToType(job and job.name)
end

--- @RETURN: boolean
--- @DESCRIPTION: Checks if the player's job is a boss job.
--- @example: if ps.isBoss() then TriggerEvent('qb-bossmenu:client:openMenu') end
function ps.isBoss()
    local job = ps.getJob()
    return job ~= nil and job.grade_name == 'boss'
end

function ps.defaultDuty()
    local job = ps.getJob()
    if job and (job.name == 'police' or job.name == 'ambulance' or job.name == 'mechanic') then
        return false
    end
    return true
end


--- @RETURN: boolean
--- @DESCRIPTION: Checks if the player is on duty for their job.
--- @example: if ps.getJobDuty() then TriggerEvent('qb-phone:client:openJobPhone') end


--- @PARAM: data: string
--- @RETURN: any
--- @DESCRIPTION: Returns the job data for the specified key.
function ps.getJobData(data)
    local job = ps.getJob()
    if not job then return nil end
    if data == 'type' then return jobToType(job.name) end
    if data == 'onduty' then return ps.getJobDuty() end
    return job[data]
end

--- @return: table
--- @DESCRIPTION: Returns the player's gang information, including name, type, and duty status.
--- @example: ps.getGang()

function ps.getGang()
    local player = ps.getPlayerData()
    return player.job
end

--- @RETURN: string
--- @DESCRIPTION: Returns the name of the player's gang.
--- @example: ps.getGangName()
--- @
--- @-- Does esx support Gangs?
--function ps.getGangName()
--    local job = ps.getGang()
--    return job.name
--end

--- @RETURN: string
--- @DESCRIPTION: Returns if the player is a gang boss.
--- @example: ps.isLeader()
function ps.isLeader()
    local Gang = ps.getGang()
    return false
end


--- @PARAM: data: string
--- @RETURN: any
--- @DESCRIPTION: Returns specific data from the gang information.
--function ps.getGangData(data)
--    local Gang = ps.getGang()
--    return Gang[data]
--end

--- @RETURN: boolean
--- @DESCRIPTION: Checks the coords of the player.
--- @example: if ps.getCoords() then  end
function ps.getCoords()
    return GetEntityCoords(ps.ped)
end

function ps.getMoneyData()
    local pd = (ESX and ESX.GetPlayerData and ESX.GetPlayerData()) or (ESX and ESX.PlayerData) or {}
    local bank = ESX and ESX.GetAccount and ESX.GetAccount('bank') or nil
    return {
        cash = pd.money or 0,
        bank = bank and bank.money or 0,
    }
end
function ps.getMoney(type)
    return ps.getMoneyData()[type] or 0
end

function ps.getAllMoney()
    local money = ps.getMoneyData()
    local moneyData = {}
    for k, v in pairs(money) do
       table.insert(moneyData, {
            amount = v,
            name = k
        })
    end
    return moneyData
end

-- Aliases for cross-framework parity (qb/qbx expose these names).
ps.getName = ps.getPlayerName
ps.getCid = ps.getIdentifier

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
exports('defaultDuty', ps.defaultDuty)
exports('isLeader', ps.isLeader)
exports('getGangData', ps.getGangData)
exports('getCoords', ps.getCoords)
exports('getMoneyData', ps.getMoneyData)
exports('getMoney', ps.getMoney)
exports('getAllMoney', ps.getAllMoney)

ps.registerCallback('ps:esx:jobDuty', function(job)
    if ESX then
        ESX.PlayerData = ESX.PlayerData or {}
        ESX.PlayerData.job = job
    end
    return true
end)