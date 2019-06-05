_ = require 'lodash'
tools = require '../tools'

module.exports = class ColumnCompiler
    adapter: require './adapter'

    constructor: (options)->
        options = this.options = _.clone options
        this.args = {}

        if !!options.lower
            this.words = this.LOWERWORDS
        else
            this.words = this.UPPERWORDS

        for method in ['escape', 'escapeId', 'escapeSearch', 'escapeBeginWith', 'escapeEndWith']
            if 'function' is typeof this.adapter[method]
                @[method] = this.adapter[method].bind this.adapter

        this.aliases()

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
    enum: 'enum'
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
# ColumnCompiler::smallincrements = -> throw new Error 'smallincrements type is not defined'
# ColumnCompiler::increments = -> throw new Error 'increments type is not defined'
# ColumnCompiler::bigincrements = -> throw new Error 'bigincrements type is not defined'

_.extend LOWERWORDS,
    tinyint: 'tinyint'
    smallint: 'smallint'
    integer: 'integer'
    bigint: 'bigint'

ColumnCompiler::tinyint =
ColumnCompiler::smallint = -> this.words.smallint
# ColumnCompiler::integer = -> this.words.integer
# ColumnCompiler::bigint = -> this.words.bigint

_.extend LOWERWORDS,
    decimal: 'decimal'
    numeric: 'numeric'
    float: 'float'
    double: 'double precision'
    real: 'real'

# ColumnCompiler::decimal =
# ColumnCompiler::numeric = (precision, scale) ->
#     this.words.numeric + '(' + this._num(precision, 8) + ', ' + this._num(scale, 2) + ')'

# ColumnCompiler::float = (precision, scale) ->
#     this.words.float + '(' + this._num(precision, 8) + ', ' + this._num(scale, 2) + ')'

# ColumnCompiler::double = -> this.words.double

# ================================================================
# Character Types
# ================================================================
_.extend LOWERWORDS,
    char: 'char'
    varchar: 'varchar'
    tinytext: 'tinytext'
    mediumtext: 'mediumtext'
    text: 'text'

# ColumnCompiler::char = (length)->
#     this.words.char + '(' + this._num(length, 255) + ')'

# ColumnCompiler::varchar = (length)->
#     this.words.varchar + '(' + this._num(length, 255) + ')'

ColumnCompiler::tinytext =
ColumnCompiler::mediumtext =
ColumnCompiler::text = -> this.words.text

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

# ColumnCompiler::date = -> this.words.date
# ColumnCompiler::datetime = -> this.words.datetime
# ColumnCompiler::time = -> this.words.time
# ColumnCompiler::timestamp = -> this.words.timestamp

# ================================================================
# Other Types
# ================================================================
_.extend LOWERWORDS,
    bool: 'bool'
    boolean: 'boolean'
    enum: 'enum'

# ColumnCompiler::bool = -> this.words.boolean
# ColumnCompiler::enum = -> throw new Error 'enum type is not defined'

_.extend LOWERWORDS,
    binary: 'binary'
    bit: 'bit'
    varbinary: 'varbinary'
    varbit: 'varbit'

# ColumnCompiler::binary =
# ColumnCompiler::bit = (length)->
#     length = this._num(length, null)
#     if length then this.words.bit + '(' + length + ')' else this.words.bit

ColumnCompiler::varbinary =
ColumnCompiler::varbit = (length)->
    length = this._num(length, null)
    if length then this.words.bit + '(' + length + ')' else this.words.bit

_.extend LOWERWORDS,
    xml: 'xml'
    json: 'json'
    jsonb: 'jsonb'
    uuid: 'uuid'

ColumnCompiler::xml =
ColumnCompiler::json =
ColumnCompiler::jsonb = -> this.words.text
ColumnCompiler::uuid = -> this.words.char + '(63)'

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
    integer: ['int', 'int4', 'mediumint']
    decimal: ['numeric']
    float: ['real', 'float4']
    mediumint: ['mediuminteger']
    numeric: ['decimal']
    smallint: ['int2', 'smallinteger']

ColumnCompiler::aliases = ->
    instance = @

    for type, aliases of this.ALIASES
        for alias in aliases
            if 'function' isnt typeof instance[alias]
                instance[alias] = instance[type]

    instance

ColumnCompiler::pkString = (pkName, columns)->
    this.adapter.escapeId(pkName) + ' ' + this.words.primary_key + ' (' + columns.map(this.adapter.escapeId).join(', ') + ')'

ColumnCompiler::ukString = (ukName, columns)->
    this.adapter.escapeId(ukName) + ' ' + this.words.unique + ' (' + columns.map(this.adapter.escapeId).join(', ') + ')'

ColumnCompiler::indexString = (indexName, columns, tableNameId)->
    this.adapter.escapeId(indexName) + ' ' + this.words.on + ' ' + tableNameId + '(' + columns.map(this.adapter.escapeId).join(', ') + ')'

ColumnCompiler::getTypeString = (spec)->
    type = spec.type.toLowerCase()
    type_args = if Array.isArray(spec.type_args) then spec.type_args else []
    if 'function' is typeof @[type]
        type = @[type].apply @, type_args
    else
        err = new Error "Unknown type '#{type}'"
        err.code = 'UNKNOWN_TYPE'
        throw err
        # type_args.unshift type
        # type = type_args.join(' ')

    type

ColumnCompiler::getColumnModifier = (spec)->
    if spec.defaultValue isnt undefined and spec.defaultValue isnt null
        return this.words.default + ' ' + spec.defaultValue
    else if spec.nullable is false
        return this.words.not_null
    else
        return this.words.null

ColumnCompiler::UPPERWORDS = tools.toUpperWords ColumnCompiler::LOWERWORDS
