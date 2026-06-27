ps.Shared = {}

-- Resolve the ESX shared object defensively. Config.lua sets the global `ESX`
-- during shared-script load, but that check can lose a startup race when
-- es_extended is still 'starting'. Without this, every getter below that calls
-- ESX.* would fail. Resolve it here so the bridge is self-sufficient.
if not ESX then
    local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
    if ok and obj then ESX = obj end
end

-- Backwards-compatible default job->type map. The authoritative map lives in
-- Config.ESXJobTypes; this is only a fallback if that config is missing.
local esxJOBCompat = {
    ['police'] = 'leo',
    ['unemployed'] = 'loser',
    ['ambulance'] = 'ems',
    ['mechanic'] = 'mechanic',
    ['cardealer'] = 'cardealer',
}

-- Resolve an ESX job name to a job "type". Config-driven so server owners can
-- map their own LEO/EMS/DOJ job names without editing the bridge.
local function jobToType(jobName)
    if not jobName then return 'none' end
    if Config and Config.ESXJobTypes and Config.ESXJobTypes[jobName] then
        return Config.ESXJobTypes[jobName]
    end
    return esxJOBCompat[jobName] or 'none'
end

local jobs, vehicles = {}, {}
local function handleJobGrades(jobName)
    local result = MySQL.query.await('SELECT * FROM job_grades WHERE job_name = ?', {jobName}) or {}
    local grades = {}
    for k, v in pairs(result) do
        grades[tostring(v.grade)] = {
            name = v.label,
            label = v.label,
            level = v.grade,
            grade = v.grade,
            payment = v.salary,
            isboss = (v.label == 'boss') or nil,
        }
    end
    return grades
end

local function loadJobsCompat()
    local result = MySQL.query.await('SELECT * FROM jobs',{}) or {}
    for k, v in pairs(result) do
        jobs[v.name] = {
            label = v.label,
            defaultDuty = false,
            type = jobToType(v.name),
            offDutyPay = 0,
            grades = handleJobGrades(v.name),
        }
    end
end

local function loadVehiclesCompat()
    local result = MySQL.query.await('SELECT * FROM vehicles') or {}
    for k, v in pairs(result) do
        vehicles[v.model] = {
            name = v.name,
            price = v.price,
            category = v.category,
        }
    end
end
-- These hydrate `jobs`/`vehicles` from the DB at load time. They MUST NOT be
-- allowed to throw: loadLib() executes this whole file inside a pcall, so a raw
-- error here (e.g. the server's ESX schema has no `jobs`/`job_grades`/`vehicles`
-- table) would abort the file before the ps.* getters below are ever defined —
-- producing "attempt to call a nil value (field 'getJobType')" downstream.
-- Guard them so the bridge always finishes loading; job types still resolve via
-- Config.ESXJobTypes and vehicle labels fall back to game model names.
local okJobs, jobsErr = pcall(loadJobsCompat)
if not okJobs then
    ps.warn(('[esx bridge] Could not load jobs from DB (%s) - falling back to Config.ESXJobTypes.'):format(tostring(jobsErr)))
end

local okVehicles, vehErr = pcall(loadVehiclesCompat)
if not okVehicles then
    ps.warn(('[esx bridge] Could not load vehicles from DB (%s) - falling back to game model names.'):format(tostring(vehErr)))
end

ps.Shared.Vehicles = vehicles
ps.Shared.Jobs = jobs

ps.registerCallback('ps_lib:esx:getVehicleLabel', function(_src, model)
    -- Server callbacks receive (source, ...); the first arg is the invoking
    -- source, the model is the second. Run the query synchronously and return
    -- its result (the previous async-callback form always returned nil).
    local result = MySQL.query.await('SELECT name FROM vehicles WHERE model = ?', { model })
    if result and result[1] then
        return result[1].name
    end
    return GetDisplayNameFromVehicleModel(model)
end)

function ps.getJobTable()
    return jobs
end

--- Player Getters -----------------------------------------------------------
function ps.getPlayer(source)
    return ESX.GetPlayerFromId(source)
end

--- Build a lightweight offline player object from the `users` table so name
--- lookups work for players who are not currently connected (ESX's native
--- GetPlayerFromIdentifier is online-only).
function ps.getOfflinePlayer(identifier)
    local online = ESX.GetPlayerFromIdentifier(identifier)
    if online then return online end
    if not identifier then return nil end
    local row = MySQL.single.await('SELECT identifier, firstname, lastname, job, job_grade, dateofbirth, sex FROM users WHERE identifier = ? LIMIT 1', { identifier })
    if not row then return nil end
    local fullname = ((row.firstname or '') .. ' ' .. (row.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return {
        offline = true,
        source = nil,
        identifier = row.identifier,
        name = fullname ~= '' and fullname or 'Unknown',
        firstName = row.firstname,
        lastName = row.lastname,
        dateofbirth = row.dateofbirth,
        sex = row.sex,
        getName = function() return fullname ~= '' and fullname or 'Unknown' end,
        getIdentifier = function() return row.identifier end,
    }
end

function ps.getPlayerByIdentifier(identifier)
    return ESX.GetPlayerFromIdentifier(identifier) or ps.getOfflinePlayer(identifier)
end
ps.getPlayerByCid = ps.getPlayerByIdentifier

function ps.getLicense(source)
    if GetConvarInt('sv_fxdkMode', 0) == 1 then return 'license:fxdk' end
    return GetPlayerIdentifierByType(source, 'license')
end

function ps.getIdentifier(source)
    local Player = ps.getPlayer(source)
    if not Player then return nil end
    return Player.getIdentifier()
end
ps.getCid = ps.getIdentifier

function ps.getSource(identifier)
    local player = ESX.GetPlayerFromIdentifier(identifier)
    if not player then return nil end
    return player.source
end

local function nameFromPlayer(player)
    if not player then return nil end
    if player.getName then
        local ok, n = pcall(player.getName)
        if ok and n and n ~= '' then return n end
    end
    return player.name
end

function ps.getPlayerName(source)
    local player = ps.getPlayer(source)
    if not player then return 'Unknown' end
    return nameFromPlayer(player) or 'Unknown'
end
ps.getName = ps.getPlayerName

function ps.getPlayerNameByIdentifier(identifier)
    local player = ESX.GetPlayerFromIdentifier(identifier)
    if player then
        return nameFromPlayer(player) or 'Unknown Person'
    end
    -- Offline fallback: read straight from the DB.
    local row = MySQL.single.await('SELECT firstname, lastname FROM users WHERE identifier = ? LIMIT 1', { identifier })
    if row then
        local full = ((row.firstname or '') .. ' ' .. (row.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
        if full ~= '' then return full end
    end
    return 'Unknown Person'
end
ps.getPlayerNameByCid = ps.getPlayerNameByIdentifier

function ps.getPlayerData(source)
    local player = ps.getPlayer(source)
    if not player then return nil end
    -- ESX has no PlayerData wrapper; expose the xPlayer table itself.
    return player
end

local function getStatus(source, type)
    local player = ps.getPlayer(source)
    if not player or not player.variables or not player.variables.status then return 0 end
    for k, v in pairs (player.variables.status) do
        if v.name == type then
            return math.floor(v.percent)
        end
    end
    return 0
end

function ps.getMetadata(source, meta)
    local player = ps.getPlayer(source)
    if not player then
        return meta == 'licences' and {} or nil
    end
    if meta == 'hunger' or meta == 'thirst' or meta == 'stress' then
        return getStatus(source, meta)
    elseif meta == 'isdead' then
        return player.isDead
    end
    -- Arbitrary metadata via ESX Legacy meta API (callsign, licences, fingerprint, dna, bloodtype...)
    if player.getMeta then
        local ok, val = pcall(player.getMeta, meta)
        if ok and val ~= nil then return val end
    end
    -- Safe default so callers that index the result (e.g. licences.driver) don't error.
    if meta == 'licences' then return {} end
    return nil
end

function ps.setMetadata(source, meta, value)
    local player = ps.getPlayer(source)
    if not player then return false end
    if player.setMeta then
        player.setMeta(meta, value)
        return true
    end
    return false
end

function ps.getCharInfo(source, info)
    local player = ps.getPlayer(source) or ps.getOfflinePlayer(source)
    if not player then return nil end
    local charinfo = {
        firstname = player.firstName,
        lastname = player.lastName,
        birthdate = player.dateofbirth,
        gender = player.sex
    }
    return charinfo[info]
end

--- Job Getters --------------------------------------------------------------
function ps.getJob(source)
    local player = ps.getPlayer(source)
    if not player then return nil end
    return player.job
end

function ps.getJobName(source)
    local player = ps.getPlayer(source)
    if not player then return nil end
    return player.job.name
end

function ps.getJobType(source)
    local player = ps.getPlayer(source)
    if not player then return 'none' end
    return jobToType(player.job.name)
end

function ps.getJobDuty(source)
    local player = ps.getPlayer(source)
    if not player then return false end
    local duty = player.job.onDuty
    -- ESX core has no native duty toggle; if the server runs no duty system the
    -- field is nil. Default to true so duty-gated features remain usable.
    if duty == nil then return true end
    return duty
end

function ps.getJobData(source, data)
    local player = ps.getPlayer(source)
    if not player then return nil end
    if data == nil then
        -- Return a QBCore-shaped job table for cross-framework consumers that
        -- expect job.grade to be a TABLE (job.grade.name / job.grade.level).
        local j = player.job
        return {
            name = j.name,
            label = j.label,
            type = jobToType(j.name),
            onduty = ps.getJobDuty(source),
            isboss = ps.isBoss(source),
            grade = {
                level = j.grade,
                grade = j.grade,
                name = j.grade_name,
                label = j.grade_label or j.grade_name,
                isboss = (j.grade_name == 'boss') or nil,
                payment = j.grade_salary,
            },
        }
    end
    if data == 'type' then return jobToType(player.job.name) end
    if data == 'onduty' then return ps.getJobDuty(source) end
    return player.job[data]
end

function ps.getJobGrade(source)
    local player = ps.getPlayer(source)
    if not player then return nil end
    return player.job.grade
end

function ps.getJobGradeLevel(source)
    local player = ps.getPlayer(source)
    if not player then return nil end
    return player.job.grade
end

function ps.getJobGradeName(source)
    local player = ps.getPlayer(source)
    if not player then return nil end
    return player.job.grade_name
end

function ps.getJobGradePay(source)
    local player = ps.getPlayer(source)
    if not player then return 0 end
    return player.job.grade_salary
end

function ps.isBoss(source)
    local player = ps.getPlayer(source)
    if not player then return false end
    local job = player.job
    if job.grade_name == 'boss' then return true end
    local shared = jobs[job.name]
    if shared and shared.grades then
        local g = shared.grades[tostring(job.grade)]
        if g and g.isboss then return true end
    end
    return false
end

function ps.getAllPlayers()
    return ESX.GetPlayers()
end

function ps.getEntityCoords(source)
    return GetEntityCoords(GetPlayerPed(source))
end

function ps.getDistance(source, location)
    local pcoords = GetEntityCoords(GetPlayerPed(source))
    local loc = vector3(location.x, location.y, location.z)
    return #(pcoords - loc)
end

function ps.checkDistance(source, location, distance)
    if not distance then distance = 2.5 end
    local pcoords = GetEntityCoords(GetPlayerPed(source))
    local loc = vector3(location.x, location.y, location.z)
    return #(pcoords - loc) <= distance
end

function ps.getNearbyPlayers(source, distance)
    if not distance then distance = 10.0 end
    local players = {}
    local origin = GetEntityCoords(GetPlayerPed(source))
    for _, v in pairs(ps.getAllPlayers()) do
        local dist = #(GetEntityCoords(GetPlayerPed(v)) - origin)
        if dist < distance then
            table.insert(players, {
                value = ps.getIdentifier(v),
                label = ps.getPlayerName(v),
                source = v,
                distance = dist,
            })
        end
    end
    return players
end

function ps.getJobCount(jobName)
    local count = 0
    for _, src in pairs(ps.getAllPlayers()) do
        local p = ps.getPlayer(src)
        if p and p.job.name == jobName and ps.getJobDuty(src) then
            count = count + 1
        end
    end
    return count
end

function ps.getJobTypeCount(jobType)
    local count = 0
    for _, src in pairs(ps.getAllPlayers()) do
        local p = ps.getPlayer(src)
        if p and p.job and jobToType(p.job.name) == jobType and ps.getJobDuty(src) then
            count = count + 1
        end
    end
    return count
end

function ps.createUseable(item, func)
    if not item or not func then return end
    ESX.RegisterUsableItem(item, func)
end

function ps.setJob(source, jobName, rank)
    local player = ps.getPlayer(source)
    if not player then return false end
    if ESX.DoesJobExist and not ESX.DoesJobExist(jobName, rank or 0) then return false end
    player.setJob(jobName, rank or 0)
    return true
end

function ps.setJobDuty(source, duty)
    local player = ps.getPlayer(source)
    if not player then return false end
    if player.setJob then
        player.setJob(player.job.name, player.job.grade, duty)
    end
    return true
end

function ps.addMoney(source, type, amount, reason)
    local player = ps.getPlayer(source)
    if not player then return false end
    if type == 'cash' or type == 'money' then
        player.addMoney(amount, reason or 'Added by script')
        return true
    elseif type == 'bank' then
        player.addAccountMoney('bank', amount, reason or 'Added by script')
        return true
    end
    return false
end

function ps.removeMoney(source, type, amount, reason)
    local player = ps.getPlayer(source)
    if not player then return false end
    if type == 'cash' or type == 'money' then
        local balance = player.getAccount('money').money
        if balance - amount < 0 then return false end
        player.removeAccountMoney('money', amount, reason or 'Removed by script')
        return true
    elseif type == 'bank' then
        local balance = player.getAccount('bank').money
        if balance - amount >= 0 then
            player.removeAccountMoney('bank', amount, reason or 'Removed by script')
            return true
        end
    end
    return false
end

function ps.getMoney(source, type)
    local player = ps.getPlayer(source)
    if not player then return 0 end
    if not type then type = 'cash' end
    if type == 'cash' or type == 'money' then
        return player.getMoney()
    elseif type == 'bank' then
        return player.getAccount('bank').money
    end
    return 0
end

--- Shared / Job catalog ------------------------------------------------------
function ps.getAllJobs()
    local jobSend = {}
    for k, v in pairs (jobs) do
        table.insert(jobSend, k)
    end
    return jobSend
end

function ps.getSharedJob(jobName)
    if not jobName then return nil end
    return ps.Shared.Jobs[jobName]
end

function ps.getSharedJobData(jobName, data)
    local jobData = ps.getSharedJob(jobName)
    if not jobData then return nil end
    return jobData[data]
end

function ps.getSharedJobGrade(jobName, grade)
    if type(grade) == 'number' then grade = tostring(grade) end
    local job = ps.Shared.Jobs[jobName]
    if not job then return nil end
    return job.grades[grade]
end

function ps.getSharedJobGradeData(jobName, rank, data)
    local grade = ps.getSharedJobGrade(jobName, rank)
    if not grade then return nil end
    return grade[data]
end

function ps.jobExists(jobName)
    return ps.Shared.Jobs[jobName] ~= nil
end

--- Gangs are not a native ESX concept; provide safe no-ops for bridge parity.
function ps.getGang(source) return nil end
function ps.getGangName(source) return nil end
function ps.getGangData(source, data) return nil end
function ps.getGangGrade(source) return nil end
function ps.getGangGradeLevel(source) return nil end
function ps.getGangGradeName(source) return nil end
function ps.isLeader(source) return false end
function ps.getAllGangs() return {} end
function ps.getSharedGang(gang) return nil end
function ps.getSharedGangData(gang, data) return nil end
function ps.getSharedGangRankData(gang, rank, data) return nil end

--- Vehicle / weapon shared catalogs -----------------------------------------
function ps.vehicleOwner(licensePlate)
    local vehicle = MySQL.query.await('SELECT owner FROM owned_vehicles WHERE plate = ?', {licensePlate})
    if not vehicle or #vehicle == 0 then
        return false
    end
    return vehicle[1].owner
end

function ps.getSharedVehicle(model)
    return ps.Shared.Vehicles[model]
end

function ps.getSharedVehicleData(model, dataType)
    local vehicleData = ps.getSharedVehicle(model)
    if not vehicleData then return nil end
    return vehicleData[dataType]
end

function ps.getSharedWeapons(model)
    -- ESX delegates weapon data to inventory resources (e.g. ox_inventory).
    return nil
end

function ps.getSharedWeaponData(model, dataType)
    return nil
end

function ps.hasPermission(source, permission)
    if IsPlayerAceAllowed(source, permission) then
        return true
    end
    return false
end

function ps.isOnline(identifier)
    return ESX.GetPlayerFromIdentifier(identifier) ~= nil
end

--- Items --------------------------------------------------------------------
function ps.getSharedItems()
    if GetResourceState('ox_inventory') == 'started' then
        return exports.ox_inventory:GetItems()
    end
    if ESX.GetItems then return ESX.GetItems() end
    return {}
end

function ps.getItemLabel(item)
    local itemData = ps.getSharedItems()[item]
    if not itemData then return item end
    return itemData.label
end

function ps.getItemWeight(item)
    local itemData = ps.getSharedItems()[item]
    if not itemData then return 0 end
    return itemData.weight or 0
end

RegisterNetEvent('ps_lib:server:toggleDuty', function(bool)
    local src = source
    if bool == nil then
        bool = not ps.getJobDuty(src)
    end
    ps.setJobDuty(src, bool)
end)

--- Exports (parity with qb/qbx bridges) --------------------------------------
exports('getPlayer', ps.getPlayer)
exports('getPlayerByIdentifier', ps.getPlayerByIdentifier)
exports('getPlayerByCid', ps.getPlayerByCid)
exports('getOfflinePlayer', ps.getOfflinePlayer)
exports('getLicense', ps.getLicense)
exports('getIdentifier', ps.getIdentifier)
exports('getCid', ps.getCid)
exports('getSource', ps.getSource)
exports('getPlayerName', ps.getPlayerName)
exports('getName', ps.getName)
exports('getPlayerNameByIdentifier', ps.getPlayerNameByIdentifier)
exports('getPlayerNameByCid', ps.getPlayerNameByCid)
exports('getPlayerData', ps.getPlayerData)
exports('getMetadata', ps.getMetadata)
exports('setMetadata', ps.setMetadata)
exports('getCharInfo', ps.getCharInfo)
exports('getJob', ps.getJob)
exports('getJobName', ps.getJobName)
exports('getJobType', ps.getJobType)
exports('getJobDuty', ps.getJobDuty)
exports('getJobData', ps.getJobData)
exports('getJobGrade', ps.getJobGrade)
exports('getJobGradeLevel', ps.getJobGradeLevel)
exports('getJobGradeName', ps.getJobGradeName)
exports('getJobGradePay', ps.getJobGradePay)
exports('isBoss', ps.isBoss)
exports('getAllPlayers', ps.getAllPlayers)
exports('getEntityCoords', ps.getEntityCoords)
exports('getDistance', ps.getDistance)
exports('checkDistance', ps.checkDistance)
exports('getNearbyPlayers', ps.getNearbyPlayers)
exports('getJobCount', ps.getJobCount)
exports('getJobTypeCount', ps.getJobTypeCount)
exports('createUseable', ps.createUseable)
exports('setJob', ps.setJob)
exports('setJobDuty', ps.setJobDuty)
exports('addMoney', ps.addMoney)
exports('removeMoney', ps.removeMoney)
exports('getMoney', ps.getMoney)
exports('getAllJobs', ps.getAllJobs)
exports('getJobTable', ps.getJobTable)
exports('getSharedJob', ps.getSharedJob)
exports('getSharedJobData', ps.getSharedJobData)
exports('getSharedJobGrade', ps.getSharedJobGrade)
exports('getSharedJobGradeData', ps.getSharedJobGradeData)
exports('getGang', ps.getGang)
exports('getGangName', ps.getGangName)
exports('getGangData', ps.getGangData)
exports('getGangGrade', ps.getGangGrade)
exports('getGangGradeLevel', ps.getGangGradeLevel)
exports('getGangGradeName', ps.getGangGradeName)
exports('isLeader', ps.isLeader)
exports('getAllGangs', ps.getAllGangs)
exports('vehicleOwner', ps.vehicleOwner)
exports('jobExists', ps.jobExists)
exports('hasPermission', ps.hasPermission)
exports('isOnline', ps.isOnline)
exports('getSharedVehicle', ps.getSharedVehicle)
exports('getSharedVehicleData', ps.getSharedVehicleData)
exports('getSharedWeapons', ps.getSharedWeapons)
exports('getSharedWeaponData', ps.getSharedWeaponData)
exports('getSharedGang', ps.getSharedGang)
exports('getSharedGangData', ps.getSharedGangData)
exports('getSharedGangRankData', ps.getSharedGangRankData)
exports('getSharedItems', ps.getSharedItems)
exports('getItemLabel', ps.getItemLabel)
exports('getItemWeight', ps.getItemWeight)
