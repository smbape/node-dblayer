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

{PersistenceManager} = require('../')
Model = PersistenceManager::Model

domains = {
    serial:
        type: 'bigincrements'
    short_label:
        type: 'varchar'
        type_args: [31]
    medium_label:
        type: 'varchar'
        type_args: [63]
    long_label:
        type: 'varchar'
        type_args: [255]
    version:
        type: 'varchar'
        type_args: [10]
        nullable: false
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
    datetime:
        type: 'timestamp'
        nullable: false
        handlers:
            insert: (model, options, extra)->
                new Date()
            read: (value, model, options)->
                moment.utc(moment(value).format 'YYYY-MM-DD HH:mm:ss.SSS').toDate()
            write: (value, model, options)->
                moment(value).utc().format 'YYYY-MM-DD HH:mm:ss.SSS'
}

domains.mdate = _.defaults {
    lock: true
    update: (model, options, extra)->
        new Date()
}, domains.datetime

class ModelA extends Model
    className: 'ClassA'

mapping['ClassA'] =
    ctor: ModelA
    table: 'CLASS_A'
    id:
        name: 'idA'
        column: 'A_ID'
        domain: domains.serial
    properties:
        propA1:
            column: 'PROP_A1'
            domain: domains.short_label
        propA2:
            column: 'PROP_A2'
            domain: domains.short_label
        propA3:
            column: 'PROP_A3'
            domain: domains.short_label
        creationDate:
            column: 'CREATION_DATE'
            domain: domains.datetime
        modificationDate:
            column: 'MODIFICATION_DATE'
            domain: domains.mdate
        version:
            lock: true
            column: 'VERSION'
            domain: domains.version

class ModelB extends Model
    className: 'ClassB'

mapping['ClassB'] =
    ctor: ModelB
    table: 'CLASS_B'
    id: className: 'ClassA'
    properties:
        propB1:
            column: 'PROP_B1'
            domain: domains.short_label
        propB2:
            column: 'PROP_B2'
            domain: domains.short_label
        propB3:
            column: 'PROP_B3'
            domain: domains.short_label

class ModelC extends Model
    className: 'ClassC'

mapping['ClassC'] =
    ctor: ModelC
    table: 'CLASS_C'
    id:
        name: 'idC'
        column: 'C_ID'
        domain: domains.serial
    properties:
        propC1:
            column: 'PROP_C1'
            domain: domains.short_label
        propC2:
            column: 'PROP_C2'
            domain: domains.short_label
        propC3:
            column: 'PROP_C3'
            domain: domains.short_label

class ModelD extends Model
    className: 'ClassD'

mapping['ClassD'] =
    ctor: ModelD
    table: 'CLASS_D'
    id: className: 'ClassA'
    mixins: 'ClassC'
    properties:
        propD1:
            column: 'PROP_D1'
            domain: domains.short_label
        propD2:
            column: 'PROP_D2'
            domain: domains.short_label
        propD3:
            column: 'PROP_D3'
            domain: domains.short_label

class ModelE extends Model
    className: 'ClassE'

mapping['ClassE'] =
    ctor: ModelE
    table: 'CLASS_E'
    id: className: 'ClassB'
    mixins: 'ClassC'
    properties:
        propE1:
            column: 'PROP_E1'
            domain: domains.short_label
        propE2:
            column: 'PROP_E2'
            domain: domains.short_label
        propE3:
            column: 'PROP_E3'
            domain: domains.short_label

class ModelF extends Model
    className: 'ClassF'

mapping['ClassF'] =
    ctor: ModelF
    table: 'CLASS_F'
    id:
        className: 'ClassC'
        pk: 'CUSTOM'
    properties:
        propF1:
            column: 'PROP_F1'
            domain: domains.short_label
        propF2:
            column: 'PROP_F2'
            domain: domains.short_label
        propF3:
            column: 'PROP_F3'
            domain: domains.short_label
        propClassD:
            column: 'A_ID'
            className: 'ClassD'
            fk: 'CUSTOM'
        propClassE:
            column: 'CLA_A_ID'
            className: 'ClassE'

class ModelG extends Model
    className: 'ClassG'

mapping['ClassG'] =
    ctor: ModelG
    table: 'CLASS_G'
    id:
        name: 'idG'
        column: 'G_ID'
        domain: domains.serial
    constraints: {type: 'unique', properties: ['propG1', 'propG2']}
    properties:
        propG1:
            column: 'PROP_G1'
            domain: domains.short_label
        propG2:
            column: 'PROP_G2'
            domain: domains.short_label
        propG3:
            column: 'PROP_G3'
            domain: domains.short_label

class ModelH extends Model
    className: 'ClassH'

mapping['ClassH'] =
    ctor: ModelH
    table: 'CLASS_H'
    mixins: ['ClassD', 'ClassG']
    properties:
        propH1:
            column: 'PROP_H1'
            domain: domains.short_label
        propH2:
            column: 'PROP_H2'
            domain: domains.short_label
        propH3:
            column: 'PROP_H3'
            domain: domains.short_label

class ModelI extends Model
    className: 'ClassI'

mapping['ClassI'] =
    ctor: ModelI
    table: 'CLASS_I'
    id: className: 'ClassG'
