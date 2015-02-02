mysql = require 'mysql'
MySQLLibConnection = require 'mysql/lib/Connection'
ConnectionConfig = require 'mysql/lib/ConnectionConfig'
prependListener = require 'prepend-listener'
once = require 'once'
_ = require 'lodash'
path = require 'path'
GenericUtil = require '../GenericUtil'
HWM = Math.pow 2, 7

adapter =
    name: 'mysql'
    createQuery: (text, values, callback)->
        if typeof callback is 'undefined' and typeof values is 'function'
            callback = values
            values = undefined

        values = values or []
        query = mysql.createQuery text, values

        stream = query.stream highWaterMark: HWM
        emitClose = once stream.emit.bind stream, 'close'
        prependListener query, 'end', emitClose

        stream.query = query
        stream.text = text
        stream.values = values
        stream.callback = callback

        if typeof callback is 'function'
            result =
                rowCount: 0
                rows: []
                lastInsertId: 0
                fields: null

            hasError = false
            stream.on 'error', (err)->
                emitClose()
                hasError = true
                @callback err
                return
            stream.on 'fields', (fields) ->
                result.fields = fields
                return
            stream.on 'data', (row) ->
                if row.constructor.name is 'OkPacket'
                    result.fieldCount = row.fieldCount
                    result.affectedRows = row.affectedRows
                    result.changedRows = row.changedRows
                    result.lastInsertId = row.insertId
                else
                    ++result.rowCount
                    result.rows.push(row)
                return
            stream.on 'end', ->
                @callback null, result unless hasError
                return

        stream.once 'end', ->
            delete @query
            return

        stream
    createConnection: (options, callback)->
        callback = (->) if typeof callback isnt 'function'
        client = new MySQLConnection options
        client.connect (err)->
            return callback(err) if err
            callback err, client

class MySQLConnection extends MySQLLibConnection
    adapter: adapter
    constructor: (options)->
        @options = _.clone options
        super config: new ConnectionConfig(options)
    getConnectionName: ->
        @options.adapter + '://' + @options.host + ':' + @options.port + '/' + @options.database
    query: (query, params, callback)->
        stream = adapter.createQuery query, params, callback
        super stream.query
        stream
    stream: (query, params, callback, done)->
        if arguments.length is 3
            done = callback
            callback = params
            params = []
        params = [] if not (params instanceof Array)
        done = (->) if typeof done isnt 'function'
        stream = MySQLLibConnection::query.call(@, query, params).stream highWaterMark: HWM
        hasError = false
        result = rowCount: 0
        stream.once 'error', (err)->
            hasError = err
            done err
            return
        stream.on 'fields', (fields) ->
            result.fields = fields
            return
        stream.on 'data', (row)->
            if row.constructor.name is 'OkPacket'
                result.fieldCount = row.fieldCount
                result.affectedRows = row.affectedRows
                result.changedRows = row.changedRows
                result.lastInsertId = row.insertId
            else
                ++result.rowCount
                callback row
            return
        stream.once 'end', ->
            done undefined, result unless hasError
            return
        stream
    getModel: (callback)->
        callback = (->) if typeof callback isnt 'function'
        query = """
            select 
                tabs.TABLE_NAME,
                cols.COLUMN_NAME,
                cols.ORDINAL_POSITION,
                cols.COLUMN_DEFAULT,
                cols.IS_NULLABLE,
                cols.DATA_TYPE,
                cols.CHARACTER_MAXIMUM_LENGTH,
                cols.NUMERIC_PRECISION,
                cols.COLUMN_KEY,
                cols.EXTRA
            from
                information_schema.tables as tabs
                    inner join
                information_schema.columns as cols ON cols.TABLE_SCHEMA = tabs.TABLE_SCHEMA
                    and cols.TABLE_NAME = tabs.TABLE_NAME
            where
                tabs.TABLE_SCHEMA = '#{@options.database}'
            order by tabs.TABLE_NAME
        """
        @query query, (err, result)->
            return callback(err) if err
            DbUtil = require '../DbUtil'
            DbUtil.computeColumnRows result.rows, callback

_.extend adapter, require './common'
_.extend adapter,
    escape: (value)->
        MySQLConnection::escape.call {config: {}}, value
    escapeId: MySQLConnection::escapeId

module.exports = adapter
