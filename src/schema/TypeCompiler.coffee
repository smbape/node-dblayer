_ = require 'lodash'
tools = require '../tools'

module.exports = class TypeCompiler
    adapter: require './adapter'

    constructor: (options)->
        options = @options = _.clone options
        @args = {}

        if !!options.lower
            @words = @LOWERWORDS
        else
            @words = @UPPERWORDS

LOWERWORDS = TypeCompiler::LOWERWORDS = {
    in: 'in'
    on: 'on'
    create: 'create'
    create_table: 'create table'
    alter: 'alter'
    table: 'table'
    column: 'column'
    create_index: 'create index'
    create_unique_index: 'create unique index'
    index: 'index'
    if_exists: 'if exists'
    if_not_exists: 'if not exists'
    constraint: 'constraint'
    not: 'not'
    null: 'null'
    not_null: 'not null'
    check: 'check'
    default: 'default'
    unique: 'unique'
    primary_key: 'primary key'
    references: 'references'
    foreign_key: 'foreign key'
    add: 'add'
    add_constraint: 'add constraint'
    cascade: 'cascade'
    restrict: 'restrict'
    on_update: 'on update'
    on_delete: 'on delete'
    drop: 'drop'
    alter_table: 'alter table'
    alter_column: 'alter column'
    alter_index: 'alter index'
    drop_column: 'drop column'
    drop_constraint: 'drop constraint'
    drop_index: 'drop index'
    type: 'type'
    set: 'set'
    set_default: 'set default'
}

# ================================================================
# Numeric Types
# ================================================================
TypeCompiler::smallincrements = -> throw new Error 'smallincrements type is not defined'
TypeCompiler::increments = -> throw new Error 'increments type is not defined'
TypeCompiler::bigincrements = -> throw new Error 'bigincrements type is not defined'

_.extend LOWERWORDS,
    smallint: 'smallint'
    integer: 'integer'
    bigint: 'bigint'

TypeCompiler::tinyint =
TypeCompiler::smallint = -> @words.smallint
TypeCompiler::integer = -> @words.integer
TypeCompiler::bigint = -> @words.bigint

_.extend LOWERWORDS,
    numeric: 'numeric'
    float: 'float'
    double: 'double precision'

TypeCompiler::numeric = (precision, scale) ->
    @words.numeric + '(' + @_num(precision, 8) + ', ' + @_num(scale, 2) + ')'

TypeCompiler::float = (precision, scale) ->
    @words.float + '(' + @_num(precision, 8) + ', ' + @_num(scale, 2) + ')'

TypeCompiler::double = -> @words.double

# ================================================================
# Character Types
# ================================================================
_.extend LOWERWORDS,
    char: 'char'
    varchar: 'varchar'
    text: 'text'

TypeCompiler::char = (length)->
    @words.char + '(' + @_num(length, 255) + ')'

TypeCompiler::varchar = (length)->
    @words.varchar + '(' + @_num(length, 255) + ')'

TypeCompiler::text = -> @words.text

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

TypeCompiler::date = -> @words.date
TypeCompiler::datetime = -> @words.datetime
TypeCompiler::time = -> @words.time
TypeCompiler::timestamp = -> @words.timestamp

_.extend LOWERWORDS,
    binary: 'binary'
    bool: 'bool'

TypeCompiler::binary = -> @words.blob
TypeCompiler::bool = -> @words.boolean
TypeCompiler::enu = -> throw new Error 'enu type is not defined'

_.extend LOWERWORDS,
    bit: 'bit'
    varbit: 'varbit'

TypeCompiler::bit = -> throw new Error 'bit type is not defined'
TypeCompiler::varbit = -> throw new Error 'varbit type is not defined'

_.extend LOWERWORDS,
    xml: 'xml'
    json: 'json'
    jsonb: 'jsonb'
    uuid: 'uuid'

TypeCompiler::xml =
TypeCompiler::json =
TypeCompiler::jsonb = -> @words.text
TypeCompiler::uuid = -> @words.char

TypeCompiler::_num = (val, fallback) ->
    if val is undefined or val is null
        return fallback
    number = parseInt(val, 10)
    if isNaN(number) then fallback else number

TypeCompiler::ALIASES =
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

TypeCompiler::aliases = ->
    instance = @

    for type, aliases of TypeCompiler::ALIASES
        for alias in aliases
            if 'function' isnt typeof instance[alias]
                instance[alias] = instance[type]

    for method in ['time', 'timestamp']
        alias = method + 'tz'
        if 'function' isnt typeof instance[alias]
            instance[alias] = instance[method].bind instance, true

    instance

TypeCompiler::UPPERWORDS = tools.toUpperWords TypeCompiler::LOWERWORDS
