_ = require 'lodash'
TypeCompiler = require '../../schema/TypeCompiler'
tools = require '../../tools'

LOWERWORDS =
    smallserial: 'smallserial'
    serial: 'serial'
    bigserial: 'bigserial'
    bytea: 'bytea'
    text_check: 'text check'
    add_primary_key: 'add primary key'
    rename_to: 'rename to'

module.exports = class PgTypeCompiler extends TypeCompiler
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

PgTypeCompiler::LOWERWORDS = _.defaults LOWERWORDS, TypeCompiler::LOWERWORDS
PgTypeCompiler::UPPERWORDS = _.defaults tools.toUpperWords(LOWERWORDS), TypeCompiler::UPPERWORDS
PgTypeCompiler::datetime = PgTypeCompiler::timestamp
