log4js = global.log4js or (global.log4js = require 'log4js')
logger = log4js.getLogger 'PersistenceManager'

GenericUtil = require './GenericUtil'
_ = require 'lodash'
squel = require './SquelPatch'
RowMap = require './RowMap'
CompiledMapping = require './CompiledMapping'
async = require 'async'
semLib = require 'sem-lib'

module.exports = class PersistenceManager extends CompiledMapping

isValidModelInstance = (model)->
    if not model or 'object' isnt typeof model
        err = new Error 'Invalid model'
        err.code = 'INVALID_MODEL'
        return err

    for method in ['get', 'set', 'unset', 'toJSON']
        if 'function' isnt typeof model[method]
            err = new Error "method #{method} was not found"
            err.code = 'INVALID_MODEL'
            return err

    return true

assertValidModelInstance = (model)->
    err = isValidModelInstance model
    if err instanceof Error
        throw err

PersistenceManager::dialects =
    postgres:
        squelOptions:
            # autoQuoteTableNames: true
            # autoQuoteFieldNames: true
            replaceSingleQuotes: true
            nameQuoteCharacter: '"'
            fieldAliasQuoteCharacter: '"'
            tableAliasQuoteCharacter: '"'
        decorateInsert: (query, column)->
            if GenericUtil.notEmptyString column
                query += ' RETURNING "' + column + '"'
            else
                query
    mysql:
        squelOptions:
            # autoQuoteTableNames: true
            # autoQuoteFieldNames: true
            replaceSingleQuotes: true
            nameQuoteCharacter: '`'
            fieldAliasQuoteCharacter: '`'
            tableAliasQuoteCharacter: '`'
    sqlite3:
        squelOptions:
            # autoQuoteTableNames: true
            # autoQuoteFieldNames: true
            replaceSingleQuotes: true
            nameQuoteCharacter: '"'
            fieldAliasQuoteCharacter: '"'
            tableAliasQuoteCharacter: '"'

PersistenceManager::getSquelOptions = (dialect)->
    if @ instanceof PersistenceManager
        instance = @
    else
        instance = PersistenceManager::

    if instance.dialects.hasOwnProperty dialect
        _.clone instance.dialects[dialect].squelOptions

PersistenceManager::decorateInsert = (dialect, query, column)->
    if @dialects.hasOwnProperty(dialect) and 'function' is typeof @dialects[dialect].decorateInsert
        @dialects[dialect].decorateInsert query, column
    else
        query

PersistenceManager::insert = (model, options, callback)->
    connector = options.connector
    try
        query = @getInsertQuery model, _.extend {dialect: connector.getDialect()}, options, {autoRollback: false}
    catch err
        return callback err
    
    connector.acquire (err, performed)->
        return callback(err) if err
        connector.begin (err)->
            if err
                if performed
                    connector.release (_err)->
                        callback if _err then [err, _err] else err
                        return
                    return
                callback err
                return
            query.execute connector, (err)->
                if err
                    method = 'rollback'
                else
                    method = 'commit'

                args = Array::slice.call arguments, 0
                connector[method] (err)->
                    if err
                        if args[0]
                            args[0] = [err, args[0]]
                        else
                            args[0] = err
                    if performed
                        connector.release (err)->
                            callback.apply null, args
                            return
                    else
                        callback.apply null, args
                    return
                return
            return
        return
    return

PersistenceManager::getInsertQuery = (model, options)->
    new InsertQuery @, model, options

PersistenceManager::list = (className, options, callback)->
    connector = options.connector
    try
        query = @getSelectQuery className, _.extend {dialect: connector.getDialect()}, options
    catch err
        return callback err
    query.list connector, callback

PersistenceManager::stream = (className, options, callback, done)->
    connector = options.connector
    listConnector = options.listConnector or connector.clone()

    try
        query = @getSelectQuery className, _.extend {dialect: connector.getDialect()}, options
    catch err
        return done err
    query.stream connector, listConnector, callback, done

PersistenceManager::getSelectQuery = (className, options)->
    if not options.where and _.isPlainObject options.attributes
        definition = @_getDefinition className
        options.where = _getInitializeCondition @, null, className, definition, _.extend {}, options, {useDefinitionColumn: false}

    new SelectQuery @, className, options

PersistenceManager::update = (model, options, callback)->
    connector = options.connector
    try
        query = @getUpdateQuery model, _.extend {dialect: connector.getDialect()}, options, {autoRollback: false}
    catch err
        return callback err
    connector.acquire (err, performed)->
        return callback(err) if err
        connector.begin (err)->
            if err
                if performed
                    connector.release (_err)->
                        callback if _err then [err, _err] else err
                        return
                    return
                callback err
                return
            query.execute connector, (err)->
                if err
                    method = 'rollback'
                else
                    method = 'commit'

                args = Array::slice.call arguments, 0
                connector[method] (err)->
                    if err
                        if args[0]
                            args[0] = [err, args[0]]
                        else
                            args[0] = err
                    if performed
                        connector.release (err)->
                            callback.apply null, args
                            return
                    else
                        callback.apply null, args
                    return
                return
            return
        return
    return

PersistenceManager::getUpdateQuery = (model, options)->
    new UpdateQuery @, model, options

PersistenceManager::delete = PersistenceManager::remove = (model, options, callback)->
    connector = options.connector
    try
        query = @getDeleteQuery model, _.extend {dialect: connector.getDialect()}, options, {autoRollback: false}
    catch err
        return callback err
    query.execute connector, callback
    return

PersistenceManager::getDeleteQuery = (model, options)->
    new DeleteQuery @, model, options

PersistenceManager::save = (model, options, callback)->
    callback err if (err = isValidModelInstance model) instanceof Error

    # if arguments.length is 2 and 'function' is typeof options
    #     callback = options
    # options = {} if not _.isPlainObject options
    (callback = ->) if 'function' isnt typeof callback

    className = options.className or model.className
    definition = @_getDefinition className

    try
        where = _getInitializeCondition @, model, className, definition, _.extend {}, options,
            useDefinitionColumn: false
            useAttributes: false
    catch err
        callback err
        return
    
    if where.length is 0
        @insert model, _.extend({}, options, reflect: true), callback
    else
        backup = options
        options = _.extend {}, options,
            where: where
            limit: 2 # Expecting one result. Limit is for unique checking without getting all results
        @list className, options, (err, models)=>
            return callback(err) if err
            if models.length is 1
                @update model, backup, callback
            else
                @insert model, _.extend({}, backup, reflect: true), callback
            return
    return

PersistenceManager::initializeOrInsert = (model, options, callback)->
    callback err if (err = isValidModelInstance model) instanceof Error

    if arguments.length is 2 and 'function' is typeof options
        callback = options
    options = {} if not _.isPlainObject options
    (callback = ->) if 'function' isnt typeof callback

    className = options.className or model.className
    definition = @_getDefinition className

    try
        where = _getInitializeCondition @, model, className, definition, _.extend {}, options,
            useDefinitionColumn: false
            useAttributes: false
    catch err
        callback err
        return
    
    if where.length is 0
        @insert model, _.extend({}, options, reflect: true), callback
    else
        backup = options
        options = _.extend {}, options,
            where: where
            limit: 2 # Expecting one result. Limit is for unique checking without getting all results
        @list className, options, (err, models)=>
            return callback(err) if err
            if models.length is 1
                model.set models[0].attributes
                callback err, model.get definition.id.name
            else
                @insert model, _.extend({}, backup, reflect: true), callback
            return
    return

PersistenceManager::initialize = (model, options, callback)->
    callback err if (err = isValidModelInstance model) instanceof Error

    (callback = ->) if 'function' isnt typeof callback

    if not _.isObject model
        err = new Error 'No model'
        err.code = 'NO_MODEL'
        return callback err
    
    className = options.className or model.className
    definition = @_getDefinition className
    options = _.extend {}, options,
        models: [model]

    try
        options.where = _getInitializeCondition @, model, className, definition, _.extend {}, options, {useDefinitionColumn: false}
    catch err
        callback err
        return
    
    @list className, options, callback

# return where condition to be parsed by RowMap
_getInitializeCondition = (pMgr, model, className, definition, options)->
    connector = options.connector

    if typeof options.where is 'undefined'
        if not model
            attributes = options.attributes
        else if _.isPlainObject(definition.id) and value = model.get definition.id.name
            # id is define
            attributes = {}
            attributes[definition.id.name] = value
        else
            if definition.constraints.unique.length isnt 0 and (options.useAttributes is false or not options.attributes)
                attributes = {}
                # check unique constraints properties
                for constraint, index in definition.constraints.unique
                    isSetted = true
                    for prop in constraint
                        value = model.get prop

                        # null and undefined are not allowed values for unique columns
                        # 0 is a falsy value but a valid value for  unique columns
                        if value is null or 'undefined' is typeof value
                            isSetted = false
                            break

                        attributes[prop] = value
                    break if isSetted

            attributes = options.attributes or model.toJSON() if not isSetted and options.useAttributes isnt false
        where = []
        
        if _.isPlainObject attributes
            for attr, value of attributes
                _addWhereCondition pMgr, model, attr, value, definition, connector, where, options
        else if Array.isArray attributes
            for attr in attributes
                value = model.get attr
                _addWhereCondition pMgr, model, attr, value, definition, connector, where, options
    else
        where = options.where

    if isSetted
        _.isPlainObject(options.result) or (options.result = {})
        options.result.constraint = index

    where or []

PRIMITIVE_TYPES = /^(?:string|boolean|number)$/

_addWhereCondition = (pMgr, model, attr, value, definition, connector, where, options)->
    if typeof value is 'undefined'
        return

    if options.useDefinitionColumn
        column = connector.escapeId definition.properties[attr].column
    else
        column = '{' + attr + '}'

    propDef = definition.availableProperties[attr].definition
    if _.isPlainObject(propDef.handlers) and typeof propDef.handlers.write is 'function'
        value = propDef.handlers.write value, model, options

    if  PRIMITIVE_TYPES.test typeof value
        where.push column + ' = ' + connector.escape value
    else if _.isObject value
        propClassName = propDef.className
        value = value.get pMgr.getIdName propClassName
        if typeof value isnt 'undefined'
            if value is null
                where.push column + ' IS NULL'
            else if PRIMITIVE_TYPES.test typeof value
                where.push column + ' = ' + connector.escape value

    return

class InsertQuery
    constructor: (pMgr, model, options = {})->
        assertValidModelInstance model

        @getModel = -> model
        @getManager = -> pMgr
        @getOptions = -> options
        @getDefinition = -> definition

        connector = options.connector
        if connector
            @escapeId = (str)->
                connector.escapeId str
        else
            @escapeId = (str)->
                str

        fields = {}
        @getFields = (column)->
            #  for mysql when lastInsertId is not available because there is no autoincrement
            fields
        @set = (column, value)->
            insert.set @escapeId(column), value
            fields[column] = value
        # @toParam = ->
        #     return insert.toParam()
        @toString = @oriToString = ->
            return insert.toString()

        className = options.className or model.className
        definition = pMgr._getDefinition className
        insert = squel.insert(pMgr.getSquelOptions(options.dialect)).into @escapeId(definition.table)

        # if not options.force and typeof model.get(definition.id.name) isnt 'undefined'
        #     err = new Error "[#{className}]: Model has already and id"
        #     err.code = 'ID_EXISTS'
        #     throw err

        # ids of mixins will be setted at execution
        if definition.mixins.length > 0
            @toString = ->
                return insert.toParam().text
            @toParam = ->
                params = insert.toParam()
                for mixin, index in definition.mixins
                    params.values[index] = new InsertQuery pMgr, model, _.extend {}, options, className: mixin.className
                return params

            for mixin in definition.mixins
                insert.set @escapeId(mixin.column), '$id'

        idName = pMgr.getIdName className
        id = model.get idName if idName isnt null
        insert.set @escapeId(definition.id.column), id if id

        for prop, propDef of definition.properties
            column = propDef.column

            if propDef.hasOwnProperty 'className'
                parentModel = model.get prop
                if typeof parentModel is 'undefined'
                    continue
                prop = pMgr._getDefinition propDef.className

                # # If column is not setted assume it has the same name as the column id
                # if typeof column is 'undefined'
                #     column = prop.id.column
                if parentModel is null or typeof parentModel is 'number'
                    # assume it is the id
                    value = parentModel
                else if typeof parentModel is 'string'
                    if parentModel.length is 0
                        value = null
                    else
                        # assume it is the id
                        value = parentModel
                else
                    value = parentModel.get prop.id.name

                # Throw if id of property class is not set
                if typeof value is 'undefined'
                    err = new Error "[#{className}] - [#{propDef.className}]: id is not defined. Save property value before saving model"
                    err.code = 'NO_ID'
                    throw err
            else
                value = model.get prop

            # Handlers
            handlers = propDef.handlers
            insertHandler = null
            writeHandler = null
            if typeof handlers isnt 'undefined'
                insertHandler = handlers.insert
                writeHandler = handlers.write

            # Insert handler
            if typeof value is 'undefined' and typeof insertHandler is 'function'
                value = insertHandler model, options, {column: column}

            # Only set defined values
            if typeof value is 'undefined'
                continue

            # Write handler
            if typeof writeHandler is 'function'
                value = writeHandler value, model, options

            # Only set defined values
            if typeof value is 'undefined'
                continue

            insert.set @escapeId(column), value

        # check
        @toString()

    execute: (connector, callback)->
        if @toString is @oriToString
            @_execute connector, callback
            return

        params = @toParam()
        idIndex = 0
        tasks = []
        for value, index in params.values
            if value instanceof InsertQuery
                tasks.push ((query)=>
                    (next)=>
                        query.execute connector, (err, id)=>
                            return next(err) if err
                            definition = @getDefinition()
                            column = definition.mixins[idIndex++].column
                            @set column, id
                            next()
                )(value)
            else
                break

        async.series tasks, (err)=>
            return callback(err) if err
            @_execute connector, callback
            return
        return

    _execute: (connector, callback)->
        pMgr = @getManager()
        query = @oriToString()
        definition = @getDefinition()
        model = @getModel()
        fields = @getFields()
        options = @getOptions()

        query = pMgr.decorateInsert options.dialect, query, definition.id.column
        connector.query query, (err, res)->
            return callback(err) if err

            if definition.id.hasOwnProperty 'column'
                # On sqlite, lastInsertId is only valid on autoincremented id's
                # Therefor, always take setted field when possible
                if fields[definition.id.column]
                    id = fields[definition.id.column]
                else if res.hasOwnProperty 'lastInsertId'
                    id = res.lastInsertId
                else
                    id = Array.isArray(res.rows) and res.rows.length > 0 and res.rows[0][definition.id.column]

            logger.trace '[' + definition.className + '] - INSERT ' + id

            if options.reflect
                if definition.id.hasOwnProperty 'column'
                    where = '{' + pMgr.getIdName(definition.className) + '} = ' + id
                options = _.extend {}, options,
                    where: where
                pMgr.initialize model, options, (err, models)->
                    callback err, id
            else
                callback err, id

            return
        , options.executeOptions

        return

# _fnIds = {}

# _serialize = (cacheId, key, value)->
#     if 'function' is typeof value
#         # TOFIX: if mutilple functions have the same string, we are screwed
#         str = value.toString()
#         _fnIds[cacheId] or (_fnIds[cacheId] = {})
#         _fnIds[cacheId][str] = value
#         return str

#     value

# _desirialize = (cacheId, key, value)->
#     if value and typeof value is 'string' and /function\b/.test value.substr(0, 9)
#         return _fnIds[cacheId][value]
#     value

_getCacheId = (options)->
    json = {}
    for opt in ['dialect', 'type', 'count', 'attributes', 'fields', 'join', 'where', 'group', 'having', 'order', 'limit', 'offset']
        if options.hasOwnProperty opt
            if Array.isArray options[opt]
                json[opt] = []
                for val in options[opt]
                    if Array.isArray val
                        arr = []
                        json[opt].push arr
                        for item in val
                            arr.push JSON.stringify item
                    else
                        json[opt].push JSON.stringify val
            else
                json[opt] = JSON.stringify options[opt]
    
    JSON.stringify json

PersistenceManager::addCachedRowMap = (cacheId, className, rowMap)->
    # keeping references of complex object makes the hole process slow
    # don't know why
    logger.trace 'add cache', className, cacheId
    # serialize = (key, value)->
    #     _serialize cacheId, key, value
    json = _.pick rowMap, ['_infos', '_tableAliases', '_tabId', '_columnAliases', '_colId', '_tables', '_mixins', '_joining']
    cache = @classes[className].cache[cacheId] =
        rowMap: JSON.stringify json
        template: rowMap.getTemplate()
        select: JSON.stringify rowMap.select

PersistenceManager::getCachedRowMap = (cacheId, className, options)->
    cache = @classes[className].cache[cacheId]
    return if not cache
    logger.trace 'read cache', className, cacheId
    rowMap = new RowMap className, @, options, true
    select = new squel.select.constructor()
    # desirialize = (key, value)->
    #     _desirialize cacheId, key, value
    _.extend select, JSON.parse cache.select
    _.extend rowMap, JSON.parse cache.rowMap
    rowMap.template = cache.template
    rowMap.select = select
    rowMap.values = options.values
    rowMap._initialize()
    rowMap._processColumns()
    rowMap._selectCount() if options.count
    rowMap._updateInfos()
    rowMap

PersistenceManager.SelectQuery = PersistenceManager::SelectQuery = class SelectQuery
    constructor: (pMgr, className, options)->
        if arguments.length is 1
            if arguments[0] instanceof RowMap
                @rowMap = arguments[0]
                return @
            else
                throw new Error 'Given parameter do not resolve to a RowMap'

        useCache = options.cache isnt false
        cacheId = _getCacheId options if useCache

        if not useCache or not rowMap = pMgr.getCachedRowMap cacheId, className, options
            select = squel.select pMgr.getSquelOptions options.dialect
            rowMap = new RowMap className, pMgr, _.extend {}, options, select: select

            # check
            select.toParam()
            select.toString()
            if useCache
                @cacheId = cacheId
                pMgr.addCachedRowMap cacheId, className, rowMap

        @rowMap = rowMap
        return @
    toString: ->
        @rowMap.toString()

    stream: (streamConnector, listConnector, callback, done)->
        (callback = ->) if 'function' isnt typeof callback
        (done = ->) if 'function' isnt typeof done

        rowMap = @rowMap
        query = rowMap.toString()
        pMgr = rowMap.manager
        options = rowMap.options

        models= options.models or []
        doneSem = semLib.semCreate()
        doneSem.semGive()
        timeout = 60 * 1000
        hasError = false

        ret = (err, fields)->
            doneSem.semTake
                timeout: timeout
                onTake: ->
                    if hasError
                        if _.isObject err
                            err.subError = hasError
                        else
                            err = hasError
                    done err, fields
                    return
            return

        streamConnector.stream query, (row, stream)->
            tasks = []
            model = rowMap.initModel row, null, tasks
            if tasks.length > 0
                if listConnector is streamConnector or
                (listConnector.getPool() is streamConnector.getPool() and listConnector.getMaxConnection() < 2)
                    # preventing dead block
                    err = new Error 'List connector and stream connector are the same. To retrieve nested data, listConnector must be different from streamConnector and if used pools are the same, they must admit more than 1 connection'
                    err.code = 'STREAM_CONNECTION'
                    stream.emit 'error', err
                    return

                stream.pause()
                doneSem.semTake
                    priority: 1
                    timeout: timeout
                
                async.eachSeries tasks, (task, next)->
                    pMgr.list task.className , _.extend({connector: listConnector, dialect: options.dialect}, task.options), (err, models)->
                        return next(err) if err
                        if models.length isnt 1
                            msg = 'Expecting one result. Given ' + models.length + '.'
                            if models.length is 0
                                msg += '\n    You are most likely querying uncomitted data. listConnector has it\'s own transaction. Therefore, only committed changes will be seen.'

                            msg += '\n    Checks those cases: database error, library bug, something else.'

                            err = new Error msg
                            err.code = 'UNKNOWN'
                            return next err
                        next()
                        return
                    return
                , (err)->
                    doneSem.semGive()
                    stream.resume()
                    if err
                        hasError = err
                        stream.emit 'error', err
                    else
                        callback model, stream
                    return

                return

            callback model, stream
            return
        , ret, options.executeOptions

    toQueryString: ->
        @toString()

    list: (connector, callback)->
        (callback = ->) if 'function' isnt typeof callback

        rowMap = @rowMap
        query = rowMap.toString()
        pMgr = rowMap.manager
        options = rowMap.options

        connector.query query, (err, res)->
            return callback(err) if err
            rows = res.rows
            return callback(err, rows) if rows.length is 0
            ret = []
            if Array.isArray options.models
                models = options.models
                if models.length isnt rows.length
                    err = new Error 'Returned rows and given number of models doesn\'t match'
                    err.extend = [models.length, rows.length]
                    err.code = 'OPT_MODELS'
                    return callback err
            else
                models= []
            tasks = []

            for row, index in rows
                model = rowMap.initModel row, models[index], tasks
                ret.push model

            if tasks.length > 0
                async.eachSeries tasks, (task, next)->
                    pMgr.list task.className , _.extend({connector: options.connector, dialect: options.dialect}, task.options), (err, models)->
                        return next(err) if err
                        if models.length isnt 1
                            err = new Error 'database is corrupted or there is bug'
                            err.code = 'UNKNOWN'
                            return next err
                        next()
                        return
                    return
                , (err)->
                    return callback(err) if err
                    callback null, ret
                    return
                return

            if options.count
                callback null, ret[0].count
            else
                callback null, ret

            return
        , options, options.executeOptions
        @

_addUpdateOrDeleteCondition = (action, name, connector, pMgr, model, className, definition, options)->
    idName = pMgr.getIdName className
    idName = null if typeof idName isnt 'string' or idName.length is 0
    if definition.constraints.unique.length is 0 and idName is null
        err = new Error "Cannot #{name} #{className} models because id has not been defined"
        err.code = name.toUpperCase()
        throw err

    id = model.get idName if idName isnt null
    hasNoCondition = hasNoId = id is null or 'undefined' is typeof id
    if hasNoId
        options = _.extend {}, options, {useDefinitionColumn: true}
        where = _getInitializeCondition pMgr, model, className, definition, options
        result = options.result
        hasNoCondition = where.length is 0
        for condition in where
            action.where condition
    else
        action.where connector.escapeId(definition.id.column) + ' = ' + connector.escape id
    
    if hasNoCondition
        err = new Error "Cannot #{name} #{className} model because id is null or undefined"
        err.code = name.toUpperCase()
        throw err
    return result

class UpdateQuery
    constructor: (pMgr, model, options = {})->
        assertValidModelInstance model

        @getModel = -> model
        @getManager = -> pMgr
        @getOptions = -> options

        # @toParam = -> update.toParam()
        @toString = @oriToString = -> update.toString()
        # @getClassName = -> className
        @getDefinition = -> definition
        @setChangeCondition = ->
            update.where changeCondition
            @

        connector = options.connector
        if connector
            @escapeId = (str)->
                connector.escapeId str
        else
            @escapeId = (str)->
                str

        className = options.className or model.className
        definition = pMgr._getDefinition className
        update = squel.update(pMgr.getSquelOptions(options.dialect)).table @escapeId(definition.table)

        result = _addUpdateOrDeleteCondition update, 'update', connector, pMgr, model, className, definition, options

        # condition to track changes
        changeCondition = squel.expr()
        @lockCondition = lockCondition = squel.expr()

        # update owned properties
        for prop, propDef of definition.properties
            if result
                # contraint used as discriminator must not be update
                # causes an error on postgres
                constraint = definition.constraints.unique[result.constraint]
                if -1 isnt constraint.indexOf prop
                    continue

            if propDef.hasOwnProperty('className') and typeof (parentModel = model.get prop) isnt 'undefined'
                # Class property
                if parentModel is null or typeof parentModel is 'number'
                    # assume it is the id
                    value = parentModel
                else if typeof parentModel is 'string'
                    if parentModel.length is 0
                        value = null
                    else
                        # assume it is the id
                        value = parentModel
                else
                    value = parentModel.get pMgr._getDefinition(propDef.className).id.name
            else
                value = model.get prop

            column = propDef.column

            # Handlers
            handlers = propDef.handlers
            if _.isObject(options.overrides) and _.isObject(options.overrides[prop])
                if _.isObject(options.overrides[prop].handlers)
                    handlers = _.extend {}, handlers, options.overrides[prop].handlers
                dontQuote = options.overrides[prop].dontQuote
                dontLock = options.overrides[prop].dontLock

            writeHandler = undefined
            updateHandler = undefined

            if typeof handlers isnt 'undefined'
                # Write handler
                if typeof handlers.write is 'function'
                    writeHandler = handlers.write

                # Update handler
                if typeof handlers.update is 'function'
                    updateHandler = handlers.update

            if not dontLock and propDef.lock
                lock = value
                if typeof writeHandler is 'function'
                    lock = writeHandler lock, model, options
                    lockCondition.and connector.exprEqual lock, connector.escapeId column

            if typeof updateHandler is 'function'
                value = updateHandler model, options, {column: column}

            # Only set defined values
            if typeof value is 'undefined'
                continue

            # Value handler
            if typeof writeHandler is 'function'
                value = writeHandler value, model, options

            # Only set defined values
            if typeof value is 'undefined'
                continue

            update.set @escapeId(column), value, {dontQuote: !!dontQuote}
            @hasData = true
            
            if not dontLock and not propDef.lock
                changeCondition.or connector.exprNotEqual value, connector.escapeId column

        update.where lockCondition
        
        # update mixin properties
        if definition.mixins.length is 0
            @setChangeCondition()
        else
            if @hasData
                @toString = -> update.toString()
            else
                @toString = -> ''

            @toParam = ->
                if @hasData
                    params = update.toParam()
                else
                    params = values: []

                for mixin, index in definition.mixins
                    params.values.push new UpdateQuery pMgr, model,
                        className: mixin.className
                        dialect: options.dialect
                        connector: connector
                return params

        # check
        # for block in update.blocks
        #     if block instanceof squel.cls.SetFieldBlock
        #         if block.fields.length is 0
        #             hasNoUpdate = true
        #         break
        
        @toString() if @hasData

    execute: (connector, callback)->
        if @toString is @oriToString
            return @_execute connector, callback

        params = @toParam()
        idIndex = 0
        tasks = []
        for index in [(params.values.length - 1)..0] by -1
            value = params.values[index]
            if value instanceof UpdateQuery and value.hasData
                ((query, connector)->
                    tasks.push (next)->
                        query.execute connector, next
                        return
                    return
                )(value, connector)
            else
                break

        hasUpdate = false
        definition = @getDefinition()
        async.series tasks, (err, results)=>
            return callback(err) if err

            # Check if parent mixin has been updated
            if Array.isArray(results) and results.length > 0
                for result in results
                    if Array.isArray(result) and result.length > 0
                        id = result[0]
                        extended = result[1]
                        if not extended
                            logger.trace '[' + definition.className + '] - UPDATE: has update ' + id
                            hasUpdate = true
                            break
                if Array.isArray results[results.length - 1]
                    id = results[results.length - 1][0]

            if not @hasData
                callback err, id, not hasUpdate
                return

            # If parent mixin has been update, child must be considered as being updated
            if not hasUpdate
                logger.trace '[' + definition.className + '] - UPDATE: has no update ' + id
                @setChangeCondition()

            @_execute connector, (err, id, extended)->
                hasUpdate = not extended
                callback err, id, extended
                return
            return
        return

    _execute: (connector, callback)->
        pMgr = @getManager()
        query = @oriToString()
        definition = @getDefinition()
        model = @getModel()
        options = @getOptions()

        query = pMgr.decorateInsert options.dialect, query, definition.id.column
        connector.query query, (err, res)->
            return callback(err) if err

            if res.hasOwnProperty 'affectedRows'
                hasNoUpdate = res.affectedRows is 0
            else if definition.id.hasOwnProperty('column') and res.rows
                hasNoUpdate = res.rows.length is 0
            else if res.hasOwnProperty 'rowCount'
                hasNoUpdate = res.rowCount is 0

            id = model.get definition.id.name

            if 'undefined' is typeof id
                try
                    where = _getInitializeCondition pMgr, model, definition.className, definition, _.extend {}, options, useDefinitionColumn: false
                catch err
                    callback err
                    return
            else if definition.id.hasOwnProperty 'column'
                where = '{' + pMgr.getIdName(definition.className) + '} = ' + id

            options = _.extend {}, options, where: where

            pMgr.initialize model, options, (err, models)->
                return callback err if err
                id = model.get definition.id.name

                if hasNoUpdate 
                    if models.length is 0
                        err = new Error 'id or lock condition'
                        err.code = 'NO_UPDATE'
                        logger.trace '[' + definition.className + '] - NO UPDATE ' + id
                    else
                        extended = 'no-update'
                else
                    logger.trace '[' + definition.className + '] - UPDATE ' + id
                callback err, id, extended
                return
            return
        , options.executeOptions
        return

class DeleteQuery
    constructor: (pMgr, model, options = {})->
        assertValidModelInstance model

        @toParam = ->
            remove.toParam()
        @toString = @oriToString = ->
            remove.toString()
        @getOptions = ->
            options

        connector = options.connector
        className = options.className or model.className
        definition = pMgr._getDefinition className
        remove = squel.delete(pMgr.getSquelOptions(options.dialect)).from connector.escapeId definition.table

        _addUpdateOrDeleteCondition remove, 'delete', connector, pMgr, model, className, definition, options

        # optimistic lock
        for prop, propDef of definition.properties

            if propDef.hasOwnProperty 'className'
                # cascade delete is not yet defined
                continue

            if propDef.lock
                column = propDef.column
                value = model.get prop

                # Handlers
                handlers = propDef.handlers
                writeHandler = null
                if typeof handlers isnt 'undefined'
                    writeHandler = handlers.write

                # Write handler
                if typeof writeHandler is 'function'
                    value = writeHandler value, model, options
                remove.where connector.escapeId(column) + ' = ' + connector.escape value

        # delete mixins lines
        if definition.mixins.length > 0
            @toString = ->
                remove.toString()

            @toParam = ->
                params = remove.toParam()
                for mixin, index in definition.mixins
                    params.values.push new DeleteQuery pMgr, model,
                        className: mixin.className
                        dialect: options.dialect
                        connector: connector
                return params

        # check
        @toString()

    execute: (connector, callback)->
        next = (err, res)->
            return callback(err) if err

            if not res.affectedRows and res.hasOwnProperty 'rowCount'
                res.affectedRows = res.rowCount

            callback err, res
            return

        if @toString is @oriToString
            return @_execute connector, next

        params = @toParam()
        idIndex = 0
        tasks = []
        for index in [(params.values.length - 1)..0] by -1
            value = params.values[index]
            if value instanceof DeleteQuery
                ((query)->
                    tasks.push (next)->
                        query.execute connector, next
                        return
                    return
                )(value)
            else
                break

        @_execute connector, (err, res)->
            return next(err) if err
            async.series tasks, (err, results)->
                return next(err) if err
                for result in results
                    return next(new Error 'sub class has not been deleted') if result.affectedRows is 0
                next err, res
                return
            return

        return

    _execute: (connector, callback)->
        query = @oriToString()
        connector.query query, callback, @getOptions().executeOptions
        return

# error codes abstraction
# check: database and mapping are compatible
# collection
# stream with inherited =>
#   2 connections?
# stream with collections?
#   two connections?
# decision: manually set joins, stream only do one request, charge to you to recompute records
