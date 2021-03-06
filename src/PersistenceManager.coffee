log4js = require './log4js'
logger = log4js.getLogger __filename.replace /^(?:.+[\/\\])?([^.\/\\]+)(?:.[^.]+)?$/, '$1'

_ = require 'lodash'
squel = require 'squel'
RowMap = require './RowMap'
CompiledMapping = require './CompiledMapping'
AdapterPool = require './AdapterPool'
async = require 'async'
semLib = require 'sem-lib'
tools = require './tools'
{adapter: getAdapter, guessEscapeOpts} = tools

hasProp = Object::hasOwnProperty

flavours = {}
do ->
    for dialect of squel.flavours
        _squel = squel.useFlavour(dialect)
        _squel.cls.Expression = squel.cls.Expression
        flavours[dialect] = _squel
    return flavours

getSquel = (dialect)->
    if hasProp.call(flavours, dialect) then flavours[dialect] else squel

DefaultQueryBuilderOptions = _.defaults
    replaceSingleQuotes: true
, squel.cls.DefaultQueryBuilderOptions

delegateMethod = (self, className, method, target = method)->
    if method is 'new'
        self[method + className] = self.newInstance.bind self, className
        return

    self[method + className] = (model, options, done)->
        if _.isPlainObject model
            model = self.newInstance className, model

        if 'function' is typeof options
            done = options
            options = {}

        self[target] model, _.extend({className}, options), done
    return

module.exports = class PersistenceManager extends CompiledMapping
    defaults:
        list: {
            depth: 10
        }
        insert: {}
        update: {}
        save: {}
        delete: {}
        sync: {}

    constructor: (...args)->
        super(...args)
        [mapping, options] = args
        this.defaults = _.cloneDeep this.defaults

        for className of this.classes
            for method in ['insert', 'update', 'save', 'delete']
                delegateMethod @, className, method

            delegateMethod @, className, 'new'
            @['list' + className] = this.list.bind @, className
            @['remove' + className] = @['delete' + className]

        pools = this.pools = {}
        connectors = this.connectors = {}

        if options and _.isObject(users = options.users)
            for name in ['admin', 'writer', 'reader']
                if hasProp.call users, name
                    pool = pools[name] = new AdapterPool(users[name])
                    connectors[name] = pool.createConnector()

            this.defaults.sync = _.defaults {connector: connectors.admin}, this.defaults.sync
            this.defaults.insert = _.defaults {connector: connectors.writer or connectors.admin}, this.defaults.insert
            this.defaults.update = _.defaults {connector: connectors.writer or connectors.admin}, this.defaults.update
            this.defaults.delete = _.defaults {connector: connectors.writer or connectors.admin}, this.defaults.delete
            this.defaults.save = _.defaults {connector: connectors.writer or connectors.admin}, this.defaults.save
            this.defaults.list = _.defaults {connector: connectors.reader or connectors.writer or connectors.admin}, this.defaults.list

    destroyPools: (safe = true, done)->
        if 'function' is typeof safe
            done = safe
            safe = true

        count = Object.keys(this.pools).length
        if count is 0
            done() if 'function' is typeof done
            return

        for name, pool of this.pools
            do (name, pool)->
                pool.destroyAll safe, (err)->
                    console.error(err) if err
                    if --count is 0
                        done() if 'function' is typeof done
                    return
                return
        return

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

PersistenceManager.getSquelQuery = PersistenceManager::getSquelQuery = (type, dialect)->
    options = _.defaults getAdapter(dialect).squelOptions, DefaultQueryBuilderOptions
    return getSquel(dialect)[type](options)

PersistenceManager.getSquelOptions = PersistenceManager::getSquelOptions = (dialect)->
    return _.defaults getAdapter(dialect).squelOptions, DefaultQueryBuilderOptions

PersistenceManager.decorateInsert = PersistenceManager::decorateInsert = (dialect, insert, column)->
    adapter = getAdapter(dialect)

    if 'function' is typeof adapter.decorateInsert
        adapter.decorateInsert insert, column

    insert

PersistenceManager.insertDefaultValue = PersistenceManager::insertDefaultValue = (dialect, insert, column)->
    adapter = getAdapter(dialect)

    if 'function' is typeof adapter.insertDefaultValue
        adapter.insertDefaultValue insert, column, getSquel(dialect)

    insert

PersistenceManager::insert = (model, options, callback, guess = true)->
    if guess
        options = _.defaults {autoRollback: false}, guessEscapeOpts(options, this.defaults.insert)
    try
        query = this.getInsertQuery model, options, false
    catch err
        return callback err

    connector = options.connector
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
            query.execute connector, (...args)->
                method = if args[0] then 'rollback' else 'commit'

                connector[method] (err)->
                    if err
                        if args[0]
                            args[0] = [err, args[0]]
                        else
                            args[0] = err
                    if performed
                        connector.release (err)->
                            logger.error err if err
                            callback.apply null, args
                            return
                    else
                        callback.apply null, args
                    return
                return
            return
        return
    return

PersistenceManager::getInsertQuery = (model, options, guess = true)->
    if guess
        options = guessEscapeOpts(options, this.defaults.insert)
    new InsertQuery @, model, options, false

PersistenceManager::list = (className, options, callback, guess = true)->
    if 'function' is typeof options
        callback = options
        options = {}

    if guess
        options = guessEscapeOpts(options, this.defaults.list)
    try
        query = this.getSelectQuery className, options, false
    catch err
        return callback err

    connector = options.connector
    query.list connector, callback

PersistenceManager::stream = (className, options, callback, done)->
    options = guessEscapeOpts(options, this.defaults.list)
    try
        query = this.getSelectQuery className, options, false
    catch err
        return done err

    connector = options.connector
    listConnector = options.listConnector or connector.clone()
    query.stream connector, listConnector, callback, done

PersistenceManager::getSelectQuery = (className, options, guess = true)->
    if guess
        options = guessEscapeOpts(options, this.defaults.list)

    if _.isPlainObject options.where
        options.attributes = options.where
        options.where = undefined

    if not options.where and _.isPlainObject options.attributes
        definition = this._getDefinition className
        {where: options.where} = _getInitializeCondition @, null, definition, _.defaults({useDefinitionColumn: false}, options)

    new SelectQuery @, className, options, false

PersistenceManager::update = (model, options, callback, guess = true)->
    if guess
        options = _.defaults {autoRollback: false}, guessEscapeOpts(options, this.defaults.update, PersistenceManager::defaults.update)
    try
        query = this.getUpdateQuery model, options, false
    catch err
        return callback err

    connector = options.connector
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
            query.execute connector, (...args)->
                method = if args[0] then 'rollback' else 'commit'

                connector[method] (err)->
                    if err
                        if args[0]
                            args[0] = [err, args[0]]
                        else
                            args[0] = err
                    if performed
                        connector.release (err)->
                            logger.error(err) if err
                            callback.apply null, args
                            return
                    else
                        callback.apply null, args
                    return
                return
            return
        return
    return

PersistenceManager::getUpdateQuery = (model, options, guess = true)->
    if guess
        options = guessEscapeOpts(options, this.defaults.update, PersistenceManager::defaults.update)
    new UpdateQuery @, model, options, false

PersistenceManager::delete = PersistenceManager::remove = (model, options, callback)->
    if 'function' is typeof options
        callback = options
        options = {}

    options = _.defaults {autoRollback: false}, guessEscapeOpts(options, this.defaults.delete, PersistenceManager::defaults.delete)
    try
        query = this.getDeleteQuery model, options, false
    catch err
        return callback err

    connector = options.connector
    query.execute connector, callback
    return

PersistenceManager::getDeleteQuery = (model, options, guess = true)->
    if guess
        options = guessEscapeOpts(options, this.defaults.delete, PersistenceManager::defaults.delete)
    new DeleteQuery @, model, options, false

PersistenceManager::save = (model, options, callback)->
    return callback err if (err = isValidModelInstance model) instanceof Error
    options = guessEscapeOpts(options, this.defaults.save, PersistenceManager::defaults.save)

    # if arguments.length is 2 and 'function' is typeof options
    #     callback = options
    # options = {} if not _.isPlainObject options
    (callback = ->) if 'function' isnt typeof callback

    className = options.className or model.className
    definition = this._getDefinition className

    try
        {fields, where} = _getInitializeCondition @, model, definition, _.defaults(
            useDefinitionColumn: false
            useAttributes: false
        ,  options)
    catch err
        callback err
        return

    if where.length is 0
        this.insert model, _.defaults({reflect: true}, options), (err, id)->
            callback(err, id, 'insert')
            return
        , false
    else
        backup = options
        options = _.defaults
            fields: fields
            where: where
            limit: 2 # Expecting one result. Limit is for unique checking without getting all results
        , options
        this.list className, options, (err, models)=>
            return callback(err) if err
            if models.length is 1
                # update properties
                model.set _.defaults model.toJSON(), models[0].toJSON()
                this.update model, backup, callback, false
            else
                this.insert model, _.defaults({reflect: true}, backup), (err, id)->
                    callback(err, id, 'insert')
                    return
                , false
            return
        , false
    return

PersistenceManager::initialize = (model, options, callback, guess = true)->
    return callback err if (err = isValidModelInstance model) instanceof Error

    if guess
        options = guessEscapeOpts(options)

    (callback = ->) if 'function' isnt typeof callback

    if not _.isObject model
        err = new Error 'No model'
        err.code = 'NO_MODEL'
        return callback err

    className = options.className or model.className
    definition = this._getDefinition className
    options = _.extend {}, options,
        models: [model]

    try
        {where: options.where} = _getInitializeCondition @, model, definition, _.defaults({useDefinitionColumn: false}, options)
    catch err
        callback err
        return

    this.list className, options, callback, false

# return where condition to be parsed by RowMap
_getInitializeCondition = (pMgr, model, definition, options)->
    where = []

    if typeof options.where is 'undefined'
        if not model
            attributes = options.attributes
        else if _.isPlainObject(definition.id) and value = model.get definition.id.name
            # id is defined
            attributes = {}
            attributes[definition.id.name] = value
            fields = [definition.id.name]
        else
            if definition.hasUniqueConstraints and (options.useAttributes is false or not options.attributes)
                attributes = {}
                # check unique constraints properties
                for constraintKey, constraint of definition.constraints.unique
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

                if not isSetted
                    # the model cannot be initialized using it's attributes
                    return {fields, where}

                fields = Object.keys attributes

            attributes = options.attributes or model.toJSON() if not isSetted and options.useAttributes isnt false

        if _.isPlainObject attributes
            for attr, value of attributes
                _addWhereAttr pMgr, model, attr, value, definition, where, options
        else if Array.isArray attributes
            for attr in attributes
                value = model.get attr
                _addWhereAttr pMgr, model, attr, value, definition, where, options
    else
        where = options.where

    if isSetted
        _.isPlainObject(options.result) or (options.result = {})
        options.result.constraint = constraint

    {fields, where}

PRIMITIVE_TYPES = /^(?:string|boolean|number)$/

_addWhereAttr = (pMgr, model, attr, value, definition, where, options)->
    if typeof value is 'undefined'
        return

    if options.useDefinitionColumn
        # ignore not defined properties
        if not hasProp.call definition.properties, attr
            return
        column = options.escapeId definition.properties[attr].column
    else
        # ignore not defined properties
        if not hasProp.call definition.availableProperties, attr
            return

        column = '{' + attr + '}'

    propDef = definition.availableProperties[attr].definition
    if _.isPlainObject(propDef.handlers) and typeof propDef.handlers.write is 'function'
        value = propDef.handlers.write value, model, options

    if  PRIMITIVE_TYPES.test typeof value
        where.push column + ' = ' + options.escape value
    else if _.isObject value
        propClassName = propDef.className
        value = value.get pMgr.getIdName propClassName
        if typeof value isnt 'undefined'
            if value is null
                where.push column + ' IS NULL'
            else if PRIMITIVE_TYPES.test typeof value
                where.push column + ' = ' + options.escape value

    return

PersistenceManager.InsertQuery = class InsertQuery
    constructor: (pMgr, model, options, guess = true)->
        assertValidModelInstance model
        if guess
            options = guessEscapeOpts(options, pMgr.defaults.insert, PersistenceManager::defaults.insert)
        this.options = options

        this.model = model
        this.pMgr = pMgr
        this.options = options
        root = options.root or @

        #  for mysql when lastInsertId is not available because there is no autoincrement
        fields = this.fields = {}

        this.set = (column, value)->
            insert.set this.options.escapeId(column), value
            fields[column] = value
        this.toString = this.oriToString = -> insert.toString()
        this.toParam = -> insert.toParam()
        this.toQuery = -> insert

        this.className = className = options.className or model.className
        definition = this.definition = pMgr._getDefinition className
        table = definition.table
        insert = pMgr.getSquelQuery('insert', options.dialect).into this.options.escapeId(table)

        # ids of mixins will be setted at execution
        if definition.mixins.length > 0
            this.toString = -> insert.toParam().text

            this.toParam = ->
                param = insert.toParam()
                for value, index in values
                    param.values[index] = values[index]
                param

            values = insert.toParam().values
            for mixin, index in definition.mixins
                nested = options.nested or 0
                values[index] = new InsertQuery pMgr, model, _.defaults({
                    className: mixin.className
                    dialect: options.dialect
                    nested: ++nested
                    root
                    allowEmpty: true
                }, options) , false

            for mixin in definition.mixins
                insert.set this.options.escapeId(mixin.column), '$id'

        idName = pMgr.getIdName className
        id = model.get idName if idName isnt null
        props = Object.keys(definition.properties)

        if id
            insert.set this.options.escapeId(definition.id.column), id
            this.hasData = true if props.length is 0

        for prop in props
            propDef = definition.properties[prop]

            column = propDef.column

            if hasProp.call propDef, 'className'
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
                value = insertHandler value, model, _.defaults {table, column}, options

            # Only set defined values
            if typeof value is 'undefined'
                continue

            # Write handler
            if typeof writeHandler is 'function'
                value = writeHandler value, model, options

            # Only set defined values
            if typeof value is 'undefined'
                continue

            root.hasData = this.hasData = true

            insert.set this.options.escapeId(column), value

        # check
        this.toString()

    execute: (connector, callback)->
        if this.toString is this.oriToString
            this._execute connector, callback
            return

        self = @
        definition = this.definition
        params = this.toParam()
        tasks = []

        _addTask = (query, connector, index)->
            if query.hasData and not self.hasData
                self.hasData = query.hasData

            tasks.push (next)->
                query.execute connector, (err, id)->
                    return next(err) if err
                    column = definition.mixins[index].column
                    self.set column, id
                    next()
                    return
                return

            return

        for value, index in params.values
            if value instanceof InsertQuery
                _addTask value, connector, index
            else
                break

        async.series tasks, (err)->
            return callback(err) if err
            self._execute connector, callback
            return
        return

    _execute: (connector, callback)->
        pMgr = this.pMgr
        query = this.toQuery()
        definition = this.definition
        model = this.model
        fields = this.fields
        options = this.options

        # empty objects are not inserted by default
        if not this.hasData 
            if not options.allowEmpty
                callback(new Error('no data to insert'))
                return

            if definition.id.column
                pMgr.insertDefaultValue options.dialect, query, definition.id.column
            else
                for prop, propDef of definition.properties
                    column = propDef.column
                    pMgr.insertDefaultValue options.dialect, query, column
                    break

        if definition.id.column
            pMgr.decorateInsert options.dialect, query, definition.id.column

        connector.query query.toString(), (err, res)->
            return callback(err) if err

            if hasProp.call definition.id, 'column'
                # On sqlite, lastInsertId is only valid on autoincremented id's
                # Therefor, always take setted field when possible
                if fields[definition.id.column]
                    id = fields[definition.id.column]
                else if hasProp.call res, 'lastInsertId'
                    id = res.lastInsertId
                else
                    id = Array.isArray(res.rows) and res.rows.length > 0 and res.rows[0][definition.id.column]

            logger.debug '[', definition.className, '] - INSERT', id

            if options.reflect
                if hasProp.call definition.id, 'column'
                    where = '{' + pMgr.getIdName(definition.className) + '} = ' + id
                pMgr.initialize model, _.defaults({connector, where}, options), (err)->
                    callback err, id
                    return
                , false
            else
                callback err, id

            return
        , options.executeOptions

        return

    toSingleQuery: ->
        query = @
        withs = []
        line = _toInsertLine.call query, 0, withs

        if withs.length is 0
            return line

        'WITH ' + _.map(withs, ([column, line], index)->
            """
            insert_#{index} (#{query.options.escapeId column}) AS (
            #{line}
            )
            """
        ).join(',\n') + '\n' + line

_toInsertLine = (level, withs)->
    if level > 0
        indent = '    '
    else
        indent = ''

    definition = this.definition
    {blocks} = this.toQuery()
    {values} = this.toParam()

    if definition.id?.column
        returning = "#{indent}RETURNING #{this.options.escapeId definition.id.column}"
    else
        returning = ''

    if this.toString is this.oriToString
        return """
        #{indent}INSERT INTO #{blocks[1].table} (#{blocks[2].fields.join(', ')})
        #{indent}VALUES (#{_.map(values, this.options.escape).join(', ')})
        #{returning}
        """

    tables = []

    for value, index in values
        if value instanceof InsertQuery
            line = _toInsertLine.call value, ++level, withs
            column = definition.mixins[index].column
            tables.push "insert_#{withs.length}"
            values[index] = "insert_#{withs.length}.#{this.options.escapeId column}"
            withs.push [column, line]
        else
            values[index] = this.options.escape value

    """
    #{indent}INSERT INTO #{blocks[1].table} (#{blocks[2].fields.join(', ')})
    #{indent}SELECT #{values.join(', ')}
    #{indent}FROM #{tables.join(', ')}
    #{returning}
    """

_getCacheId = (options)->
    json = {}
    for opt in ['dialect', 'type', 'count', 'attributes', 'fields', 'join', 'where', 'group', 'having', 'order', 'limit', 'offset']
        if hasProp.call options, opt
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
    logger.trace 'add cache"', className, '"', cacheId
    # serialize = (key, value)->
    #     _serialize cacheId, key, value
    json = _.pick rowMap, ['_infos', '_tableAliases', '_tabId', '_columnAliases', '_colId', '_tables', '_mixins', '_joining']
    value = 
        rowMap: JSON.stringify json
        template: rowMap.getTemplate()
        select: JSON.stringify rowMap.select

    this.classes[className].cache.set cacheId, value
    value

PersistenceManager::getCachedRowMap = (cacheId, className, options)->
    cached = this.classes[className].cache.get cacheId
    return if not cached
    logger.trace 'read cache', className, cacheId
    rowMap = new RowMap className, @, options, true
    select = new squel.select.constructor()
    # desirialize = (key, value)->
    #     _desirialize cacheId, key, value
    _.extend select, JSON.parse cached.select
    _.extend rowMap, JSON.parse cached.rowMap
    rowMap.template = cached.template
    rowMap.select = select
    rowMap.values = options.values
    rowMap._initialize()
    rowMap._processColumns()
    rowMap._selectCount() if options.count
    rowMap._updateInfos()
    rowMap

PersistenceManager.SelectQuery = class SelectQuery
    constructor: (pMgr, className, options, guess = true)->
        if arguments.length is 1
            if arguments[0] instanceof RowMap
                this.rowMap = arguments[0]
                return @
            else
                throw new Error 'Given parameter do not resolve to a RowMap'

        if guess
            options = guessEscapeOpts(options, pMgr.defaults.list)

        useCache = options.cache isnt false
        cacheId = _getCacheId options if useCache

        if not useCache or not rowMap = pMgr.getCachedRowMap cacheId, className, options
            select = pMgr.getSquelQuery('select', options.dialect)
            rowMap = new RowMap className, pMgr, _.extend {}, options, select: select

            # check
            select.toParam()
            select.toString()
            if useCache
                this.cacheId = cacheId
                pMgr.addCachedRowMap cacheId, className, rowMap

        this.rowMap = rowMap
        return @

    toString: ->
        this.rowMap.toString()

    stream: (streamConnector, listConnector, callback, done)->
        (callback = ->) if 'function' isnt typeof callback
        (done = ->) if 'function' isnt typeof done

        rowMap = this.rowMap
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
        this.toString()

    list: (connector, callback)->
        (callback = ->) if 'function' isnt typeof callback

        rowMap = this.rowMap
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
                    pMgr.list task.className , _.defaults({connector}, task.options), (err, models)->
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

_addUpdateOrDeleteCondition = (action, name, pMgr, model, className, definition, options)->
    idName = pMgr.getIdName className
    idName = null if typeof idName isnt 'string' or idName.length is 0
    if ! definition.hasUniqueConstraints and idName is null
        err = new Error "Cannot #{name} #{className} models because id has not been defined"
        err.code = name.toUpperCase()
        throw err

    id = model.get idName if idName isnt null
    hasNoCondition = hasNoId = id is null or 'undefined' is typeof id
    if hasNoId
        options = _.extend {}, options, {useDefinitionColumn: true}
        {where} = _getInitializeCondition pMgr, model, definition, options
        result = options.result
        hasNoCondition = where.length is 0
        for condition in where
            action.where condition
    else
        action.where options.escapeId(definition.id.column) + ' = ' + options.escape id

    if hasNoCondition
        err = new Error "Cannot #{name} #{className} model because id is null or undefined"
        err.code = name.toUpperCase()
        throw err
    return result

PersistenceManager.UpdateQuery = class UpdateQuery
    constructor: (pMgr, model, options, guess = true)->
        assertValidModelInstance model
        if guess
            options = guessEscapeOpts(options, pMgr.defaults.insert, PersistenceManager::defaults.insert)
        this.options = options

        this.model = model
        this.pMgr = pMgr

        this.toQuery = -> update
        this.toParam = -> update.toParam()
        this.toString = this.oriToString = -> update.toString()
        # this.getClassName = -> className
        this.getDefinition = -> definition
        this.setChangeCondition = ->
            update.where changeCondition
            @

        className = options.className or model.className
        definition = this.definition = pMgr._getDefinition className
        table = definition.table
        update = pMgr.getSquelQuery('update', options.dialect).table options.escapeId(table)

        result = _addUpdateOrDeleteCondition update, 'update', pMgr, model, className, definition, options

        # condition to track changes
        changeCondition = squel.expr()
        this.lockCondition = lockCondition = squel.expr()

        # update owned properties
        for prop, propDef of definition.properties
            if result and result.constraint
                # constraint used as discriminator must not be update
                # causes an error on postgres
                if -1 isnt result.constraint.indexOf prop
                    continue

            if hasProp.call(propDef, 'className') and typeof (parentModel = model.get prop) isnt 'undefined'
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
                    lock = writeHandler lock, model, _.defaults {table, column}, options
                    lockCondition.and options.exprEqual lock, options.escapeId column

            if typeof updateHandler is 'function'
                value = updateHandler value, model, _.defaults {table, column}, options

            # Only set defined values
            if typeof value is 'undefined'
                continue

            # Value handler
            if typeof writeHandler is 'function'
                value = writeHandler value, model, _.defaults {table, column}, options

            # Only set defined values
            if typeof value is 'undefined'
                continue

            update.set options.escapeId(column), value, {dontQuote: !!dontQuote}
            this.hasData = true

            if not dontLock and not propDef.lock
                changeCondition.or options.exprNotEqual value, options.escapeId column

        update.where lockCondition

        # update mixin properties
        if definition.mixins.length is 0
            this.setChangeCondition()
        else
            if this.hasData
                this.toString = -> update.toString()
            else
                this.toString = -> ''

            this.toParam = ->
                if this.hasData
                    params = update.toParam()
                else
                    params = values: []

                for mixin, index in definition.mixins
                    nested = options.nested or 0
                    params.values.push new UpdateQuery pMgr, model, _.defaults({
                        className: mixin.className
                        dialect: options.dialect
                        nested: ++nested
                    }, options) , false
                return params

        this.toString() if this.hasData

    execute: (connector, callback)->
        if this.toString is this.oriToString
            return this._execute connector, callback

        params = this.toParam()
        idIndex = 0
        tasks = []

        _addTask = (query, connector)->
            tasks.push (next)-> query.execute connector, next
            return

        for index in [(params.values.length - 1)..0] by -1
            value = params.values[index]
            if value instanceof UpdateQuery and value.hasData
                _addTask value, connector
            else
                break

        hasUpdate = false
        definition = this.definition
        async.series tasks, (err, results)=>
            return callback(err) if err

            # Check if parent mixin has been updated
            if Array.isArray(results) and results.length > 0
                for result in results
                    if Array.isArray(result) and result.length > 0
                        [id, msg] = result
                        if msg is 'update'
                            logger.debug '[', definition.className, '] - UPDATE: has update', id
                            hasUpdate = true
                            break
                if Array.isArray results[results.length - 1]
                    id = results[results.length - 1][0]

            if not this.hasData
                callback err, id, not hasUpdate
                return

            # If parent mixin has been update, child must be considered as being updated
            if not hasUpdate
                logger.debug '[', definition.className, '] - UPDATE: has no update', id
                this.setChangeCondition()

            this._execute connector, (err, id, msg)->
                hasUpdate = hasUpdate or msg is 'update'
                callback err, id, if hasUpdate then 'update' else 'no-update'
                return
            return
        return

    _execute: (connector, callback)->
        pMgr = this.pMgr
        query = this.toQuery()
        definition = this.definition
        model = this.model
        options = this.options

        if definition.id.column
            query = pMgr.decorateInsert options.dialect, query, definition.id.column

        connector.query query.toString(), (err, res)->
            return callback(err) if err

            if hasProp.call res, 'affectedRows'
                hasNoUpdate = res.affectedRows is 0
            else if hasProp.call(definition.id, 'column') and res.rows
                hasNoUpdate = res.rows.length is 0
            else if hasProp.call res, 'rowCount'
                hasNoUpdate = res.rowCount is 0

            id = model.get definition.id.name

            msg = if hasNoUpdate then 'no-update' else 'update'

            if options.nested isnt undefined and options.nested isnt 0
                callback err, id, msg
                return

            if 'undefined' is typeof id
                try
                    {where} = _getInitializeCondition pMgr, model, definition, _.defaults({connector, useDefinitionColumn: false}, options)
                catch err
                    callback err
                    return
            else if hasProp.call definition.id, 'column'
                where = '{' + pMgr.getIdName(definition.className) + '} = ' + id

            # only initialize owned properties
            # parent and mixins will initialized their owned properties
            fields = Object.keys definition.availableProperties
            for field, i in fields
                propDef = definition.availableProperties[field]
                if definition.id isnt propDef.definition and not propDef.mixin and hasProp.call(propDef.definition, 'className')
                    fields[i] = field + ':*'

            options = _.defaults({connector, fields, where}, options)

            logger.debug '[', definition.className, '] - UPDATE initializing', where
            pMgr.initialize model, options, (err, models)->
                return callback err if err
                id = model.get definition.id.name

                if hasNoUpdate 
                    if models.length is 0
                        err = new Error 'id or lock condition'
                        err.code = 'NO_UPDATE'
                        logger.debug '[', definition.className, '] - NO UPDATE', id
                else
                    logger.debug '[', definition.className, '] - UPDATE', id

                logger.debug '[', definition.className, '] - UPDATE initialized', id
                callback err, id, msg
                return
            , false
            return
        , options.executeOptions
        return

PersistenceManager.DeleteQuery = class DeleteQuery
    constructor: (pMgr, model, options, guess = true)->
        assertValidModelInstance model
        if guess
            options = guessEscapeOpts(options, pMgr.defaults.insert, PersistenceManager::defaults.insert)
        this.options = options

        this.toParam = ->
            remove.toParam()
        this.toString = this.oriToString = ->
            remove.toString()
        this.options = options

        className = options.className or model.className
        definition = this.definition = pMgr._getDefinition className
        remove = pMgr.getSquelQuery('delete', options.dialect).from options.escapeId definition.table

        _addUpdateOrDeleteCondition remove, 'delete', pMgr, model, className, definition, options

        # optimistic lock
        for prop, propDef of definition.properties

            if hasProp.call propDef, 'className'
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
                remove.where options.escapeId(column) + ' = ' + options.escape value

        # delete mixins lines
        if definition.mixins.length > 0
            this.toString = ->
                remove.toString()

            this.toParam = ->
                params = remove.toParam()
                for mixin, index in definition.mixins
                    nested = options.nested or 0
                    params.values.push new DeleteQuery pMgr, model, _.defaults({
                        className: mixin.className
                        dialect: options.dialect
                        nested: ++nested
                    }, options) , false
                return params

        # check
        this.toString()

    execute: (connector, callback)->
        next = (err, res)->
            return callback(err) if err

            if not res.affectedRows and hasProp.call res, 'rowCount'
                res.affectedRows = res.rowCount

            callback err, res
            return

        if this.toString is this.oriToString
            return this._execute connector, next

        params = this.toParam()
        _addTask = (query, connector)->
            tasks.push (next)-> query.execute connector, next
            return

        tasks = []
        for index in [(params.values.length - 1)..0] by -1
            value = params.values[index]
            if value instanceof DeleteQuery
                _addTask value, connector
            else
                break

        this._execute connector, (err, res)->
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
        query = this.oriToString()
        connector.query query, callback, this.options.executeOptions
        return

PersistenceManager::getInsertQueryString = (className, entries, options)->
    table = this.getTable className
    rows = []

    for attributes in entries
        row = {}
        query = this.getInsertQuery this.newInstance(className, attributes), options
        {blocks} = query.toQuery()
        {fields: columns, values: [values]} = blocks[2]
        for column, i in columns
            row[column] = values[i]
        rows.push row

    this.getSquelQuery('insert', query.options.dialect)
        .into query.options.escapeId this.getTable className
        .setFieldsRows rows
        .toString()

PersistenceManager::sync = require('./schema/sync').sync

# error codes abstraction
# check: database and mapping are compatible
# collection
# stream with inherited =>
#   2 connections?
# stream with collections?
#   two connections?
# decision: manually set joins, stream only do one request, charge to you to recompute records
