log4js = global.log4js or (global.log4js = require 'log4js')
logger = log4js.getLogger 'PersistenceManager'

GenericUtil = require './GenericUtil'
_ = require 'lodash'
squel = require './SquelPatch'
RowMap = require './RowMap'
async = require 'async'
semLib = require 'sem-lib'

module.exports = class PersistenceManager
    constructor: (mapping)->
        sanitized = _resolve mapping
        @getId = (className)->
            _assertClassHasMapping sanitized, className
            sanitized.classes[className].id.name
        @getDefinition = (className)->
            _assertClassHasMapping sanitized, className
            _.cloneDeep sanitized.classes[className]
        @getMapping = ->
            _.cloneDeep sanitized.classes
        @getColumn = (className, prop)->
            _assertClassHasMapping sanitized, className
            definition = sanitized.classes[className]
            if definition.id.name is prop
                definition.id.column
            else if definition.properties.hasOwnProperty prop
                definition.properties[prop].column

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
        decorateInsert: (query, column)->
            query

PersistenceManager::getSquelOptions = (dialect)->
    if @dialects.hasOwnProperty dialect
        _.clone @dialects[dialect].squelOptions

PersistenceManager::decorateInsert = (dialect, query, column)->
    if @dialects.hasOwnProperty dialect
        @dialects[dialect].decorateInsert query, column
    else
        query

PersistenceManager::insert = (model, options, callback)->
    connector = options.connector
    try
        query = @getInsertQuery model, _.extend {dialect: connector.getDialect()}, options, {autoRollback: false}
    catch err
        return callback err
    
    connector.acquire (err)->
        return callback(err) if err
        connector.begin (err)->
            return callback(err) if err
            query.execute connector, (err)->
                if err
                    method = 'rollback'
                else
                    method = 'commit'

                args = Array::slice.call arguments, 0
                connector[method] (err)->
                    if err
                        if GenericUtil.isObject args[0]
                            args[0].subError = err
                        else
                            args[0] = err
                    connector.release (err)->
                        callback.apply null, args

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
    new SelectQuery @, className, options

PersistenceManager::update = (model, options, callback)->
    connector = options.connector
    try
        query = @getUpdateQuery model, _.extend {dialect: connector.getDialect()}, options, {autoRollback: false}
    catch err
        return callback err
    connector.acquire (err)->
        return callback(err) if err
        connector.begin (err)->
            return callback(err) if err
            query.execute connector, (err)->
                if err
                    method = 'rollback'
                else
                    method = 'commit'

                args = Array::slice.call arguments, 0
                connector[method] (err)->
                    if err
                        if GenericUtil.isObject(err)
                            args[0].subError = err
                        else
                            args[0] = err
                    connector.release (err)->
                        callback.apply null, args

PersistenceManager::getUpdateQuery = (model, options)->
    new UpdateQuery @, model, options

PersistenceManager::delete = (model, options, callback)->
    connector = options.connector
    try
        query = @getDeleteQuery model, _.extend {dialect: connector.getDialect()}, options, {autoRollback: false}
    catch err
        return callback err
    query.execute connector, callback

PersistenceManager::getDeleteQuery = (model, options)->
    new DeleteQuery @, model, options

PersistenceManager::save = (model, options, callback)->
    className = options.className or model.className
    id = model.get @getId className

    if typeof id is 'undefined'
        @insert model, _.extend({}, options, reflect: true), callback
    else
        @update model, options, callback

PersistenceManager::initialize = (model, options, callback)->
    className = options.className or model.className
    definition = @getDefinition className
    connector = options.connector
    if not GenericUtil.isObject model
        return next 'No model'

    if typeof options.where is 'undefined'
        attributes = options.attributes or model.toJSON()
        where = []
        try
            if _.isPlainObject attributes
                for attr, value of attributes
                    _addWhereCondition @, model, attr, value, definition, connector, where
            else if attributes instanceof Array
                for attr in attributes
                    value = model.get attr
                    _addWhereCondition @, model, attr, value, definition, connector, where
        catch err
            return callback err
    else
        where = options.where

    options = _.extend {}, options,
        where: where
        models: [model]
    @list className, options, callback

_addWhereCondition = (pMgr, model, attr, value, definition, connector, where = [])->
    if typeof value is 'undefined' or not definition.available.properties.hasOwnProperty attr
        return

    propDef = definition.available.properties[attr].definition
    if _.isPlainObject(propDef.handlers) and typeof propDef.handlers.write is 'function'
        value = propDef.handlers.write value, model, options
    if  /^(?:string|boolean|number)$/.test typeof value
        where.push '{' + attr + '} = ' + connector.escape value
    else if GenericUtil.isObject value
        propClassName = definition.available.properties[attr].definition.className
        value = value.get pMgr.getId propClassName
        if _.isPlainObject(propDef.handlers) and typeof propDef.handlers.write is 'function'
            value = propDef.handlers.write value, model, options
        if typeof value isnt 'undefined'
            if value is null
                where.push '{' + attr + '} IS NULL'
            else if /^(?:string|boolean|number)$/.test typeof value
                where.push '{' + attr + '} = ' + connector.escape value

class SanitizedMapping
    constructor: ->
        _.extend @,
            classes: {}
            resolved: {}
            unresolved: {}
            tables: {}

    startResolving: (className)->
        @unresolved[className] = true
        @classes[className] =
            className: className
            available:
                properties: {}
                mixins: {}
            columns: {}
            dependencies:
                resolved: {}
                normalized: []

        return @classes[className]

    markResolved: (className)->
        delete @unresolved[className]
        @resolved[className] = true

    hasResolved: (className)->
        @resolved.hasOwnProperty className

    isResolving: (className)->
        @unresolved.hasOwnProperty className

    hasTable: (table)->
        @tables.hasOwnProperty table

    hasColumn: (className, column)->
        definition = @classes[className]
        definition.columns.hasOwnProperty column

    getDepResolved: (className)->
        definition = @classes[className]
        definition.dependencies.resolved

    setDepResolved: (className, dependency)->
        definition = @classes[className]
        definition.dependencies.resolved[dependency] = true

    hasDepResolved: (className, dependency)->
        definition = @classes[className]
        definition.dependencies.resolved[dependency]

    addTable: (className)->
        definition = @classes[className]
        if @hasTable definition.table
            err = new Error "[#{definition.className}] table '#{definition.table}' already exists"
            err.code = 'DUP_TABLE'
            throw err
        @tables[definition.table] = true

    addColumn: (className, column, prop)->
        definition = @classes[className]
        if @hasColumn className, column
            err = new Error "[#{definition.className}] column '#{column}' already exists"
            err.code = 'DUP_COLUMN'
            throw err

        if GenericUtil.notEmptyString column
            definition.columns[column] = prop
        else
            err = new Error "[#{definition.className}] column must be a not empty string"
            err.code = 'COLUMN'
            throw err

    addNormalize: (className, mixin)->
        definition = @classes[className]
        normalized = definition.dependencies.normalized
        dependency = mixin.className
        parents = []
        for index in [(normalized.length - 1)..0] by -1
            dep = normalized[index]
            if dep.className is dependency
                # if dependency already exists
                return
            
            if @hasDepResolved dep.className, dependency
                # if dependency is a parent of another normalized dependency, ignore it
                return
            
            if @hasDepResolved dependency, dep.className
                # if dependency is a child of another normalized dependency, mark it
                parents.push dep.className

        obj = className: dependency
        if GenericUtil.notEmptyString mixin.column
            obj.column = mixin.column
        else
            obj.column = @classes[dependency].id.column

        normalized.push obj
        return parents

class InsertQuery
    constructor: (pMgr, model, options = {})->
        @getModel = ->
            model
        @getManager = ->
            pMgr
        @getOptions = ->
            options
        @getDefinition = ->
            definition

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
        @toParam = ->
            return insert.toParam()
        @toString = @oriToString = ->
            return insert.toString()

        className = options.className or model.className
        definition = pMgr.getDefinition className
        insert = squel.insert(pMgr.getSquelOptions(options.dialect)).into @escapeId(definition.table)

        if not options.force and typeof model.get(definition.id.name) isnt 'undefined'
            err = new Error "[#{className}]: Model has already and id"
            err.code = 'ID_EXISTS'
            throw err

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

        for prop, propDef of definition.properties
            column = propDef.column

            if propDef.hasOwnProperty 'className'
                parentModel = model.get prop
                if typeof parentModel is 'undefined'
                    continue
                prop = pMgr.getDefinition propDef.className

                # If column is not setted assume it has the same name as the column id
                if typeof column is 'undefined'
                    column = prop.id.column
                if parentModel is null or typeof parentModel is 'number'
                    # assume it is the id
                    value = parentModel
                else if typeof parentModel is 'string'
                    if parentModel.length is 0
                        value = null
                    else
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
                value = insertHandler options

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
        return

    execute: (connector, callback)->
        if @toString is @oriToString
            return @_execute connector, callback

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
                if res.hasOwnProperty 'lastInsertId'
                    id = res.lastInsertId or fields[definition.id.column]
                else
                    id = res.rows[0][definition.id.column]

            logger.trace '[' + definition.className + '] - INSERT ' + id

            if options.reflect
                if definition.id.hasOwnProperty 'column'
                    where = '{' + pMgr.getId(definition.className) + '} = ' + id
                options = _.extend {}, options,
                    where: where
                pMgr.initialize model, options, (err, models)->
                    callback err, id
            else
                callback err, id
        , options.executeOptions

class SelectQuery
    constructor: (pMgr, className, options = {})->
        @getOptions = ->
            options
        @getClassName = ->
            className
        @toString = ->
            select.toString()
        @getRowMap = ->
            rowMap
        @getManager = ->
            pMgr

        select = squel.select pMgr.getSquelOptions options.dialect
        rowMap = new RowMap className, pMgr, _.extend {}, options, select: select

        # check
        query = @toString()
        return

    stream: (streamConnector, listConnector, callback, done)->
        rowMap = @getRowMap()
        query = rowMap.parse @toString()
        # query = @toString()
        pMgr = @getManager()
        options= @getOptions()
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
                        if GenericUtil.isObject err
                            err.subError = hasError
                        else
                            err = hasError
                    done err, fields

        streamConnector.stream query, (row, stream)=>
            tasks = []
            model = rowMap.initModel row, null, tasks
            if tasks.length > 0
                if listConnector is streamConnector or
                (listConnector.getInnerPool() is streamConnector.getInnerPool() and listConnector.getMaxConnection() < 2)
                    err = new Error 'To retrieve nested data, listConnector must be different from streamConnector and used pool if they are the same, must admit more than 1 connection'
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
                                msg += ' You are most likely querying uncomitted data. listConnector has it\'s own transaction. Therefore only committed changes will be seen.'

                            msg = ' Checks those cases: database error, library bug, something else.'

                            err = new Error msg
                            err.code = 'UNKNOWN'
                            return next err
                        next()
                , (err)->
                    doneSem.semGive()
                    stream.resume()
                    if err
                        hasError = err
                        stream.emit 'error', err
                    else
                        callback model, stream
                return

            callback model, stream
        , ret, options.executeOptions

    list: (connector, callback)->
        rowMap = @getRowMap()
        query = rowMap.parse @toString()
        # query = @toString()
        pMgr = @getManager()
        options= @getOptions()

        connector.query query, (err, res)->
            return callback(err) if err
            rows = res.rows
            return callback(err, rows) if rows.length is 0
            ret = []
            if options.models instanceof Array
                models = options.models
                if models.length isnt rows.length
                    err = new Error 'Returned rows and given number of models doesn\'t match'
                    err.extend = [models.length, rows.length]
                    err.code = 'UNKNOWN'
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
                        # task.done()
                        next()
                , (err)->
                    return callback(err) if err
                    callback null, ret
                return

            callback null, ret
        , options, options.executeOptions
        query

class UpdateQuery
    constructor: (pMgr, model, options = {})->
        @getModel = ->
            model
        @getManager = ->
            pMgr
        @getOptions = ->
            options

        @toParam = ->
            update.toParam()
        @toString = @oriToString = ->
            update.toString()
        @getClassName = ->
            className
        @getDefinition = ->
            definition

        connector = options.connector
        if connector
            @escapeId = (str)->
                connector.escapeId str
        else
            @escapeId = (str)->
                str

        className = options.className or model.className
        definition = pMgr.getDefinition className
        update = squel.update(pMgr.getSquelOptions(options.dialect)).table @escapeId(definition.table)
        update.where connector.escapeId(definition.id.column) + ' = ' + connector.escape model.get pMgr.getId className

        # update mixin properties
        if definition.mixins.length > 0
            @toString = ->
                update.toString()

            @toParam = ->
                params = update.toParam()
                for mixin, index in definition.mixins
                    params.values.push new UpdateQuery pMgr, model,
                        className: mixin.className
                        dialect: options.dialect
                        connector: connector
                return params

        # condition to track changes
        changeCondition = squel.expr()
        @lockCondition = lockCondition = squel.expr()

        # update owned properties
        for prop, propDef of definition.properties

            if propDef.hasOwnProperty('className') and typeof (parentModel = model.get prop) isnt 'undefined'
                if parentModel is null or typeof parentModel is 'number'
                    # assume it is the id
                    value = parentModel
                else if typeof parentModel is 'string'
                    if parentModel.length is 0
                        value = null
                    else
                        value = parentModel
                else
                    prop = pMgr.getDefinition propDef.className
                    value = parentModel.get prop.id.name
            else
                value = model.get prop

            column = propDef.column

            # Handlers
            handlers = propDef.handlers
            writeHandler = undefined
            updateHandler = undefined

            if typeof handlers isnt 'undefined'
                # Write handler
                if typeof handlers.write is 'function'
                    writeHandler = handlers.write

                # Update handler
                if typeof handlers.update is 'function'
                    updateHandler = handlers.update

            if propDef.lock
                lock = value
                if typeof writeHandler is 'function'
                    lock = writeHandler lock, options
                    lockCondition.and connector.exprEqual lock, connector.escapeId(column), connector

            if typeof updateHandler is 'function'
                value = updateHandler options

            # Only set defined values
            if typeof value is 'undefined'
                continue

            # Value handler
            if typeof writeHandler is 'function'
                value = writeHandler value, model, options

            # Only set defined values
            if typeof value is 'undefined'
                continue

            update.set @escapeId(column), value
            
            if not propDef.lock
                changeCondition.or connector.exprNotEqual value, connector.escapeId column

        update.where lockCondition
        update.where changeCondition
        
        # check
        query = @toString()
        return

    execute: (connector, callback)->
        if @toString is @oriToString
            return @_execute connector, callback

        params = @toParam()
        idIndex = 0
        tasks = []
        for index in [(params.values.length - 1)..0] by -1
            value = params.values[index]
            if value instanceof UpdateQuery
                tasks.push ((query)->
                    (next)->
                        query.execute connector, next
                )(value)
            else
                break

        hasUpdate = false
        async.series tasks, (err, args)=>
            if args instanceof Array and args.length > 0
                args = args[args.length - 1]
                if args instanceof Array and args.length > 0
                    id = args[0]
                    extended = args[1]
                    hasUpdate = true if not extended
            return callback(err) if err
            @_execute connector, (err, id, extended)->
                hasUpdate = true if not extended
                callback err, id, not hasUpdate and extended

    _execute: (connector, callback)->
        pMgr = @getManager()
        query = @oriToString()
        definition = @getDefinition()
        model = @getModel()
        options = @getOptions()
        # where = [@lockCondition]
        where = []

        query = pMgr.decorateInsert options.dialect, query, definition.id.column
        connector.query query, (err, res)->
            return callback(err) if err
            id = model.get definition.id.name

            if definition.id.hasOwnProperty 'column'
                if res.hasOwnProperty 'affectedRows'
                    # assume it's mysql connector
                    if res.affectedRows is 0
                        _exit = true
                else if res.rows 
                    if res.rows.length is 0
                        _exit = true
                if _exit
                    # Nothing has been updated
                    hasNoUpdate = true

            logger.trace '[' + definition.className + '] - UPDATE ' + id

            if definition.id.hasOwnProperty 'column'
                where[where.length] = '{' + pMgr.getId(definition.className) + '} = ' + id
            options = _.extend {}, options,
                where: where
            pMgr.initialize model, options, (err, models)->
                return callback err if err
                if hasNoUpdate 
                    if models.length is 0
                        err = new Error 'id or lock condition'
                        err.code = 'NO_UPDATE'
                    else
                        extended = 'no-update'
                callback err, id, extended
        , options.executeOptions
        return

class DeleteQuery
    constructor: (pMgr, model, options = {})->
        @toParam = ->
            remove.toParam()
        @toString = @oriToString = ->
            remove.toString()
        @getOptions = ->
            options

        connector = options.connector
        className = options.className or model.className
        definition = pMgr.getDefinition className
        remove = squel.delete(pMgr.getSquelOptions(options.dialect)).from connector.escapeId definition.table
        remove.where connector.escapeId(definition.id.column) + ' = ' + connector.escape model.get pMgr.getId className

        # optimistic lock
        for prop, propDef of definition.properties

            if propDef.hasOwnProperty 'className'
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
        query = @toString()
        return
    execute: (connector, callback)->
        if @toString is @oriToString
            return @_execute connector, callback

        params = @toParam()
        idIndex = 0
        tasks = []
        for index in [(params.values.length - 1)..0] by -1
            value = params.values[index]
            if value instanceof DeleteQuery
                tasks.push ((query)->
                    (next)->
                        query.execute connector, (err, id)->
                            next err
                )(value)
            else
                break

        @_execute connector, (err)->
            return callback(err) if err
            async.series tasks, callback

        return

    _execute: (connector, callback)->
        query = @oriToString()
        connector.query query, callback, @getOptions().executeOptions
        return

_assertClassHasMapping = (sanitized, className)->
    if not sanitized.classes.hasOwnProperty className
        err = new Error "No mapping were found for class '#{className}'"
        err.code = 'UNDEF_CLASS'
        throw err

_resolve = (mapping)->
    sanitized = new SanitizedMapping()

    for className of mapping
        _depResolve className, mapping, sanitized

    for className, map of sanitized.classes
        for prop, value of map.properties
            if value.hasOwnProperty('className') and not value.hasOwnProperty 'column'
                _assertClassHasMapping sanitized, value.className
                map = sanitized.classes[value.className]
                value.column = map.id.column
            sanitized.addColumn className, value.column, prop

    sanitized.resolved = true
    return sanitized

_depResolve = (className, mapping, sanitized)->
    if typeof className isnt 'string' or className.length is 0
        err = new Error 'class is undefined'
        err.code = 'UNDEF_CLASS'
        throw err

    return if sanitized.hasResolved className
    
    definition = mapping[className]
    if not _.isPlainObject definition
        err = new Error "Class '#{className}'' is undefined"
        err.code = 'UNDEF_CLASS'
        throw err

    # className if computed be reading given definition and peeking relevant properties of given definition
    # Peeking and not copying properties allows to have only what is needed and modify our definition without
    # altering (corrupting) given properties

    # Mark this className as being resolved, for circular reference check
    sanDef = sanitized.startResolving className
    
    if not definition.hasOwnProperty 'table'
        # default table name is className
        sanDef.table = className
    else if GenericUtil.notEmptyString definition.table
        sanDef.table = definition.table
    else
        err = new Error "[#{sanDef.className}] table is not a string"
        err.code = 'TABLE'
        throw err

    # check duplicate table
    sanitized.addTable sanDef.className

    # All class definition must have an id column for performant read, join, update
    # update: Collection are nn-tables that may not have id's
    # if not definition.hasOwnProperty 'id'
    #     err = new Error "[#{sanDef.className}] id property must be defined"
    #     err.code = 'NO_ID'
    #     throw err

    if typeof definition.id is 'string'
        sanDef.id =
            name: definition.id
            column: definition.id
    else if typeof definition.id isnt 'undefined' and not _.isPlainObject definition.id
        err = new Error "[#{sanDef.className}] id property must be a not null object"
        err.code = 'ID'
        throw err

    hasId = true
    if sanDef.hasOwnProperty 'id'
        id = sanDef.id
    else if definition.hasOwnProperty 'id'
        id = definition.id
    else
        hasId = false
        id = {}

    if not _.isPlainObject id
        err = new Error "[#{sanDef.className}] name xor className must be defined as a not empty string for id"
        err.code = 'ID'
        throw err

    sanDef.id = {}
    if GenericUtil.notEmptyString id.column
        sanDef.id.column = id.column

    if id.hasOwnProperty('name') and id.hasOwnProperty('className')
        err = new Error "[#{sanDef.className}] name and className are incompatible properties for id"
        err.code = 'INCOMP_ID'
        throw err

    if GenericUtil.notEmptyString id.name
        sanDef.id.name = id.name
        if not id.hasOwnProperty 'column'
            # default id column is id name
            sanDef.id.column = id.name
        else if not GenericUtil.notEmptyString id.column
            err = new Error "[#{sanDef.className}] column must be a not empty string for id"
            err.code = 'ID_COLUMN'
            throw err

        sanitized.addColumn className, sanDef.id.column, sanDef.id.name
        
    else if GenericUtil.notEmptyString id.className
        sanDef.id.className = id.className
    else if hasId
        err = new Error "[#{sanDef.className}] name xor className must be defined as a not empty string for id"
        err.code = 'ID'
        throw err

    _addProperty = (prop, value)->
        if typeof value is 'string'
            value = column: value

        if not _.isPlainObject value
            err = new Error "[#{sanDef.className}] property '#{prop}' must be an object"
            err.code = 'PROP'
            throw err

        sanDef.properties[prop] = {}
        if GenericUtil.notEmptyString value.column
            sanDef.properties[prop].column = value.column

        # add this property as available properties for this className
        # Purposes:
        #   - Fastly get property definition
        sanDef.available.properties[prop] =
            definition: sanDef.properties[prop]

        # composite element definition
        if value.hasOwnProperty 'className'
            sanDef.properties[prop].className = value.className

        if value.hasOwnProperty 'handlers'
            sanDef.properties[prop].handlers = handlers = {}

            # insert: default value if undefined
            # update: automatic value, don't care about setted one
            # read: from database to value. Ex: Date, Json
            # write: from value to database. Ex: Data, Json
            for type in ['insert', 'update', 'read', 'write']
                handler = value.handlers[type]
                if typeof handler is 'function'
                    handlers[type] = handler


        # optimistic lock definition
        if value.hasOwnProperty 'lock'
            sanDef.properties[prop].lock = typeof value.lock is 'boolean' and value.lock

    # =============================================================================
    #  Properties checking
    # =============================================================================
    sanDef.properties = {}
    if _.isPlainObject definition.properties
        properties = definition.properties
    else
        properties = {}

    for prop, value of properties
        _addProperty prop, value
    # =============================================================================
    #  Properties checking - End
    # =============================================================================

    # =============================================================================
    #  Mixins checking
    # =============================================================================
    if not definition.hasOwnProperty 'mixins'
        mixins = []
    else if typeof definition.mixins is 'string' and definition.mixins.length > 0
        mixins = [definition.mixins]
    else if definition.mixins instanceof Array
        mixins = definition.mixins.slice 0
    else
        err = new Error "[#{sanDef.className}] mixins property can only be a string or an array of strings"
        err.code = 'MIXINS'
        throw err

    sanDef.mixins = []
    if GenericUtil.notEmptyString id.className
        mixins.unshift id.className
    seenMixins = {}
    
    for mixin in mixins
        if typeof mixin is 'string'
            mixin = className: mixin

        if not _.isPlainObject mixin
            err = new Error "[#{sanDef.className}] mixin can only be a string or a not null object"
            err.code = 'MIXIN'
            throw err

        if not mixin.hasOwnProperty 'className'
            err = new Error "[#{sanDef.className}] mixin has no className property"
            err.code = 'MIXIN'
            throw err

        className = mixin.className

        if seenMixins[className]
            err = new Error "[#{sanDef.className}] mixin [#{mixin.className}]: duplicate mixin. Make sure it's not also and id className"
            err.code = 'DUP_MIXIN'
            throw err

        seenMixins[className] = true
        _mixin = className: className
        if GenericUtil.notEmptyString mixin.column
            _mixin.column = mixin.column
        else if mixin.hasOwnProperty 'column'
            err = new Error "[#{sanDef.className}] mixin [#{mixin.className}]: Column is not a string or is empty"
            err.code = 'MIXIN_COLUMN'
            throw err
        sanDef.mixins.push _mixin

        if not sanitized.hasResolved className
            if sanitized.isResolving className
                err = new Error "[#{sanDef.className}] mixin [#{mixin.className}]: Circular reference detected: -> '#{className}'"
                err.code = 'CIRCULAR_REF'
                throw err
            _depResolve className, mapping, sanitized

        # Mark this mixin as dependency resolved
        sanitized.setDepResolved sanDef.className, className

        # mixin default column if miin className id column
        if not _mixin.hasOwnProperty 'column'
            _mixin.column = sanitized.classes[_mixin.className].id.column

        # id column of mixins that are not class parent have not been added as column,
        # add them to avoid duplicate columns
        if sanDef.id.className isnt _mixin.className
            sanitized.addColumn sanDef.className, _mixin.column, sanitized.classes[_mixin.className].id.name

        # Mark all resolved dependencies,
        # Used to check circular references and related mixin
        resolved = sanitized.getDepResolved className
        for className of resolved
            sanitized.setDepResolved sanDef.className, className

        # check related mixin
        parents = sanitized.addNormalize sanDef.className, mixin
        if (parents instanceof Array) and parents.length > 0
            err = new Error "[#{sanDef.className}] mixin '#{mixin}' depends on mixins #{parents}. Add only mixins with no relationship or you have a problem in your design"
            err.code = 'RELATED_MIXIN'
            err.extend = parents
            throw err

        # add this mixin available properties as available properties for this className
        # Purposes:
        #   - On read, to fastly check if join on this mixin is required
        mixinDef = sanitized.classes[_mixin.className]
        sanDef.available.mixins[_mixin.className] = _mixin
        for prop of mixinDef.available.properties
            if not sanDef.available.properties.hasOwnProperty prop
                sanDef.available.properties[prop] =
                    mixin: _mixin
                    definition: mixinDef.available.properties[prop].definition

    # =============================================================================
    #  Mixins checking - End
    # =============================================================================

    if typeof sanDef.id.className is 'string'
        map = sanitized.classes[sanDef.id.className]
        sanDef.id.name = map.id.name

        if not sanDef.id.hasOwnProperty 'column'
            sanDef.id.column = map.id.column
            sanitized.addColumn sanDef.className, sanDef.id.column, sanDef.id.name

    # add id as an available property
    if typeof sanDef.id.name is 'string'
        sanDef.available.properties[sanDef.id.name] = definition: sanDef.id

    if definition.hasOwnProperty 'ctor'
        _setConstructor sanDef.className, definition.ctor, sanDef

    sanitized.markResolved sanDef.className

_getValidOptions = (validOptions, options)->
    _options = {}
    if not _.isPlainObject options
        return _options
    for key in validOptions
        if typeof options[key] isnt 'undefined'
            _options[key] = options[key]
    _options

_setConstructor = (className, Ctor, definition)->
    if GenericUtil.notEmptyString Ctor
        Ctor = require Ctor

    if typeof Ctor isnt 'function'
        err = new Error "[#{className}] given constructor is not a function"
        err.code = 'CTOR'
        throw err
    definition.ctor = Ctor

_coerce = (value, connector)->
    if value instanceof Array
        res = []
        for val in value
            res.push connector.escape val
        '(' + res.join ', ' + ')'
    else
        value
