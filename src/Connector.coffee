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
        super
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
            @options = _.clone options
        else
            @options = {}

        @timeout = @options.timeout or MAX_ACQUIRE_TIME
        @resourceSem = semLib.semCreate 1, true
        @pool = pool
        @_savepoints = 0
        @state = STATES.AVAILABLE
        @acquireTimeout = 0

        @resource = 1
        @waiting = []

    clone: ->
        new Connector @pool, @options

    getPool: ->
        @pool

    # getPoolSize: ->
    #     @pool.getPoolSize()

    getMaxConnection: ->
        @pool.getMaxConnection()

    _addSavePoint: (connection)->
        @_connection = connection if connection
        @_savepoints++

    _removeSavepoint: ->
        @_savepoints--

    # getConnection: ->
    #     @_connection

    getState: ->
        return @state

    getSavepointsSize: ->
        return @_savepoints

    _hasError: ->
        if @state is STATES.INVALID
            error = new Error('Connector is in invalid state.')
            error.code = 'INVALID_STATE'
            return error

    _takeResource: (state, callback, prior)->
        return callback(err) if err = @_hasError()

        if @resource is 1
            @resource = 0
            @state = state if state?
            callback()
        else if prior
            @waiting.unshift [state, callback, prior]
        else
            @waiting.push [state, callback, prior]
        return

    _giveResource: ->
        @resource = 1
        @state = STATES.AVAILABLE if @state isnt STATES.INVALID
        if @waiting.length
            [state, callback, prior] = @waiting.shift()
            @_takeResource state, callback, prior
        return

        # @resourceSem.semGive()

    acquire: (callback)->
        logger.trace @pool.options.name, 'acquire'
        ret = =>
            @_giveResource()
            callback.apply null, arguments if typeof callback is 'function'
            return

        @_takeResource STATES.ACQUIRE, (err)=>
            return ret err if err
            @_acquire ret
            return

    _acquire: (callback)->
        # check if connection has already been acquired
        if @_savepoints > 0
            logger.trace @pool.options.name, 'already acquired'
            callback null, false
            return

        @pool.acquire (err, connection)=>
            return callback err if err
            logger.trace @pool.options.name, 'acquired'
            @_addSavePoint connection
            @acquireTimeout = setTimeout =>
                @_takeResource STATES.FORCE_RELEASE, =>
                    if @_savepoints is 0
                        return @_giveResource()
                    @state = STATES.INVALID
                    logger.error 'Force rollback and release cause acquire last longer than acceptable'
                    @_rollback =>
                        @_giveResource()
                    , true
                    return
                , true
                return
            , @timeout
            callback null, true
        return

    query: (query, callback, options)->
        ret = =>
            @_giveResource()
            callback.apply null, arguments if typeof callback is 'function'
            return

        @_takeResource STATES.QUERY, (err)=>
            return ret err if err

            if @_savepoints is 0
                logger.trace @pool.options.name, 'automatic acquire for query'
                return @_acquire (err)=>
                    return ret err if err
                    @_query query, (err)=>
                        args = Array::slice.call arguments, 0
                        logger.trace @pool.options.name, 'automatic release for query'
                        @_release (err)=>
                            args[0] = err
                            ret.apply @, args
                        , err
                    , options

            @_query query, ret, options
            return
        return

    _query: (query, callback, options = {})->
        logger.trace @pool.options.name, '[query] -', query

        @_connection.query query, (err, res)=>
            if err and options.autoRollback isnt false
                logger.error @pool.options.name, 'automatic rollback on query error', err
                return @_rollback callback, false, err
            callback err, res

    stream: (query, callback, done, options = {})->
        ret = =>
            @_giveResource()
            done.apply null, arguments if typeof done is 'function'
            return

        @_takeResource STATES.STREAM, (err)=>
            return ret err if err

            if @_savepoints is 0
                logger.trace @pool.options.name, 'automatic acquire for stream'
                return @_acquire (err)=>
                    return ret err if err
                    logger.trace @pool.options.name, 'automatic release for stream'
                    @_stream query, callback, (err)=>
                        args = Array::slice.call arguments, 0
                        @_release (err)=>
                            args[0] = err
                            ret.apply @, args
                        , err
                    , options
            @_stream query, callback, ret, options
            return
         return

    _stream: (query, callback, done, options = {})->
        logger.trace @pool.options.name, '[stream] -', query

        stream = @_connection.stream query, (row)->
            callback row, stream
        , (err)=>
            if err and options.autoRollback isnt false
                logger.error @pool.options.name, 'automatic rollback on stream error', err
                return @_rollback done, false, err
            done.apply null, arguments
        return

    begin: (callback)->
        if @_savepoints is 0
            # No automatic acquire because there cannot be an automatic release
            # Programmer may or may not perform a query/stream with the connection.
            # Therefore, there is no way to know when to release connection
            err = new Error 'Connector has no active connection. You must acquire a connection before begining a transaction.'
            err.code = 'NO_CONNECTION'
            return callback err

        logger.debug @pool.options.name, 'begin'
        ret = =>
            @_giveResource()
            logger.debug @pool.options.name, 'begun'
            callback.apply null, arguments if typeof callback is 'function'
            return
        @_takeResource STATES.START_TRANSACTION, (err)=>
            return ret err if err

            if @_savepoints is 0
                # No automatic acquire because there cannot be an automatic release
                # Programmer may or may not perform a query/stream with the connection.
                # Therefore, there is no way to know when to release connection
                err = new Error 'Connector has no active connection. You must acquire a connection before begining a transaction.'
                err.code = 'NO_CONNECTION'
                return ret err

            @_begin ret

    _begin: (callback)->
        if @_savepoints is 1
            # we have no transaction
            query = 'BEGIN'
        else if @_savepoints > 0
            # we are in a transaction, make a savepoint
            query = 'SAVEPOINT sp_' + (@_savepoints - 1)

        logger.trace @pool.options.name, '[query] -', query

        @_connection.query query, (err, res)=>
            return callback err if err
            @_addSavePoint()
            logger.trace @pool.options.name, 'begun'
            callback null
            return
        return

    rollback: (callback, all = false)->
        logger.debug @pool.options.name, 'rollback'

        ret = =>
            @_giveResource()
            logger.debug @pool.options.name, 'rollbacked'
            callback.apply null, arguments if typeof callback is 'function'
            return
        @_takeResource STATES.ROLLBACK, (err)=>
            return ret err if err
            return ret null if @_savepoints is 0
            @_rollback ret, all

    _rollback: (callback, all, errors)->
        if @_savepoints is 1
            return @_release callback, errors if all
            return callback errors
        else if @_savepoints is 0
            return callback errors
        else if @_savepoints is 2
            query = 'ROLLBACK'
        else
            query = 'ROLLBACK TO sp_' + (@_savepoints - 2)

        @_removeSavepoint()

        logger.trace @pool.options.name, '[query] -', query

        @_connection.query query, (err)=>
            if err
                if typeof errors is 'undefined'
                    errors = err
                else if errors instanceof Array
                    errors.push err
                else
                    errors = [errors]
                    errors.push err

            return @_rollback(callback, all, errors) if all
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

        logger.debug @pool.options.name, 'commit'
        ret = =>
            @_giveResource()
            logger.debug @pool.options.name, 'comitted'
            callback.apply null, arguments if typeof callback is 'function'
            return
        @_takeResource STATES.COMMIT, (err)=>
            return ret err if err
            return ret null if @_savepoints is 0
            @_commit ret, all

    _commit: (callback, all, errors)->
        if @_savepoints is 1
            return @_release callback, errors if all
            return callback errors
        else if @_savepoints is 0
            return callback errors
        else if @_savepoints is 2
            query = 'COMMIT'
        else
            query = 'RELEASE SAVEPOINT sp_' + (@_savepoints - 2)

        logger.trace @pool.options.name, '[query] -', query

        @_connection.query query, (err)=>
            if err
                if typeof errors is 'undefined'
                    errors = err
                else if errors instanceof Array
                    errors.push err
                else
                    errors = [errors]
                    errors.push err

            return @_rollback(callback, all, errors) if err
            @_removeSavepoint()
            return @_commit(callback, all, errors) if all
            callback null

    release: (callback)->
        logger.debug @pool.options.name, 'release'
        ret = =>
            @_giveResource()
            callback.apply null, arguments if typeof callback is 'function'
            return
        @_takeResource STATES.RELEASE, (err)=>
            return ret err if err
            if @_savepoints is 0
                logger.debug @pool.options.name, 'already released'
                return ret null
            if @_savepoints isnt 1
                err = new Error 'There is a begining transaction. End it before release'
                err.code = 'NO_RELEASE'
                return ret(err)
            @_release ret
            return

    _release: (callback, errors)->
        clearTimeout @acquireTimeout
        @pool.release @_connection
        logger.debug @pool.options.name, 'released'
        @_removeSavepoint()
        callback(errors)
        return
