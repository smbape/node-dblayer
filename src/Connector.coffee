log4js = global.log4js or (global.log4js = require 'log4js')
logger = log4js.getLogger 'Connector'

EventEmitter = require('events').EventEmitter
GenericUtil = require './GenericUtil'
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

    clone: ->
        new Connector @pool, @options

    getDialect: ->
        @pool.getDialect()
    
    # getPool: ->
    #     @pool
    getInnerPool: ->
        @pool.pool
    # getPoolSize: ->
    #     @pool.pool.getPoolSize()
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

    _stateError: (expected)->
        return if @state is expected
        err = new Error "Connector must be '#{expected}' but it is '#{@state}'"
        err.code = 'STATE'
        return err

    _hasError: ->
        if @state is STATES.INVALID
            error = new Error('Connector is in invalid state.')
            error.code = 'INVALID_STATE'
            return error

    _takeResource: (state, settings)->
        if _.isPlainObject settings
            onTake = if typeof settings.onTake is 'function' then settings.onTake else (->)
            settings = _.clone(settings)
        else
            onTake = settings
            settings = {}

        return onTake(err) if err = @_hasError()
        settings.onTake = =>
            onTake @_hasError()

        @state = state if state?
        @resourceSem.semTake settings

    _giveResource: ->
        @state = STATES.AVAILABLE if @state isnt STATES.INVALID
        @resourceSem.semGive()

    acquire: (callback)->
        logger.debug @pool.options.name, 'acquire'
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
            logger.debug @pool.options.name, 'already acquired'
            callback null, false
            return

        @pool.acquire (err, connection)=>
            return callback err if err
            logger.debug @pool.options.name, 'acquired'
            @_addSavePoint connection
            @acquireTimeout = setTimeout =>
                @_takeResource STATES.FORCE_RELEASE,
                    priority: 1
                    onTake: =>
                        if @_savepoints is 0
                            return @_giveResource()
                        @state = STATES.INVALID
                        logger.error 'Force rollback and release cause acquire last longer than acceptable'
                        # @emit 'beforeForceRelease'
                        @_rollback =>
                            # @emit 'afterForceRelease'
                            @_giveResource()
                        , true
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
                logger.debug @pool.options.name, 'automatic acquire for query'
                return @_acquire (err)=>
                    return ret err if err
                    @_query query, (err)=>
                        args = Array::slice.call arguments, 0
                        logger.debug @pool.options.name, 'automatic release for query'
                        @_release (err)=>
                            args[0] = err
                            ret.apply @, args
                        , err
                    , options

            @_query query, ret, options
            return
        return

    _query: (query, callback, options = {})->
        logger.trace @pool.options.name, '[query] - ' + query

        @_connection.query query, (err, res)=>
            if err and options.autoRollback isnt false
                logger.error @pool.options.name, 'automatic rollback on query error'
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
                logger.debug @pool.options.name, 'automatic acquire for stream'
                return @_acquire (err)=>
                    return ret err if err
                    logger.debug @pool.options.name, 'automatic release for stream'
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
        logger.trace @pool.options.name, '[stream] - ' + query

        stream = @_connection.stream query, (row)->
            callback row, stream
        , (err)=>
            if err and options.autoRollback isnt false
                logger.error @pool.options.name, 'automatic rollback on stream error'
                return @_rollback done, false, err
            done.apply null, arguments
        return

    begin: (callback, options)->
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
        else
            # Something mess up
            err = new Error 'You probably have called this private method outside'
            err.code = 'MESS'
            return callback err

        logger.trace @pool.options.name, '[query] - ' + query

        @_connection.query query, (err, res)=>
            return callback err if err
            @_addSavePoint()
            logger.debug @pool.options.name, 'begun'
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

        logger.trace @pool.options.name, '[query] - ' + query

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
        
        logger.trace @pool.options.name, '[query] - ' + query

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

    escape: ->
        @pool.adapter.escape.apply @pool.adapter, arguments
    escapeId: ->
        @pool.adapter.escapeId.apply @pool.adapter, arguments
    escapeSearch: ->
        @pool.adapter.escapeSearch.apply @pool.adapter, arguments
    escapeBeginWith: ->
        @pool.adapter.escapeBeginWith.apply @pool.adapter, arguments
    escapeEndWith: ->
        @pool.adapter.escapeEndWith.apply @pool.adapter, arguments
    exprEqual: ->
        @pool.adapter.exprEqual.apply @pool.adapter, arguments
    exprNotEqual: ->
        @pool.adapter.exprNotEqual.apply @pool.adapter, arguments
