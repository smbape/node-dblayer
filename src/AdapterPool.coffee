log4js = global.log4js or (global.log4js = require 'log4js')
logger = log4js.getLogger 'AdapterPool'

_ = require 'lodash'
url = require 'url'
sysPath = require 'path'
GenericUtil = require './GenericUtil'
semLib = require 'sem-lib'

internal = {}
internal.adapters = {}

internal.getAdapter = (options)->
    ### istanbul ignore else ###
    if typeof options.adapter is 'string'
        adapter = internal.adapters[options.adapter]
        if typeof adapter is 'undefined'
            adapter = require sysPath.join __dirname, 'adapters', options.adapter
            internal.adapters[options.adapter] = adapter
    # else if _.isPlainObject options.adapter
    #     adapter = options.adapter

    if typeof adapter.createConnection isnt 'function'
        err = new Error 'adapter object has no method createConnection'
        err.code = 'BAD_ADAPTER'
        throw err

    adapter

defaultOptions =
    minConnection: 0
    maxConnection: 1
    idleTimeout: 10 * 60 #idle for 10 minutes

levelMap =
    error: 'error'
    warn: 'warn'
    info: 'debug'
    verbose: 'trace'

clientId = 0
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
        self = @
        self.semTake
            priority: opts.priority
            num: 1
            timeOut: opts.timeOut
            onTimeOut: opts.onTimeOut
            onTake: ->
                logger.trace "[#{self._factory.name}] [#{self.id}] acquire", self._avalaible.length
                if self._avalaible.length is 0
                    self._factory.create (err, client)->
                        return callback err if err
                        self._created.push client
                        self._removeIdle client
                        callback null, client
                        return
                    return
                client = self._avalaible.shift()
                self._removeIdle client
                callback null, client
                return
    release: (client)->
        index = @_created.indexOf client
        if ~index
            logger.trace "[#{this._factory.name}] [#{this.id}] release '#{client.id}'. Avalaible #{this._avalaible.length}"
            @_avalaible.push client
            @_idle client
            return @semGive()
        return false
    _idle: (client)->
        self = @
        if @_factory.idle > 0
            self._removeIdle client
            self._timers[client.id] = setTimeout ->
                self.destroy client
                return
            , self._factory.idle
        return
    _removeIdle: (client)->
        clearTimeout @_timers[client.id]
        delete @_timers[client.id]
        return
    destroy: (client, force)->
        index = @_created.indexOf client

        # ensure minimum
        if ~index
            if force or @_factory.min < @_created.length
                logger.debug "[#{this._factory.name}] [#{this.id}] destroying '#{client.id}'. #{this._avalaible.length}/#{this._created.length}"
                @_created.splice index, 1

                # remove it from available since it will be destroyed
                index = @_avalaible.indexOf client
                @_avalaible.splice index, 1 if ~index

                @_factory.destroy client
                logger.debug "[#{this._factory.name}] [#{this.id}] destroyed '#{client.id}'. #{this._avalaible.length}/#{this._created.length}"

                @_ensureMinimum() if force
                return true
            else
                @_idle client
        return false
    _superDestroy: (safe, _onDestroy)->
        SemaphorePool.__super__.destroy.call @, safe, _onDestroy

    destroyAll: (safe, _onDestroy)->
        self = @
        if safe isnt false
            self._superDestroy true, ->
                self._onDestroy()
                _onDestroy() if 'function' is typeof _onDestroy
                return
        else
            self._superDestroy false, ->
                self._onDestroy()
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
        self = @
        if self._factory.min > self._created.length
            logger.debug "[#{self._factory.name}] [#{self.id}] _ensureMinimum. #{self._created.length}/#{self._factory.min}"
            self.acquire (err, client)->
                return self.emit 'error', err if err
                self.release client
                self._ensureMinimum()
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

            parsed = url.parse connectionUrl, true, true
            @options = {}
            @options.adapter = parsed.protocol and parsed.protocol.substring(0, parsed.protocol.length - 1)
            @options.database = parsed.pathname and parsed.pathname.substring(1)
            @options.host = parsed.hostname
            @options.port = parseInt(parsed.port, 10) if GenericUtil.isNumeric parsed.port
            if parsed.auth
                # treat the first : as separator since password may contain : as well
                index = parsed.auth.indexOf ':'
                @options.user = parsed.auth.substring 0, index
                @options.password = parsed.auth.substring index + 1

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

        self = @
        super
            name: self.options.name

            create: (callback)->
                logger.debug "[#{self._factory.name}] [#{self.id}] create"
                self.adapter.createConnection self.options, (err, client)->
                    return callback(err, null) if err
                    client.id = ++clientId

                    client.on 'error', (err)->
                        # TODO: write why destruction should not be done on error
                        # self.destroy client
                        self.emit 'error', err
                        return

                    # Remove connection from pool on disconnect because it is no more usable
                    client.on 'end', (err)->
                        return if client._destroying
                        self.destroy client, true
                        return

                    callback null, client

                    return
                return

            destroy: (client)->
                return if client._destroying
                logger.debug "[#{self._factory.name}] [#{self.id}] destroy"
                client._destroying = true
                client.end()
                return

            max: self.options.maxConnection
            min: self.options.minConnection
            idle: self.options.idleTimeout * 1000

        self.check(next) if typeof next is 'function'
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
