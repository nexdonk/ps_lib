Config = {}
ps = {}

Config.Debug = false -- Set true to turn ps_lib debug prints on, false to turn them off
Config.Inventory = "auto" -- auto, ox_inventory, qb-inventory, qb-inventory, lj-inventory, tgiann-inventory, jpr-inventory
Config.Target = "auto" -- auto, ox_target, qb-target, interact
Config.EmoteMenu = "rpemotes" -- rpemotes, dpemotes, scully, anything else for custom
Config.Notify = "ox" -- qb, ox, ps, esx, mad_thoughts, okok, lation
Config.Menus = "ox" -- qb, ox, ps, lation
Config.DrawText = "ox" -- qb, ox, ps, lation, okok 
Config.Banking = "qb" -- qb, okok, Renewed, none
Config.VehicleKeys = "qb" -- qb, mrnewb, none
Config.ConvertQBMenu = false -- Convert qb-menu to ps-ui context menu and qb-input to ps-ui input

Config.Progressbar = { -- these are DEFAULT values, you can override them in the progressbar function
    style = "oxcircle", -- qb, oxbar, oxcircle, keep
    Movement = true, -- Disable movement
    CarMovement = true, -- Disable car movement
    Mouse = true, -- Disable mouse
    Combat = true, -- Disable combat
}

Config.Logs = "fivemerr" -- fivemerr or fivemanage

-- ESX job -> job "type" mapping.
-- ESX jobs have no native `type` field (unlike QBCore/Qbox). Resources such as
-- ps-mdt gate access by job type ('leo', 'ems', 'doj'). Map your ESX job NAMES
-- to the appropriate type here so the framework bridge can report a job type.
-- Anything not listed resolves to 'none'.
Config.ESXJobTypes = {
    -- Law Enforcement
    ['police']      = 'leo',
    ['lspd']        = 'leo',
    ['bcso']        = 'leo',
    ['sahp']        = 'leo',
    ['sast']        = 'leo',
    ['sheriff']     = 'leo',
    ['statepolice'] = 'leo',
    ['fib']         = 'leo',
    ['gov']         = 'leo',
    -- EMS / Fire
    ['ambulance']   = 'ems',
    ['ems']         = 'ems',
    ['lsfd']        = 'ems',
    ['fire']        = 'ems',
    ['doctor']      = 'ems',
    -- Department of Justice
    ['lawyer']      = 'doj',
    ['judge']       = 'doj',
    ['attorney']    = 'doj',
    -- Misc (kept for backwards compatibility)
    ['unemployed']  = 'loser',
    ['mechanic']    = 'mechanic',
    ['cardealer']   = 'cardealer',
}

QBCore, ESX, qbx, langs = nil, nil, nil

if GetResourceState('qbx_core') == 'started' then
    qbx = exports.qbx_core
    langs = GetConvar('ox:locale', 'en') or 'en'
elseif GetResourceState('es_extended') == 'started' then
    ESX = exports['es_extended']:getSharedObject()
    langs = GetConvar('esx:locale', 'en') or 'en'
elseif GetResourceState('qb-core') == 'started' then
    QBCore = exports['qb-core']:GetCoreObject()
    langs = GetConvar('qb_locale', 'en') or 'en'
end