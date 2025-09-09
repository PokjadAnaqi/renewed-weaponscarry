local weaponModule   = require 'modules.weapons'
local carryModule    = require 'modules.carry'
local weaponsConfig  = require 'data.weapons'

local Inventory      = exports.ox_inventory:GetPlayerItems() or {}
local playerState    = LocalPlayer.state
local currentWeapon  = {}
local hasFlashLight

-- Flashlight loop lifecycle
local FLASH_LOOP_KEY = nil

local function startFlashLoopIfNeeded(weapon)
    if not weapon or not weapon.metadata then return end
    if not hasFlashLight or type(hasFlashLight) ~= 'function' then return end
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

-- Only allow props from slots 1–6 / if you use custom hotbar slots [default 1-5]
local function filterSlotsCustom(inv)
    local out = {}
    for slot, item in pairs(inv) do
        local s = tonumber(slot)
        if s and s >= 1 and s <= 6 then
            out[s] = item
        end
    end
    return out
end

-- Ensure a weapon object complies with 1–6 visibility rule
local function coerceWeaponToVisibleSlot(weapon)
    if not weapon then return nil end
    local s = tonumber(weapon.slot)
    if not s or s < 1 or s > 6 then
        return nil
    end
    return weapon
end

local _scheduled = false
local function scheduleRefresh()
    if _scheduled then return end
    _scheduled = true
    SetTimeout(0, function()
        _scheduled = false

        -- Only pass allowed slots to visual modules
        local filtered = filterSlotsCustom(Inventory)
        local cw = coerceWeaponToVisibleSlot(currentWeapon)

        weaponModule.updateWeapons(filtered, cw)
        carryModule.updateCarryState(filtered)
    end)
end

do
    local ok, utils = pcall(require, 'modules.utils')
    if ok and utils and type(utils.hasFlashLight) == 'function' then
        hasFlashLight = utils.hasFlashLight
    else
        print('^3[Renewed-Weaponscarry]^7 hasFlashLight missing or not a function in modules.utils; flashlight checks disabled')
        hasFlashLight = function() return false end
    end
end

AddEventHandler('ox_inventory:currentWeapon', function(weapon)
    if weapon and weapon.name then
        local searchName = weapon.name:lower()
        if weaponsConfig[searchName] then
            currentWeapon = weapon

            -- manage flashlight loop & refresh visuals
            startFlashLoopIfNeeded(currentWeapon)
            scheduleRefresh()
            return
        end
    else
        -- weapon unequipped; stop loop and clear current
        local weaponName = (currentWeapon and currentWeapon.name) and currentWeapon.name:lower() or nil
        stopFlashLoop()
        currentWeapon = {}

        if weaponName and weaponsConfig[weaponName] then
            scheduleRefresh()
            return
        end
    end
end)

AddEventHandler('ox_inventory:updateInventory', function(changes)
    if not changes then return end

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

local function refreshWeapons()
    if playerState.weapons_carry and table.type(playerState.weapons_carry) ~= 'empty' then
        Inventory = exports.ox_inventory:GetPlayerItems()
        playerState:set('weapons_carry', false, true)
        scheduleRefresh()
    end
end
exports("RefreshWeapons", refreshWeapons)

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

lib.onCache('ped', function()
    refreshWeapons()
end)

-- Some components (e.g., flashlights) are removed on vehicle enter; refresh after exit
-- Hide back-weapons when entering vehicles (except motorcycles)
lib.onCache('vehicle', function(vehicle)
    if vehicle then
        -- entering a vehicle
        local class = GetVehicleClass(vehicle)
        if class ~= 8 then -- 8 = Motorcycles (exempt)
            local items = playerState.weapons_carry
            if items and table.type(items) ~= 'empty' then
                -- remember we hid due to vehicle, so we can restore on exit
                playerState:set('weapons_carry', false, true)
                playerState:set('hide_on_vehicle', true, true)
            end
        end
    else
        -- exiting a vehicle
        if playerState.hide_on_vehicle then
            playerState:set('hide_on_vehicle', false, true)
            -- rebuild props next tick
            scheduleRefresh()
        else
            -- keep your existing exit logic (e.g. component refresh checks)
            refreshWeapons()
        end
    end
end)

AddStateBagChangeHandler('instance', ('player:%s'):format(cache.serverId), function(_, _, value)
    if value == 0 then
        if playerState.weapons_carry and table.type(playerState.weapons_carry) ~= 'empty' then
            weaponModule.refreshProps(filterSlotsCustom(Inventory), coerceWeaponToVisibleSlot(currentWeapon))
        end
    end
end)
