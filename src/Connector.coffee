log4js = require './log4js'
logger = log4js.getLogger __filename.replace /^(?:.+[\/\\])?([^.\/\\]+)(?:.[^.]+)?$/, '$1'

EventEmitter = require('events').EventEmitter
semLib = require 'sem-lib'
_ = require 'lodash'

STATES =
    INVALID: -1
    AVAILABLE: 0
    START_TRANSACTION: 1
    ROLLBACK: 2
    COMMIT: 3
    ACQUIRE: 4
    RELEASE: 5
    QUERY: 6
    FORCE_RELEASE: 6

MAX_ACQUIRE_TIME = 1 * 60 * 1000

module.exports = class Connector extends EventEmitter
    STATES: STATES
    constructor: (pool, options)->
        super()
        if not _.isObject pool
            error = new Error 'pool is not defined'
            error.code = 'POOL_UNDEFINED'
            throw error

        for method in ['escape', 'escapeId', 'escapeSearch', 'escapeBeginWith', 'escapeEndWith']
            if 'function' is typeof pool.adapter[method]
                @[method] = pool.adapter[method].bind pool.adapter

        for method in ['getDialect', 'exec', 'execute']
            if 'function' is typeof pool[method]
                @[method] = pool[method].bind pool

        if _.isPlainObject options
            this.options = _.clone options
        else
            this.options = {}

        this.timeout = this.options.timeout or MAX_ACQUIRE_TIME
        this.resourceSem = semLib.semCreate 1, true
        this.pool = pool
        this._savepoints = 0
        this.state = STATES.AVAILABLE
        this.acquireTimeout = 0

        this.resource = 1
        this.waiting = []
        this._savepointsStack = []

    clone: ->
        new Connector this.pool, this.options

    getPool: ->
        this.pool

    getMaxConnection: ->
        this.pool.getMaxConnection()

    _addSavePoint: (client)->
        this._savepointsStack.push(new Error("_addSavePoint"))
        if client
            this._client = client
            this.acquireTimeout = setTimeout this._forceRelease, this.timeout
            client.on 'end', this._checkSafeEnd
            logger.debug 'acquired client', client.id
        this._savepoints++

    _forceRelease: =>
        this._takeResource STATES.FORCE_RELEASE, =>
            if this._savepoints is 0
                return this._giveResource()
            this.state = STATES.INVALID
            logger.warn 'Force rollback and release cause acquire last longer than acceptable'
            this._rollback this._giveResource, true
            return
        , true
        return

    _checkSafeEnd: =>
        if this._savepoints isnt 0
            logger.warn 'client ends in the middle of a transaction'
            this.state = STATES.INVALID
            this._release(->)
        return

    _removeSavepoint: ->
        this._savepointsStack.pop()
        if --this._savepoints is 0
            this._client.removeListener 'end', this._checkSafeEnd
            logger.debug 'released client', this._client.id
            this._client = null

    getState: ->
        return this.state

    getSavepointsSize: ->
        return this._savepoints

    _hasError: ->
        if this.state is STATES.INVALID
            error = new Error('Connector is in invalid state.')
            error.code = 'INVALID_STATE'
            return error

    _takeResource: (state, callback, prior)->
        return callback(err) if err = this._hasError()

        if this.resource is 1
            this.resource = 0
            this.state = state if state?
            callback()
        else if prior
            this.waiting.unshift [state, callback, prior]
        else
            this.waiting.push [state, callback, prior]
        return

    _giveResource: =>
        this.resource = 1
        this.state = STATES.AVAILABLE if this.state isnt STATES.INVALID
        if this.waiting.length
            [state, callback, prior] = this.waiting.shift()
            this._takeResource state, callback, prior
        return

    acquire: (callback)->
        logger.trace this.pool.options.name, 'acquire'
        ret = (...args) =>
            this._giveResource()
            callback(...args) if typeof callback is 'function'
            return

        this._takeResource STATES.ACQUIRE, (err)=>
            return ret err if err
            this._acquire ret
            return

    _acquire: (callback)->
        # check if connection has already been acquired
        if this._savepoints > 0
            logger.trace this.pool.options.name, 'already acquired'
            callback null, false
            return

        this.pool.acquire (err, client)=>
            return callback err if err
            logger.trace this.pool.options.name, 'acquired'
            this._addSavePoint client
            callback null, true
        return

    query: (query, callback, options)->
        ret = (...args) =>
            this._giveResource()
            callback(...args) if typeof callback is 'function'
            return

        this._takeResource STATES.QUERY, (err)=>
            return ret err if err

            if this._savepoints is 0
                logger.trace this.pool.options.name, 'automatic acquire for query'
                return this._acquire (err)=>
                    return ret err if err
                    this._query query, (...args)=>
                        logger.trace this.pool.options.name, 'automatic release for query'
                        this._release (err)=>
                            args[0] = err
                            ret.apply @, args
                        , args[0]
                    , options

            this._query query, ret, options
            return
        return

    _query: (query, callback, options = {})->
        logger.trace this.pool.options.name, '[query] -', query

        this._client.query query, (err, res)=>
            if err and options.autoRollback isnt false
                logger.warn this.pool.options.name, 'automatic rollback on query error', err
                return this._rollback callback, false, err
            callback err, res

    stream: (query, callback, done, options = {})->
        ret = (...args) =>
            this._giveResource()
            done(...args) if typeof done is 'function'
            return

        this._takeResource STATES.STREAM, (err)=>
            return ret err if err

            if this._savepoints is 0
                logger.trace this.pool.options.name, 'automatic acquire for stream'
                return this._acquire (err)=>
                    return ret err if err
                    logger.trace this.pool.options.name, 'automatic release for stream'
                    this._stream query, callback, (...args)=>
                        this._release (err)=>
                            args[0] = err
                            ret.apply @, args
                        , args[0]
                    , options
            this._stream query, callback, ret, options
            return
         return

    _stream: (query, callback, done, options = {})->
        logger.trace this.pool.options.name, '[stream] -', query

        stream = this._client.stream query, (row)->
            callback row, stream
        , (err, ...args) =>
            if err and options.autoRollback isnt false
                logger.warn this.pool.options.name, 'automatic rollback on stream error', err
                return this._rollback done, false, err
            done(err, ...args)
        return

    begin: (callback)->
        if this._savepoints is 0
            # No automatic acquire because there cannot be an automatic release
            # Programmer may or may not perform a query/stream with the connection.
            # Therefore, there is no way to know when to release connection
            err = new Error 'Connector has no active connection. You must acquire a connection before begining a transaction.'
            err.code = 'NO_CONNECTION'
            return callback err

        logger.debug this.pool.options.name, 'begin'
        ret = (...args) =>
            this._giveResource()
            logger.debug this.pool.options.name, 'begun'
            callback(...args) if typeof callback is 'function'
            return
        this._takeResource STATES.START_TRANSACTION, (err)=>
            return ret err if err

            if this._savepoints is 0
                # No automatic acquire because there cannot be an automatic release
                # Programmer may or may not perform a query/stream with the connection.
                # Therefore, there is no way to know when to release connection
                err = new Error 'Connector has no active connection. You must acquire a connection before begining a transaction.'
                err.code = 'NO_CONNECTION'
                return ret err

            this._begin ret

    _begin: (callback)->
        if this._savepoints is 1
            # we have no transaction
            query = 'BEGIN'
        else if this._savepoints > 0
            # we are in a transaction, make a savepoint
            query = 'SAVEPOINT sp_' + (this._savepoints - 1)

        logger.trace this.pool.options.name, '[query] -', query

        this._client.query query, (err, res)=>
            return callback err if err
            this._addSavePoint()
            logger.trace this.pool.options.name, 'begun'
            callback null
            return
        return

    rollback: (callback, all = false)->
        logger.debug this.pool.options.name, 'rollback'

        ret = (...args) =>
            this._giveResource()
            logger.debug this.pool.options.name, 'rollbacked'
            callback(...args) if typeof callback is 'function'
            return
        this._takeResource STATES.ROLLBACK, (err)=>
            return ret err if err
            return ret null if this._savepoints is 0
            this._rollback ret, all

    _rollback: (callback, all, errors)->
        if this._savepoints is 1
            return this._release callback, errors if all
            return callback errors
        else if this._savepoints is 0
            return callback errors
        else if this._savepoints is 2
            query = 'ROLLBACK'
        else
            query = 'ROLLBACK TO sp_' + (this._savepoints - 2)

        this._removeSavepoint()

        logger.trace this.pool.options.name, '[query] -', query

        this._client.query query, (err)=>
            if err
                if typeof errors is 'undefined'
                    errors = err
                else if errors instanceof Array
                    errors.push err
                else
                    errors = [errors]
                    errors.push err

            return this._rollback(callback, all, errors) if all
            callback errors

    commit: (callback, all = false)->
        if typeof callback is 'boolean'
            _all = callback
        else if typeof all is 'boolean'
            _all = all

        if typeof callback is 'function'
            _callback = callback
        else if typeof all is 'function'
            _callback = all

        callback = _callback
        all = _all

        logger.debug this.pool.options.name, 'commit'
        ret = (...args) =>
            this._giveResource()
            logger.debug this.pool.options.name, 'comitted'
            callback(...args) if typeof callback is 'function'
            return
        this._takeResource STATES.COMMIT, (err)=>
            return ret err if err
            return ret null if this._savepoints is 0
            this._commit ret, all

    _commit: (callback, all, errors)->
        if this._savepoints is 1
            return this._release callback, errors if all
            return callback errors
        else if this._savepoints is 0
            return callback errors
        else if this._savepoints is 2
            query = 'COMMIT'
        else
            query = 'RELEASE SAVEPOINT sp_' + (this._savepoints - 2)

        logger.trace this.pool.options.name, '[query] -', query

        this._client.query query, (err)=>
            if err
                if typeof errors is 'undefined'
                    errors = err
                else if errors instanceof Array
                    errors.push err
                else
                    errors = [errors]
                    errors.push err

            return this._rollback(callback, all, errors) if err
            this._removeSavepoint()
            return this._commit(callback, all, errors) if all
            callback null

    release: (callback)->
        logger.debug this.pool.options.name, 'release'
        ret = (...args) =>
            this._giveResource()
            callback(...args) if typeof callback is 'function'
            return
        this._takeResource STATES.RELEASE, (err)=>
            return ret err if err
            if this._savepoints is 0
                logger.debug this.pool.options.name, 'already released'
                return ret null
            if this._savepoints isnt 1
                err = new Error 'There is a begining transaction. End it before release'
                err.code = 'NO_RELEASE'
                return ret(err)
            this._release ret
            return

    _release: (callback, errors)->
        clearTimeout this.acquireTimeout
        this.pool.release this._client
        logger.debug this.pool.options.name, 'released'
        this._removeSavepoint()
        callback(errors)
        return
