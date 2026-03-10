cy = {}

cy.bossmenus = {
    ['police'] = {
        job = 'police',
        grades = {15, 14, 13, 12, 4},
        coords = vec(409.3655, 313.1514, 103.0199),
        label = 'Boss menu - LSPD'
    },

    --[[
    TEMPLATE
    ['job_name'] = {
        job = 'job',
        grades = {1, 2, 3},
        coords = vec4(0.0, 0.0, 0.0, 0.0),
        label = 'Boss menu - Example'
    }
    ]]

}

cy.paycheck = {
    enabled = false,
    interval = 20, 
    bonusPercent = 10, 
    account = 'bank' 
}

cy.mingrade = 0
