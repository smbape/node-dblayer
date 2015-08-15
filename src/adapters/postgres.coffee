pg = require 'pg'
QueryStream = require 'pg-query-stream'
_ = require 'lodash'
logger = log4js.getLogger 'PostgresAdapter'
common = require './common'
_.extend adapter, common

adapter = module.exports
_.extend adapter, common

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
    handleError: (err) ->
        @push null
        super

_.extend adapter,
    name: 'postgres'
    createConnection: (options, callback) ->
        callback = (->) if typeof callback isnt 'function'
        client = new pg.Client options
        client.connect (err)->
            return callback(err, null) if err
            client.query "set schema '#{options.schema}'", (err, result)->
                callback err, client
                return
            return
        client
    escape: (value)->
        type = typeof value
        if type is 'number'
            return value
        if type is 'boolean'
            return if value then 'TRUE' else 'FALSE'
        pg.Client::escapeLiteral value
    escapeId: pg.Client::escapeIdentifier
    escapeSearch: (value)->
        common._escape value, common._escapeConfigs[common.CONSTANTS.POSTGRES].search
    escapeBeginWith: (value)->
        common._escape value, common._escapeConfigs[common.CONSTANTS.POSTGRES].begin
    escapeEndWith: (value)->
        common._escape value, common._escapeConfigs[common.CONSTANTS.POSTGRES].end
