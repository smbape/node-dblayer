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
MySQLColumnCompiler::smallincrements = -> [@words.smallint, @words.unsigned, @words.not_null, @words.auto_increment, @words.unique].join(' ')
MySQLColumnCompiler::mediumincrements = -> [@words.mediumint, @words.unsigned, @words.not_null, @words.auto_increment, @words.unique].join(' ')
MySQLColumnCompiler::increments = -> [@words.integer, @words.unsigned, @words.not_null, @words.auto_increment, @words.unique].join(' ')
MySQLColumnCompiler::bigincrements = -> [@words.bigint, @words.unsigned, @words.not_null, @words.auto_increment, @words.unique].join(' ')

# http://dev.mysql.com/doc/refman/5.7/en/numeric-type-overview.html
MySQLColumnCompiler::bit = (length) ->
    length = @_num(length, null)
    if length and length isnt 1 then @words.bit + '(' + length + ')' else @words.bit

MySQLColumnCompiler::tinyint = (m, unsigned, zerofill) ->
    if unsigned
        mdefault = 3
    else
        mdefault = 4
    m = @_num(m, mdefault)
    type = [if m isnt mdefault then @words.tinyint + '(' + m + ')' else @words.tinyint]
    type.push @words.unsigned if unsigned
    type.push @words.zerofill if zerofill
    type.join(' ')

MySQLColumnCompiler::bool = -> @words.tinyint + '(1)'

MySQLColumnCompiler::smallint = (m, unsigned, zerofill) ->
    if unsigned
        mdefault = 5
    else
        mdefault = 6
    m = @_num(m, mdefault)
    type = [if m isnt mdefault then @words.smallint + '(' + m + ')' else @words.smallint]
    type.push @words.unsigned if unsigned
    type.push @words.zerofill if zerofill
    type.join(' ')

MySQLColumnCompiler::mediumint = (m, unsigned, zerofill) ->
    if unsigned
        mdefault = 8
    else
        mdefault = 9
    m = @_num(m, mdefault)
    type = [if m isnt mdefault then @words.mediumint + '(' + m + ')' else @words.mediumint]
    type.push @words.unsigned if unsigned
    type.push @words.zerofill if zerofill
    type.join(' ')

MySQLColumnCompiler::integer = (m, unsigned, zerofill) ->
    if unsigned
        mdefault = 10
    else
        mdefault = 11
    m = @_num(m, mdefault)
    type = [if m isnt mdefault then @words.integer + '(' + m + ')' else @words.integer]
    type.push @words.unsigned if unsigned
    type.push @words.zerofill if zerofill
    type.join(' ')

MySQLColumnCompiler::bigint = (m, unsigned, zerofill) ->
    m = @_num(m, 20)
    type = [if m isnt 20 then @words.bigint + '(' + m + ')' else @words.bigint]
    type.push @words.unsigned if unsigned
    type.push @words.zerofill if zerofill
    type.join(' ')

MySQLColumnCompiler::numeric =
MySQLColumnCompiler::dec =
MySQLColumnCompiler::fixed =
MySQLColumnCompiler::decimal = (m, d, unsigned, zerofill)->
    type = [@words.decimal + '(' + @_num(m, 10) + ', ' + @_num(d, 0) + ')']
    type.push @words.unsigned if unsigned
    type.push @words.zerofill if zerofill
    type.join(' ')

MySQLColumnCompiler::float = (m, d, unsigned, zerofill)->
    m = @_num(m, null)
    if m and d
        type = [@words.float + '(' + m + ', ' + @_num(d, 2) + ')']
    else if m and m isnt 12
        type = [@words.float + '(' + m + ')']
    else
        type = [@words.float]

    type = [@words.float]
    type.push @words.unsigned if unsigned
    type.push @words.zerofill if zerofill
    type.join(' ')

MySQLColumnCompiler::double = (m, d, unsigned, zerofill)->
    m = @_num(m, null)
    if m and d
        type = [@words.double + '(' + m + ', ' + @_num(d, 2) + ')']
    else if m and m isnt 22
        type = [@words.double + '(' + m + ')']
    else
        type = [@words.double]

    type.push @words.unsigned if unsigned
    type.push @words.zerofill if zerofill
    type.join(' ')

# http://dev.mysql.com/doc/refman/5.7/en/date-and-time-type-overview.html
MySQLColumnCompiler::date = -> @words.date

MySQLColumnCompiler::datetime = (fsp)->
    type = @words.datetime

    fsp = @_num(fsp, null)
    if fsp
        "#{type}(#{fsp})"
    else
        type

MySQLColumnCompiler::timestamp = (fsp)->
    type = @words.timestamp

    fsp = @_num(fsp, null)
    if fsp
        "#{type}(#{fsp})"
    else
        type

MySQLColumnCompiler::time = (fsp)->
    type = @words.time

    fsp = @_num(fsp, null)
    if fsp
        "#{type}(#{fsp})"
    else
        type

LOWERWORDS.year = 'year'
MySQLColumnCompiler::year = -> @words.year

# http://dev.mysql.com/doc/refman/5.7/en/string-type-overview.html
MySQLColumnCompiler::char = (m)->
    @words.char + '(' + @_num(m, 255) + ')'

MySQLColumnCompiler::varchar = (m)->
    @words.varchar + '(' + @_num(m, 255) + ')'

MySQLColumnCompiler::binary = (m)->
    @words.binary + '(' + @_num(m, 255) + ')'

MySQLColumnCompiler::varbinary = (m)->
    @words.varbinary + '(' + @_num(m, 255) + ')'

LOWERWORDS.tinyblob = 'tinyblob'
MySQLColumnCompiler::tinyblob = -> @words.tinyblob

LOWERWORDS.tinytext = 'tinytext'
MySQLColumnCompiler::tinytext = -> @words.tinytext

LOWERWORDS.blob = 'blob'
MySQLColumnCompiler::blob = (m)->
    type = @words.blob

    m = @_num(m, null)
    if m and m isnt 65535
        "#{type}(#{m})"
    else
        type

MySQLColumnCompiler::text = (m)->
    type = @words.text

    m = @_num(m, null)
    if m and m isnt 65535
        "#{type}(#{m})"
    else
        type

LOWERWORDS.mediumblob = 'mediumblob'
MySQLColumnCompiler::mediumblob = -> @words.mediumblob

LOWERWORDS.mediumtext = 'mediumtext'
MySQLColumnCompiler::mediumtext = -> @words.mediumtext

LOWERWORDS.longblob = 'longblob'
MySQLColumnCompiler::longblob = -> @words.longblob

LOWERWORDS.longtext = 'longtext'
MySQLColumnCompiler::longtext = -> @words.longtext

MySQLColumnCompiler::enum = ->
    @words.enum + '(' + map.call(arguments, @adapter.escape).join(',') + ')'

# MySQ
MySQLColumnCompiler::set = ->
    @words.set + '(' + map.call(arguments, @adapter.escape).join(',') + ')'

MySQLColumnCompiler::json = -> @words.json

MySQLColumnCompiler::LOWERWORDS = _.defaults LOWERWORDS, ColumnCompiler::LOWERWORDS
MySQLColumnCompiler::UPPERWORDS = _.defaults tools.toUpperWords(LOWERWORDS), ColumnCompiler::UPPERWORDS

MySQLColumnCompiler::getColumnModifier = (spec)->
    if /^(?:(small|big)?(?:increments|serial)|serial([248]))$/.test spec.type
        return ''
    
    return super(spec)
