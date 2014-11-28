log4js = global.log4js or (global.log4js = require 'log4js')
logger = log4js.getLogger 'AdapterPool'

internal = {}
internal.adapters = {}

internal.getAdapter = (options)->
    if not _.isPlainObject options
        err = new Error 'options parameter is not an object not null'
        err.code = 'BAD_OPTION'
        throw err

    if typeof options.adapter is 'undefined'
        err = new Error 'options.adapter is not define'
        err.code = 'BAD_OPTION'
        throw err

    if typeof options.adapter is 'string'
        adapter = internal.adapters[options.adapter]
        if typeof adapter is 'undefined'
            adapter = require path.join __dirname, 'adapters', options.adapter
            internal.adapters[options.adapter] = adapter
    else if _.isPlainObject options.adapter
        adapter = options.adapter

    if typeof adapter is 'undefined'
        err = new Error 'adapter "' + options.adapter + '" is not define'
        err.code = 'BAD_adapter'
        throw err

    if typeof adapter.createConnection isnt 'function'
        err = new Error 'adapter object has no method createConnection'
        err.code = 'BAD_adapter'
        throw err

    adapter

_ = require 'lodash'
path = require 'path'
GenericUtil = require './GenericUtil'

defaultOptions =
    minConnection: 0
    maxConnection: 1
    idleTimeout: 10 * 60 #idle for 10 minutes

module.exports = class AdapterPool
    constructor: (connectionUrl, config, next)->
        if typeof connectionUrl isnt 'string'
            throw new Error "'connectionUrl' must be a String"

        @connectionUrl = connectionUrl
        url = require 'url'
        parsed = url.parse connectionUrl, true, true
        @config = {}
        @config.adapter = parsed.protocol.replace ':', ''
        @config.database = parsed.pathname.substring(1)
        @config.host = parsed.hostname
        @config.port = parseInt(parsed.port, 10) if GenericUtil.isNumeric parsed.port
        if parsed.auth
            auth = parsed.auth.split(':')
            @config.user = auth[0]
            @config.password = auth[1]

        for k of parsed.query
            @config[k] = decodeURIComponent parsed.query[k]

        if typeof @config.adapter isnt 'string' or @config.adapter.length is 0
            throw new Error "'adapter' is required in config objects"

        properties = ['name']
        for prop in properties
            @config[prop] = config[prop] if typeof config[prop] isnt 'undefined'

        if GenericUtil.isNumeric @config.maxConnection
            @config.maxConnection = parseInt @config.maxConnection, 10
        else
            @config.maxConnection = defaultOptions.maxConnection

        if GenericUtil.isNumeric @config.minConnection
            @config.minConnection = parseInt @config.minConnection, 10
        else
            @config.minConnection = defaultOptions.minConnection
        
        if GenericUtil.isNumeric @config.idleTimeout
            @config.idleTimeout = parseInt @config.idleTimeout, 10
        else
            @config.idleTimeout = defaultOptions.idleTimeout
        
        @adapter = internal.getAdapter @config

        GenericPool = require 'generic-pool'
        @pool = GenericPool.Pool
            name: @config.name

            create: (callback)=>
                logger.debug "create #{@config.name}"
                @adapter.createConnection @config, callback
                return

            destroy: (client)=>
                logger.debug "destroy #{@config.name}"
                client.end()
                return

            max: @config.maxConnection
            min: @config.minConnection
            idleTimeoutMillis: @config.idleTimeout * 1000

        for method of @pool
            continue if typeof @pool[method] isnt 'function'
            @[method] = ((obj, method)->
                =>
                    obj.pool[method].apply obj.pool, arguments
            )(@, method)

        @check(next) if typeof next is 'function'
        return

    check: (next)->
        throw new Error('next is not a function') if typeof next isnt 'function'
        @pool.acquire (err, connection)=>
            throw err if err
            @pool.release connection
            next()
    getDialect: ->
        return @config.adapter
    createConnector: (options)->
        Connector = require './Connector'
        new Connector @, options
    getMaxConnection: ->
        @config.maxConnection
    escape: ->
        @adapter.escape.apply @adapter, arguments
    escapeId: ->
        @adapter.escapeId.apply @adapter, arguments
    exprEqual: ->
        @adapter.exprEqual.apply @adapter, arguments
    exprNotEqual: ->
        @adapter.exprNotEqual.apply @adapter, arguments
