log4js = require './log4js'
logger = log4js.getLogger __filename.replace /^(?:.+[\/\\])?([^.\/\\]+)(?:.[^.]+)?$/, '$1'

url = require 'url'
sysPath = require 'path'
{Semaphore} = require 'sem-lib'

clone = require('lodash/clone')
defaults = require('lodash/defaults')
extend = require('lodash/extend')
isObject = require('lodash/isObject')
isPlainObject = require('lodash/isPlainObject')

inherits = require './inherits'
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
    else if isObject options.adapter
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

SemaphorePool = (options = {})->
    this._factory = {}

    for opt in ['name', 'create', 'destroy', 'priority']
        if options.hasOwnProperty opt
            this._factory[opt] = options[opt]

    for opt in ['min', 'max', 'idle']
        if options.hasOwnProperty opt
            this._factory[opt] = parseInt options[opt], 10
        else
            this._factory[opt] = 0

    SemaphorePool.__super__.constructor.call(this, this._max, true, this._priority)

    this._created = {length: 0}
    this._acquired = {}
    this._avalaible = []
    this._timers = {}
    this._listeners = {}
    this._ensureMinimum()
    return

inherits(SemaphorePool, Semaphore)

Object.assign(SemaphorePool.prototype, {
    getName: ->
        this._factory.name

    acquire: (callback, opts = {})->
        if this.destroyed
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

                logger.debug '[', self._factory.name, '] [', self.id, '] reused from availables', self._avalaible.length
                clientId = self._avalaible.shift()
                client = self._created[clientId]
                self._acquired[clientId] = client
                self._removeIdle client
                callback null, client
                return

    _onClientCreate: (client)->
        if this._destroying or this.destroyed
            this._factory.destroy client
            return new Error 'pool is destroyed'

        logger.debug '[', this._factory.name, '] [', this.id, '] acquire', this._avalaible.length
        this._created.length++
        this._created[client.id] = client
        this._acquired[client.id] = client
        listener = this._listeners[client.id] = this._removeClient.bind(@, client)
        client.on 'end', listener
        return

    release: (client)->
        if this._acquired.hasOwnProperty client.id
            logger.debug "[", this._factory.name, "] [", this.id, "] release '", client.id, "'. Avalaible", this._avalaible.length
            this._avalaible.push client.id
            delete this._acquired[client.id]
            this._idle client
            return this.semGive()
        return false

    _idle: (client)->
        if this._factory.idle > 0
            this._removeIdle client
            this._timers[client.id] = setTimeout this.destroy.bind(@, client), this._factory.idle
            logger.debug "[", this._factory.name, "] [", this.id, "] idle [", client.id, "]"
        return

    _removeIdle: (client)->
        if this._timers.hasOwnProperty client.id
            logger.debug "[", this._factory.name, "] [", this.id, "] remove idle [", client.id, "]"
            clearTimeout this._timers[client.id]
            delete this._timers[client.id]
        return

    destroy: (client, force)->
        if this._created.hasOwnProperty client.id
            if force or this._factory.min < this._created.length
                this._removeClient client
                this._factory.destroy client
                return true
            else
                this._idle client
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
        if this._created.hasOwnProperty client.id
            this._created.length--
            listener = this._listeners[client.id]
            client.removeListener 'end', listener
            this._removeIdle client
            this.release client
            index = this._avalaible.indexOf client.id
            this._avalaible.splice index, 1 if ~index

            delete this._listeners[client.id]
            delete this._created[client.id]
            delete this._acquired[client.id]

            logger.debug "[", this._factory.name, "] [", this.id, "] removed '", client.id, "'. ", this._avalaible.length, "/", this._created.length

            this._ensureMinimum() if not this._destroying
        return

    _onDestroy: (safe)->
        this._avalaible.splice 0, this._avalaible.length

        for clientId, client of this._created
            if clientId isnt 'length'
                this._removeClient client
                this._factory.destroy client

        for clientId, timer of this._timers
            clearTimeout timer if timer

        return
    _ensureMinimum: ->
        self = @
        if self._factory.min > self._created.length
            logger.debug "[", self._factory.name, "] [", self.id, "] _ensureMinimum.", self._created.length, "/", self._factory.min
            self.acquire (err, client)->
                return self.emit 'error', err if err
                self.release client
                self._ensureMinimum()
                return
        return
})

_delegateAdapterExec = (defaultOptions, script, options, done)->
    if isPlainObject(script)
        _script = options
        options = script
        script = _script

    if 'function' is typeof options
        done = options
        options = {}

    if not isPlainObject(options)
        options = {}

    this.exec script, defaults({}, options, defaultOptions), done

AdapterPool = (connectionUrl, options, next)->
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
        this.connectionUrl = connectionUrl

        parsed = url.parse connectionUrl, true, true
        this.options = {}
        this.options.adapter = parsed.protocol and parsed.protocol.substring(0, parsed.protocol.length - 1)
        this.options.database = parsed.pathname and parsed.pathname.substring(1)
        this.options.host = parsed.hostname
        this.options.port = parseInt(parsed.port, 10) if isNumeric parsed.port
        if parsed.auth
            # treat the first : as separator since password may contain : as well
            index = parsed.auth.indexOf ':'
            this.options.user = parsed.auth.substring 0, index
            this.options.password = parsed.auth.substring index + 1

        for key of parsed.query
            this.options[key] = parsed.query[key]

        extend this.options, options
        options or (options = {})
    else if options
        this.options = clone options
        parsed = query: {}
        parsed.protocol = this.options.adapter + '/'
        parsed.pathname = '/' + this.options.database
        parsed.hostname = this.options.host
        parsed.port = this.options.port if isNumeric this.options.port
        if 'string' is typeof this.options.user and this.options.user.length > 0
            if 'string' is typeof this.options.password and this.options.password.length > 0
                parsed.auth = this.options.user + ':' + this.options.password
            else
                parsed.auth = this.options.user

        except = ['adapter', 'database', 'port', 'user', 'password']
        for key of this.options
            if -1 is except.indexOf key
                parsed.query[key] = this.options[key]
        this.connectionUrl = url.format parsed
    else
        err = new Error "Invalid arguments. Usage: options[, fn]; url[, fn]: url, options[, fn]"
        err.code = 'INVALID_ARGUMENTS'
        throw err

    if typeof this.options.adapter isnt 'string' or this.options.adapter.length is 0
        err = new Error 'adapter must be a not empty string'
        err.code = 'BAD_ADAPTER'
        throw err

    for prop in ['name']
        this.options[prop] = options[prop] if typeof options.hasOwnProperty prop

    for prop in ['minConnection', 'maxConnection', 'idleTimeout']
        if isNumeric this.options[prop]
            this.options[prop] = parseInt this.options[prop], 10
        else
            this.options[prop] = defaultOptions[prop]

    adapter = this.adapter = internal.getAdapter this.options
    for method in ['escape', 'escapeId', 'escapeSearch', 'escapeBeginWith', 'escapeEndWith']
        if 'function' is typeof adapter[method]
            @[method] = adapter[method].bind adapter

    this.exec = this.execute = _delegateAdapterExec.bind adapter, this.options

    self = @

    AdapterPool.__super__.constructor.call(this, {
        name: self.options.name

        create: (callback)->
            self.adapter.createConnection self.options, (err, client)->
                return callback(err, null) if err
                client.id = ++client_seq_id
                logger.info "[", self._factory.name, "] [", self.id, "] create [", client_seq_id, "]"
                callback null, client
                return
            return

        destroy: (client)->
            return if client._destroying
            client._destroying = true
            client.end()
            logger.info "[", self._factory.name, "] [", self.id, "] destroy [", client.id, "]"
            return

        max: self.options.maxConnection
        min: self.options.minConnection
        idle: self.options.idleTimeout * 1000
    })

    self.check(next) if typeof next is 'function'
    return

inherits(AdapterPool, SemaphorePool)

Object.assign(AdapterPool.prototype, {
    check: (next)->
        if 'function' isnt typeof next
            next = ->
        this.acquire (err, connection)=>
            return next err if err
            this.release connection
            next()
            return
        return
    getDialect: ->
        return this.options.adapter
    createConnector: (options)->
        new Connector @, defaults {}, options, this.options
    getMaxConnection: ->
        this.options.maxConnection
})

module.exports = AdapterPool
