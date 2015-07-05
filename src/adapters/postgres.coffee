pg = require 'pg'
QueryStream = require 'pg-query-stream'
_ = require 'lodash'
logger = log4js.getLogger 'PostgresAdapter'
common = require './common'
_.extend adapter, common

adapter = module.exports
_.extend adapter, common

class PostgresClient extends pg.Client
    adapter: adapter
    constructor: (options)->
        @options = _.clone options
        @options.schema = @options.schema or 'public'
        super
    query: (query, params, callback)->
        if 'string' is typeof query and query.match /^\s*(?:insert|update|delete)\s+/i
            return super query, params, callback
        super new PostgresQueryStream query, params, callback
    stream: (query, params, callback, done)->
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
        stream.on 'fields', (fields)->
            result.fields = fields
            return
        stream.on 'data', ->
            ++result.rowCount
            callback.apply null, arguments
            return
        stream.once 'end', ->
            done undefined, result unless hasError
            return
        stream

    # getModel: (callback)->
    #     callback = (->) if typeof callback isnt 'function'
    #     query = """
    #         SELECT DISTINCT ON (inf.table_name, inf.ordinal_position, column_name)
    #         inf.table_name AS "TABLE_NAME",
    #         column_name AS "COLUMN_NAME",
    #         inf.ordinal_position AS "ORDINAL_POSITION",
    #         column_default AS "COLUMN_DEFAULT",
    #         is_nullable AS "IS_NULLABLE",
    #         udt_name AS "DATA_TYPE",
    #         character_maximum_length AS "CHARACTER_MAXIMUM_LENGTH",
    #         numeric_precision/8 AS "NUMERIC_PRECISION",
    #         CASE
    #             WHEN i.indisprimary = 't' THEN 'PRI' 
    #             WHEN i.indisunique = 't' THEN 'UNI' 
    #             ELSE ''
    #         END AS "COLUMN_KEY",
    #         CASE
    #             WHEN char_length(column_default) > 6 AND substring(column_default from 1 for 7) = 'nextval' THEN 'auto_increment'
    #             ELSE ''
    #         END AS "EXTRA"
    #         FROM information_schema.columns inf
    #         INNER JOIN pg_class c
    #         ON c.relname = inf.table_name
    #         INNER JOIN pg_attribute a
    #         ON a.attrelid = c.oid AND a.attnum > 0 AND a.attname = inf.column_name
    #         INNER JOIN pg_type t
    #         ON a.atttypid = t.oid
    #         LEFT JOIN pg_index i
    #         ON i.indrelid  = c.oid AND a.attnum = ANY(i.indkey)
    #         WHERE
    #         inf.table_schema = '#{@options.schema}'
    #         AND inf.table_catalog = '#{@options.database}'
    #         ORDER BY inf.table_name, inf.ordinal_position, column_name, i.indisprimary DESC
    #     """

    #     @query query, (err, result)->
    #         return callback(err) if err
    #         DbUtil = require '../DbUtil'
    #         DbUtil.computeColumnRows result.rows, callback

class PostgresQueryStream extends QueryStream
    constructor: (text, params, callback)->
        if typeof params is 'function'
            callback = params
            params = []
        params = [] unless params

        QueryStream.call @, text, params

        @callback = callback

        if typeof callback is 'function'
            errored = false
            @on 'error', (err)->
                errored = true
                @callback err
                return
            @on 'data', (row)->
                @_result.rowCount = @_result.rows.push(row)
                return
            @on 'end', ->
                @callback null, @_result unless errored
                return
    handleRowDescription: (message) ->
        QueryStream::handleRowDescription.call this, message
        # @_result.fieldCount = (message.fields instanceof Array) and message.fields.length
        # @_result.fields = message.fields
        @emit 'fields', message.fields
        return
    handleReadyForQuery: ->
        # @emit 'close'
        super
    handleError: (err) ->
        # @emit 'close'
        @push null
        super

_.extend adapter,
    name: 'postgres'
    createConnection: (options, callback) ->
        callback = (->) if typeof callback isnt 'function'
        client = new PostgresClient(options)
        client.connect (err, connection)->
            return callback(err) if err
            connection.query "set schema '#{connection.options.schema}'", (err, result)->
                if err
                    connection.end()
                    return callback(err)
                callback err, connection
        # client.once 'connect', client.emit.bind(client, 'open')
        client
    escape: (value)->
        type = typeof value
        if type is 'number'
            return value
        if type is 'boolean'
            return if value then 'TRUE' else 'FALSE'
        PostgresClient::escapeLiteral value
    escapeId: PostgresClient::escapeIdentifier
    escapeSearch: (value)->
        common._escape value, common._escapeConfigs[common.CONSTANTS.POSTGRES].search
    escapeBeginWith: (value)->
        common._escape value, common._escapeConfigs[common.CONSTANTS.POSTGRES].begin
    escapeEndWith: (value)->
        common._escape value, common._escapeConfigs[common.CONSTANTS.POSTGRES].end
