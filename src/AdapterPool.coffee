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
semLib = require 'sem-lib'

defaultOptions =
    minConnection: 0
    maxConnection: 1
    idleTimeout: 10 * 60 #idle for 10 minutes

levelMap =
    error: 'error'
    warn: 'warn'
    info: 'debug'
    verbose: 'trace'

class SemaphorePool extends semLib.Semaphore
    constructor: (options = {})->
        @_factory = {}

        for opt in ['name', 'create', 'destroy', 'priority']
            if options.hasOwnProperty opt
                @_factory[opt] = options[opt]

        for opt in ['min', 'max', 'idle']
            if options.hasOwnProperty opt
                @_factory[opt] = parseInt options[opt], 10
            else
                @_factory[opt] = 0

        super @_max, true, @_priority
        @_created = []
        @_timers = {}
        @_avalaible = []
        @_ensureMinimum()
    getName: ->
        @_factory.name
    acquire: (callback, opts = {})->
        @semTake
            priority: opts.priority
            num: 1
            timeOut: opts.timeOut
            onTimeOut: opts.onTimeOut
            onTake: =>
                if @_avalaible.length is 0
                    @_factory.create (err, client)=>
                        return callback err if err
                        @_created.push client
                        @_removeIdle @_created.length - 1, client
                        callback null, client
                        return
                    return
                client = @_avalaible.shift()
                @_removeIdle @_created.indexOf(client), client
                callback null, client
                return
    release: (client)->
        index = @_created.indexOf client
        if ~index
            @_avalaible.push client
            @_idle index, client
            return @semGive()
        return false
    _idle: (index, client)->
        if @_factory.idle > 0
            return if @_factory.min is @_created.length
            @_timers[index] = setTimeout =>
                return if @_factory.min is @_created.length
                @destroy client
                return
            , @_factory.idle
        return
    _removeIdle: (index, client)->
        clearTimeout @_timers[index]
        return
    destroy: (client)->
        index = @_created.indexOf client
        if ~index
            @_created.splice index, 1
            @_factory.destroy client
            @_ensureMinimum()
            return true
        return false
    _superDestroy: (safe, _onDestroy)->
        SemaphorePool.__super__.destroy.call @, safe, _onDestroy

    destroyAll: (safe, _onDestroy)->
        if safe isnt false
            @_superDestroy true, =>
                @_onDestroy()
                _onDestroy() if 'function' is typeof _onDestroy
                return
        else
            @_superDestroy false, =>
                @_onDestroy()
                _onDestroy() if 'function' is typeof _onDestroy
                return
        return
    _onDestroy: ->
        for client in @_created
            @_factory.destroy client

        for index, timer of @_timers
            clearTimeout timer if timer

        @_created.splice 0, @_created.length
        @_avalaible.splice 0, @_avalaible.length
        return
    _ensureMinimum: ->
        if @_factory.min > @_created.length
            @acquire (err, client)=>
                return @emit 'error', err if err
                @release client
                @_ensureMinimum()
                return
        return

module.exports = class AdapterPool extends SemaphorePool
    constructor: (connectionUrl, options, next)->
        if arguments.length is 1
            if connectionUrl isnt null and 'object' is typeof connectionUrl
                options = connectionUrl
                connectionUrl = null

        else if arguments.length is 2
            if 'function' is typeof options
                next = options
                options = null

            if connectionUrl isnt null and 'object' is typeof connectionUrl
                options = connectionUrl
                connectionUrl = null

        if connectionUrl and typeof connectionUrl isnt 'string'
            err = new Error "'connectionUrl' must be a String"
            err.code = 'BAD_CONNECTION_URL'
            throw err

        if options and 'object' isnt typeof options
            err = new Error "'options' must be an object"
            err.code = 'BAD_OPTION'
            throw err

        if connectionUrl
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

            for key of parsed.query
                @options[key] = parsed.query[key]

            _.extend @options, options
        else if options
            @options = _.clone options
            parsed = query: {}
            parsed.protocol = @options.adapter + '/'
            parsed.pathname = '/' + @options.database
            parsed.hostname = @options.host
            parsed.port = @options.port if GenericUtil.isNumeric @options.port
            if 'string' is typeof @options.user and @options.user.length > 0
                if 'string' is typeof @options.password and @options.password.length > 0
                    parsed.auth = @options.user + ':' + @options.password
                else
                    parsed.auth = @options.user

            except = ['adapter', 'database', 'port', 'user', 'password']
            for key of @options
                if -1 is except.indexOf key
                    parsed.query[key] = @options[key]
            @connectionUrl = url.format parsed
        else
            err = new Error "Invalid arguments. Usage: options[, fn]; url[, fn]: url, options[, fn]"
            err.code = 'INVALID_ARGUMENTS'
            throw err

        if typeof @options.adapter isnt 'string' or @options.adapter.length is 0
            err = new Error 'adapter must be a not empty string'
            err.code = 'BAD_ADAPTER'
            throw err

        for prop in ['name']
            @options[prop] = options[prop] if typeof options.hasOwnProperty prop

        for prop in ['minConnection', 'maxConnection', 'idleTimeout']
            if GenericUtil.isNumeric @options.maxConnection
                @options[prop] = parseInt @options[prop], 10
            else
                @options[prop] = defaultOptions[prop]

        @adapter = internal.getAdapter @options

        super
            name: @options.name

            create: (callback)=>
                logger.debug "#{@_factory.name} create", @id
                @adapter.createConnection @options, (err, client)=>
                    return callback(err, null) if err

                    client.on 'error', (err)=>
                        # @destroy client
                        @emit 'error', err
                        return

                    # Remove connection from pool on disconnect
                    client.on 'end', (err)=>
                        return if client._destroying
                        @destroy client
                        return

                    callback null, client

                    return
                return

            destroy: (client)=>
                return if client._destroying
                logger.debug "#{@_factory.name} destroy", @id
                client._destroying = true
                client.end()
                return

            max: @options.maxConnection
            min: @options.minConnection
            idle: @options.idleTimeout * 1000

        @check(next) if typeof next is 'function'
        return

    check: (next)->
        if 'function' isnt typeof next
            next = ->
        @acquire (err, connection)=>
            return next err if err
            @release connection
            next()
            return
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
