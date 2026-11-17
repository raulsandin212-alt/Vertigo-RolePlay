-- Repair and cleaning kits and the admin /fix of the vehicledamage module.

local KITS <const> = {
    repairkit = 'Kit de reparo',
    advancedrepairkit = 'Kit de reparo avançado',
    cleaningkit = 'Kit de limpeza',
}
local pending = {} -- [source] = kit being used, removed only when the progress bar ends

local function active()
    return Mri.enabled('vehicledamage') and GetResourceState('qbx_vehiclefailure') ~= 'started'
end

-- with the old resource still running, its items and /fix stay untouched (qbx_core keeps the last registration)
local legacy = GetResourceState('qbx_vehiclefailure') == 'started'

if not legacy then
    for kit in pairs(KITS) do
        exports.qbx_core:CreateUseableItem(kit, function(source)
            if not active() then return end
            pending[source] = kit
            TriggerClientEvent('mri_Qbox:vehicledamage:useKit', source, kit)
        end)
    end
end

lib.callback.register('mri_Qbox:vehicledamage:consume', function(source, kit)
    if not KITS[kit] or pending[source] ~= kit then return false end
    pending[source] = nil
    return exports.ox_inventory:RemoveItem(source, kit, 1) == true
end)

AddEventHandler('playerDropped', function()
    pending[source] = nil
end)

if not legacy then
    lib.addCommand('fix', { help = 'Conserta e abastece o veículo em que você está (admin)', restricted = 'group.admin' }, function(source)
        if not active() then return end
        TriggerClientEvent('mri_Qbox:vehicledamage:fix', source)
    end)
end

local function announce(on)
    TriggerEvent('mri:itemUse', on and KITS or {})
end

AddEventHandler('mri:itemUse:ask', function()
    announce(active())
end)

Mri.lifecycle('vehicledamage', function()
    if GetResourceState('qbx_vehiclefailure') == 'started' then
        print('^3[mri_Qbox] vehicledamage: o qbx_vehiclefailure está ligado, o módulo fica parado. Tire ele da pasta para usar o módulo.^7')
    end
    announce(active())
end, function() announce(false) end)
