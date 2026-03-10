local ESX = exports['es_extended']:getSharedObject()

local societyAccounts = {}
local activityLog = {}
local weeklyStats = {}

local function haspermission(xPlayer, jobName)
    if not xPlayer then return false end
    if xPlayer.job.name ~= jobName then return false end
    if xPlayer.job.grade < ae.mingrade then return false end
    return true
end

local function canmanageemployee(source, targetIdentifier, jobName)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false, nil end
    
    if not haspermission(xPlayer, jobName) then
        return false, xPlayer
    end
    
    if xPlayer.identifier == targetIdentifier then
        return false, xPlayer
    end
    
    local targetPlayer = ESX.GetPlayerFromIdentifier(targetIdentifier)
    if targetPlayer then 
        if targetPlayer.job.name == xPlayer.job.name and targetPlayer.job.grade >= xPlayer.job.grade then
            return false, xPlayer
        end
    end
    
    return true, xPlayer
end

local function GetPlayerGrade(identifier, jobName)
    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)

    if xPlayer and xPlayer.job.name == jobName then
        return xPlayer.job.grade
    end

    local result = MySQL.Sync.fetchScalar([[
        SELECT jobGrade FROM zerio_multijobs 
        WHERE identifier = @identifier AND jobName = @jobName
    ]], {
        ['@identifier'] = identifier,
        ['@jobName'] = jobName
    })

    if result then
        return tonumber(result)
    end

    result = MySQL.Sync.fetchScalar([[
        SELECT job_grade FROM users 
        WHERE identifier = @identifier AND job = @jobName
    ]], {
        ['@identifier'] = identifier,
        ['@jobName'] = jobName
    })

    if result then
        return tonumber(result)
    end

    return nil
end

CreateThread(function()
    local result = MySQL.Sync.fetchAll('SELECT * FROM boss_menu_stats', {})
    if result then
        for _, row in ipairs(result) do
            weeklyStats[row.job_name] = {
                deposits = row.deposits,
                withdrawals = row.withdrawals,
                lastReset = row.last_reset
            }
        end
    end
end)

local function weeklystats(jobName)
    if not weeklyStats[jobName] then return end
    
    MySQL.Async.execute([[
        INSERT INTO boss_menu_stats (job_name, deposits, withdrawals, last_reset)
        VALUES (@job_name, @deposits, @withdrawals, @last_reset)
        ON DUPLICATE KEY UPDATE
            deposits = @deposits,
            withdrawals = @withdrawals,
            last_reset = @last_reset
    ]], {
        ['@job_name'] = jobName,
        ['@deposits'] = weeklyStats[jobName].deposits,
        ['@withdrawals'] = weeklyStats[jobName].withdrawals,
        ['@last_reset'] = weeklyStats[jobName].lastReset
    })
end

local function weeklyresetcheck(jobName)
    if not weeklyStats[jobName] then
        weeklyStats[jobName] = {
            deposits = 0,
            withdrawals = 0,
            lastReset = os.time()
        }
        weeklystats(jobName)
        return
    end
    
    local lastReset = weeklyStats[jobName].lastReset
    local currentTime = os.time()
    local daysSinceReset = (currentTime - lastReset) / 86400
    
    if daysSinceReset >= 7 then
        weeklyStats[jobName].deposits = 0
        weeklyStats[jobName].withdrawals = 0
        weeklyStats[jobName].lastReset = currentTime
        weeklystats(jobName)
    end
end

local function adddeposit(jobName, amount)
    weeklyresetcheck(jobName)
    weeklyStats[jobName].deposits = weeklyStats[jobName].deposits + amount
    weeklystats(jobName)
end

local function addwithdrawal(jobName, amount)
    weeklyresetcheck(jobName)
    weeklyStats[jobName].withdrawals = weeklyStats[jobName].withdrawals + amount
    weeklystats(jobName)
end

local function getIdentityLabel(identifier)
    local result = MySQL.Sync.fetchAll([[
        SELECT firstname, lastname 
        FROM users 
        WHERE identifier = @identifier 
        LIMIT 1
    ]], {
        ['@identifier'] = identifier
    })

    if result and result[1] then
        local firstname = result[1].firstname or ''
        local lastname = result[1].lastname or ''
        local label = (firstname .. ' ' .. lastname):gsub('^%s*(.-)%s*$', '%1')
        if label ~= '' then
            return label
        end
    end

    return 'Zaměstnanec'
end

local function creditBonusAccount(identifier, amount)
    local targetPlayer = ESX.GetPlayerFromIdentifier(identifier)
    if targetPlayer then
        targetPlayer.addAccountMoney('bank', amount)
        return targetPlayer.getName(), true
    end

    local accounts = MySQL.Sync.fetchScalar([[
        SELECT accounts 
        FROM users 
        WHERE identifier = @identifier
    ]], {
        ['@identifier'] = identifier
    })

    if accounts then
        local decoded = json.decode(accounts) or {}
        decoded.bank = (decoded.bank or 0) + amount
        MySQL.Sync.execute([[
            UPDATE users 
            SET accounts = @accounts 
            WHERE identifier = @identifier
        ]], {
            ['@accounts'] = json.encode(decoded),
            ['@identifier'] = identifier
        })
    end

    return getIdentityLabel(identifier), false
end

local function addactvt(jobName, type, text, amount)
    if not activityLog[jobName] then
        activityLog[jobName] = {}
    end
    
    local timestamp = os.time()
    
    table.insert(activityLog[jobName], 1, {
        type = type,
        text = text,
        amount = amount,
        timestamp = timestamp
    })
    
    if #activityLog[jobName] > 10 then
        table.remove(activityLog[jobName])
    end
    
    MySQL.Async.execute([[
        INSERT INTO boss_menu_activities (job_name, type, text, amount, timestamp)
        VALUES (@job_name, @type, @text, @amount, @timestamp)
    ]], {
        ['@job_name'] = jobName,
        ['@type'] = type,
        ['@text'] = text,
        ['@amount'] = amount or 0,
        ['@timestamp'] = timestamp
    })
    
    MySQL.Async.execute('DELETE FROM boss_menu_activities WHERE timestamp < @timestamp', {
        ['@timestamp'] = timestamp - (7 * 86400)
    })
end

lib.callback.register('ae_bossmenu:getweeklystats', function(source, jobName)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not haspermission(xPlayer, jobName) then return { deposits = 0, withdrawals = 0 } end
    
    weeklyresetcheck(jobName)
    
    if not weeklyStats[jobName] then
        return { deposits = 0, withdrawals = 0 }
    end
    
    return {
        deposits = weeklyStats[jobName].deposits,
        withdrawals = weeklyStats[jobName].withdrawals
    }
end)

lib.callback.register('ae_bossmenu:chartdata', function(source, jobName)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not haspermission(xPlayer, jobName) then return {} end
    
    local chartData = {
        deposits = {},
        withdrawals = {},
        labels = {}
    }
    
    local result = MySQL.Sync.fetchAll([[
        SELECT type, amount, timestamp 
        FROM boss_menu_activities 
        WHERE job_name = @job_name 
        AND (type = 'success' OR type = 'warning')
        AND amount > 0
        AND timestamp > @week_ago
        ORDER BY timestamp ASC
    ]], {
        ['@job_name'] = jobName,
        ['@week_ago'] = os.time() - (7 * 86400)
    })
    
    if not result or #result == 0 then
        for i = 6, 0, -1 do
            local date = os.date("%d.%m", os.time() - (i * 86400))
            table.insert(chartData.labels, date)
            table.insert(chartData.deposits, 0)
            table.insert(chartData.withdrawals, 0)
        end
        return chartData
    end
    
    local dailyData = {}
    for i = 6, 0, -1 do
        local dayStart = os.time() - (i * 86400)
        local date = os.date("%d.%m", dayStart)
        dailyData[date] = { deposits = 0, withdrawals = 0 }
        table.insert(chartData.labels, date)
    end
    
    for _, row in ipairs(result) do
        local date = os.date("%d.%m", row.timestamp)
        if dailyData[date] then
            if row.type == 'success' then
                dailyData[date].deposits = dailyData[date].deposits + row.amount
            elseif row.type == 'warning' then
                dailyData[date].withdrawals = dailyData[date].withdrawals + row.amount
            end
        end
    end
    
    for _, label in ipairs(chartData.labels) do
        table.insert(chartData.deposits, dailyData[label].deposits)
        table.insert(chartData.withdrawals, dailyData[label].withdrawals)
    end
    
    return chartData
end)

lib.callback.register('ae_bossmenu:server:getactivities', function(source, jobName)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not haspermission(xPlayer, jobName) then return {} end
    
    if activityLog[jobName] and #activityLog[jobName] > 0 then
        local activities = {}
        for _, activity in ipairs(activityLog[jobName]) do
            local timeAgo = os.time() - activity.timestamp
            local timeText = ""
            
            if timeAgo < 60 then
                timeText = "Před chvílí"
            elseif timeAgo < 3600 then
                timeText = "Před " .. math.floor(timeAgo / 60) .. " min"
            elseif timeAgo < 86400 then
                timeText = "Před " .. math.floor(timeAgo / 3600) .. " hod"
            else
                timeText = "Před " .. math.floor(timeAgo / 86400) .. " dny"
            end
            
            table.insert(activities, {
                type = activity.type,
                text = activity.text,
                time = timeText
            })
        end
        return activities
    end
    
    local result = MySQL.Sync.fetchAll([[
        SELECT type, text, amount, timestamp 
        FROM boss_menu_activities 
        WHERE job_name = @job_name 
        ORDER BY timestamp DESC 
        LIMIT 10
    ]], {
        ['@job_name'] = jobName
    })
    
    if not result then return {} end
    
    activityLog[jobName] = {}
    local activities = {}
    
    for _, row in ipairs(result) do
        local activity = {
            type = row.type,
            text = row.text,
            amount = row.amount,
            timestamp = row.timestamp
        }
        
        table.insert(activityLog[jobName], activity)
        
        local timeAgo = os.time() - row.timestamp
        local timeText = ""
        
        if timeAgo < 60 then
            timeText = "Před chvílí"
        elseif timeAgo < 3600 then
            timeText = "Před " .. math.floor(timeAgo / 60) .. " min"
        elseif timeAgo < 86400 then
            timeText = "Před " .. math.floor(timeAgo / 3600) .. " hod"
        else
            timeText = "Před " .. math.floor(timeAgo / 86400) .. " dny"
        end
        
        table.insert(activities, {
            type = row.type,
            text = row.text,
            time = timeText
        })
    end
    
    return activities
end)

lib.callback.register('ae_bossmenu:server:employeedtls', function(source, jobName)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not haspermission(xPlayer, jobName) then return {} end

    local employees = {}

    local gradesData = MySQL.Sync.fetchAll([[
        SELECT grade, label, salary 
        FROM job_grades 
        WHERE job_name = @job_name
    ]], {
        ['@job_name'] = jobName
    })

    local gradesMap = {}
    if gradesData then
        for _, g in ipairs(gradesData) do
            gradesMap[g.grade] = { label = g.label, salary = g.salary or 0 }
        end
    end

    local onlinePlayers = {}
    local xPlayers = ESX.GetExtendedPlayers()
    for _, xTarget in pairs(xPlayers) do
        onlinePlayers[xTarget.identifier] = xTarget
    end

    local dbEmployees = MySQL.Sync.fetchAll([[
        SELECT zm.identifier, zm.jobGrade, u.firstname, u.lastname
        FROM zerio_multijobs zm
        LEFT JOIN users u ON u.identifier = zm.identifier
        WHERE zm.jobName = @jobName
    ]], {
        ['@jobName'] = jobName
    })

    if dbEmployees then
        for _, row in ipairs(dbEmployees) do
            local grade = tonumber(row.jobGrade) or 0
            local gradeInfo = gradesMap[grade] or { label = 'Neznámá', salary = 0 }
            local salary = gradeInfo.salary
            local bonus = math.floor(salary * 0.1)

            local xTarget = onlinePlayers[row.identifier]
            local name

            if xTarget then
                name = xTarget.getName()
            else
                if row.firstname and row.lastname then
                    name = row.firstname .. ' ' .. row.lastname
                else
                    name = 'Neznámý hráč'
                end
            end

            table.insert(employees, {
                identifier = row.identifier,
                name = name,
                grade = grade,
                grade_label = gradeInfo.label,
                salary = salary,
                bonus = bonus,
                isOnline = xTarget ~= nil
            })
        end
    end

    table.sort(employees, function(a, b)
        return a.grade > b.grade
    end)

    return employees
end)

lib.callback.register('ae_bossmenu:server:jobgrades', function(source, jobName)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not haspermission(xPlayer, jobName) then return {} end
    
    local result = MySQL.Sync.fetchAll([[
        SELECT grade, label, salary 
        FROM job_grades 
        WHERE job_name = @job_name 
        ORDER BY grade ASC
    ]], {
        ['@job_name'] = jobName
    })
    
    if not result then return {} end
    
    local grades = {}
    for _, row in ipairs(result) do
        table.insert(grades, {
            grade = row.grade,
            label = row.label,
            salary = row.salary or 0
        })
    end
    
    return grades
end)

RegisterServerEvent('ae_bossmenu:server:updatesalaries')
AddEventHandler('ae_bossmenu:server:updatesalaries', function(jobName, salaryData)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not haspermission(xPlayer, jobName) then
        TriggerClientEvent('ox_lib:notify', source, { 
            type = 'error', 
            description = 'Nemáš oprávnění.' 
        })
        return
    end
    
    for grade, data in pairs(salaryData) do
        if type(data.salary) ~= 'number' or data.salary < 0 or data.salary > 7500 then
            TriggerClientEvent('ox_lib:notify', source, { 
                type = 'error', 
                description = 'Neplatná částka mzdy.' 
            })
            return
        end
    end
    
    for grade, data in pairs(salaryData) do
        local gradeNum = tonumber(grade)
        local salary = tonumber(data.salary)
        
        MySQL.Sync.execute([[
            UPDATE job_grades 
            SET salary = @salary 
            WHERE job_name = @job_name AND grade = @grade
        ]], {
            ['@job_name'] = jobName,
            ['@grade'] = gradeNum,
            ['@salary'] = salary
        })
        
    end
    
    Wait(200)
    local xPlayers = ESX.GetExtendedPlayers('job', jobName)
    for _, targetPlayer in pairs(xPlayers) do
        local currentGrade = targetPlayer.job.grade
        targetPlayer.setJob(jobName, currentGrade)
    end
    
    addactvt(jobName, 'success', 'Mzdy byly aktualizovány')
    
    TriggerClientEvent('ox_lib:notify', source, { 
        type = 'success', 
        description = 'Mzdy byly úspěšně uloženy a aktualizovány.' 
    })
end)

lib.callback.register('ae_bossmenu:server:getsocmoney', function(source, jobName)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not haspermission(xPlayer, jobName) then return 0 end
    
    local societyName = 'society_' .. jobName
    local money = 0
    
    local finished = false
    TriggerEvent('esx_addonaccount:getSharedAccount', societyName, function(account)
        if account then
            money = account.money
            societyAccounts[societyName] = money
        end
        finished = true
    end)
    
    local timeout = 0
    while not finished and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end
    
    return money
end)

RegisterServerEvent('ae_bossmenu:server:hireplayer')
AddEventHandler('ae_bossmenu:server:hireplayer', function(targetId, grade)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    local jobName = xPlayer.job.name
    local jobLabel = xPlayer.job.label
    
    if not haspermission(xPlayer, jobName) then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Boss menu',
            description = 'Tohle nejde...',
            type = 'error'
        })
        return
    end
    
    if type(grade) ~= 'number' or grade < 0 or grade >= xPlayer.job.grade then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Boss menu',
            description = 'Tohle nejde...',
            type = 'error'
        })
        return
    end
    
    local targetPlayer = ESX.GetPlayerFromId(targetId)
    
    if not targetPlayer then
        TriggerClientEvent('ox_lib:notify', source, { 
            type = 'error', 
            description = 'Hráč nebyl nalezen.' 
        })
        return
    end

    if targetPlayer.job.name == 'unemployed' then
        targetPlayer.setJob(jobName, grade)

        MySQL.Async.execute([[
            INSERT INTO zerio_multijobs (identifier, jobName, jobGrade)
            VALUES (@identifier, @jobName, @jobGrade)
            ON DUPLICATE KEY UPDATE jobGrade = @jobGrade
        ]], {
            ['@identifier'] = targetPlayer.identifier,
            ['@jobName']   = jobName,
            ['@jobGrade']  = grade
        })
    
        addactvt(jobName, 'success', 'Nový zaměstnanec byl najat: ' .. targetPlayer.getName())
    
        TriggerClientEvent('ox_lib:notify', source, { 
            type = 'success', 
            description = 'Úspěšně jsi zaměstnal ' .. targetPlayer.getName() 
        })
        TriggerClientEvent('ox_lib:notify', targetId, { 
            type = 'success', 
            description = 'Byl si přijat do ' .. jobLabel 
        })
    else
        TriggerClientEvent('ox_lib:notify', source, { 
            type = 'error', 
            description = 'Tato osoba už má zaměstnání (' .. targetPlayer.job.label .. ').' 
        })
    end
end)

lib.callback.register('ae_bossmenu:server:nearbyplayer', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or xPlayer.job.grade < ae.mingrade then return {} end
    
    local players = {}
    local sourcePed = GetPlayerPed(source)
    local sourceCoords = GetEntityCoords(sourcePed)
    
    for _, playerId in ipairs(GetPlayers()) do
        local targetId = tonumber(playerId)
        if targetId ~= source then
            local targetPed = GetPlayerPed(targetId)
            local targetCoords = GetEntityCoords(targetPed)
            local distance = #(sourceCoords - targetCoords)
            
            if distance < 5.0 then 
                local targetPlayer = ESX.GetPlayerFromId(targetId)
                if targetPlayer then
                    table.insert(players, {
                        id = targetId,
                        name = targetPlayer.getName(),
                        job = targetPlayer.job.label,
                        distance = math.floor(distance * 10) / 10
                    })
                end
            end
        end
    end
    
    return players
end)

RegisterServerEvent('ae_bossmenu:server:fireplayer')
AddEventHandler('ae_bossmenu:server:fireplayer', function(targetIdentifier)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    local jobName = xPlayer.job.name
    local canManage, manager = canmanageemployee(source, targetIdentifier, jobName)
    
    if not canManage then
        TriggerClientEvent('ox_lib:notify', source, { 
            type = 'error', 
            description = 'Nemáš oprávnění.' 
        })
        return
    end

    MySQL.Async.execute('DELETE FROM zerio_multijobs WHERE identifier = @identifier AND jobName = @jobName', {
        ['@identifier'] = targetIdentifier,
        ['@jobName'] = jobName
    })

    local targetPlayer = ESX.GetPlayerFromIdentifier(targetIdentifier)

    if targetPlayer then
        if targetPlayer.job.name == jobName then
            targetPlayer.setJob('unemployed', 0)
        end
        TriggerClientEvent('ox_lib:notify', targetPlayer.source, { 
            type = 'inform', 
            description = 'Byl jsi vyhozen z ' .. xPlayer.job.label 
        })
    else
        MySQL.Async.execute([[
            UPDATE users 
            SET job = @job, job_grade = @job_grade 
            WHERE identifier = @identifier AND job = @jobName
        ]], {
            ['@identifier'] = targetIdentifier,
            ['@job'] = 'unemployed',
            ['@job_grade'] = 0,
            ['@jobName'] = jobName
        })
    end

    addactvt(jobName, 'danger', 'Zaměstnanec byl vyhozen.')
    TriggerClientEvent('ox_lib:notify', source, { 
        type = 'success', 
        description = 'Zaměstnanec byl vyhozen.' 
    })
end)

RegisterServerEvent('ae_bossmenu:server:promoteplayer')
AddEventHandler('ae_bossmenu:server:promoteplayer', function(targetIdentifier)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    local jobName = xPlayer.job.name
    local canManage, manager = canmanageemployee(source, targetIdentifier, jobName)
    
    if not canManage then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Boss menu',
            description = 'Tohle nejde...',
            type = 'error'
        })
        return
    end
    
    local currentGrade = GetPlayerGrade(targetIdentifier, jobName)
    if not currentGrade then
        TriggerClientEvent('ox_lib:notify', source, { description = 'Hráč už tu nepracuje.', type = 'error' })
        return
    end

    local newGrade = currentGrade + 1

    if newGrade >= xPlayer.job.grade then
        TriggerClientEvent('ox_lib:notify', source, { 
            type = 'error', 
            description = 'Nemůžeš povýšit na tuto hodnost.' 
        })
        return
    end

    local jobGrades = {}
    local jobData = ESX.GetJobs()[jobName]
    
    if jobData then
        for grade, data in pairs(jobData.grades) do
            table.insert(jobGrades, { grade = tonumber(grade), label = data.label })
        end
        table.sort(jobGrades, function(a, b) return a.grade < b.grade end)
        local maxGrade = jobGrades[#jobGrades].grade
        if newGrade > maxGrade then
            TriggerClientEvent('ox_lib:notify', source, { 
                type = 'error', 
                description = 'Tento zaměstnanec už má nejvyšší hodnost.' 
            })
            return
        end
    end

    MySQL.Sync.execute([[
        INSERT INTO zerio_multijobs (identifier, jobName, jobGrade)
        VALUES (@identifier, @jobName, @newGrade)
        ON DUPLICATE KEY UPDATE jobGrade = @newGrade
    ]], {
        ['@newGrade']   = newGrade,
        ['@identifier'] = targetIdentifier,
        ['@jobName']    = jobName
    })

    local targetPlayer = ESX.GetPlayerFromIdentifier(targetIdentifier)
    if targetPlayer and targetPlayer.job.name == jobName then
        targetPlayer.setJob(jobName, newGrade)
        TriggerClientEvent('ox_lib:notify', targetPlayer.source, { 
            type = 'success', 
            description = 'Byl si povýšen!' 
        })
    else
        MySQL.Async.execute([[
            UPDATE users SET job_grade = @newGrade 
            WHERE identifier = @identifier AND job = @jobName
        ]], {
            ['@newGrade'] = newGrade,
            ['@identifier'] = targetIdentifier,
            ['@jobName'] = jobName
        })
    end

    addactvt(jobName, 'success', 'Zaměstnanec povýšený')
    TriggerClientEvent('ox_lib:notify', source, { 
        type = 'success', 
        description = 'Zaměstnanec byl povýšen.' 
    })
end)

RegisterServerEvent('ae_bossmenu:server:demoteplayer')
AddEventHandler('ae_bossmenu:server:demoteplayer', function(targetIdentifier)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    local jobName = xPlayer.job.name
    local canManage, manager = canmanageemployee(source, targetIdentifier, jobName)
    
    if not canManage then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Boss menu',
            description = 'Tohle nejde...',
            type = 'error'
        })
        return
    end
    
    local currentGrade = GetPlayerGrade(targetIdentifier, jobName)
    if not currentGrade then
        TriggerClientEvent('ox_lib:notify', source, { description = 'Hráč už tu nepracuje.', type = 'error' })
        return
    end

    local newGrade = currentGrade - 1

    if newGrade < 0 then
        TriggerClientEvent('ox_lib:notify', source, { 
            type = 'error', 
            description = 'Tento zaměstnanec už má nejnižší hodnost.' 
        })
        return
    end

    MySQL.Sync.execute([[
        INSERT INTO zerio_multijobs (identifier, jobName, jobGrade)
        VALUES (@identifier, @jobName, @newGrade)
        ON DUPLICATE KEY UPDATE jobGrade = @newGrade
    ]], {
        ['@newGrade']   = newGrade,
        ['@identifier'] = targetIdentifier,
        ['@jobName']    = jobName
    })

    local targetPlayer = ESX.GetPlayerFromIdentifier(targetIdentifier)
    if targetPlayer and targetPlayer.job.name == jobName then
        targetPlayer.setJob(jobName, newGrade)
        TriggerClientEvent('ox_lib:notify', targetPlayer.source, { 
            type = 'inform', 
            description = 'Byl si degradován.' 
        })
    else
        MySQL.Async.execute([[
            UPDATE users SET job_grade = @newGrade 
            WHERE identifier = @identifier AND job = @jobName
        ]], {
            ['@newGrade'] = newGrade,
            ['@identifier'] = targetIdentifier,
            ['@jobName'] = jobName
        })
    end

    addactvt(jobName, 'warning', 'Zaměstnanec degradovaný')
    TriggerClientEvent('ox_lib:notify', source, { 
        type = 'success', 
        description = 'Zaměstnanec byl degradován.' 
    })
end)

RegisterServerEvent('ae_bossmenu:server:depositmoney')
AddEventHandler('ae_bossmenu:server:depositmoney', function(amount)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    local jobName = xPlayer.job.name
    
    if not haspermission(xPlayer, jobName) then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Boss menu',
            description = 'Tohle nejde...',
            type = 'error'
        })
        return
    end
    
    local society = 'society_' .. jobName

    if type(amount) ~= 'number' or amount <= 0 or amount > 99999999 then
        TriggerClientEvent('ox_lib:notify', source, { 
            type = 'error', 
            description = 'Neplatná částka.' 
        })
        return
    end

    if xPlayer.getMoney() >= amount then
        xPlayer.removeMoney(amount)
        
        TriggerEvent('esx_addonaccount:getSharedAccount', society, function(account)
            if account then
                account.addMoney(amount)
                societyAccounts[society] = account.money
            end
        end)
        
        addactvt(jobName, 'success', 'Vklad $' .. amount, amount)
        adddeposit(jobName, amount) 
        
        TriggerClientEvent('ox_lib:notify', source, { 
            type = 'success', 
            description = 'Vložil jsi $' .. amount 
        })
    else
        TriggerClientEvent('ox_lib:notify', source, { 
            type = 'error', 
            description = 'Nemáš dostatek peněz.' 
        })
    end
end)

RegisterServerEvent('ae_bossmenu:server:withdraw')
AddEventHandler('ae_bossmenu:server:withdraw', function(amount)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    local jobName = xPlayer.job.name
    
    if not haspermission(xPlayer, jobName) then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Boss menu',
            description = 'Tohle nejde...',
            type = 'error'
        })
        return
    end
    
    local society = 'society_' .. jobName

    if type(amount) ~= 'number' or amount <= 0 or amount > 150000 then
        TriggerClientEvent('ox_lib:notify', source, { 
            type = 'error', 
            description = 'Neplatná částka.' 
        })
        return
    end

    TriggerEvent('esx_addonaccount:getSharedAccount', society, function(account)
        if account and account.money >= amount then
            account.removeMoney(amount)
            xPlayer.addMoney(amount)
            societyAccounts[society] = account.money
            
            addactvt(jobName, 'warning', 'Výběr $' .. amount, amount)
            addwithdrawal(jobName, amount)

            TriggerClientEvent('ox_lib:notify', source, { 
                type = 'success', 
                description = 'Vybral jsi $' .. amount 
            })
        else
            TriggerClientEvent('ox_lib:notify', source, { 
                type = 'error', 
                description = 'Spoločnost nemá dostatek peněz.' 
            })
        end
    end)
end)

RegisterServerEvent('ae_bossmenu:server:paybonus')
AddEventHandler('ae_bossmenu:server:paybonus', function(targetIdentifier, amount)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)

    if not xPlayer then return end

    local jobName = xPlayer.job.name

    if not haspermission(xPlayer, jobName) then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'Nemáš oprávnění.'
        })
        return
    end

    if type(targetIdentifier) ~= 'string' or targetIdentifier == '' then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'Vyber platného zaměstnance.'
        })
        return
    end

    if type(amount) ~= 'number' or amount <= 0 or amount > 100000 then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'Neplatná částka bonusu (max 100 000$).'
        })
        return
    end

    if not GetPlayerGrade(targetIdentifier, jobName) then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'Tento zaměstnanec pro tebe nepracuje.'
        })
        return
    end

    local society = 'society_' .. jobName
    local balance = 0
    local finished = false

    TriggerEvent('esx_addonaccount:getSharedAccount', society, function(account)
        if account then
            balance = account.money
        end
        finished = true
    end)

    local waited = 0
    while not finished and waited < 100 do
        Wait(5)
        waited = waited + 1
    end

    if balance <= 0 or balance < amount then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'Společnost nemá dostatek prostředků.'
        })
        return
    end

    TriggerEvent('esx_addonaccount:getSharedAccount', society, function(account)
        if account then
            account.removeMoney(amount)
            societyAccounts[society] = account.money
        end
    end)

    local recipientName, isOnline = creditBonusAccount(targetIdentifier, amount)
    local formatted = (ESX.Math and ESX.Math.GroupDigits and ESX.Math.GroupDigits(amount)) or tostring(amount)

    if isOnline then
        local targetPlayer = ESX.GetPlayerFromIdentifier(targetIdentifier)
        if targetPlayer then
            TriggerClientEvent('ox_lib:notify', targetPlayer.source, {
                type = 'success',
                description = ('Obdržel jsi bonus %s.'):format(formatted)
            })
        end
    end

    addwithdrawal(jobName, amount)
    addactvt(jobName, 'success', ('Vyplacen bonus %s pro %s'):format(formatted, recipientName), amount)

    TriggerClientEvent('ox_lib:notify', source, {
        type = 'success',
        description = ('Bonus %s byl úspěšně vyplacen.'):format(formatted)
    })
end)

RegisterServerEvent('ae_bossmenu:server:sendannouncement')
AddEventHandler('ae_bossmenu:server:sendannouncement', function(message)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)

    if not xPlayer then return end

    local jobName = xPlayer.job.name

    if not haspermission(xPlayer, jobName) then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'Nemáš oprávnění.'
        })
        return
    end

    if type(message) ~= 'string' then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'Zadej text oznámení.'
        })
        return
    end

    message = message:gsub('^%s+', '')
    message = message:gsub('%s+$', '')

    if message == '' then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'Text oznámení je prázdný.'
        })
        return
    end

    if #message > 180 then
        message = message:sub(1, 180)
    end

    local recipients = ESX.GetExtendedPlayers('job', jobName) or {}
    local sent = 0

    for _, targetPlayer in pairs(recipients) do
        TriggerClientEvent('ae_bossmenu:client:announcement', targetPlayer.source, {
            sender = xPlayer.getName(),
            jobLabel = xPlayer.job.label,
            message = message
        })
        sent = sent + 1
    end

    addactvt(jobName, 'info', 'Odesláno oznámení: "' .. message .. '"')

    TriggerClientEvent('ox_lib:notify', source, {
        type = 'success',
        description = ('Oznámení bylo odesláno %s zaměstnancům.'):format(sent)
    })
end)
