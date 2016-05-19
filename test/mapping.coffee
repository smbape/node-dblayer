_ = require 'lodash'
moment = require 'moment'

mapping = module.exports

handlersDate = 
    read: (value, options)->
        moment.utc(value, 'YYYY-MM-DD HH:mm:ss.SSS').toDate()
    write: (value, model, options)->
        moment(value).utc().format 'YYYY-MM-DD HH:mm:ss.SSS'

handlersCreation = _.extend
    insert: (value, model, options)->
        new Date()
, handlersDate

handlersModification = _.extend {update: handlersCreation.insert}, handlersCreation

mapping['Data'] =
    table: 'BASIC_DATA'
    id:
        name: 'id'
        column: 'DAT_ID'
    properties:
        title:
            className: 'Property'
        author:
            column: 'AOR_ID'
            className: 'User'
        delegator: 
            column: 'DOR_ID'
            className: 'User'
        operator: 
            column: 'OOR_ID'
            className: 'User'
        cdate:
            column: 'DAT_CDATE'
            handlers: handlersCreation
        mdate:
            lock: true
            column: 'DAT_MDATE'
            handlers: handlersModification
        version:
            lock: true
            column: 'DAT_VERSION'
            handlers:
                insert: (value, model, options)->
                    '1.0'
                update: (value, model, options)->
                    if 'major' is model.get('semver')
                        return (parseInt(value.split('.')[0], 10) + 1) + '.0'
                    else
                        value = value.split('.')
                        value[1] = 1 + parseInt(value[1], 10)
                        return value.join('.')

mapping['User'] =
    table: 'USERS'
    id: className: 'Data'
    properties:
        name: 'USE_NAME'
        firstName: 'USE_FIRST_NAME'
        email: 'USE_EMAIL'
        login: 'USE_LOGIN'
        password: 'USE_PASSWORD'
        country: className: 'Country'
        occupation: 'USE_OCCUPATION'
        language: className: 'Language'
        ip: 'USE_IP'
    constraints: [
        {type: 'unique', properties: ['login']}
        {type: 'unique', properties: ['email']}
    ]

mapping['Right'] =
    table: 'RIGHTS'
    id:
        name: 'id'
        column: 'RGT_ID'
    properties:
        code: 'RGT_CODE'
    constraints: {type: 'unique', properties: ['code']}

mapping['UserRight'] =
    table: 'USR_RGT'
    properties:
        user: className: 'User'
        right: className: 'Right'
    constraints: {type: 'unique', properties: ['user', 'right']}

mapping['Property'] =
    table: 'PROPERTIES'
    id:
        name: 'id'
        column: 'LPR_ID'
    properties:
        code: 'LPR_CODE'
    constraints: {type: 'unique', properties: ['code']}

mapping['Language'] =
    table: 'LANGUAGES'
    id:
        name: 'id'
        column: 'LNG_ID'
    properties:
        code: 'LNG_CODE'
        key: 'LNG_KEY'
        label: 'LNG_LABEL'
        property: className: 'Property'
    constraints: {type: 'unique', properties: ['code']}

mapping['Translation'] =
    table: 'TRANSLATIONS'
    properties:
        value: 'TRL_VALUE'
        language: className: 'Language'
        property: className: 'Property'

mapping['Country'] =
    table: 'COUNTRIES'
    id:
        name: 'id'
        column: 'CRY_ID'
    properties:
        code: 'CRY_CODE'
        property: className: 'Property'

mapping['Processor'] =
    table: 'PROCESSORS'
    id: className: 'Data'
    properties:
        code: 'PRC_CODE'
        nbCores: 'PRC_NB_CORES'
        serie: 'PRC_SERIE'
        socket: 'PRC_SOCKET'
        manufacturer: 'PRC_MANUFACTURER'
        price: 'PRC_PRICE'
        tdp: 'PRC_TDP'
        releaseDate:
            column: 'PRC_RELEASE_DATE'
            handlers: handlersDate

mapping['Token'] =
    table: 'TOKEN'
    id:
        name: 'id'
        column: 'TOK_ID'
    properties:
        value: 'TOK_VALUE'
        user: className: 'User'
