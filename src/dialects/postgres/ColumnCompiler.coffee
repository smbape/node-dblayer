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
    interval: 'interval'

# http://www.postgresql.org/docs/9.4/static/datatype.html
module.exports = class PgColumnCompiler extends ColumnCompiler

PgColumnCompiler::adapter = require './adapter'

# https://www.postgresql.org/docs/9.4/static/datatype-numeric.html
PgColumnCompiler::smallincrements = -> @words.smallserial
PgColumnCompiler::increments = -> @words.serial
PgColumnCompiler::bigincrements = -> @words.bigserial

PgColumnCompiler::smallint = -> @words.smallint
PgColumnCompiler::integer = -> @words.integer
PgColumnCompiler::bigint = -> @words.bigint

PgColumnCompiler::numeric = (precision, scale)->
    type = @words.numeric
    type + '(' + @_num(precision, 8) + ', ' + @_num(scale, 2) + ')'

PgColumnCompiler::float = -> @words.real
PgColumnCompiler::double = -> @words.double

# https://www.postgresql.org/docs/9.4/static/datatype-character.html
PgColumnCompiler::char = (length)->
    type = @words.char
    type + '(' + @_num(length, 255) + ')'

PgColumnCompiler::varchar = (length)->
    type = @words.varchar
    type + '(' + @_num(length, 255) + ')'

# https://www.postgresql.org/docs/9.4/static/datatype-datetime.html
PgColumnCompiler::date = -> @words.date
PgColumnCompiler::time = (tz, precision)->
    if 'number' is typeof tz
        precision = tz
        tz = precision is true

    if tz
        type = @words.timetz
    else
        type = @words.time

    # 6 is the default precision
    precision = @_num(precision, 6)
    "#{type}(#{precision})"

PgColumnCompiler::timestamp = (tz, precision)->
    if 'number' is typeof tz
        precision = tz
        tz = precision is true

    if tz
        type = @words.timestamptz
    else
        type = @words.timestamp

    precision = @_num(precision, 6)
    "#{type}(#{precision})"

PgColumnCompiler::interval = (precision)->
    precision = @_num(precision, null)
    type = @words.interval

    if precision
        return "#{type}(#{precision})"

    switch precision
        when 'YEAR', 'MONTH', 'DAY', 'HOUR', 'MINUTE', 'SECOND', 'YEAR TO MONTH', 'DAY TO HOUR', 'DAY TO MINUTE', 'DAY TO SECOND', 'HOUR TO MINUTE', 'HOUR TO SECOND', 'MINUTE TO SECOND'
            return "#{type}(#{precision})"
        else
            precision = 6
            # 6 is the default precision
            return "#{type}(#{precision})"

PgColumnCompiler::binary = -> @words.bytea

PgColumnCompiler::bool = -> @words.boolean

PgColumnCompiler::enum = (allowed) ->
    # http://stackoverflow.com/questions/10923213/postgres-enum-data-type-or-check-constraint#10984951
    @words.text_check + ' (' + @adapter.escapeId(@args.column) + ' ' + @words.in + ' (' + allowed.map(@adapter.escape) + '))'

PgColumnCompiler::bit = (length) ->
    length = @_num(length, null)
    if length then @words.bit + '(' + length + ')' else @words.bit

PgColumnCompiler::varbit = (length) ->
    length = @_num(length, null)
    if length then @words.bit + '(' + length + ')' else @words.bit

PgColumnCompiler::xml = -> @words.xml
PgColumnCompiler::json = -> @words.json
PgColumnCompiler::jsonb = -> @words.jsonb

PgColumnCompiler::LOWERWORDS = _.defaults LOWERWORDS, ColumnCompiler::LOWERWORDS
PgColumnCompiler::UPPERWORDS = _.defaults tools.toUpperWords(LOWERWORDS), ColumnCompiler::UPPERWORDS
PgColumnCompiler::datetime = PgColumnCompiler::timestamp

PgColumnCompiler::aliases = ->
    instance = super

    for method in ['time', 'timestamp']
        alias = method + 'tz'
        if 'function' isnt typeof instance[alias]
            instance[alias] = instance[method].bind instance, true

    instance
