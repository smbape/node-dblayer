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
Sqlite3ColumnCompiler::increments = -> [this.words.integer, this.words.primary_key, this.words.autoincrement].join(' ')

Sqlite3ColumnCompiler::tinyint =
Sqlite3ColumnCompiler::smallint =
Sqlite3ColumnCompiler::mediumint =
Sqlite3ColumnCompiler::bigint =
Sqlite3ColumnCompiler::int2 =
Sqlite3ColumnCompiler::int8 =
Sqlite3ColumnCompiler::integer = -> this.words.integer

LOWERWORDS.character = 'character'
Sqlite3ColumnCompiler::char = (m)->
    this.words.character + '(' + this._num(m, 255) + ')'

Sqlite3ColumnCompiler::varchar = (m)->
    this.words.varchar + '(' + this._num(m, 255) + ')'

Sqlite3ColumnCompiler::text = -> this.words.text

LOWERWORDS.blob = 'blob'
Sqlite3ColumnCompiler::blob = this.words.blob

LOWERWORDS.real = 'real'
Sqlite3ColumnCompiler::real = -> this.words.real
Sqlite3ColumnCompiler::double = -> this.words.double
Sqlite3ColumnCompiler::float = -> this.words.float

Sqlite3ColumnCompiler::numeric = # -> this.words.numeric
Sqlite3ColumnCompiler::decimal = (precision, scale)->
    this.words.decimal + '(' + this._num(precision, 8) + ', ' + this._num(scale, 2) + ')'

Sqlite3ColumnCompiler::bool = -> this.words.boolean

Sqlite3ColumnCompiler::date = -> this.words.date
Sqlite3ColumnCompiler::datetime = -> this.words.date

PgColumnCompiler::enum = ->
    # http://stackoverflow.com/questions/10923213/postgres-enum-data-type-or-check-constraint#10984951
    this.words.text_check + ' (' + this.adapter.escapeId(this.args.column) + ' ' + this.words.in + ' (' + map.call(arguments, this.adapter.escape).join(',') + '))'

Sqlite3ColumnCompiler::LOWERWORDS = _.defaults LOWERWORDS, ColumnCompiler::LOWERWORDS
Sqlite3ColumnCompiler::UPPERWORDS = _.defaults tools.toUpperWords(LOWERWORDS), ColumnCompiler::UPPERWORDS

Sqlite3ColumnCompiler::getColumnModifier = (spec)->
    if /^(?:(small|big)?(?:increments|serial)|serial([248]))$/.test spec.type
        return ''
    
    return ColumnCompiler.prototype.getColumnModifier.call(this, spec)
