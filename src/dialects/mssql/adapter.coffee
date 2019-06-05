_ = require 'lodash'
common = require '../../schema/adapter'
adapter = _.extend module.exports, common
logger = log4js.getLogger __filename.replace /^(?:.+[\/\\])?([^.\/\\]+)(?:.[^.]+)?$/, '$1'

escapeOpts =
    id:
        quote: '"'
        matcher: /(["\\\0\n\r\b])/g
        replace:
            '"': '""'
            '\0': '\\0'
            '\n': '\\n'
            '\r': '\\r'
            '\b': '\\b'
    literal:
        quote: "'"
        matcher: /(['\\\0\n\r\b])/g
        replace:
            "'": "''"
            '\0': '\\0'
            '\n': '\\n'
            '\r': '\\r'
            '\b': '\\b'
    search:
        quoteStart: "'%"
        quoteEnd: "%'"
        matcher: /(['\\\0\n\r\b])/g
        replace:
            "'": "''"
            '\0': '\\0'
            '\n': '\\n'
            '\r': '\\r'
            '\b': '\\b'
            '%': '!%'
            '_': '!_'
            '!': '!!'
escapeOpts.begin = _.clone escapeOpts.search
escapeOpts.begin.quoteStart = "'"
escapeOpts.end = _.clone escapeOpts.search
escapeOpts.end.quoteEnd = "'"

adapter.escape = common._escape.bind common, escapeOpts.literal
adapter.escapeId = common._escape.bind common, escapeOpts.id
adapter.escapeSearch = common._escape.bind common, escapeOpts.search
adapter.escapeBeginWith = common._escape.bind common, escapeOpts.begin
adapter.escapeEndWith = common._escape.bind common, escapeOpts.end

EventEmitter = require('events').EventEmitter
{Connection: MSSQLConnection, Request: MSSQLRequest} = require 'tedious'
slice = Array::slice

class MSSQLClient extends EventEmitter
    adapter: adapter

    constructor: (options)->
        super()

        this.options = options = _.clone options

        options.server = options.host
        delete options.host

        options.userName = options.user
        delete options.user

        if isNaN(options.port)
            options.instanceName = options.port
            delete options.port
        this.handlers = {}
        this.handlerCount = 0
        this.queue = []
        this.available = true

    connect: (callback)->
        connection = this.connection = new MSSQLConnection this.options
        connection.on 'connect', callback

        # for evt in ['connect', 'error', 'end', 'debug', 'infoMessage', 'errorMessage', 'databaseChange', 'languageChange', 'charsetCahnge', 'secure']
        for evt in ['error', 'end']
            this._delegate evt
        return

    end: ->
        this.connection.close()
        return

    query: (query, params, callback)->
        if not callback and 'function' is typeof params
            callback = params
            params = null

        if typeof callback is 'function'
            result =
                rowCount: 0
                fields: null
                fieldCount: 0
                rows: []

            this.stream query, (row)->
                result.rows.push row
                return
            , (err, res)->
                return callback(err) if err
                result.rowCount = res.rowCount
                result.fields = res.fields
                result.fieldCount = res.fieldCount
                callback err, result
                return
        return

    stream: (query, params, callback, done)->
        if arguments.length is 3
            done = callback
            callback = params
            params = []
        params = [] if not (params instanceof Array)
        done = (->) if typeof done isnt 'function'

        result =
            rowCount: 0
            fields: null
            fieldCount: 0

        request = new MSSQLRequest query, (err, rowCount)=>
            this._release()
            result.rowCount = rowCount
            done err, result
            return

        connection = this.connection

        this._acquire ->
            request.on 'columnMetadata', (fields)->
                result.fields = fields
                for field in fields
                    field.name = field.colName
                    result.fieldCount++
                return

            request.on 'row', (columns)->
                row = {}
                if Array.isArray columns
                    for {metadata: {colName}, value} in columns
                        row[colName] = value
                else
                    for name, {metadata: {colName}, value} of columns
                        row[colName] = value

                callback row
                return

            connection.execSql(request)
            return

        request

    _delegate: (evt)->
        self = @
        self.handlers[evt] = ->
            args = slice.call arguments
            args.unshift evt
            EventEmitter::emit.apply self, args
            return

        self.handlerCount++

        self.connection.on evt, self.handlers[evt]
        self.connection.on 'end', ->
            self.connection.removeListener evt, self.handlers[evt]
            delete self.handlers[evt]
            if --self.handlerCount is 0
                delete self.connection
            return

        return

    _acquire: (callback)->
        if this.available
            this.available = false
            callback()
            return

        this.queue.push callback
        return

    _release: ->
        return if this.available
        if this.queue.length
            callback = this.queue.unshift()
            setImmediate callback
            return

        this.available = true
        return

_.extend adapter,
    name: 'mssql'

    squelOptions:
        nameQuoteCharacter: '"'
        fieldAliasQuoteCharacter: '"'
        tableAliasQuoteCharacter: '"'

    decorateInsert: (insert, column)->
        insert.output this.escapeId(column)
        return insert

    insertDefaultValue: (insert, column)->
        insert.set this.escapeId(column), 'DEFAULT', {dontQuote: true}
        return insert

    createConnection: (options, callback) ->
        client = new MSSQLClient options
        client.connect (err)-> callback err, client
        return

# https://msdn.microsoft.com/fr-fr/library/ms162773.aspx
_env = _.pick process.env, [
    'SQLCMDUSER'
    'SQLCMDPASSWORD'
    'SQLCMDSERVER'
    'SQLCMDWORKSTATION'
    'SQLCMDDBNAME'
    'SQLCMDLOGINTIMEOUT'
    'SQLCMDSTATTIMEOUT'
    'SQLCMDHEADERS'
    'SQLCMDCOLSEP'
    'SQLCMDCOLWIDTH'
    'SQLCMDPACKETSIZE'
    'SQLCMDERRORLEVEL'
    'SQLCMDMAXVARTYPEWIDTH'
    'SQLCMDMAXFIXEDTYPEWIDTH'
    'SQLCMDEDITOR'
    'SQLCMDINI'
]

fs = require 'fs'
sysPath = require 'path'
anyspawn = require 'anyspawn'
{getTemp} = require '../../tools'
umask = if process.platform is 'win32' then {encoding: 'utf-8', mode: 700} else {encoding: 'utf-8', mode: 600}

adapter.exec = adapter.execute = (script, options, done)->
    if _.isPlainObject(script)
        _script = options
        options = script
        script = _script

    if 'function' is typeof options
        done = options
        options = {}

    if not _.isPlainObject(options)
        options = {}

    {
        user
        password
        database
        schema
        cmd
        host
        port
        stdout
        stderr
        tmp
        keep
    } = options

    if cmd and 'object' is typeof cmd
        error = null
        callback = (err, res)->
            error = err
            return

        this.split script, (query)->
            if not error
                cmd.query query, callback
            return
        , (err)->
            done err or error
            return
        return

    return
