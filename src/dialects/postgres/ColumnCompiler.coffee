_ = require 'lodash'
ColumnCompiler = require '../../schema/ColumnCompiler'
tools = require '../../tools'
map = Array::map

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
    real: 'real'

# http://www.postgresql.org/docs/9.4/static/datatype.html
module.exports = class PgColumnCompiler extends ColumnCompiler

PgColumnCompiler::adapter = require './adapter'

# https://www.postgresql.org/docs/9.4/static/datatype-numeric.html
PgColumnCompiler::smallincrements = -> this.words.smallserial
PgColumnCompiler::increments = -> this.words.serial
PgColumnCompiler::bigincrements = -> this.words.bigserial

PgColumnCompiler::smallint = -> this.words.smallint
PgColumnCompiler::integer = -> this.words.integer
PgColumnCompiler::bigint = -> this.words.bigint

PgColumnCompiler::numeric = (precision, scale)->
    this.words.numeric + '(' + this._num(precision, 8) + ', ' + this._num(scale, 2) + ')'

PgColumnCompiler::float = -> this.words.real
PgColumnCompiler::double = -> this.words.double

# https://www.postgresql.org/docs/9.4/static/datatype-character.html
PgColumnCompiler::char = (length)->
    this.words.char + '(' + this._num(length, 255) + ')'

PgColumnCompiler::varchar = (length)->
    this.words.varchar + '(' + this._num(length, 255) + ')'

# https://www.postgresql.org/docs/9.4/static/datatype-datetime.html
PgColumnCompiler::date = -> this.words.date
PgColumnCompiler::time = (tz, precision)->
    if 'number' is typeof tz
        precision = tz
        tz = precision is true

    if tz
        type = this.words.timetz
    else
        type = this.words.time

    # 6 is the default precision
    precision = this._num(precision, 6)
    "#{type}(#{precision})"

PgColumnCompiler::timestamp = (tz, precision)->
    if 'number' is typeof tz
        precision = tz
        tz = precision is true

    if tz
        type = this.words.timestamptz
    else
        type = this.words.timestamp

    precision = this._num(precision, 6)
    "#{type}(#{precision})"

PgColumnCompiler::interval = (precision)->
    precision = this._num(precision, null)
    type = this.words.interval

    if precision
        return "#{type}(#{precision})"

    switch precision
        when 'YEAR', 'MONTH', 'DAY', 'HOUR', 'MINUTE', 'SECOND', 'YEAR TO MONTH', 'DAY TO HOUR', 'DAY TO MINUTE', 'DAY TO SECOND', 'HOUR TO MINUTE', 'HOUR TO SECOND', 'MINUTE TO SECOND'
            return "#{type}(#{precision})"
        else
            precision = 6
            # 6 is the default precision
            return "#{type}(#{precision})"

PgColumnCompiler::binary =
PgColumnCompiler::varbinary =
PgColumnCompiler::bytea = -> this.words.bytea

PgColumnCompiler::bool = -> this.words.boolean

PgColumnCompiler::enum = ->
    # http://stackoverflow.com/questions/10923213/postgres-enum-data-type-or-check-constraint#10984951
    this.words.text_check + ' (' + this.adapter.escapeId(this.args.column) + ' ' + this.words.in + ' (' + map.call(arguments, this.adapter.escape).join(',') + '))'

PgColumnCompiler::bit = (length) ->
    length = this._num(length, null)
    if length and length isnt 1 then this.words.bit + '(' + length + ')' else this.words.bit

PgColumnCompiler::varbit = (length) ->
    length = this._num(length, null)
    if length then this.words.varbit + '(' + length + ')' else this.words.varbit

PgColumnCompiler::uuid = -> this.words.uuid
PgColumnCompiler::xml = -> this.words.xml
PgColumnCompiler::json = -> this.words.json
PgColumnCompiler::jsonb = -> this.words.jsonb

PgColumnCompiler::LOWERWORDS = _.defaults LOWERWORDS, ColumnCompiler::LOWERWORDS
PgColumnCompiler::UPPERWORDS = _.defaults tools.toUpperWords(LOWERWORDS), ColumnCompiler::UPPERWORDS
PgColumnCompiler::datetime = PgColumnCompiler::timestamp

PgColumnCompiler::aliases = ->
    instance = ColumnCompiler.prototype.aliases.apply(this, arguments)

    for method in ['time', 'timestamp']
        alias = method + 'tz'
        if 'function' isnt typeof instance[alias]
            instance[alias] = instance[method].bind instance, true

    instance
