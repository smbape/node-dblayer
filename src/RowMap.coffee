_ = require 'lodash'
path = require 'path'
GenericUtil = require './GenericUtil'
PlaceHolderParser = require './PlaceHolderParser'
log4js = global.log4js or (global.log4js = require 'log4js')
logger = log4js.getLogger 'RowMap'
squel = require 'squel'
{guessEscapeOpts} = require './adapters/common'

STATIC =
    PROP_SEP: ':'
    FIELD_CHAR_BEGIN: '{'
    FIELD_CHAR_END: '}'
    ROOT: 'root'

fieldHolderParser = new PlaceHolderParser STATIC.FIELD_CHAR_BEGIN, STATIC.FIELD_CHAR_END
placeHolderParser = new PlaceHolderParser()

JOIN_FUNC =
    default: 'join'
    outer: 'outer_join'
    left: 'left_join'
    right: 'right_join'

_handleRead = (value, model, propDef)->
    if typeof propDef.read is 'function'
        value = propDef.read value, model
    value

_createModel = (className = @className)->
    definition = @manager.getDefinition className
    Ctor = definition.ctor
    new Ctor()
_setModelValue = (model, prop, value, propDef)->
    model.set prop, _handleRead value, model, propDef
_getModelValue = (model, prop)->
    model.get prop

_createPlainObject = (className)->
    {}
_setPlainObjectValue = (model, prop, value, propDef)->
    model[prop] = _handleRead value, model, propDef
_getPlainObjectValue = (model, prop)->
    model[prop]

# Private Class, supposed to be used in conjunction with PersistenceManager Class
module.exports = class RowMap
    static: LIMIT: 500

    # Class that do the mapping between className, queries to execute and properties of className
    constructor: (@className, @manager, options, skip)->
        @options = guessEscapeOpts(options)
        return if skip

        _.extend @,
            _infos: {}
            _tableAliases: {}
            _tabId: 0
            _columnAliases: {}
            _colId: 0
            _tables: {}
            _mixins: {}
            _joining: {}

        @select = options.select
        @values = options.values
        delete @options.select
        delete @options.values

        @_initialize()
        @_initRootElement @className, @_getUniqueId()

        @_processJoins()
        @_processFields()
        @_processColumns()
        @_processBlocks()

    setValues: (@values)->

    setValue: (key, value)->
        @values[key] = value

    _initialize: ->
        options = @options
        if options.type is 'json' or options.count
            @_setValue = _setPlainObjectValue
            @_getValue = _getPlainObjectValue
            @_create = _createPlainObject
        else
            @_setValue = _setModelValue
            @_getValue = _getModelValue
            @_create = _createModel

        return

    _initRootElement: (className, id, options = {})->
        if @_tables.hasOwnProperty id
            return

        if not className
            if not @options.hasOwnProperty('join') or not @options.join.hasOwnProperty id
                err = new Error "#{id} was not found in any join definitions"
                err.code = 'TABLE_UNDEF'
                throw err
            className = @options.join[id].entity
            options = @options.join[id]

        definition = @manager.getDefinition className
        table = definition.table
        tableAlias = @_uniqTabAlias()

        select = @select
        if options.hasOwnProperty 'condition'
            @_tables[id] = tableAlias
            @_infos[id] = className: className
            if @_joining.hasOwnProperty id
                err = new Error "#{id} has already been joined. Look at stack to find the circular reference"
                err.code = 'CIRCULAR_REF'
                throw err

            @_joining[id] = true

            if JOIN_FUNC.hasOwnProperty options.type
                hasJoin = JOIN_FUNC[options.type]
            else if 'undefined' is typeof options.type
                hasJoin = JOIN_FUNC.default
            else if 'string' is typeof options.type
                type = options.type.toUpperCase()
                hasJoin = JOIN_FUNC.default
            else
                err = new Error "#{id} has an invalid join type"
                err.code = 'JOIN_TYPE'
                throw err

            # make necessary joins
            condition = _coerce.call @, options.condition

            select[hasJoin] @options.escapeId(table), tableAlias, condition, type

            # make necessary joins
            # condition = _coerce.call @, options.condition

            delete @_joining[id]
            @_infos[id].hasJoin = hasJoin
        else if _.isEmpty @_tables
            select.from @options.escapeId(table), tableAlias
            @_tables[id] = tableAlias
            @_infos[id] =
                className: className
                hasJoin: JOIN_FUNC.default
            @_rootInfo = @_infos[id]
        else
            err = new Error "#{id} has no joining condition"
            err.code = 'JOIN_COND'
            throw err

        return

    _processJoins: ->
        join = @options.join
        if _.isEmpty join
            return
        for alias, joinDef of join
            @_initRootElement joinDef.entity, alias, joinDef
            fields = @_sanitizeFields joinDef.fields
            if fields.length > 0
                @_rootInfo.properties = @_rootInfo.properties or {}
                @_rootInfo.properties[alias] = true
                @_infos[alias].attribute = alias

                if not @options.count
                    for field in fields
                        @_setField @_getUniqueId(field, alias), true
        return

    _processFields: ->
        if @options.count
            @_selectCount()
            return

        fields = @_sanitizeFields @options.fields, ['*']
        for field in fields
            @_setField field

        return

    _processColumns: ->
        columns = @options.columns
        if _.isEmpty columns
            return

        for prop, field of columns
            @_selectCustomField prop, field

        return

    _processBlocks: ->
        select = @select

        for block in ['where', 'group', 'having', 'order', 'limit', 'offset']
            option = @options[block]

            if  /^(?:string|boolean|number)$/.test typeof option
                option = [option]
            else if block is 'limit'
                option = [@static.LIMIT]
            else if _.isEmpty option
                continue

            if not (option instanceof Array)
                err = new Error "[#{@className}]: #{block} can only be a string or an array"
                err.code = block.toUpperCase()
                throw err

            if block is 'limit' and option[0] < 0
                continue

            for opt in option
                _readFields.call @, opt, select, block

        if @options.distinct
            select.distinct()

        return

    _getSetColumn: (field)->
        allAncestors = @_getAncestors field
        ancestors = []

        for prop, index in allAncestors
            ancestors.push prop
            if index is 0
                @_initRootElement null, prop
                continue

            id = @_getUniqueId null, ancestors
            @_getSetInfo id

            if index is allAncestors.length - 1
                continue

            parentInfo = info
            @_joinProp id, parentInfo
            info = @_getInfo id
            if info.hasOwnProperty('properties') and not info.setted
                for prop of info.properties
                    @_setField prop, true
                info.setted = true
        @_getColumn id

    _sanitizeFields: (fields, defaultValue)->
        if typeof fields is 'undefined'
            fields = defaultValue or []

        if typeof fields is 'string'
            fields = [fields]

        if not (fields instanceof Array)
            err = new Error "[#{@className}]: fields can only be a string or an array"
            err.code = 'FIELDS'
            throw err

        if fields.length is 0
            return []

        return fields

    # field: full field name
    _setField: (field, isFull)->
        allAncestors = @_getAncestors field, isFull
        ancestors = []

        for prop, index in allAncestors
            if index is allAncestors.length - 1
                @_selectProp prop, ancestors
                continue

            parentInfo = info
            ancestors.push prop
            id = @_getUniqueId null, ancestors
            info = @_getSetInfo id
            if parentInfo
                parentInfo.properties = parentInfo.properties or {}
                @_set parentInfo.properties, id, true

            @_joinProp id, parentInfo

        return

    _selectCount: ->
        @_selectCustomField 'count',
            column: 'count(1)'
            read: (value)->
                parseInt value, 10
        return

    _selectCustomField: (prop, field)->
        ancestors = [STATIC.ROOT]
        type = typeof field

        if 'undefined' is type
            column = prop
        else if 'string' is type
            column = field
        else if _.isPlainObject field
            column = field.column
            handlerRead = field.read

        id = @_getUniqueId prop, ancestors
        info = @_getSetInfo id, true

        @_set info, 'read', handlerRead if 'function' is typeof handlerRead

        if info.hasOwnProperty 'field'
            # this property has already been selected
            return

        columnAlias = @_uniqColAlias()
        column = _coerce.call @, column
        @select.field column, columnAlias

        # map columnAlias to prop
        @_set info, 'field', columnAlias

        parentInfo = @_getInfo @_getUniqueId null, ancestors
        parentInfo.properties = parentInfo.properties or {}

        # mark current prop as field of parent prop
        @_set parentInfo.properties, id, true
        return

    # set column alias as field of prop
    # must be called step by step
    _selectProp: (prop, ancestors)->
        parentId = @_getUniqueId null, ancestors
        parentInfo = @_getInfo parentId
        parentDefinition = @manager.getDefinition parentInfo.className

        if prop is '*'
            @_set parentInfo, 'selectAll', true
            for prop of parentDefinition.availableProperties
                @_setField @_getUniqueId(prop, ancestors), true
            return

        id = @_getUniqueId prop, ancestors
        info = @_getSetInfo id

        if info.hasOwnProperty 'field'
            # this property has already been selected
            return

        column = @_getColumn id
        columnAlias = @_uniqColAlias()
        @select.field column, columnAlias #, ignorePeriodsForFieldNameQuotes: true
        @_set info, 'field', columnAlias
        parentInfo = @_getInfo @_getUniqueId null, ancestors
        parentInfo.properties = parentInfo.properties or {}
        @_set parentInfo.properties, id, true
        @_set info, 'selectAll', parentInfo.selectAll

        if info.selectAll and info.hasOwnProperty('className') and not info.hasOwnProperty 'selectedAll'
            if parentDefinition.availableProperties[prop].definition.nullable is false
                isNullable = false
                ancestors = ancestors.concat([prop])
            else
                isNullable = true

            parentProp = prop
            properties = @manager.getDefinition(info.className).availableProperties
            info.properties = {}
            for prop of properties
                if isNullable
                    @_set info.properties, @_getUniqueId(prop, parentProp, ancestors), true
                else
                    # not nullable => select all fields
                    @_setField @_getUniqueId(prop, ancestors), true
            @_set info, 'selectedAll', true
        return

    # Is called step by step .i.e. parent is supposed to be defined
    _joinProp: (id, parentInfo)->
        info = @_getInfo id

        if info.hasOwnProperty 'hasJoin'
            return

        if not info.hasOwnProperty 'className'
            err = new Error "[#{id}] is not a class"
            err.code = 'FIELDS'
            throw err

        connector = @options.connector

        column = @_getColumn id
        propDef = @manager.getDefinition info.className
        idColumn = @options.escapeId propDef.id.column
        table = propDef.table
        tableAlias = @_uniqTabAlias()
        select = @select

        if parentInfo
            parentDef = @manager.getDefinition parentInfo.className
            if parentDef.properties.hasOwnProperty(info.attribute) and not parentDef.properties[info.attribute].nullable and parentInfo.hasJoin is JOIN_FUNC.default
                hasJoin = JOIN_FUNC.default

        if typeof hasJoin is 'undefined'
            hasJoin = JOIN_FUNC.left

        select[hasJoin] @options.escapeId(table), tableAlias, @options.escapeId(tableAlias) + '.' + idColumn + ' = ' + column

        @_tables[id] = tableAlias
        @_set info, 'hasJoin', hasJoin
        # info.hasJoin = true
        return

    _getPropAncestors: (id)->
        ancestors = id.split STATIC.PROP_SEP
        prop = ancestors.pop()
        return [prop, ancestors]

    _updateInfos: ->
        for id, info of @_infos
            [prop, ancestors] = @_getPropAncestors id
            @_updateInfo info, prop, ancestors if ancestors.length > 0
        return

    _updateInfo: (info, prop, ancestors)->
        return if info.asIs

        parentInfo = @_getInfo @_getUniqueId null, ancestors
        definition = @manager.getDefinition parentInfo.className
        availableProperty = definition.availableProperties[prop]
        if 'undefined' is typeof availableProperty
            throw new Error "Property '#{prop}' is not defined for class '#{parentInfo.className}'"
        propDef = availableProperty.definition

        if propDef.hasOwnProperty('className') and propDef isnt definition.id
            @_set info, 'className', propDef.className

        if propDef.hasOwnProperty('handlers') and propDef.handlers.hasOwnProperty 'read'
            @_set info, 'read', propDef.handlers.read

        # if _.isObject(overrides = @options.overrides) and _.isObject(overrides = overrides[definition.className]) and _.isObject(overrides = overrides.properties) and _.isObject(overrides = overrides[prop]) and _.isObject(handlers = overrides.handlers) and 'function' is typeof handlers.read
        #     @_set info, 'read', handlers.read

        return

    # Is called step by step .i.e. parent is supposed to be defined
    _getSetInfo: (id, asIs)->
        info = @_getInfo id
        return info if info

        [prop, ancestors] = @_getPropAncestors id

        return @_setInfo id, attribute: prop, asIs: asIs if asIs

        # info = _.extend {attribute: prop}, extra
        info = attribute: prop
        @_updateInfo info, prop, ancestors
        @_setInfo id, info

    # Get parent prop column alias, mixins join
    # Must be called step by step
    _getColumn: (id)->
        info = @_getInfo id
        return info.column if info.hasOwnProperty 'column'

        [prop, ancestors] = @_getPropAncestors id

        parentId = @_getUniqueId null, ancestors
        availableProperty = @_getAvailableProperty prop, ancestors, id
        connector = @options.connector
        select = @select
        tableAlias = @_tables[parentId]

        if availableProperty.mixin
            parentInfo = @_getInfo parentId
            if parentInfo.hasJoin is JOIN_FUNC.left
                joinFunc = JOIN_FUNC.left
            else
                joinFunc = JOIN_FUNC.default

        # join while mixin prop
        while mixin = availableProperty.mixin
            className = mixin.className
            mixinDef = @manager.getDefinition className
            mixinId = parentId + STATIC.PROP_SEP + className

            # check if it has already been joined
            # join mixin only once even if multiple field of this mixin
            if typeof @_mixins[mixinId] is 'undefined'
                idColumn = @options.escapeId mixinDef.id.column
                joinColumn = @options.escapeId(tableAlias) + '.' + @options.escapeId(mixin.column)
                table = mixinDef.table
                tableAlias = @_uniqTabAlias()
                select[joinFunc] @options.escapeId(table), tableAlias, @options.escapeId(tableAlias) + '.' + idColumn + ' = ' + joinColumn
                @_mixins[mixinId] = tableAlias: tableAlias
            else
                tableAlias = @_mixins[mixinId].tableAlias

            availableProperty = mixinDef.availableProperties[prop]

        propDef = availableProperty.definition

        @_set info, 'column', @options.escapeId(tableAlias) + '.' + @options.escapeId(propDef.column)
        # info.column = @options.escapeId(tableAlias) + '.' + @options.escapeId(propDef.column)

        info.column

    # Return the model initialized using row,
    initModel: (row, model, tasks = [])->
        if not model
            model = @_create()

        id = @_getUniqueId()
        info = @_getInfo id

        # init prop model with this row
        for prop of info.properties
            @_initValue prop, row, model, tasks

        return model

    # prop: full info name
    _initValue: (id, row, model, tasks)->
        info = @_getInfo id

        value = row[info.field]
        prop = info.attribute

        # if value is null, no futher processing is needed
        # if Property has no sub-elements, no futher processing is needed
        if value is null or not info.hasOwnProperty 'className'
            @_setValue model, prop, value, info
            return model

        propClassName = info.className
        childModel = @_getValue model, prop
        if childModel is null or 'object' isnt typeof childModel
            childModel = @_create propClassName
            @_setValue model, prop, childModel, info

        if info.hasOwnProperty 'hasJoin'
            # this row contains needed data
            # init prop model with this row
            for childProp of info.properties
                @_initValue childProp, row, childModel, tasks

            # id is null, it means that value is null
            childIdProp = @manager.getIdName propClassName
            if null is @_getValue childModel, childIdProp
                @_setValue model, prop, null, info
        else
            # a new request is needed to get properties value
            # that avoids stack overflow in case of "circular" reference with a property
            tasks.push
                className: propClassName
                options:
                    type: @options.type
                    models: [childModel]
                    # for nested element, value is the id
                    where: STATIC.FIELD_CHAR_BEGIN + @manager.getIdName(propClassName) + STATIC.FIELD_CHAR_END + ' = ' + value
                    # expect only one result. limit 2 is for unique checking without returning all rows
                    limit: 2

        return model

    _getUniqueId: (ancestors...)->
        if ancestors.length is 0
            return STATIC.ROOT

        res = []
        for ancestor in ancestors
            if typeof ancestor is 'string'
                res.unshift ancestor
            else if ancestor instanceof Array
                res.unshift ancestor.join STATIC.PROP_SEP
        return res.join STATIC.PROP_SEP

    _uniqTabAlias: ->
        tableAlias = 'TBL_' + @_tabId++
        # while @_tableAliases.hasOwnProperty tableAlias
        #     tableAlias = 'TBL_' + @_tabId++
        @_tableAliases[tableAlias] = true
        tableAlias

    _uniqColAlias: ->
        columnAlias = 'COL_' + @_colId++
        # while @_columnAliases.hasOwnProperty columnAlias
        #     columnAlias = 'COL_' + @_colId++
        @_columnAliases[columnAlias] = true
        columnAlias

    # for debugging purpose
    # allow to know where a property was setted
    _set: (obj, key, value)->
        obj[key] = value

    # Return info of a property
    # id: full property name
    _getInfo: (id)->
        @_infos[id]

    _setInfo: (id, extra)->
        info = @_infos[id]
        if info
            _.extend info, extra
        else
            @_infos[id] = extra

        @_infos[id]

    _getAvailableProperty: (prop, ancestors)->
        id = @_getUniqueId null, ancestors
        info = @_getInfo id

        definition = @manager.getDefinition info.className
        if prop
            definition.availableProperties[prop]
        else
            definition

    _getAncestors: (field, isFull)->
        if typeof field is 'string'
            if isFull
                ancestors = field.split STATIC.PROP_SEP
            else if /^[^,]+,[^,]+$/.test field
                field = field.split /\s*,\s*/
                ancestors = field[1].split STATIC.PROP_SEP
                ancestors.unshift field[0]
            else
                ancestors = field.split STATIC.PROP_SEP
                ancestors.unshift STATIC.ROOT
        else if not (field instanceof Array)
            err = new Error "Field '#{field}' is not an Array nor a string"
            err.code = 'FIELDS'
            throw err

        ancestors or []

    toQueryString: ->
        fieldHolderParser.replace @select.toString(), (field)=>
            @_getSetColumn field

    getTemplate: (force)->
        return @template if force isnt true and @template
        @template = placeHolderParser.unsafeCompile @toQueryString()
        # @template = placeHolderParser.safeCompile @toQueryString()

    # replace fields by corresponding column
    toString: ->
        @getTemplate() @values

_readFields = (values, select, block)->
    if values instanceof Array
        for value in values
            if Array.isArray value
                for val in value
                    _coerce.call @, val
            else
                _coerce.call @, value

        select[block].apply select, values
    else
        ret = _coerce.call @, values
        select[block] values

    ret or values

_coerce = (str)->
    if 'string' is typeof str
        return fieldHolderParser.replace str, (field)=>
            @_getSetColumn field
    else if _.isObject(str) and not Array.isArray str
        return fieldHolderParser.replace str.toString(), (field)=>
            @_getSetColumn field

    return str
        