_ = require 'lodash'
tools = require '../tools'

module.exports = class ColumnCompiler
    adapter: require './adapter'

    constructor: (options)->
        options = @options = _.clone options
        @args = {}

        if !!options.lower
            @words = @LOWERWORDS
        else
            @words = @UPPERWORDS

        for method in ['escape', 'escapeId', 'escapeSearch', 'escapeBeginWith', 'escapeEndWith']
            if 'function' is typeof @adapter[method]
                @[method] = @adapter[method].bind @adapter

LOWERWORDS = ColumnCompiler::LOWERWORDS = {
    add: 'add'
    add_column: 'add column'
    add_constraint: 'add constraint'
    alter: 'alter'
    alter_column: 'alter column'
    alter_index: 'alter index'
    alter_table: 'alter table'
    cascade: 'cascade'
    check: 'check'
    column: 'column'
    constraint: 'constraint'
    create: 'create'
    create_index: 'create index'
    create_table: 'create table'
    create_unique_index: 'create unique index'
    default: 'default'
    drop: 'drop'
    drop_column: 'drop column'
    drop_constraint: 'drop constraint'
    drop_index: 'drop index'
    drop_table: 'drop table'
    foreign_key: 'foreign key'
    if_exists: 'if exists'
    if_not_exists: 'if not exists'
    in: 'in'
    index: 'index'
    not: 'not'
    not_null: 'not null'
    null: 'null'
    on: 'on'
    on_delete: 'on delete'
    on_update: 'on update'
    primary_key: 'primary key'
    references: 'references'
    restrict: 'restrict'
    set: 'set'
    set_default: 'set default'
    table: 'table'
    to: 'to'
    type: 'type'
    unique: 'unique'
}

# ================================================================
# Numeric Types
# ================================================================
ColumnCompiler::smallincrements = -> throw new Error 'smallincrements type is not defined'
ColumnCompiler::increments = -> throw new Error 'increments type is not defined'
ColumnCompiler::bigincrements = -> throw new Error 'bigincrements type is not defined'

_.extend LOWERWORDS,
    smallint: 'smallint'
    integer: 'integer'
    bigint: 'bigint'

ColumnCompiler::tinyint =
ColumnCompiler::smallint = -> @words.smallint
ColumnCompiler::integer = -> @words.integer
ColumnCompiler::bigint = -> @words.bigint

_.extend LOWERWORDS,
    numeric: 'numeric'
    float: 'float'
    double: 'double precision'

ColumnCompiler::numeric = (precision, scale) ->
    @words.numeric + '(' + @_num(precision, 8) + ', ' + @_num(scale, 2) + ')'

ColumnCompiler::float = (precision, scale) ->
    @words.float + '(' + @_num(precision, 8) + ', ' + @_num(scale, 2) + ')'

ColumnCompiler::double = -> @words.double

# ================================================================
# Character Types
# ================================================================
_.extend LOWERWORDS,
    char: 'char'
    varchar: 'varchar'
    text: 'text'

ColumnCompiler::char = (length)->
    @words.char + '(' + @_num(length, 255) + ')'

ColumnCompiler::varchar = (length)->
    @words.varchar + '(' + @_num(length, 255) + ')'

ColumnCompiler::text = -> @words.text

# ================================================================
# Date/Time Types
# ================================================================
_.extend LOWERWORDS,
    date: 'date'
    datetime: 'datetime'
    time: 'time'
    timestamp: 'timestamp'
    timetz: 'timetz'
    timestamptz: 'timestamptz'

ColumnCompiler::date = -> @words.date
ColumnCompiler::datetime = -> @words.datetime
ColumnCompiler::time = -> @words.time
ColumnCompiler::timestamp = -> @words.timestamp

_.extend LOWERWORDS,
    binary: 'binary'
    bool: 'bool'

ColumnCompiler::binary = -> @words.blob
ColumnCompiler::bool = -> @words.boolean
ColumnCompiler::enu = -> throw new Error 'enu type is not defined'

_.extend LOWERWORDS,
    bit: 'bit'
    varbit: 'varbit'

ColumnCompiler::bit = -> throw new Error 'bit type is not defined'
ColumnCompiler::varbit = -> throw new Error 'varbit type is not defined'

_.extend LOWERWORDS,
    xml: 'xml'
    json: 'json'
    jsonb: 'jsonb'
    uuid: 'uuid'

ColumnCompiler::xml =
ColumnCompiler::json =
ColumnCompiler::jsonb = -> @words.text
ColumnCompiler::uuid = -> @words.char

ColumnCompiler::_num = (val, fallback) ->
    if val is undefined or val is null
        return fallback
    number = parseInt(val, 10)
    if isNaN(number) then fallback else number

ColumnCompiler::ALIASES =
    smallincrements: ['serial2', 'smallserial']
    increments: ['serial', 'serial4']
    bigincrements: ['serial8', 'bigserial']
    bigint: ['biginteger', 'int8']
    bool: ['boolean']
    double: ['float8']
    enu: ['enum']
    interger: ['int', 'int4', 'mediumint']
    decimal: ['numeric']
    float: ['real', 'float4']
    mediumint: ['mediuminteger']
    numeric: ['decimal']
    smallint: ['int2', 'smallinteger']

ColumnCompiler::aliases = ->
    instance = @

    for type, aliases of ColumnCompiler::ALIASES
        for alias in aliases
            if 'function' isnt typeof instance[alias]
                instance[alias] = instance[type]

    for method in ['time', 'timestamp']
        alias = method + 'tz'
        if 'function' isnt typeof instance[alias]
            instance[alias] = instance[method].bind instance, true

    instance

ColumnCompiler::UPPERWORDS = tools.toUpperWords ColumnCompiler::LOWERWORDS

ColumnCompiler::getTypeString = (spec)->
    type = spec.type.toLowerCase()
    type_args = if Array.isArray(spec.type_args) then spec.type_args else []
    if 'function' is typeof @[type]
        type = @[type].apply @, type_args
    else
        err = new Error 'Unknown type'
        err.code = 'UNKNOWN TYPE'
        throw err
        # type_args.unshift type
        # type = type_args.join(' ')

    type

ColumnCompiler::getColumnModifier = (spec)->
    if spec.nullable is false
        return @words.not_null
    else if spec.defaultValue isnt undefined and spec.defaultValue isnt null
        return @words.default + ' ' + spec.defaultValue
    else
        return @words.null
