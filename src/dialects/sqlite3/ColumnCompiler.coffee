_ = require 'lodash'
ColumnCompiler = require '../../schema/ColumnCompiler'
tools = require '../../tools'
map = Array::map

LOWERWORDS = {}

# https://www.sqlite.org/datatype3.html
module.exports = class Sqlite3ColumnCompiler extends ColumnCompiler

Sqlite3ColumnCompiler::adapter = require './adapter'

# https://www.sqlite.org/lang_createtable.html
LOWERWORDS.autoincrement = 'autoincrement'
Sqlite3ColumnCompiler::smallincrements =
Sqlite3ColumnCompiler::mediumincrements =
Sqlite3ColumnCompiler::bigincrements =
Sqlite3ColumnCompiler::increments = -> [@words.integer, @words.primary_key, @words.autoincrement].join(' ')

Sqlite3ColumnCompiler::tinyint =
Sqlite3ColumnCompiler::smallint =
Sqlite3ColumnCompiler::mediumint =
Sqlite3ColumnCompiler::bigint =
Sqlite3ColumnCompiler::int2 =
Sqlite3ColumnCompiler::int8 =
Sqlite3ColumnCompiler::integer = -> @words.integer

LOWERWORDS.character = 'character'
Sqlite3ColumnCompiler::char = (m)->
    @words.character + '(' + @_num(m, 255) + ')'

Sqlite3ColumnCompiler::varchar = (m)->
    @words.varchar + '(' + @_num(m, 255) + ')'

Sqlite3ColumnCompiler::text = -> @words.text

LOWERWORDS.blob = 'blob'
Sqlite3ColumnCompiler::blob = @words.blob

LOWERWORDS.real = 'real'
Sqlite3ColumnCompiler::real = -> @words.real
Sqlite3ColumnCompiler::double = -> @words.double
Sqlite3ColumnCompiler::float = -> @words.float

Sqlite3ColumnCompiler::numeric = # -> @words.numeric
Sqlite3ColumnCompiler::decimal = (precision, scale)->
    @words.decimal + '(' + @_num(precision, 8) + ', ' + @_num(scale, 2) + ')'

Sqlite3ColumnCompiler::bool = -> @words.boolean

Sqlite3ColumnCompiler::date = -> @words.date
Sqlite3ColumnCompiler::datetime = -> @words.date

PgColumnCompiler::enum = ->
    # http://stackoverflow.com/questions/10923213/postgres-enum-data-type-or-check-constraint#10984951
    @words.text_check + ' (' + @adapter.escapeId(@args.column) + ' ' + @words.in + ' (' + map.call(arguments, @adapter.escape).join(',') + '))'

Sqlite3ColumnCompiler::LOWERWORDS = _.defaults LOWERWORDS, ColumnCompiler::LOWERWORDS
Sqlite3ColumnCompiler::UPPERWORDS = _.defaults tools.toUpperWords(LOWERWORDS), ColumnCompiler::UPPERWORDS

Sqlite3ColumnCompiler::getColumnModifier = (spec)->
    if /^(?:(small|big)?(?:increments|serial)|serial([248]))$/.test spec.type
        return ''
    
    return super(spec)
