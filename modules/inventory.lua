local weaponModule = require 'modules.weapons'
local carryModule = require 'modules.carry'
local weaponsConfig = require 'data.weapons'

local Inventory = exports.ox_inventory:GetPlayerItems() or {}
local playerState = LocalPlayer.state
local currentWeapon = {}

-- Flashlight loop lifecycle
local FLASH_LOOP_KEY = nil

local function startFlashLoopIfNeeded(weapon)
    if not weapon or not weapon.metadata then return end
    if not hasFlashLight(weapon.metadata.components) then return end

    local serial = weapon.metadata.serial
    if serial and serial ~= FLASH_LOOP_KEY then
        -- stop previous loop if module provides a stopper
        if FLASH_LOOP_KEY and weaponModule.stopFlashlight then
            pcall(weaponModule.stopFlashlight, FLASH_LOOP_KEY)
        end
        FLASH_LOOP_KEY = serial
        CreateThread(function()
            weaponModule.loopFlashlight(serial)
        end)
    end
end

local function stopFlashLoop()
    if FLASH_LOOP_KEY and weaponModule.stopFlashlight then
        pcall(weaponModule.stopFlashlight, FLASH_LOOP_KEY)
    end
    FLASH_LOOP_KEY = nil
end

-- Debounce heavy rebuilds to next tick
local _scheduled = false
local function scheduleRefresh()
    if _scheduled then return end
    _scheduled = true
    SetTimeout(0, function()
        _scheduled = false
        weaponModule.updateWeapons(Inventory, currentWeapon)
        carryModule.updateCarryState(Inventory)
    end)
end

local hasFlashLight = require 'modules.utils'.hasFlashLight
AddEventHandler('ox_inventory:currentWeapon', function(weapon)
    if weapon and weapon.name then
        local searchName = weapon.name:lower()
        if weaponsConfig[searchName] then
            currentWeapon = weapon

            startFlashLoopIfNeeded(currentWeapon)
            scheduleRefresh()
            return

        end
    else
        local weaponName = (currentWeapon and currentWeapon.name) and currentWeapon.name:lower() or nil
        
        -- stop any running flashlight loop
        stopFlashLoop()
        
        currentWeapon = {}
        
        if weaponName and weaponsConfig[weaponName] then
            scheduleRefresh()
            return
        end
    end
end)

--- Updates the inventory with the changes
AddEventHandler('ox_inventory:updateInventory', function(changes)
    if not changes then
        return
    end

    for slot, item in pairs(changes) do
        local s = tonumber(slot) or slot
        if item == nil or item == false then
            Inventory[s] = nil       -- clear removed slot
        else
            Inventory[s] = item      -- add/update slot
        end
    end

    scheduleRefresh()
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == cache.resource then
        Wait(100)
        if table.type(playerState.weapons_carry or {}) ~= 'empty' then
            playerState:set('weapons_carry', false, true)

            scheduleRefresh()
        end

        if table.type(playerState.carry_items or {}) ~= 'empty' then
            playerState:set('carry_items', false, true)

            scheduleRefresh()
        end
    end
end)








--[[
    Utility functions for handling updates such as going into different instances, vehicles, ped changes etc.
]]

local function refreshWeapons()
    if playerState.weapons_carry and table.type(playerState.weapons_carry) ~= 'empty' then
        Inventory = exports.ox_inventory:GetPlayerItems()

        playerState:set('weapons_carry', false, true)

        scheduleRefresh()
    end
end exports("RefreshWeapons", refreshWeapons)


AddStateBagChangeHandler('hide_props', ('player:%s'):format(cache.serverId), function(_, _, value)
    if value then
        local items = playerState.weapons_carry

        if items and table.type(items) ~= 'empty' then
            playerState:set('weapons_carry', false, true)
        end

        local carryItems = playerState.carry_items

        if carryItems and table.type(carryItems) ~= 'empty' then
            playerState:set('carry_items', false, true)
            playerState:set('carry_loop', false, true)
        end
        stopFlashLoop()
    else
        CreateThread(function()
            scheduleRefresh()
        end)
    end
end)

-- To be fair I don't know if this is needed but it's here just in case
lib.onCache('ped', function()
   refreshWeapons()
end)

-- Some components like flashlights are being removed whenever a player enters a vehicle so we need to refresh the weapons_carry state when they exit
lib.onCache('vehicle', function(value)
    if not value then
        local items = playerState.weapons_carry

        if items and table.type(items) ~= 'empty' then
            for i = 1, #items do
                local item = items[i]

                if item.components and table.type(item.components) ~= 'empty' then
                    return refreshWeapons()
                end
            end
        end
    end
end)

AddStateBagChangeHandler('instance', ('player:%s'):format(cache.serverId), function(_, _, value)
    if value == 0 then
        if playerState.weapons_carry and table.type(playerState.weapons_carry) ~= 'empty' then
            weaponModule.refreshProps(Inventory, currentWeapon)
        end
    end
end)
