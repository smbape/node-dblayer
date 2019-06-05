log4js = require './log4js'
logger = log4js.getLogger __filename.replace /^(?:.+[\/\\])?([^.\/\\]+)(?:.[^.]+)?$/, '$1'

_ = require 'lodash'
path = require 'path'
PlaceHolderParser = require './PlaceHolderParser'
squel = require 'squel'
{guessEscapeOpts} = require './tools'

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

_createModel = (className = this.className)->
    definition = this.manager.getDefinition className
    Ctor = definition.ctor
    new Ctor()
_setModelValue = (model, prop, value, propDef)->
    model.set prop, _handleRead value, model, propDef
_getModelValue = (model, prop)->
    model.get prop

_createPlainObject = ->
    {}
_setPlainObjectValue = (model, prop, value, propDef)->
    model[prop] = _handleRead value, model, propDef
_getPlainObjectValue = (model, prop)->
    model[prop]

# Private Class, supposed to be used in conjunction with PersistenceManager Class
module.exports = class RowMap

    # Class that do the mapping between className, queries to execute and properties of className
    constructor: (@className, @manager, options, skip)->
        this.options = guessEscapeOpts(options)
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

        this.select = options.select
        this.values = options.values
        delete this.options.select
        delete this.options.values

        this._initialize()
        this._initRootElement this.className, this._getUniqueId()

        this._processJoins()
        this._processFields()
        this._processColumns()
        this._processBlocks()

    setValues: (@values)->

    setValue: (key, value)->
        this.values[key] = value

    _initialize: ->
        options = this.options
        if options.type is 'json' or options.count
            this._setValue = _setPlainObjectValue
            this._getValue = _getPlainObjectValue
            this._create = _createPlainObject
        else
            this._setValue = _setModelValue
            this._getValue = _getModelValue
            this._create = _createModel

        return

    _initRootElement: (className, id, options = {})->
        if this._tables.hasOwnProperty id
            return

        if not className
            if not this.options.hasOwnProperty('join') or not this.options.join.hasOwnProperty id
                err = new Error "#{id} was not found in any join definitions"
                err.code = 'TABLE_UNDEF'
                throw err
            className = this.options.join[id].entity
            options = this.options.join[id]

        definition = this.manager.getDefinition className
        table = definition.table
        tableAlias = this._uniqTabAlias()

        select = this.select
        if options.hasOwnProperty 'condition'
            this._tables[id] = tableAlias
            this._infos[id] = className: className
            if this._joining.hasOwnProperty id
                err = new Error "#{id} has already been joined. Look at stack to find the circular reference"
                err.code = 'CIRCULAR_REF'
                throw err

            this._joining[id] = true

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

            select[hasJoin] this.options.escapeId(table), tableAlias, condition, type

            # make necessary joins
            # condition = _coerce.call @, options.condition

            delete this._joining[id]
            this._infos[id].hasJoin = hasJoin
        else if _.isEmpty this._tables
            select.from this.options.escapeId(table), tableAlias
            this._tables[id] = tableAlias
            this._infos[id] =
                className: className
                hasJoin: JOIN_FUNC.default
            this._rootInfo = this._infos[id]
        else
            err = new Error "#{id} has no joining condition"
            err.code = 'JOIN_COND'
            throw err

        return

    _processJoins: ->
        join = this.options.join
        if _.isEmpty join
            return
        for alias, joinDef of join
            this._initRootElement joinDef.entity, alias, joinDef
            fields = this._sanitizeFields joinDef.fields
            if fields.length > 0
                this._rootInfo.properties = this._rootInfo.properties or {}
                this._rootInfo.properties[alias] = true
                this._infos[alias].attribute = alias

                if not this.options.count
                    for field in fields
                        this._setField this._getUniqueId(field, alias), true
        return

    _processFields: ->
        if this.options.count
            this._selectCount()
            return

        fields = this._sanitizeFields this.options.fields, ['*']
        for field in fields
            this._setField field

        return

    _processColumns: ->
        columns = this.options.columns
        if _.isEmpty columns
            return

        for prop, field of columns
            this._selectCustomField prop, field

        return

    _processBlocks: ->
        select = this.select

        for block in ['where', 'group', 'having', 'order', 'limit', 'offset']
            option = this.options[block]

            if  /^(?:string|boolean|number)$/.test typeof option
                option = [option]
            else if _.isEmpty option
                continue

            if not (option instanceof Array)
                err = new Error "[#{this.className}]: #{block} can only be a string or an array"
                err.code = block.toUpperCase()
                throw err

            if block is 'limit' and option[0] < 0
                continue

            for opt in option
                _readFields.call @, opt, select, block

        if this.options.distinct
            select.distinct()

        return

    _getSetColumn: (field)->
        allAncestors = this._getAncestors field
        ancestors = []

        for prop, index in allAncestors
            ancestors.push prop
            if index is 0
                this._initRootElement null, prop
                continue

            id = this._getUniqueId null, ancestors
            this._getSetInfo id

            if index is allAncestors.length - 1
                continue

            parentInfo = info
            this._joinProp id, parentInfo
            info = this._getInfo id
            if info.hasOwnProperty('properties') and not info.setted
                for prop of info.properties
                    this._setField prop, true
                info.setted = true
        this._getColumn id

    _sanitizeFields: (fields, defaultValue)->
        if typeof fields is 'undefined'
            fields = defaultValue or []

        if typeof fields is 'string'
            fields = [fields]

        if not (fields instanceof Array)
            err = new Error "[#{this.className}]: fields can only be a string or an array"
            err.code = 'FIELDS'
            throw err

        if fields.length is 0
            return []

        return fields

    # field: full field name
    _setField: (field, isFull)->
        allAncestors = this._getAncestors field, isFull
        ancestors = []

        for prop, index in allAncestors
            if index is allAncestors.length - 1
                this._selectProp prop, ancestors
                continue

            parentInfo = info
            ancestors.push prop
            id = this._getUniqueId null, ancestors
            info = this._getSetInfo id
            if parentInfo
                parentInfo.properties = parentInfo.properties or {}
                this._set parentInfo.properties, id, true

            this._joinProp id, parentInfo

        return

    _selectCount: ->
        this._selectCustomField 'count',
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

        id = this._getUniqueId prop, ancestors
        info = this._getSetInfo id, true

        this._set info, 'read', handlerRead if 'function' is typeof handlerRead

        if info.hasOwnProperty 'field'
            # this property has already been selected
            return

        columnAlias = this._uniqColAlias()
        column = _coerce.call @, column
        this.select.field column, columnAlias

        # map columnAlias to prop
        this._set info, 'field', columnAlias

        parentInfo = this._getInfo this._getUniqueId null, ancestors
        parentInfo.properties = parentInfo.properties or {}

        # mark current prop as field of parent prop
        this._set parentInfo.properties, id, true
        return

    # set column alias as field of prop
    # must be called step by step
    _selectProp: (prop, ancestors)->
        parentId = this._getUniqueId null, ancestors
        parentInfo = this._getInfo parentId
        parentDef = this.manager.getDefinition parentInfo.className

        if prop is '*'
            if this.options.depth < ancestors.length
                logger.warn 'max depth reached'
                return
            this._set parentInfo, 'selectAll', true
            for prop of parentDef.availableProperties
                this._setField this._getUniqueId(prop, ancestors), true
            return

        id = this._getUniqueId prop, ancestors
        info = this._getSetInfo id

        if info.hasOwnProperty 'field'
            # this property has already been selected
            return

        column = this._getColumn id
        columnAlias = this._uniqColAlias()
        this.select.field column, columnAlias #, ignorePeriodsForFieldNameQuotes: true
        this._set info, 'field', columnAlias
        parentInfo = this._getInfo this._getUniqueId null, ancestors
        parentInfo.properties = parentInfo.properties or {}
        this._set parentInfo.properties, id, true
        this._set info, 'selectAll', parentInfo.selectAll

        if info.selectAll and info.hasOwnProperty('className') and not info.hasOwnProperty 'selectedAll'
            if parentDef.availableProperties[prop].definition.nullable is false
                isNullable = false
                ancestors = ancestors.concat([prop])
            else
                isNullable = true

            parentProp = prop
            properties = this.manager.getDefinition(info.className).availableProperties
            info.properties = {}
            for prop of properties
                if isNullable
                    this._set info.properties, this._getUniqueId(prop, parentProp, ancestors), true
                else
                    # not nullable => select all fields
                    this._setField this._getUniqueId(prop, ancestors), true
            this._set info, 'selectedAll', true
        return

    # Is called step by step .i.e. parent is supposed to be defined
    _joinProp: (id, parentInfo)->
        info = this._getInfo id

        if info.hasOwnProperty 'hasJoin'
            return

        if not info.hasOwnProperty 'className'
            err = new Error "[#{id}] is not a class"
            err.code = 'FIELDS'
            throw err

        connector = this.options.connector

        column = this._getColumn id
        propDef = this.manager.getDefinition info.className
        idColumn = this.options.escapeId propDef.id.column
        table = propDef.table
        tableAlias = this._uniqTabAlias()
        select = this.select

        if parentInfo
            parentDef = this.manager.getDefinition parentInfo.className
            prop = info.attribute
            if (parentDef.availableProperties[prop].definition.nullable is false) and parentInfo.hasJoin is JOIN_FUNC.default
                hasJoin = JOIN_FUNC.default

        if typeof hasJoin is 'undefined'
            hasJoin = JOIN_FUNC.left

        select[hasJoin] this.options.escapeId(table), tableAlias, this.options.escapeId(tableAlias) + '.' + idColumn + ' = ' + column

        this._tables[id] = tableAlias
        this._set info, 'hasJoin', hasJoin
        # info.hasJoin = true
        return

    _getPropAncestors: (id)->
        ancestors = id.split STATIC.PROP_SEP
        prop = ancestors.pop()
        return [prop, ancestors]

    _updateInfos: ->
        for id, info of this._infos
            [prop, ancestors] = this._getPropAncestors id
            this._updateInfo info, prop, ancestors if ancestors.length > 0
        return

    _updateInfo: (info, prop, ancestors)->
        return if info.asIs

        parentInfo = this._getInfo this._getUniqueId null, ancestors
        definition = this.manager.getDefinition parentInfo.className
        availableProperty = definition.availableProperties[prop]
        if 'undefined' is typeof availableProperty
            throw new Error "Property '#{prop}' is not defined for class '#{parentInfo.className}'"
        propDef = availableProperty.definition

        if propDef.hasOwnProperty('className') and propDef isnt definition.id
            this._set info, 'className', propDef.className

        if propDef.hasOwnProperty('handlers') and propDef.handlers.hasOwnProperty 'read'
            this._set info, 'read', propDef.handlers.read

        # if _.isObject(overrides = this.options.overrides) and _.isObject(overrides = overrides[definition.className]) and _.isObject(overrides = overrides.properties) and _.isObject(overrides = overrides[prop]) and _.isObject(handlers = overrides.handlers) and 'function' is typeof handlers.read
        #     this._set info, 'read', handlers.read

        return

    # Is called step by step .i.e. parent is supposed to be defined
    _getSetInfo: (id, asIs)->
        info = this._getInfo id
        return info if info

        [prop, ancestors] = this._getPropAncestors id

        return this._setInfo id, attribute: prop, asIs: asIs if asIs

        # info = _.extend {attribute: prop}, extra
        info = attribute: prop
        this._updateInfo info, prop, ancestors
        this._setInfo id, info

    # Get parent prop column alias, mixins join
    # Must be called step by step
    _getColumn: (id)->
        info = this._getInfo id
        return info.column if info.hasOwnProperty 'column'

        [prop, ancestors] = this._getPropAncestors id

        parentId = this._getUniqueId null, ancestors
        availableProperty = this._getAvailableProperty prop, ancestors, id
        connector = this.options.connector
        select = this.select
        tableAlias = this._tables[parentId]

        if availableProperty.mixin
            parentInfo = this._getInfo parentId
            if parentInfo.hasJoin is JOIN_FUNC.left
                joinFunc = JOIN_FUNC.left
            else
                joinFunc = JOIN_FUNC.default

        # join while mixin prop
        while mixin = availableProperty.mixin
            className = mixin.className
            mixinDef = this.manager.getDefinition className
            mixinId = parentId + STATIC.PROP_SEP + className

            # check if it has already been joined
            # join mixin only once even if multiple field of this mixin
            if typeof this._mixins[mixinId] is 'undefined'
                idColumn = this.options.escapeId mixinDef.id.column
                joinColumn = this.options.escapeId(tableAlias) + '.' + this.options.escapeId(mixin.column)
                table = mixinDef.table
                tableAlias = this._uniqTabAlias()
                select[joinFunc] this.options.escapeId(table), tableAlias, this.options.escapeId(tableAlias) + '.' + idColumn + ' = ' + joinColumn
                this._mixins[mixinId] = tableAlias: tableAlias
            else
                tableAlias = this._mixins[mixinId].tableAlias

            availableProperty = mixinDef.availableProperties[prop]

        propDef = availableProperty.definition

        this._set info, 'column', this.options.escapeId(tableAlias) + '.' + this.options.escapeId(propDef.column)
        # info.column = this.options.escapeId(tableAlias) + '.' + this.options.escapeId(propDef.column)

        info.column

    # Return the model initialized using row,
    initModel: (row, model, tasks = [])->
        if not model
            model = this._create()

        id = this._getUniqueId()
        info = this._getInfo id

        # init prop model with this row
        for prop of info.properties
            this._initValue prop, row, model, tasks

        return model

    # prop: full info name
    _initValue: (id, row, model, tasks)->
        info = this._getInfo id

        value = row[info.field]
        prop = info.attribute

        # if value is null, no futher processing is needed
        # if Property has no sub-elements, no futher processing is needed
        if value is null or not info.hasOwnProperty 'className'
            this._setValue model, prop, value, info
            return model

        propClassName = info.className
        childModel = this._getValue model, prop
        if childModel is null or 'object' isnt typeof childModel
            childModel = this._create propClassName
            this._setValue model, prop, childModel, info

        if info.hasOwnProperty 'hasJoin'
            # this row contains needed data
            # init prop model with this row
            for childProp of info.properties
                this._initValue childProp, row, childModel, tasks

            # id is null, it means that value is null
            childIdProp = this.manager.getIdName propClassName
            if null is this._getValue childModel, childIdProp
                this._setValue model, prop, null, info
        else
            # a new request is needed to get properties value
            # that avoids stack overflow in case of "circular" reference with a property
            tasks.push
                className: propClassName
                options:
                    type: this.options.type
                    models: [childModel]
                    # for nested element, value is the id
                    where: STATIC.FIELD_CHAR_BEGIN + this.manager.getIdName(propClassName) + STATIC.FIELD_CHAR_END + ' = ' + value
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
        tableAlias = 'TBL_' + this._tabId++
        # while this._tableAliases.hasOwnProperty tableAlias
        #     tableAlias = 'TBL_' + this._tabId++
        this._tableAliases[tableAlias] = true
        tableAlias

    _uniqColAlias: ->
        columnAlias = 'COL_' + this._colId++
        # while this._columnAliases.hasOwnProperty columnAlias
        #     columnAlias = 'COL_' + this._colId++
        this._columnAliases[columnAlias] = true
        columnAlias

    # for debugging purpose
    # allow to know where a property was setted
    _set: (obj, key, value)->
        obj[key] = value

    # Return info of a property
    # id: full property name
    _getInfo: (id)->
        this._infos[id]

    _setInfo: (id, extra)->
        info = this._infos[id]
        if info
            _.extend info, extra
        else
            this._infos[id] = extra

        this._infos[id]

    _getAvailableProperty: (prop, ancestors)->
        id = this._getUniqueId null, ancestors
        info = this._getInfo id

        definition = this.manager.getDefinition info.className
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
        fieldHolderParser.replace this.select.toString(), (field)=>
            this._getSetColumn field

    getTemplate: (force)->
        return this.template if force isnt true and this.template
        this.template = placeHolderParser.unsafeCompile this.toQueryString()
        # this.template = placeHolderParser.safeCompile this.toQueryString()

    # replace fields by corresponding column
    toString: ->
        this.getTemplate() this.values

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
            this._getSetColumn field
    else if _.isObject(str) and not Array.isArray str
        return fieldHolderParser.replace str.toString(), (field)=>
            this._getSetColumn field

    return str
        