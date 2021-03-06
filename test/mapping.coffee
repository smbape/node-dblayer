_ = require 'lodash'
moment = require 'moment'
Backbone = require 'backbone'
mapping = exports

domains = {
    serial:
        type: 'increments'
    short_label:
        type: 'varchar'
        type_args: [31]
    medium_label:
        type: 'varchar'
        type_args: [63]
    long_label:
        type: 'varchar'
        type_args: [255]
    comment:
        type: 'varchar'
        type_args: [1024]
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
    email:
        type: 'varchar'
        type_args: [63]
    code:
        type: 'varchar'
        type_args: [31]
}

domains.mdate = _.defaults {
    lock: true
    update: (model, options, extra)->
        new Date()
}, domains.datetime

mapping['Data'] =
    table: 'BASIC_DATA'
    ctor: Backbone.Model.extend {className: 'Data'}
    id:
        name: 'id'
        column: 'DAT_ID'
        domain: domains.serial
    properties:
        title: className: 'Property'
        author:
            column: 'AOR_ID'
            className: 'User'
            fk: 'AUTHOR'
        delegator: 
            column: 'DOR_ID'
            className: 'User'
            fk: 'DELEGATOR'
        operator: 
            column: 'OOR_ID'
            className: 'User'
            fk: 'OPERATOR'
        cdate:
            column: 'DAT_CDATE'
            domain: domains.datetime
        mdate:
            lock: true
            column: 'DAT_MDATE'
            domain: domains.mdate
        version:
            column: 'DAT_VERSION'
            domain: domains.version

mapping['User'] =
    table: 'USERS'
    id: className: 'Data'
    properties:
        name:
            column: 'USE_NAME'
            domain: domains.medium_label
        firstName:
            column: 'USE_FIRST_NAME'
            domain: domains.long_label
        email:
            column: 'USE_EMAIL'
            domain: domains.email
        login:
            column: 'USE_LOGIN'
            domain: domains.short_label
        password:
            column: 'USE_PASSWORD'
            domain: domains.long_label
        country: className: 'Country'
        occupation:
            column: 'USE_OCCUPATION'
            domain: domains.long_label
        language: className: 'Language'
    constraints: [
        {type: 'unique', name: 'LOGIN', properties: ['login']}
        {type: 'unique', name: 'EMAIL', properties: ['email']}
    ]

mapping['Property'] =
    table: 'PROPERTIES'
    id:
        name: 'id'
        column: 'LPR_ID'
        domain: domains.serial
    properties:
        code:
            column: 'LPR_CODE'
            domain: domains.code
            nullable: false
    constraints: {type: 'unique', properties: ['code']}

mapping['Language'] =
    table: 'LANGUAGES'
    id:
        name: 'id'
        column: 'LNG_ID'
        domain: domains.serial
    properties:
        code:
            column: 'LNG_CODE'
            domain: domains.short_label
        key:
            column: 'LNG_KEY'
            domain: domains.short_label
        label:
            column: 'LNG_LABEL'
            domain: domains.medium_label
        property: className: 'Property'
    constraints: {type: 'unique', properties: ['code']}

mapping['Translation'] =
    table: 'TRANSLATIONS'
    id:
        name: 'id'
        column: 'TRL_ID'
        domain: domains.serial
    properties:
        value:
            column: 'TRL_VALUE'
            domain: domains.comment
        language:
            className: 'Language'
            nullable: false

            # since the unique index starts with this property
            # there is no need for a separate index to make joinction on foreign key faster
            # this is the default behaviour on mysql
            fkindex: false
        property:
            className: 'Property'
            nullable: false
    constraints: {type: 'unique', properties: ['language', 'property']}

mapping['Country'] =
    table: 'COUNTRIES'
    id:
        name: 'id'
        column: 'CRY_ID'
        domain: domains.serial
    properties:
        code:
            column: 'CRY_CODE'
            domain: domains.code
            nullable: false
        property: className: 'Property'

{PersistenceManager} = require('../')
Model = PersistenceManager::Model

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

class ModelJ extends Model
    className: 'ClassJ'

mapping['ClassJ'] =
    ctor: ModelJ
    table: 'CLASS_J'
    id:
        className: 'ClassC'
    properties:
        propJ1:
            column: 'PROP_J1'
            domain: domains.short_label
        propJ2:
            column: 'PROP_J2'
            domain: domains.short_label
        propJ3:
            column: 'PROP_J3'
            domain: domains.short_label
        propJ4:
            column: 'PROP_J4'
            domain: domains.short_label
            defaultValue: 'default value'
        propClassD:
            column: 'PROP_J5'
            className: 'ClassD'
        propClassE:
            column: 'PROP_J6'
            className: 'ClassE'

mapping.numeric_types =
    id:
        name: 'id'
        type: 'smallincrements'
    properties:
        tinyint:
            column: 'tinyint'
            type: 'tinyint'
        smallint:
            column: 'smallint'
            type: 'smallint'
        integer:
            column: 'integer'
            type: 'integer'
        bigint:
            column: 'bigint'
            type: 'bigint'
        numeric:
            column: 'numeric'
            type: 'numeric'
        'numeric(11,3)':
            column: 'numeric(11,3)'
            type: 'numeric'
            type_args: [11, 3]
        float:
            column: 'float'
            type: 'float'
        double:
            column: 'double'
            type: 'double'

mapping.character_types =
    id:
        name: 'id'
        type: 'increments'
    properties:
        char:
            column: 'char'
            type: 'char'
        varchar:
            column: 'varchar'
            type: 'varchar'
        tinytext:
            column: 'tinytext'
            type: 'tinytext'
        mediumtext:
            column: 'mediumtext'
            type: 'mediumtext'
        text:
            column: 'text'
            type: 'text'

mapping.date_time_types =
    id:
        name: 'id'
        type: 'bigincrements'
    properties:
        date:
            column: 'date'
            type: 'date'
        datetime:
            column: 'datetime'
            type: 'datetime'
        timestamp:
            column: 'timestamp'
            type: 'timestamp'
        time:
            column: 'time'
            type: 'time'

mapping.other_types =
    id:
        name: 'id'
        type: 'smallincrements'
    properties:
        bool:
            column: 'bool'
            type: 'bool'
        enum:
            column: 'enum'
            type: 'enum'
            type_args: ['a', 'b', 'c', 'd']
        binary:
            column: 'binary'
            type: 'binary'
        varbinary:
            column: 'varbinary'
            type: 'varbinary'
        bit:
            column: 'bit'
            type: 'bit'
        varbit:
            column: 'varbit'
            type: 'varbit'
        xml:
            column: 'xml'
            type: 'xml'
        json:
            column: 'json'
            type: 'json'
        jsonb:
            column: 'jsonb'
            type: 'jsonb'
        uuid:
            column: 'uuid'
            type: 'uuid'
