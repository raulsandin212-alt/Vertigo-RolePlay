-- Engine damage and failure: collisions wear the engine, which degrades slowly, then fails fast, then stops.

local ENGINE_FACTOR <const> = 3.0
local BODY_FACTOR <const> = 3.0
local TANK_FACTOR <const> = 32.0
local CLASS_FACTOR <const> = 0.3
local DEGRADE_BELOW <const> = 250.0
local CASCADE_BELOW <const> = 200.0
local SAFEGUARD <const> = 50.0
local DEGRADE_STEP <const> = 0.076
local CASCADE_STEP <const> = 0.4
local LIMP_TORQUE <const> = 0.15
local TANK_FLOOR <const> = 750.0
local COLLISION_EXPONENT <const> = 0.5
local ENGINE_EXPONENT <const> = 0.3
local ACCEL_SHAPE <const> = 10.0 - 7.5 * 2.0
local BRAKE_SHAPE <const> = 10.0 - 5.0 * 2.0

local DAMAGE_SCALE <const> = { light = 0.5, normal = 1.0, heavy = 2.0 }
local WEAPON_SCALE <const> = { light = 0.6, normal = 1.2, heavy = 2.4 }
local TIRE_MINUTES <const> = { rare = 60, often = 15 }
-- bikes take no extra damage; aircraft, cycles and trains keep the game's own
local NO_SCALE_CLASS <const> = { [8] = true, [13] = true, [15] = true, [16] = true, [21] = true }
local PARTS <const> = { 'radiator', 'axle', 'clutch', 'fuel', 'brakes' }

local tracked, original, last
local brakingForward, brakingReverse = false, false

local function active()
    return Mri.enabled('vehicledamage') and GetResourceState('qbx_vehiclefailure') ~= 'started'
end

local function handling(vehicle, field, value)
    if value == nil then return GetVehicleHandlingFloat(vehicle, 'CHandlingData', field) end
    SetVehicleHandlingFloat(vehicle, 'CHandlingData', field, value + 0.0)
end

local function restoreHandling()
    if tracked and original and DoesEntityExist(tracked) then
        for field, value in pairs(original) do handling(tracked, field, value) end
    end
    tracked, original, last = nil, nil, nil
end

local function trackVehicle(vehicle, cfg)
    restoreHandling()
    tracked = vehicle
    original = {
        fCollisionDamageMult = handling(vehicle, 'fCollisionDamageMult'),
        fEngineDamageMult = handling(vehicle, 'fEngineDamageMult'),
        fWeaponDamageMult = handling(vehicle, 'fWeaponDamageMult'),
        fBrakeForce = handling(vehicle, 'fBrakeForce'),
    }
    -- pulling the handling values toward 1.0 makes cars take damage more alike
    handling(vehicle, 'fCollisionDamageMult', original.fCollisionDamageMult ^ COLLISION_EXPONENT)
    handling(vehicle, 'fEngineDamageMult', original.fEngineDamageMult ^ ENGINE_EXPONENT)
    handling(vehicle, 'fWeaponDamageMult', (WEAPON_SCALE[cfg.weaponDamage] or 1.2) / BODY_FACTOR)
    last = {
        engine = GetVehicleEngineHealth(vehicle),
        body = math.max(GetVehicleBodyHealth(vehicle), CASCADE_BELOW),
        tank = GetVehiclePetrolTankHealth(vehicle),
    }
end

local function wearRandomPart(vehicle)
    if GetResourceState('qbx_mechanicjob') ~= 'started' then return end
    local plate = GetVehicleNumberPlateText(vehicle):match('^%s*(.-)%s*$')
    local part = PARTS[math.random(#PARTS)]
    pcall(function()
        local current = exports.qbx_mechanicjob:GetVehicleStatus(plate, part)
        if current then
            exports.qbx_mechanicjob:SetVehicleStatus(plate, part, current - (math.random() + math.random(0, 1)) * (math.random() + math.random(0, 2)))
        end
    end)
end

local function wheelIndex(vehicle)
    local wheels = GetVehicleNumberOfWheels(vehicle)
    if wheels == 2 then return (math.random(2) - 1) * 4 end
    if wheels == 6 then return math.random(6) - 1 end
    local index = math.random(4) - 1
    return index > 1 and index + 2 or index
end

local function damageStep(vehicle, cfg)
    local engine = GetVehicleEngineHealth(vehicle)
    local body = GetVehicleBodyHealth(vehicle)
    local tank = GetVehiclePetrolTankHealth(vehicle)
    -- a full repair from any script starts the count over
    if engine >= 1000.0 then last.engine = 1000.0 end
    if body >= 1000.0 then last.body = 1000.0 end
    if tank >= 1000.0 then last.tank = 1000.0 end

    local newEngine, newBody, newTank = engine, math.max(body, 0.0), tank
    if engine < 1000.0 or body < 1000.0 or tank < 1000.0 then
        local class = GetVehicleClass(vehicle)
        local scale = NO_SCALE_CLASS[class] and 0.0 or CLASS_FACTOR * (DAMAGE_SCALE[cfg.damage] or 1.0)
        local hit = math.max(
            (last.engine - engine) * ENGINE_FACTOR,
            (last.body - body) * BODY_FACTOR,
            (last.tank - tank) * TANK_FACTOR
        ) * scale
        if hit > engine - SAFEGUARD then hit = hit * 0.7 end
        -- a hit that would kill the engine leaves it a few seconds of life
        if hit > engine then hit = engine - CASCADE_BELOW / 5 end

        newEngine = last.engine - hit
        if newEngine > CASCADE_BELOW + 5 and newEngine < DEGRADE_BELOW then newEngine = newEngine - DEGRADE_STEP end
        if newEngine < CASCADE_BELOW then newEngine = newEngine - CASCADE_STEP end
        if newEngine < SAFEGUARD then newEngine = SAFEGUARD end
        if cfg.explosionGuard and tank < TANK_FLOOR then newTank = TANK_FLOOR end
    end

    if newEngine ~= engine then
        SetVehicleEngineHealth(vehicle, newEngine)
        if cfg.mechanicParts and engine - newEngine > 0.8 then wearRandomPart(vehicle) end
    end
    if newBody ~= body then SetVehicleBodyHealth(vehicle, newBody) end
    if newTank ~= tank then SetVehiclePetrolTankHealth(vehicle, newTank) end
    SetVehicleUndriveable(vehicle, not cfg.limpMode and newEngine <= SAFEGUARD + 1)

    last.engine, last.body, last.tank = newEngine, newBody, newTank

    local minutes = TIRE_MINUTES[cfg.tireBurst]
    if minutes and GetEntitySpeed(vehicle) > 10.0 and GetVehicleTyresCanBurst(vehicle)
        and math.random(minutes * 1200) == 1 then
        SetVehicleTyreBurst(vehicle, wheelIndex(vehicle), false, 1000.0)
    end
end

-- shape > 0 makes the start of the pedal travel softer
local function pedalCurve(value, outMin, outMax, shape)
    local n = math.max(0.0, math.min(1.0, (value - 127.0) / 127.0))
    return outMin + n ^ (10.0 ^ (-shape / 10.0)) * (outMax - outMin)
end

local function driveFrame(vehicle, cfg)
    local engine = last and last.engine or GetVehicleEngineHealth(vehicle)
    local torque = 1.0
    if cfg.torqueLoss and engine < 900.0 then torque = (engine + 200.0) / 1100.0 end

    if cfg.smoothPedals and GetVehicleClass(vehicle) ~= 14 and original then
        local maxBrake = original.fBrakeForce
        local brake = maxBrake
        local accel, reverse = GetControlValue(2, 71), GetControlValue(2, 72)
        local forward = GetEntitySpeedVector(vehicle, true).y
        if forward >= 1.0 then
            if accel > 127 then torque = torque * pedalCurve(accel, 0.1, 1.0, ACCEL_SHAPE) end
            if reverse > 127 then
                brakingForward = true
                brake = pedalCurve(reverse, 0.01, maxBrake, BRAKE_SHAPE)
            end
        elseif forward <= -1.0 then
            if reverse > 127 then torque = torque * pedalCurve(reverse, 0.1, 1.0, ACCEL_SHAPE) end
            if accel > 127 then
                brakingReverse = true
                brake = pedalCurve(accel, 0.01, maxBrake, BRAKE_SHAPE)
            end
        elseif GetEntitySpeed(vehicle) < 1.0 then
            -- hold the stop instead of rolling into reverse until the pedal is released
            if brakingForward then
                DisableControlAction(2, 72, true)
                SetVehicleForwardSpeed(vehicle, forward * 0.98)
                SetVehicleBrakeLights(vehicle, true)
                if GetDisabledControlNormal(2, 72) == 0 then brakingForward = false end
            end
            if brakingReverse then
                DisableControlAction(2, 71, true)
                SetVehicleForwardSpeed(vehicle, forward * 0.98)
                SetVehicleBrakeLights(vehicle, true)
                if GetDisabledControlNormal(2, 71) == 0 then brakingReverse = false end
            end
        end
        if brake > maxBrake - 0.02 then brake = maxBrake end
        handling(vehicle, 'fBrakeForce', brake)
    end

    if cfg.limpMode and engine < SAFEGUARD + 5 then torque = LIMP_TORQUE end
    SetVehicleEngineTorqueMultiplier(vehicle, torque)

    if cfg.preventFlip then
        local roll = GetEntityRoll(vehicle)
        if (roll > 75.0 or roll < -75.0) and GetEntitySpeed(vehicle) < 2.0 then
            DisableControlAction(2, 59, true)
            DisableControlAction(2, 60, true)
        end
    end
end

local driving = false
local function startDriving()
    if driving then return end
    driving = true
    CreateThread(function()
        while cache.seat == -1 and cache.vehicle and active() do
            local cfg = Mri.cfg('vehicledamage')
            if tracked ~= cache.vehicle then trackVehicle(cache.vehicle, cfg) end
            driveFrame(cache.vehicle, cfg)
            Wait(0)
        end
        driving = false
    end)
end

CreateThread(function()
    while true do
        local sleep = 1000
        if cache.seat == -1 and cache.vehicle and active() then
            sleep = 50
            local cfg = Mri.cfg('vehicledamage')
            if tracked ~= cache.vehicle then trackVehicle(cache.vehicle, cfg) end
            damageStep(cache.vehicle, cfg)
            startDriving()
        elseif tracked then
            restoreHandling()
        end
        Wait(sleep)
    end
end)

-- ===== kits ================================================================

local function enginePoint(vehicle)
    local bone = GetEntityBoneIndexByName(vehicle, 'engine')
    if bone ~= -1 then
        local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, GetWorldPositionOfEntityBone(vehicle, bone))
        local rear = offset.y < 0.0
        return GetOffsetFromEntityInWorldCoords(vehicle, 0.0, rear and -2.5 or 2.5, 0.0), rear and 5 or 4
    end
    return GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 2.5, 0.0), 4
end

local function vehicleToRepair()
    if cache.vehicle then
        exports.qbx_core:Notify(locale('vehicledamage.inside_vehicle'), 'error')
        return
    end
    local coords = GetEntityCoords(cache.ped)
    local vehicle = lib.getClosestVehicle(coords, 5.0, false)
    if not vehicle then
        exports.qbx_core:Notify(locale('vehicledamage.no_vehicle'), 'error')
        return
    end
    local point, door = enginePoint(vehicle)
    if #(coords - point) > 2.0 then
        exports.qbx_core:Notify(locale('vehicledamage.go_to_engine'), 'error')
        return
    end
    return vehicle, door
end

local function repair(kit)
    local vehicle, door = vehicleToRepair()
    if not vehicle then return end
    local full = kit == 'advancedrepairkit'
    if not full and GetVehicleEngineHealth(vehicle) >= 500.0 then
        return exports.qbx_core:Notify(locale('vehicledamage.too_healthy'), 'error')
    end

    SetVehicleDoorOpen(vehicle, door, false, false)
    local done = lib.progressBar({
        duration = full and math.random(20000, 30000) or math.random(10000, 20000),
        label = locale('vehicledamage.repairing'),
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, mouse = false, combat = true },
        anim = { dict = 'mini@repair', clip = 'fixing_a_player', flag = 16 },
    })
    SetVehicleDoorShut(vehicle, door, false)
    if not done then return exports.qbx_core:Notify(locale('vehicledamage.canceled'), 'error') end
    if not lib.callback.await('mri_Qbox:vehicledamage:consume', false, kit) then return end

    SetVehicleEngineHealth(vehicle, full and 1000.0 or 500.0)
    SetVehicleEngineOn(vehicle, true, false, false)
    for tyre = 0, 5 do SetVehicleTyreFixed(vehicle, tyre) end
    exports.qbx_core:Notify(locale('vehicledamage.repaired'), 'success')
end

local function clean()
    if cache.vehicle then return exports.qbx_core:Notify(locale('vehicledamage.inside_vehicle'), 'error') end
    local vehicle = lib.getClosestVehicle(GetEntityCoords(cache.ped), 3.0, false)
    if not vehicle then return exports.qbx_core:Notify(locale('vehicledamage.no_vehicle'), 'error') end

    TaskStartScenarioInPlace(cache.ped, 'WORLD_HUMAN_MAID_CLEAN', 0, true)
    local done = lib.progressBar({
        duration = math.random(10000, 20000),
        label = locale('vehicledamage.cleaning'),
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, mouse = false, combat = true },
    })
    ClearPedTasks(cache.ped)
    if not done then return exports.qbx_core:Notify(locale('vehicledamage.canceled'), 'error') end
    if not lib.callback.await('mri_Qbox:vehicledamage:consume', false, 'cleaningkit') then return end

    -- dirt only syncs from the entity owner
    NetworkRequestControlOfEntity(vehicle)
    pcall(lib.waitFor, function() return NetworkHasControlOfEntity(vehicle) or nil end, nil, 2000)
    SetVehicleDirtLevel(vehicle, 0.0)
    WashDecalsFromVehicle(vehicle, 1.0)
    exports.qbx_core:Notify(locale('vehicledamage.cleaned'), 'success')
end

RegisterNetEvent('mri_Qbox:vehicledamage:useKit', function(kit)
    if not active() then return end
    if kit == 'cleaningkit' then clean() else repair(kit) end
end)

RegisterNetEvent('mri_Qbox:vehicledamage:fix', function()
    local vehicle = cache.vehicle
    if not vehicle or cache.seat ~= -1 then
        return exports.qbx_core:Notify(locale('vehicledamage.driver_required'), 'error')
    end
    SetVehicleFixed(vehicle)
    SetVehicleDeformationFixed(vehicle)
    SetVehicleDirtLevel(vehicle, 0.0)
    WashDecalsFromVehicle(vehicle, 1.0)
    SetVehicleUndriveable(vehicle, false)
    SetVehicleEngineOn(vehicle, true, false, false)
    if last then last.engine, last.body, last.tank = 1000.0, 1000.0, 1000.0 end

    if GetResourceState('cdn-fuel') == 'started' then
        pcall(function() exports['cdn-fuel']:SetFuel(vehicle, 100.0) end)
    else
        SetVehicleFuelLevel(vehicle, 100.0)
        Entity(vehicle).state:set('fuel', 100.0, true)
    end
    if GetResourceState('qbx_mechanicjob') == 'started' then
        TriggerEvent('vehiclemod:client:fixEverything')
    end
    exports.qbx_core:Notify(locale('vehicledamage.repaired'), 'success')
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then restoreHandling() end
end)
