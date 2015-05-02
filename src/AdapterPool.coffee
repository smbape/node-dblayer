log4js = global.log4js or (global.log4js = require 'log4js')
logger = log4js.getLogger 'AdapterPool'

internal = {}
internal.adapters = {}

internal.getAdapter = (options)->
    ### istanbul ignore else ###
    if typeof options.adapter is 'string'
        adapter = internal.adapters[options.adapter]
        if typeof adapter is 'undefined'
            adapter = require path.join __dirname, 'adapters', options.adapter
            internal.adapters[options.adapter] = adapter
    # else if _.isPlainObject options.adapter
    #     adapter = options.adapter

    if typeof adapter.createConnection isnt 'function'
        err = new Error 'adapter object has no method createConnection'
        err.code = 'BAD_ADAPTER'
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
    constructor: (connectionUrl, options, next)->
        if typeof connectionUrl isnt 'string'
            err = new Error "'connectionUrl' must be a String"
            err.code = 'BAD_CONNECTION_URL'
            throw err

        @connectionUrl = connectionUrl
        url = require 'url'
        
        parsed = url.parse connectionUrl, true, true
        @options = {}
        @options.adapter = parsed.protocol and parsed.protocol.substring(0, parsed.protocol.length - 1)
        @options.database = parsed.pathname and parsed.pathname.substring(1)
        @options.host = parsed.hostname
        @options.port = parseInt(parsed.port, 10) if GenericUtil.isNumeric parsed.port
        if parsed.auth
            auth = parsed.auth.split(':')
            @options.user = auth[0]
            @options.password = auth[1]

        for k of parsed.query
            @options[k] = parsed.query[k]

        if typeof @options.adapter isnt 'string' or @options.adapter.length is 0
            err = new Error 'adapter must be a not empty string'
            err.code = 'BAD_ADAPTER'
            throw err

        properties = ['name']
        for prop in properties
            @options[prop] = options[prop] if typeof options[prop] isnt 'undefined'

        if GenericUtil.isNumeric @options.maxConnection
            @options.maxConnection = parseInt @options.maxConnection, 10
        else
            @options.maxConnection = defaultOptions.maxConnection

        if GenericUtil.isNumeric @options.minConnection
            @options.minConnection = parseInt @options.minConnection, 10
        else
            @options.minConnection = defaultOptions.minConnection
        
        if GenericUtil.isNumeric @options.idleTimeout
            @options.idleTimeout = parseInt @options.idleTimeout, 10
        else
            @options.idleTimeout = defaultOptions.idleTimeout
        
        @adapter = internal.getAdapter @options

        GenericPool = require 'generic-pool'
        @pool = GenericPool.Pool
            name: @options.name

            create: (callback)=>
                logger.debug "create #{@options.name}"
                @adapter.createConnection @options, callback
                return

            destroy: (client)=>
                logger.debug "destroy #{@options.name}"
                client.end()
                return

            max: @options.maxConnection
            min: @options.minConnection
            idleTimeoutMillis: @options.idleTimeout * 1000

        # Proxy all pool methods
        for method of @pool
            ### istanbul ignore if ###
            continue if typeof @pool[method] isnt 'function'

            @[method] = ((pool, method)->
                =>
                    pool[method].apply pool, arguments
            )(@pool, method)

        @check(next) if typeof next is 'function'
        return

    check: (next)->
        # throw new Error('next is not a function') if typeof next isnt 'function'
        @pool.acquire (err, connection)=>
            throw err if err
            @pool.release connection
            next() if 'function' is typeof next
        return
    getDialect: ->
        return @options.adapter
    createConnector: (options)->
        Connector = require './Connector'
        new Connector @, options
    getMaxConnection: ->
        @options.maxConnection
    # escape: ->
    #     @adapter.escape.apply @adapter, arguments
    # escapeId: ->
    #     @adapter.escapeId.apply @adapter, arguments
    # exprEqual: ->
    #     @adapter.exprEqual.apply @adapter, arguments
    # exprNotEqual: ->
    #     @adapter.exprNotEqual.apply @adapter, arguments
