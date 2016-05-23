_ = require 'lodash'
common = require '../../schema/adapter'
adapter = module.exports
_.extend adapter, common
logger = log4js.getLogger __filename.replace /^(?:.+[\/])?([^.\/]+)(?:.[^.]+)?$/, '$1'

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

pg = require('pg')
QueryStream = require 'pg-query-stream'

pg.Client::stream = (query, params, callback, done)->
        if arguments.length is 3
            done = callback
            callback = params
            params = []
        params = [] if not (params instanceof Array)
        done = (->) if typeof done isnt 'function'

        query = new PostgresQueryStream query
        stream = pg.Client::query.call @, query, params
        hasError = false
        result = rowCount: 0
        stream.once 'error', (err)->
            hasError = err
            done err
            return
        stream.on 'fields', (fields)->
            result.fields = fields
            return
        stream.on 'data', ->
            ++result.rowCount
            callback.apply null, arguments
            return
        stream.once 'end', ->
            done null, result unless hasError
            return
        stream

class PostgresQueryStream extends QueryStream
    handleRowDescription: (message) ->
        QueryStream::handleRowDescription.call this, message
        @emit 'fields', message.fields
        return
    handleError: ->
        @push null
        super

_.extend adapter,
    name: 'postgres'

    createConnection: (options, callback) ->
        callback = (->) if typeof callback isnt 'function'
        client = new pg.Client options
        client.connect (err)->
            return callback(err, null) if err
            query = "SET SCHEMA '#{options.schema}'"
            logger.trace '[query] - ' + query
            client.query query, (err)->
                callback err, client
                return
            return
        client

    squelOptions:
        replaceSingleQuotes: true
        nameQuoteCharacter: '"'
        fieldAliasQuoteCharacter: '"'
        tableAliasQuoteCharacter: '"'

    decorateInsert: (query, column)->
        if typeof column is 'string' and column.length > 0
            query += ' RETURNING "' + column + '"'
        else
            query
