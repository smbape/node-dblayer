log4js = global.log4js or (global.log4js = require 'log4js')
logger = log4js.getLogger 'CompiledMapping'
_ = require 'lodash'
LRU = require 'lru-cache'

isStringNotEmpty = (str)->
    typeof str is 'string' and str.length > 0

modelId = 0
class Model
    constructor: (attributes)->
        @cid = ++modelId
        if _.isPlainObject attributes
            @attributes = _.clone attributes
        else
            @attributes = {}
    clone: ->
        _clone = new @constructor()
        for own prop of @
            if prop isnt 'cid'
                _clone[prop] = _.clone @[prop]
        _clone
    set: (prop, value)->
        if _.isPlainObject prop
            for attr of prop
                @set attr, prop[attr]
            return @
        if prop is 'id'
            @id = value
        @attributes[prop] = value
        return @
    get: (prop)->
        @attributes[prop]
    unset: (prop)->
        delete @attributes[prop]
    toJSON: ->
        @attributes

specProperties = ['type', 'type_args', 'nullable', 'pk', 'fk']

module.exports = class CompiledMapping
    constructor: (mapping, options)->
        for prop in ['classes', 'resolved', 'unresolved', 'tables']
            @[prop] = {}

        @indexNames =
            pk: {}
            uk: {}
            fk: {}
            ix: {}

        # Resolve mapping
        for className of mapping
            _resolve className, mapping, @

        propToColumn = (prop)-> classDef.properties[prop].column

        for className, classDef of @classes
            # Set undefined column for className properties
            for prop, propDef of classDef.properties
                if propDef.hasOwnProperty('className')
                    parentDef = @_getDefinition propDef.className
                    _inheritType propDef, parentDef.id
                    if not propDef.hasOwnProperty('column')
                        propDef.column = parentDef.id.column
                @_addColumn className, propDef.column, prop

            # Set undefined fk for className properties
            for prop, propDef of classDef.properties
                if propDef.hasOwnProperty('className')
                    if not propDef.hasOwnProperty('fk')
                        parentDef = @_getDefinition propDef.className
                        fk = "#{classDef.table}_#{propDef.column}_HAS_#{parentDef.table}_#{parentDef.id.column}"
                        propDef.fk = fk
                    _addIndexName propDef.fk, 'fk', @

            # Set undefined constraint names
            {indexes, constraints: {unique, names}} = classDef
            for key, properties of unique
                classDef.hasUniqueConstraints = true
                if not names[key]
                    name = 'UK_' + properties.map(propToColumn).join('_')
                    _addIndexName name, 'uk', @
                    names[key] = name

        @resolved = true

    Model: Model
    specProperties: specProperties

    getConstructor: (className)->
        @assertClassHasMapping className
        @classes[className].ctor

    newInstance: (className, attributes)->
        @assertClassHasMapping className
        new @classes[className].ctor attributes

    getIdName: (className)->
        @assertClassHasMapping className
        @classes[className].id.name

    getDefinition: (className)->
        _.cloneDeep @_getDefinition className

    getMapping: ->
        _.cloneDeep @classes

    getTable: (className)->
        @_getDefinition(className).table

    getColumn: (className, prop)->
        definition = @_getDefinition className
        if definition.id.name is prop
            definition.id.column
        else if definition.properties.hasOwnProperty prop
            definition.properties[prop].column

    assertClassHasMapping: (className)->
        if not @classes.hasOwnProperty className
            err = new Error "No mapping were found for class '#{className}'"
            err.code = 'UNDEF_CLASS'
            throw err
        return

    _getDefinition: (className)->
        @assertClassHasMapping className
        @classes[className]

    _startResolving: (className)->
        @unresolved[className] = true

        classDef =
            className: className
            properties: {}
            availableProperties: {}
            columns: {}
            dependencies:
                resolved: {}
                mixins: []
            constraints:
                unique: {}
                names: {}
            indexes: {}
            cache: LRU(10)

        @classes[className] = classDef

    _markResolved: (className)->
        delete @unresolved[className]
        @resolved[className] = true
        return

    _hasResolved: (className)->
        @resolved.hasOwnProperty className

    _isResolving: (className)->
        @unresolved.hasOwnProperty className

    _hasTable: (table)->
        @tables.hasOwnProperty table

    _hasColumn: (className, column)->
        definition = @classes[className]
        definition.columns.hasOwnProperty column

    _getResolvedDependencies: (className)->
        definition = @classes[className]
        definition.dependencies.resolved

    _setResolvedDependency: (className, dependency)->
        definition = @classes[className]
        definition.dependencies.resolved[dependency] = true
        return

    _hasResolvedDependency: (className, dependency)->
        definition = @classes[className]
        definition.dependencies.resolved[dependency]

    _addTable: (className)->
        definition = @classes[className]
        if @_hasTable definition.table
            err = new Error "[#{definition.className}] table '#{definition.table}' already exists"
            err.code = 'DUP_TABLE'
            throw err
        @tables[definition.table] = true
        return

    _addColumn: (className, column, prop)->
        if @_hasColumn className, column
            err = new Error "[#{className}.#{prop}] column '#{column}' already exists"
            err.code = 'DUP_COLUMN'
            throw err

        definition = @classes[className]
        if isStringNotEmpty column
            definition.columns[column] = prop
        else
            err = new Error "[#{className}.#{prop}] column must be a not empty string"
            err.code = 'COLUMN'
            throw err
        return

    # Returns parents of added mixin if they exist in this mapping
    _addMixin: (className, mixin)->
        definition = @classes[className]
        mixins = definition.dependencies.mixins
        mixinClassName = mixin.className
        parents = []
        for index in [(mixins.length - 1)..0] by -1
            dependencyClassName = mixins[index].className
            if dependencyClassName is mixinClassName
                # if mixinClassName already exists
                return

            if @_hasResolvedDependency dependencyClassName, mixinClassName
                # if mixinClassName is a parent of another mixins dependencyClassName, ignore it
                # depending on child => depending on parent
                return

            if @_hasResolvedDependency mixinClassName, dependencyClassName
                # if mixinClassName is a child of another mixins dependencyClassName, mark it
                # it is not allowed to depend on parent and child, you must depend on child => parent
                parents.push dependencyClassName

        obj = className: mixinClassName
        if isStringNotEmpty mixin.column
            obj.column = mixin.column
        else
            obj.column = @classes[mixinClassName].id.column

        mixins.push obj
        parents

_resolve = (className, mapping, compiled)->
    if typeof className isnt 'string' or className.length is 0
        err = new Error 'class is undefined'
        err.code = 'UNDEF_CLASS'
        throw err

    return if compiled._hasResolved className

    rawDefinition = mapping[className]
    if not _.isPlainObject rawDefinition
        err = new Error "Class '#{className}' is undefined"
        err.code = 'UNDEF_CLASS'
        throw err

    # className is computed by reading given mapping and peeking relevant properties of given mapping
    # Peeking and not copying properties allows to have only what is needed and modify our ClassDefinition without
    # altering (corrupting) given rawDefinition

    # Mark this className as being resolved. For circular reference check
    classDef = compiled._startResolving className

    if not rawDefinition.hasOwnProperty 'table'
        # default table name is className
        classDef.table = className
    else if isStringNotEmpty rawDefinition.table
        classDef.table = rawDefinition.table
    else
        err = new Error "[#{classDef.className}] table is not a string"
        err.code = 'TABLE'
        throw err

    # check duplicate table and add
    compiled._addTable classDef.className

    if typeof rawDefinition.id is 'string'
        # id as string => name
        classDef.id = name: rawDefinition.id
    else if typeof rawDefinition.id isnt 'undefined' and not _.isPlainObject rawDefinition.id
        err = new Error "[#{classDef.className}] id property must be a not null plain object"
        err.code = 'ID'
        throw err

    if classDef.hasOwnProperty 'id'
        id = classDef.id
        isIdMandatory = true
    else if rawDefinition.hasOwnProperty 'id'
        id = rawDefinition.id
        isIdMandatory = true
    else
        isIdMandatory = false
        id = {}


    if not _.isPlainObject id
        err = new Error "[#{classDef.className}] id is not well defined. Expecting String|{name: String}|{className: String}. Given #{id}"
        err.code = 'ID'
        throw err

    _.defaults id, id.domain
    delete id.domain

    classDef.id = name: null
    if isStringNotEmpty id.column
        classDef.id.column = id.column

    if id.hasOwnProperty('name') and id.hasOwnProperty('className')
        err = new Error "[#{classDef.className}] name and className are mutally exclusive properties for id"
        err.code = 'INCOMP_ID'
        throw err

    if isStringNotEmpty id.name
        classDef.id.name = id.name
        if not id.hasOwnProperty 'column'
            # default id column is id name
            classDef.id.column = id.name
        else if not isStringNotEmpty id.column
            err = new Error "[#{classDef.className}] column must be a not empty string for id"
            err.code = 'ID_COLUMN'
            throw err

        compiled._addColumn className, classDef.id.column, classDef.id.name
    else if isStringNotEmpty id.className
        classDef.id.className = id.className
    else if isIdMandatory
        err = new Error "[#{classDef.className}] name xor className must be defined as a not empty string for id"
        err.code = 'ID'
        throw err

    # =============================================================================
    #  Properties checking
    # =============================================================================
    _addProperties compiled, classDef, rawDefinition.properties
    # =============================================================================
    #  Properties checking - End
    # =============================================================================

    # =============================================================================
    #  Mixins checking
    # =============================================================================
    _addMixins compiled, classDef, rawDefinition, id, mapping
    # =============================================================================
    #  Mixins checking - End
    # =============================================================================

    # =============================================================================
    #  Constraints checking
    # =============================================================================
    _addConstraints compiled, classDef, rawDefinition
    # =============================================================================
    #  Constraints checking - End
    # =============================================================================

    # =============================================================================
    #  Indexes checking
    # =============================================================================
    _addIndexes compiled, classDef, rawDefinition
    # =============================================================================
    #  Indexes checking - End
    # =============================================================================

    if typeof classDef.id.className is 'string'

        # single parent inheritence => name = parent name
        idClassDef = compiled.classes[classDef.id.className]
        classDef.id.name = idClassDef.id.name

        # single parent no column define => assume same column as parent
        if not classDef.id.hasOwnProperty 'column'
            classDef.id.column = idClassDef.id.column
            compiled._addColumn classDef.className, classDef.id.column, classDef.id.name

        _inheritType classDef.id, idClassDef.id

    # add id as an available property
    if typeof classDef.id.name is 'string'
        classDef.availableProperties[classDef.id.name] = definition: classDef.id

    _addSpecProperties classDef.id, id

    if not classDef.id.pk
        pk = classDef.table
        classDef.id.pk = pk
    _addIndexName classDef.id.pk, 'pk', compiled

    _setConstructor classDef, rawDefinition.ctor

    compiled._markResolved classDef.className
    return

_addProperties = (compiled, classDef, rawProperties)->
    return if not _.isPlainObject rawProperties
    constraints = classDef.constraints

    for prop, rawPropDef of rawProperties
        if typeof rawPropDef is 'string'
            rawPropDef = column: rawPropDef

        if not _.isPlainObject rawPropDef
            err = new Error "[#{classDef.className}] property '#{prop}' must be an object or a string"
            err.code = 'PROP'
            throw err

        _.defaults rawPropDef, rawPropDef.domain
        delete rawPropDef.domain

        classDef.properties[prop] = propDef = {}
        if isStringNotEmpty rawPropDef.column
            propDef.column = rawPropDef.column

        # add this property as available properties for this className
        # Purposes:
        #   - Fastly get property definition
        classDef.availableProperties[prop] = definition: propDef

        # composite element definition
        if rawPropDef.hasOwnProperty 'className'
            propDef.className = rawPropDef.className

        if rawPropDef.hasOwnProperty 'handlers'
            propDef.handlers = handlers = {}

            # insert: default value if undefined
            # update: automatic value on update, don't care about setted one
            # read: from database to value. Ex: SQL Format Date String -> Javascript Date, JSON String -> JSON Object
            # write: from value to database. Ex: Javascript Date -> SQL Format Date String, JSON Object -> JSON String
            for handlerType in ['insert', 'update', 'read', 'write']
                handler = rawPropDef.handlers[handlerType]
                if typeof handler is 'function'
                    handlers[handlerType] = handler

        # optimistic lock definition
        # update only values where lock is the same
        # with update handler, prevents concurrent update
        if rawPropDef.hasOwnProperty 'lock'
            propDef.lock = typeof rawPropDef.lock is 'boolean' and rawPropDef.lock

        _addSpecProperties propDef, rawPropDef, classDef

        if rawPropDef.unique
            propDef.unique = rawPropDef.unique
            _addUniqueConstraint propDef.unique, [prop], classDef, compiled

    return

_addMixins = (compiled, classDef, rawDefinition, id, mapping)->
    if not rawDefinition.hasOwnProperty 'mixins'
        mixins = []
    else if isStringNotEmpty(rawDefinition.mixins)
        mixins = [rawDefinition.mixins]
    else if Array.isArray(rawDefinition.mixins)
        mixins = rawDefinition.mixins[0..]
    else
        err = new Error "[#{classDef.className}] mixins property can only be a string or an array of strings"
        err.code = 'MIXINS'
        throw err

    classDef.mixins = []
    if isStringNotEmpty id.className
        mixins.unshift id
    seenMixins = {}

    for mixin in mixins
        if typeof mixin is 'string'
            mixin = className: mixin

        if not _.isPlainObject mixin
            err = new Error "[#{classDef.className}] mixin can only be a string or a not null object"
            err.code = 'MIXIN'
            throw err

        if not mixin.hasOwnProperty 'className'
            err = new Error "[#{classDef.className}] mixin has no className property"
            err.code = 'MIXIN'
            throw err

        className = mixin.className

        if seenMixins[className]
            err = new Error "[#{classDef.className}] mixin [#{mixin.className}]: duplicate mixin. Make sure it's not also and id className"
            err.code = 'DUP_MIXIN'
            throw err

        _.defaults mixin, mixin.domain
        delete mixin.domain

        seenMixins[className] = true
        _mixin = className: className
        if isStringNotEmpty mixin.column
            _mixin.column = mixin.column
        else if mixin.hasOwnProperty 'column'
            err = new Error "[#{classDef.className}] mixin [#{mixin.className}]: Column is not a string or is empty"
            err.code = 'MIXIN_COLUMN'
            throw err
        classDef.mixins.push _mixin

        if not compiled._hasResolved className
            if compiled._isResolving className
                err = new Error "[#{classDef.className}] mixin [#{mixin.className}]: Circular reference detected: -> '#{className}'"
                err.code = 'CIRCULAR_REF'
                throw err
            _resolve className, mapping, compiled

        # Mark this mixin as dependency resolved
        compiled._setResolvedDependency classDef.className, className

        # mixin default column if miin className id column
        if not _mixin.hasOwnProperty 'column'
            _mixin.column = compiled.classes[_mixin.className].id.column

        # id column of mixins that are not class parent have not been added as column,
        # add them to avoid duplicate columns
        if classDef.id.className isnt _mixin.className
            compiled._addColumn classDef.className, _mixin.column, compiled.classes[_mixin.className].id.name

        # Mark all resolved dependencies,
        # Used to check circular references and related mixin
        resolved = compiled._getResolvedDependencies className
        for className of resolved
            compiled._setResolvedDependency classDef.className, className

        # check related mixin
        parents = compiled._addMixin classDef.className, mixin
        if Array.isArray(parents) and parents.length > 0
            err = new Error "[#{classDef.className}] mixin '#{mixin}' depends on mixins #{parents}. Add only mixins with no relationship or you have a problem in your design"
            err.code = 'RELATED_MIXIN'
            err.extend = parents
            throw err

        # add this mixin available properties as available properties for this className
        # Purposes:
        #   - On read, to fastly check if join on this mixin is required
        mixinDef = compiled.classes[_mixin.className]
        _inheritType _mixin, mixinDef.id
        _addSpecProperties _mixin, mixin

        if not _mixin.fk
            fk = "#{classDef.table}_#{_mixin.column}_EXT_#{mixinDef.table}_#{mixinDef.id.column}"
            _mixin.fk = fk
        _addIndexName _mixin.fk, 'fk', compiled

        for prop of mixinDef.availableProperties
            if not classDef.availableProperties.hasOwnProperty prop
                classDef.availableProperties[prop] =
                    mixin: _mixin
                    definition: mixinDef.availableProperties[prop].definition

    return

_addConstraints = (compiled, classDef, rawDefinition)->
    constraints = classDef.constraints

    ERR_CODE = 'CONSTRAINT'

    rawConstraints = rawDefinition.constraints
    rawConstraints = [rawConstraints] if _.isPlainObject rawConstraints
    if not Array.isArray rawConstraints
        if rawConstraints
            err = new Error "[#{classDef.className}] constraints can only be a plain object or an array of plain objects"
            err.code = ERR_CODE
            throw err
        return

    for constraint, index in rawConstraints
        if not _.isPlainObject constraint
            err = new Error "[#{classDef.className}] constraint at index #{index} is not a plain object"
            err.code = ERR_CODE
            throw err

        if constraint.type isnt 'unique'
            err = new Error "[#{classDef.className}] constraint at index #{index} is not supported. Supported constraint type is 'unique'"
            err.code = ERR_CODE
            throw err

        properties = constraint.properties
        if isStringNotEmpty properties
            properties = [properties]

        if not Array.isArray properties
            err = new Error "[#{classDef.className}] constraint at index #{index}: properties must be a not empty string or an array of strings"
            err.code = ERR_CODE
            throw err

        for prop in properties
            if not classDef.properties.hasOwnProperty prop
                err = new Error "[#{classDef.className}] - constraint at index #{index}: class does not owned property '#{prop}'"
                err.code = ERR_CODE
                throw err

        if constraint.name and ('string' isnt typeof constraint.name or constraint.name.length is 0)
            err = new Error "[#{classDef.className}] constraint at index #{index}: Name must be a string"
            err.code = ERR_CODE
            throw err

        keys = properties[0..]
        if keys.length is 1
            prop = properties[0]
            propDef = classDef.properties[prop]
            propDef.unique = true

        _addUniqueConstraint constraint.name, keys, classDef, compiled

    return

_addIndexes = (compiled, classDef, rawDefinition)->
    indexes = classDef.indexes

    ERR_CODE = 'INDEX'

    rawIndexes = rawDefinition.indexes
    if not _.isPlainObject rawIndexes
        if rawIndexes
            err = new Error "[#{classDef.className}] indexes can only be a plain object"
            err.code = ERR_CODE
            throw err
        return

    constraints = classDef.constraints
    names = constraints.names
    for name, properties of rawIndexes
        if isStringNotEmpty(properties)
            properties = [properties]

        if not Array.isArray properties
            err = new Error "[#{classDef.className}] index '#{name}' is not an Array"
            err.code = ERR_CODE
            throw err

        for prop in properties
            if not classDef.properties.hasOwnProperty prop
                err = new Error "[#{classDef.className}] - index '#{name}': class does not owned property '#{prop}'"
                err.code = ERR_CODE
                throw err

        properties = properties[0..].sort()
        key = properties.join(':')

        if constraints.unique.hasOwnProperty(key)
            err = new Error "the unique constraint with name #{constraints.names[key]} matches #{key}. Only one index per set of properties is allowed"
            err.code = ERR_CODE
            throw err

        _addIndexName name, 'ix', compiled
        indexes[name] = properties

    return

_addUniqueConstraint = (name, properties, classDef, compiled)->
    properties.sort()
    key = properties.join(':')
    {constraints} = classDef
    if constraints.unique.hasOwnProperty(key)
        err = new Error "the unique constraint with name #{constraints.names[key]} matches #{key}. Only one index per set of properties is allowed"
        err.code = 'CONSTRAINT'
        throw err

    if name
        _addIndexName name, 'uk', compiled
        constraints.names[key] = name
    constraints.unique[key] = properties
    return

_addIndexName = (name, type, compiled)->
    if not isStringNotEmpty name
        err = new Error "a #{type} index must be a not empty string"
        err.code = 'INDEX'
        throw err

    indexNames = compiled.indexNames[type]
    if indexNames.hasOwnProperty name
        err = new Error "a #{type} index with name #{name} is already defined"
        err.code = 'INDEX'
        throw err

    indexNames[name] = true
    return

_inheritType = (child, parent)->
    {type, type_args} = parent
    if type and match = type.match(/^(?:(small|big)?(?:increments|serial)|serial([248]))$/)
        length = match[1] or match[2]
        switch length
            when 'big', '8'
                type = 'bigint'
            when 'small', '2'
                type = 'smallint'
            else
                type = 'integer'

    child.type = type if type
    child.type_args = type_args if type_args
    child

_addSpecProperties = (definition, rawDefinition)->
    for prop in specProperties
        if rawDefinition.hasOwnProperty prop
            value = rawDefinition[prop]
            switch prop
                when 'type'
                    value = value.toLowerCase()
                when 'type_args'
                    if value and not Array.isArray(value)
                        err = new Error "[#{definition.className}] - property '#{prop}': type_args must be an Array"
                        err.code = ERR_CODE
                        throw err
            definition[prop] = value
    return

_setConstructor = (classDef, Ctor)->
    if 'undefined' is typeof Ctor
        class Ctor extends Model
            className: classDef.className

    if typeof Ctor isnt 'function'
        err = new Error "[#{classDef.className}] given constructor is not a function"
        err.code = 'CTOR'
        throw err

    classDef.ctor = Ctor
    return
