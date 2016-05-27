log4js = require './log4js'
logger = log4js.getLogger __filename.replace /^(?:.+[\/\\])?([^.\/\\]+)(?:.[^.]+)?$/, '$1'

_ = require 'lodash'
url = require 'url'
sysPath = require 'path'
semLib = require 'sem-lib'
Connector = require './Connector'

# Based on jQuery 1.11
isNumeric = (obj) ->
    !Array.isArray( obj ) and (obj - parseFloat( obj ) + 1) >= 0

internal = {}
internal.adapters = {}

internal.getAdapter = (options)->
    if typeof options.adapter is 'string'
        adapter = internal.adapters[options.adapter]
        if typeof adapter is 'undefined'
            adapter = require './dialects/' + options.adapter + '/adapter'
            internal.adapters[options.adapter] = adapter
    else if _.isObject options.adapter
        adapter = options.adapter

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

client_seq_id = 0
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
        @_created = {length: 0}
        @_acquired = {}
        @_avalaible = []
        @_timers = {}
        @_listeners = {}
        @_ensureMinimum()

    getName: ->
        @_factory.name

    acquire: (callback, opts = {})->
        if @destroyed
            callback new Error 'pool is destroyed'
            return
        self = @
        self.semTake
            priority: opts.priority
            num: 1
            timeOut: opts.timeOut
            onTimeOut: opts.onTimeOut
            onTake: ->
                if self._avalaible.length is 0
                    self._factory.create (err, client)->
                        return callback err if err
                        err = self._onClientCreate client
                        callback err, client
                        return
                    return

                logger.debug '[', self._factory.name, '] [', self.id, '] reused', self._avalaible.length
                clientId = self._avalaible.shift()
                client = self._created[clientId]
                self._acquired[clientId] = client
                self._removeIdle client
                callback null, client
                return

    _onClientCreate: (client)->
        if @_destroying or @destroyed
            @_factory.destroy client
            return new Error 'pool is destroyed'

        logger.debug '[', @_factory.name, '] [', @id, '] acquire', @_avalaible.length
        @_created.length++
        @_created[client.id] = client
        @_acquired[client.id] = client
        @_removeIdle client
        listener = @_listeners[client.id] = @_removeClient.bind(@, client)
        client.on 'end', listener
        return

    release: (client)->
        if @_acquired.hasOwnProperty client.id
            logger.debug "[", @_factory.name, "] [", @id, "] release '", client.id, "'. Avalaible", @_avalaible.length
            @_avalaible.push client.id
            delete @_acquired[client.id]
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
        if @_created.hasOwnProperty client.id
            if force or @_factory.min < @_created.length
                @_removeClient client
                @_factory.destroy client
                return true
            else
                @_idle client
        return false

    _superDestroy: (safe, _onDestroy)->
        SemaphorePool.__super__.destroy.call @, safe, _onDestroy

    destroyAll: (safe, _onDestroy)->
        self = @
        self._superDestroy safe, ->
            self._onDestroy()
            _onDestroy() if 'function' is typeof _onDestroy
            return
        return

    _removeClient: (client)->
        if @_created.hasOwnProperty client.id
            @_created.length--
            listener = @_listeners[client.id]
            client.removeListener 'end', listener
            @_removeIdle client
            @release client
            index = @_avalaible.indexOf client.id
            @_avalaible.splice index, 1 if ~index

            delete @_listeners[client.id]
            delete @_created[client.id]
            delete @_acquired[client.id]

            logger.debug "[", @_factory.name, "] [", @id, "] removed '", client.id, "'. ", @_avalaible.length, "/", @_created.length

            @_ensureMinimum() if not @_destroying
        return

    _onDestroy: (safe)->
        @_avalaible.splice 0, @_avalaible.length

        for clientId, client of @_created
            if clientId isnt 'length'
                @_removeClient client
                @_factory.destroy client

        for clientId, timer of @_timers
            clearTimeout timer if timer

        return
    _ensureMinimum: ->
        self = @
        if self._factory.min > self._created.length
            logger.debug "[", self._factory.name, "] [", self.id, "] _ensureMinimum.", self._created.length, "/", self._factory.min, ""
            self.acquire (err, client)->
                return self.emit 'error', err if err
                self.release client
                self._ensureMinimum()
                return
        return

_delegateAdapterExec = (defaultOptions, script, options, done)->
    if _.isPlainObject(script)
        _script = options
        options = script
        script = _script

    if 'function' is typeof options
        done = options
        options = {}

    if not _.isPlainObject(options)
        options = {}

    @exec script, _.defaults({}, options, defaultOptions), done

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
            @options.port = parseInt(parsed.port, 10) if isNumeric parsed.port
            if parsed.auth
                # treat the first : as separator since password may contain : as well
                index = parsed.auth.indexOf ':'
                @options.user = parsed.auth.substring 0, index
                @options.password = parsed.auth.substring index + 1

            for key of parsed.query
                @options[key] = parsed.query[key]

            _.extend @options, options
            options or (options = {})
        else if options
            @options = _.clone options
            parsed = query: {}
            parsed.protocol = @options.adapter + '/'
            parsed.pathname = '/' + @options.database
            parsed.hostname = @options.host
            parsed.port = @options.port if isNumeric @options.port
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
            if isNumeric @options[prop]
                @options[prop] = parseInt @options[prop], 10
            else
                @options[prop] = defaultOptions[prop]

        adapter = @adapter = internal.getAdapter @options
        for method in ['escape', 'escapeId', 'escapeSearch', 'escapeBeginWith', 'escapeEndWith']
            if 'function' is typeof adapter[method]
                @[method] = adapter[method].bind adapter

        @exec = @execute = _delegateAdapterExec.bind adapter, @options

        self = @
        super
            name: self.options.name

            create: (callback)->
                self.adapter.createConnection self.options, (err, client)->
                    return callback(err, null) if err
                    logger.info '[', self._factory.name, '] [', self.id, '] create'
                    client.id = ++client_seq_id
                    callback null, client
                    return
                return

            destroy: (client)->
                return if client._destroying or not client.end
                logger.info "[", self._factory.name, "] [", self.id, "] destroy"
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
        new Connector @, _.defaults {}, options, @options
    getMaxConnection: ->
        @options.maxConnection
