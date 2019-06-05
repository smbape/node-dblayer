_ = require 'lodash'
ColumnCompiler = require '../../schema/ColumnCompiler'
tools = require '../../tools'
map = Array::map

LOWERWORDS =
    auto_increment: 'auto_increment'
    tinyint: 'tinyint'
    mediumint: 'mediumint'
    unsigned: 'unsigned'
    zerofill: 'zerofill'
    drop_primary_key: 'drop primary key'
    drop_foreign_key: 'drop foreign key'
    rename_index: 'rename index'
    change_column: 'change column'

# http://dev.mysql.com/doc/refman/5.7/en/data-type-overview.html
module.exports = class MySQLColumnCompiler extends ColumnCompiler

MySQLColumnCompiler::adapter = require './adapter'

# http://dev.mysql.com/doc/refman/5.7/en/numeric-type-overview.html
MySQLColumnCompiler::smallincrements = -> [this.words.smallint, this.words.unsigned, this.words.not_null, this.words.auto_increment, this.words.unique].join(' ')
MySQLColumnCompiler::mediumincrements = -> [this.words.mediumint, this.words.unsigned, this.words.not_null, this.words.auto_increment, this.words.unique].join(' ')
MySQLColumnCompiler::increments = -> [this.words.integer, this.words.unsigned, this.words.not_null, this.words.auto_increment, this.words.unique].join(' ')
MySQLColumnCompiler::bigincrements = -> [this.words.bigint, this.words.unsigned, this.words.not_null, this.words.auto_increment, this.words.unique].join(' ')

# http://dev.mysql.com/doc/refman/5.7/en/numeric-type-overview.html
MySQLColumnCompiler::bit = (length) ->
    length = this._num(length, null)
    if length and length isnt 1 then this.words.bit + '(' + length + ')' else this.words.bit

MySQLColumnCompiler::tinyint = (m, unsigned, zerofill) ->
    if unsigned
        mdefault = 3
    else
        mdefault = 4
    m = this._num(m, mdefault)
    type = [if m isnt mdefault then this.words.tinyint + '(' + m + ')' else this.words.tinyint]
    type.push this.words.unsigned if unsigned
    type.push this.words.zerofill if zerofill
    type.join(' ')

MySQLColumnCompiler::bool = -> this.words.tinyint + '(1)'

MySQLColumnCompiler::smallint = (m, unsigned, zerofill) ->
    if unsigned
        mdefault = 5
    else
        mdefault = 6
    m = this._num(m, mdefault)
    type = [if m isnt mdefault then this.words.smallint + '(' + m + ')' else this.words.smallint]
    type.push this.words.unsigned if unsigned
    type.push this.words.zerofill if zerofill
    type.join(' ')

MySQLColumnCompiler::mediumint = (m, unsigned, zerofill) ->
    if unsigned
        mdefault = 8
    else
        mdefault = 9
    m = this._num(m, mdefault)
    type = [if m isnt mdefault then this.words.mediumint + '(' + m + ')' else this.words.mediumint]
    type.push this.words.unsigned if unsigned
    type.push this.words.zerofill if zerofill
    type.join(' ')

MySQLColumnCompiler::integer = (m, unsigned, zerofill) ->
    if unsigned
        mdefault = 10
    else
        mdefault = 11
    m = this._num(m, mdefault)
    type = [if m isnt mdefault then this.words.integer + '(' + m + ')' else this.words.integer]
    type.push this.words.unsigned if unsigned
    type.push this.words.zerofill if zerofill
    type.join(' ')

MySQLColumnCompiler::bigint = (m, unsigned, zerofill) ->
    m = this._num(m, 20)
    type = [if m isnt 20 then this.words.bigint + '(' + m + ')' else this.words.bigint]
    type.push this.words.unsigned if unsigned
    type.push this.words.zerofill if zerofill
    type.join(' ')

MySQLColumnCompiler::numeric =
MySQLColumnCompiler::dec =
MySQLColumnCompiler::fixed =
MySQLColumnCompiler::decimal = (m, d, unsigned, zerofill)->
    type = [this.words.decimal + '(' + this._num(m, 10) + ', ' + this._num(d, 0) + ')']
    type.push this.words.unsigned if unsigned
    type.push this.words.zerofill if zerofill
    type.join(' ')

MySQLColumnCompiler::float = (m, d, unsigned, zerofill)->
    m = this._num(m, null)
    if m and d
        type = [this.words.float + '(' + m + ', ' + this._num(d, 2) + ')']
    else if m and m isnt 12
        type = [this.words.float + '(' + m + ')']
    else
        type = [this.words.float]

    type = [this.words.float]
    type.push this.words.unsigned if unsigned
    type.push this.words.zerofill if zerofill
    type.join(' ')

MySQLColumnCompiler::double = (m, d, unsigned, zerofill)->
    m = this._num(m, null)
    if m and d
        type = [this.words.double + '(' + m + ', ' + this._num(d, 2) + ')']
    else if m and m isnt 22
        type = [this.words.double + '(' + m + ')']
    else
        type = [this.words.double]

    type.push this.words.unsigned if unsigned
    type.push this.words.zerofill if zerofill
    type.join(' ')

# http://dev.mysql.com/doc/refman/5.7/en/date-and-time-type-overview.html
MySQLColumnCompiler::date = -> this.words.date

MySQLColumnCompiler::datetime = (fsp)->
    type = this.words.datetime

    fsp = this._num(fsp, null)
    if fsp
        "#{type}(#{fsp})"
    else
        type

MySQLColumnCompiler::timestamp = (fsp)->
    type = this.words.timestamp

    fsp = this._num(fsp, null)
    if fsp
        "#{type}(#{fsp})"
    else
        type

MySQLColumnCompiler::time = (fsp)->
    type = this.words.time

    fsp = this._num(fsp, null)
    if fsp
        "#{type}(#{fsp})"
    else
        type

LOWERWORDS.year = 'year'
MySQLColumnCompiler::year = -> this.words.year

# http://dev.mysql.com/doc/refman/5.7/en/string-type-overview.html
MySQLColumnCompiler::char = (m)->
    this.words.char + '(' + this._num(m, 255) + ')'

MySQLColumnCompiler::varchar = (m)->
    this.words.varchar + '(' + this._num(m, 255) + ')'

MySQLColumnCompiler::binary = (m)->
    this.words.binary + '(' + this._num(m, 255) + ')'

MySQLColumnCompiler::varbinary = (m)->
    this.words.varbinary + '(' + this._num(m, 255) + ')'

LOWERWORDS.tinyblob = 'tinyblob'
MySQLColumnCompiler::tinyblob = -> this.words.tinyblob

LOWERWORDS.tinytext = 'tinytext'
MySQLColumnCompiler::tinytext = -> this.words.tinytext

LOWERWORDS.blob = 'blob'
MySQLColumnCompiler::blob = (m)->
    type = this.words.blob

    m = this._num(m, null)
    if m and m isnt 65535
        "#{type}(#{m})"
    else
        type

MySQLColumnCompiler::text = (m)->
    type = this.words.text

    m = this._num(m, null)
    if m and m isnt 65535
        "#{type}(#{m})"
    else
        type

LOWERWORDS.mediumblob = 'mediumblob'
MySQLColumnCompiler::mediumblob = -> this.words.mediumblob

LOWERWORDS.mediumtext = 'mediumtext'
MySQLColumnCompiler::mediumtext = -> this.words.mediumtext

LOWERWORDS.longblob = 'longblob'
MySQLColumnCompiler::longblob = -> this.words.longblob

LOWERWORDS.longtext = 'longtext'
MySQLColumnCompiler::longtext = -> this.words.longtext

MySQLColumnCompiler::enum = ->
    this.words.enum + '(' + map.call(arguments, this.adapter.escape).join(',') + ')'

# MySQ
MySQLColumnCompiler::set = ->
    this.words.set + '(' + map.call(arguments, this.adapter.escape).join(',') + ')'

MySQLColumnCompiler::json = -> this.words.json

MySQLColumnCompiler::LOWERWORDS = _.defaults LOWERWORDS, ColumnCompiler::LOWERWORDS
MySQLColumnCompiler::UPPERWORDS = _.defaults tools.toUpperWords(LOWERWORDS), ColumnCompiler::UPPERWORDS

MySQLColumnCompiler::getColumnModifier = (spec)->
    if /^(?:(small|big)?(?:increments|serial)|serial([248]))$/.test spec.type
        return ''
    
    return ColumnCompiler.prototype.getColumnModifier.call(this, spec)
