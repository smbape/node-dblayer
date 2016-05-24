_ = require 'lodash'
ColumnCompiler = require '../../schema/ColumnCompiler'
tools = require '../../tools'

LOWERWORDS =
    smallserial: 'smallserial'
    serial: 'serial'
    bigserial: 'bigserial'
    bytea: 'bytea'
    text_check: 'text check'
    add_primary_key: 'add primary key'
    rename_to: 'rename to'
    no_action: 'no action'
    set_null: 'set null'
    set_default: 'set default'
    rename_constraint: 'rename constraint'
    inherits: 'inherits'

# http://www.postgresql.org/docs/9.4/static/datatype.html
module.exports = class PgColumnCompiler extends ColumnCompiler
    adapter: require './adapter'
    smallincrements: -> @words.smallserial
    increments: -> @words.serial
    bigincrements: -> @words.bigserial

    # smallint: -> @words.smallint
    # integer: -> @words.integer
    # bigint: -> @words.bigint

    # numeric: (precision, scale)->
    #     type = @words.numeric
    #     type + '(' + @_num(precision, 8) + ', ' + @_num(scale, 2) + ')'

    float: -> @words.real
    # double: -> @words.double

    # char: (length)->
    #     type = @words.char
    #     type + '(' + @_num(length, 255) + ')'

    # varchar: (length)->
    #     type = @words.varchar
    #     type + '(' + @_num(length, 255) + ')'

    # date: -> @words.date
    time: (tz, precision)->
        if 'number' is typeof tz
            precision = tz
            tz = precision is true

        if tz
            type = @words.timetz
        else
            type = @words.time

        precision = @_num(precision, null)
        if precision
            "#{type}(#{precision})"
        else
            type

    timestamp: (tz, precision)->
        if 'number' is typeof tz
            precision = tz
            tz = precision is true

        if tz
            type = @words.timestamptz
        else
            type = @words.timestamp

        precision = @_num(precision, null)
        if precision
            "#{type}(#{precision})"
        else
            type

    binary: -> @words.bytea

    # exports.bool = -> @words.boolean

    enu: (allowed) ->
        # http://stackoverflow.com/questions/10923213/postgres-enum-data-type-or-check-constraint#10984951
        @words.text_check + ' (' + @adapter.escapeId(@args.column) + ' ' + @words.in + ' (\'' + allowed.map(@adapter.escape) + '\'))'

    bit: (length) ->
        length = @_num(length, null)
        if length then @words.bit + '(' + length + ')' else @words.bit

    varbit: (length) ->
        length = @_num(length, null)
        if length then @words.bit + '(' + length + ')' else @words.bit

    xml: -> @words.xml
    json: -> @words.json
    jsonb: -> @words.jsonb

    pkString: (pkName, columns)->
        @adapter.escapeId(pkName) + ' ' + @words.primary_key + ' (' + columns.sort().map(@adapter.escapeId).join(', ') + ')'

    ukString: (ukName, columns)->
        @adapter.escapeId(ukName) + ' ' + @words.unique + ' (' + columns.sort().map(@adapter.escapeId).join(', ') + ')'

    indexString: (indexName, columns, tableNameId)->
        @adapter.escapeId(indexName) + ' ' + @words.on + ' ' + tableNameId + '(' + columns.sort().map(@adapter.escapeId).join(', ') + ')'

PgColumnCompiler::LOWERWORDS = _.defaults LOWERWORDS, ColumnCompiler::LOWERWORDS
PgColumnCompiler::UPPERWORDS = _.defaults tools.toUpperWords(LOWERWORDS), ColumnCompiler::UPPERWORDS
PgColumnCompiler::datetime = PgColumnCompiler::timestamp
