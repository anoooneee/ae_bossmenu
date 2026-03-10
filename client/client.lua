local ESX = exports['es_extended']:getSharedObject()
local isBoss = false
local playerJob = nil
local bossMenuOpen = false

local function IsPlayerBoss()
    if not playerJob or not ae.bossmenus[playerJob.name] then
        return false
    end
    for _, grade in ipairs(ae.bossmenus[playerJob.name].grades) do
        if playerJob.grade == grade then
            return true
        end
    end
    return false
end

CreateThread(function()
    for jobName, data in pairs(ae.bossmenus) do
        exports.ox_target:addSphereZone({
            coords = data.coords.xyz,
            radius = 1.5,
            options = {
                {
                    name = 'bossmenu_' .. jobName,
                    icon = 'fas fa-briefcase',
                    label = data.label,
                    onSelect = function()
                        if IsPlayerBoss() then
                            OpenBossMenu()
                        else
                            lib.notify({
                                title = 'Chyba',
                                description = 'Nemáš oprávnění na otevření tohoto menu.',
                                type = 'error'
                            })
                        end
                    end,
                    canInteract = function(entity, distance, coords, name)
                        return IsPlayerBoss()
                    end
                }
            }
        })
    end
end)

function OpenBossMenu()
    if bossMenuOpen or not isBoss then return end
    
    bossMenuOpen = true
    SetNuiFocus(true, true)

    local employees = lib.callback.await('ae_bossmenu:server:employeedtls', false, playerJob.name)
    local money = lib.callback.await('ae_bossmenu:server:getsocmoney', false, playerJob.name)
    local activities = lib.callback.await('ae_bossmenu:server:getactivities', false, playerJob.name)
    local weeklyStats = lib.callback.await('ae_bossmenu:getweeklystats', false, playerJob.name)
    local chartData = lib.callback.await('ae_bossmenu:chartdata', false, playerJob.name)
    local grades = lib.callback.await('ae_bossmenu:server:jobgrades', false, playerJob.name) 

    local resourceName = GetCurrentResourceName()

    SendNUIMessage({
        action = 'showMenu',
        jobLabel = playerJob.label,
        employees = employees,
        money = money,
        activities = activities,
        weeklyStats = weeklyStats,
        chartData = chartData,
        grades = grades,
        resourceName = resourceName
    })
end

function CloseBossMenu()
    if not bossMenuOpen then return end
    
    bossMenuOpen = false
    SetNuiFocus(false, false) 
    SendNUIMessage({ action = 'hideMenu' })
end

function RefreshUI()
    if not bossMenuOpen then return end
    local employees = lib.callback.await('ae_bossmenu:server:employeedtls', false, playerJob.name)
    local money = lib.callback.await('ae_bossmenu:server:getsocmoney', false, playerJob.name)
    local activities = lib.callback.await('ae_bossmenu:server:getactivities', false, playerJob.name)
    local weeklyStats = lib.callback.await('ae_bossmenu:getweeklystats', false, playerJob.name)
    local chartData = lib.callback.await('ae_bossmenu:chartdata', false, playerJob.name)
    local grades = lib.callback.await('ae_bossmenu:server:jobgrades', false, playerJob.name)

    SendNUIMessage({
        action = 'updateData',
        employees = employees,
        money = money,
        activities = activities,
        weeklyStats = weeklyStats,
        chartData = chartData,
        grades = grades 
    })
end



RegisterNUICallback('close', function(data, cb)
    CloseBossMenu()
    cb('ok')
end)

RegisterNUICallback('deposit', function(data, cb)
    if data.amount then
        TriggerServerEvent('ae_bossmenu:server:depositmoney', data.amount) 
        RefreshUI() 
    end
    cb('ok')
end)

RegisterNUICallback('withdraw', function(data, cb)
    if data.amount then
        TriggerServerEvent('ae_bossmenu:server:withdraw', data.amount)
        RefreshUI()
    end
    cb('ok')
end)


RegisterNUICallback('hirePlayer', function(data, cb)
    if data.targetId and data.grade then
        TriggerServerEvent('ae_bossmenu:server:hireplayer', data.targetId, data.grade)
        Wait(500)
        RefreshUI()
    end
    cb('ok')
end)

RegisterNUICallback('openHireMenu', function(data, cb)
    local players = lib.callback.await('ae_bossmenu:server:nearbyplayer', false)
    local grades = lib.callback.await('ae_bossmenu:server:jobgrades', false, playerJob.name)
    
    SendNUIMessage({
        action = 'showHireMenu',
        players = players,
        grades = grades
    })
    cb('ok')
end)

RegisterNUICallback('fire', function(data, cb)
    if data.identifier then
        TriggerServerEvent('ae_bossmenu:server:fireplayer', data.identifier)
        Wait(500)
        RefreshUI()
    end
    cb('ok')
end)

RegisterNUICallback('promote', function(data, cb)
    if data.identifier then
        TriggerServerEvent('ae_bossmenu:server:promoteplayer', data.identifier) 
        RefreshUI()
    end
    cb('ok')
end)

RegisterNUICallback('demote', function(data, cb)
    if data.identifier then
        TriggerServerEvent('ae_bossmenu:server:demoteplayer', data.identifier)
        RefreshUI()
    end
    cb('ok')
end)

RegisterNUICallback('refreshEmployees', function(data, cb)
    RefreshUI()
    cb('ok')
end)

RegisterNUICallback('updateSalaries', function(data, cb)
    if data.salaryData then
        TriggerServerEvent('ae_bossmenu:server:updatesalaries', playerJob.name, data.salaryData)
    end
    cb('ok')
end)

RegisterNUICallback('payBonus', function(data, cb)
    if data.identifier and data.amount then
        TriggerServerEvent('ae_bossmenu:server:paybonus', data.identifier, data.amount)
        Wait(500)
        RefreshUI()
    end
    cb('ok')
end)

RegisterNUICallback('sendAnnouncement', function(data, cb)
    if data.message then
        TriggerServerEvent('ae_bossmenu:server:sendannouncement', data.message)
    end
    cb('ok')
end)

RegisterNetEvent('esx:setJob', function(job)
    playerJob = job
    isBoss = IsPlayerBoss()
    if bossMenuOpen and not isBoss then
        CloseBossMenu() 
    end
end)

CreateThread(function()
    ESX.PlayerData = ESX.GetPlayerData()
    playerJob = ESX.PlayerData.job
    isBoss = IsPlayerBoss()
end)

RegisterNetEvent('ae_bossmenu:openFromLunar', function()
    if IsPlayerBoss() then
        OpenBossMenu()
    else
        lib.notify({
            title = 'Chyba',
            description = 'Nemáš oprávnění na otevření tohoto menu.',
            type = 'error'
        })
    end
end)

RegisterNetEvent('ae_bossmenu:client:announcement', function(payload)
    if not payload or not payload.message then return end

    local sender = payload.sender or 'Vedení'
    local title = payload.jobLabel and (payload.jobLabel .. ' | Vedení') or 'Firemní oznámení'

    SendNUIMessage({
        action = 'aeBossToast',
        data = {
            title = title,
            message = payload.message,
            sender = sender
        }
    })
end)
