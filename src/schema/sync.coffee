_ = require 'lodash'
# tools = require '../tools'

# PersistenceManager sync method
exports.sync = (connector, options, callback)->
    pMgr = @
    dialect = connector.getDialect()
    sync = require('../dialects/' + dialect + '/sync')

    sync.getModel connector, (err, oldModel)->
        return callback(err) if err
        schema = require('../dialects/' + dialect + '/schema')
        try
            queries = _sync pMgr, schema, oldModel, options
            console.log queries.drop_constraints.join(';\n'), ';\n'
            console.log queries.drops.join(';\n'), ';\n'
            console.log queries.creates.join('\n'), ';\n'
            console.log queries.alters.join(';\n')
            # console.log '\n'
            callback null, queries
        catch err
            callback(err)
        
        return

_sync = (pMgr, schema, oldModel, options)->
    newModel = {}

    propToColumn = (prop)-> definition.properties[prop].column

    for className, definition of pMgr.classes
        tableName = definition.table
        table = newModel[tableName] =
            name: tableName
            columns: {}
            constraints:
                'PRIMARY KEY': {}
                'FOREIGN KEY': {}
                'UNIQUE': {}
            indexes: {}

        if definition.id and definition.id.column
            primaryKey = 'PK_' + (definition.id.pk or tableName)
            table.constraints['PRIMARY KEY'][primaryKey] = [definition.id.column]
            column = table.columns[definition.id.column] = _.pick definition.id, pMgr.specProperties
            if not column.type
                throw new Error "[#{className}] No type has been defined for id"

            column.nullable = false
            # a primary key implies unique index and not null
            # indexKey = tableName + '_PK'
            # table.constraints['UNIQUE'][indexKey] = [definition.id.column]

            if definition.id.className
                parentDef = pMgr._getDefinition definition.id.className
                _addOneNRelation 'EXT', table, definition.id, parentDef, {index: false}

        if _.isEmpty table.constraints['PRIMARY KEY']
            delete table.constraints['PRIMARY KEY']

        for mixin, index in definition.mixins
            if mixin.column is definition.id.column
                continue

            parentDef = pMgr._getDefinition mixin.className

            column = table.columns[mixin.column] = _.pick mixin, pMgr.specProperties
            if not column.type
                throw new Error "[#{className}] No type has been defined for mixin #{mixin.className}"

            column.nullable = false
            [foreignKey, indexKey] = _addOneNRelation 'EXT', table, mixin, parentDef, {index: false}

            # enforce unique key
            table.constraints['UNIQUE'][indexKey] = [mixin.column]

        for prop, propDef of definition.properties
            column = table.columns[propDef.column] = _.pick propDef, pMgr.specProperties
            if not column.type
                throw new Error "[#{className}] No type has been defined for property #{prop}"

            if propDef.className
                parentDef = pMgr._getDefinition propDef.className
                _addOneNRelation 'HAS', table, propDef, parentDef

        if _.isEmpty table.constraints['FOREIGN KEY']
            delete table.constraints['FOREIGN KEY']

        {unique, names} = definition.constraints
        for key, properties of unique
            name = 'UK_' + names[key]
            table.constraints['UNIQUE'][name] = properties.map propToColumn

        if _.isEmpty table.constraints['UNIQUE']
            delete table.constraints['UNIQUE']

        for name, properties in definition.indexes
            table.indexes[name] = properties.map propToColumn

    queries =
        creates: []
        alters: []
        drops: []
        drop_constraints: []

    opts = _.defaults {schema}, options
    {purge} = options

    for tableName, oldTable of oldModel
        # if tableName isnt 'CLASS_D'
        #     continue
        if newModel.hasOwnProperty(tableName)
            {creates, alters, drops} = _tableDiff oldTable, newModel[tableName], opts
            delete newModel[tableName]
            queries.creates.push.apply queries.creates, creates
            queries.alters.push.apply queries.alters, alters
            queries.drops.push.apply queries.drops, drops
        else if purge
            # drop foreign keys
            if (keys = oldTable.constraints['FOREIGN KEY']) and not _.isEmpty(keys)
                for fkName of keys
                    queries.drop_constraints.push schema.dropForeignKey(tableName, fkName, options)

            # drop unique indexes
            if (keys = oldTable.constraints['UNIQUE']) and not _.isEmpty(keys)
                for indexName of keys
                    queries.drop_constraints.push schema.dropUniqueIndex(tableName, indexName, options)

            # drop indexes
            if not _.isEmpty(oldTable.indexes)
                for indexName of oldTable.indexes
                    queries.drop_constraints.push schema.dropIndex(tableName, indexName, options)

            # drop table
            queries.drops.push schema.dropTable(tableName, options)

    for tableName of newModel
        # if tableName isnt 'CLASS_D'
        #     continue
        {create, alter} = schema.createTable(newModel[tableName], opts)
        queries.creates.push create
        queries.alters.push alter

    return queries

_addOneNRelation = (name, table, propDef, parentDef, options = {})->
    keyName = propDef.fk or "#{table.name}_#{propDef.column}_#{name}_#{parentDef.table}_#{parentDef.id.column}"

    foreignKey = "FK_#{keyName}"
    table.constraints['FOREIGN KEY'][foreignKey] =
        column: propDef.column
        references_table: parentDef.table
        references_column: parentDef.id.column
        update_rule: 'RESTRICT'
        delete_rule: 'RESTRICT'

    indexKey = "#{keyName}_FK"
    if ! propDef.unique and options.index isnt false
        table.indexes[indexKey] = [propDef.column]

    [foreignKey, indexKey]

_tableDiff = (oldTable, newTable, options = {})->
    # console.log require('util').inspect(oldTable, {colors: true, depth: null})
    # console.log require('util').inspect(newTable, {colors: true, depth: null})

    oldTable = _.cloneDeep oldTable
    newTable = _.cloneDeep newTable
    {schema, renames, queries, purge} = options
    {adapter} = schema

    tableName = newTable.name
    drops = []
    alters = []

    for column, oldSpec of oldTable.columns
        if renames and renames.hasOwnProperty(column)
            newName = renames[column]
            if newName and newTable.columns.hasOwnProperty(newName)
                newSpec = newTable.columns[newName]
                delete newTable.columns[newName]
                alter = schema.diffType(tableName, column, oldSpec, newSpec, options)
                if alter
                    alters.push alter
                else
                    alters.push schema.renameColumn(tableName, column, newName, options)
            else if purge
                drops.push schema.dropColumn tableName, column, options
        else if newTable.columns.hasOwnProperty column
            newSpec = newTable.columns[column]
            delete newTable.columns[column]
            alter = schema.diffType(tableName, column, oldSpec, newSpec, options)
            if alter
                alters.push alter
        else if purge
            drops.push schema.dropColumn(tableName, column, options)

    for column, newSpec of newTable.columns
        alters.push schema.addColumn(tableName, column, newSpec, options)

    # primary key
    if (pk = oldTable.constraints['PRIMARY KEY']) and not _.isEmpty(pk)
        count = 0
        for pkName, columns of pk
            if ++count is 2
                throw new Error "#{tableName} oldTable has more than one primary key"
            oldPkName = pkName
            oldColumns = columns
            oldJoinedColumns = columns.sort().map(adapter.escapeId).join(', ')

    if (pk = newTable.constraints['PRIMARY KEY']) and not _.isEmpty(pk)
        count = 0
        for pkName, columns of pk
            if ++count is 2
                throw new Error "#{tableName} newTable has more than one primary key"
            newPkName = pkName
            newColumns = columns
            newJoinedColumns = columns.sort().map(adapter.escapeId).join(', ')

    if oldJoinedColumns isnt newJoinedColumns
        if not newJoinedColumns
            if purge
                alters.push schema.dropPrimaryKey(tableName, oldPkName, options)
        else if oldJoinedColumns
            alters.push schema.dropPrimaryKey(tableName, oldPkName, options)
            alters.push schema.addPrimaryKey(tableName, newPkName, newColumns, options)
        else
            alters.push schema.addPrimaryKey(tableName, newPkName, newColumns, options)
    else if oldPkName isnt newPkName
        alters.push schema.renamePrimaryKey(tableName, oldPkName, newPkName, options)

    # foreign keys
    if (keys = oldTable.constraints['FOREIGN KEY']) and not _.isEmpty(keys)
        oldKeys = _flipForeignKeys keys

    if (keys = newTable.constraints['FOREIGN KEY']) and not _.isEmpty(keys)
        newKeys = _flipForeignKeys keys

    for column, oldKey of oldKeys
        if newKeys and newKeys.hasOwnProperty(column)
            newKey = newKeys[column]
            delete newKeys[column]
            if oldKey.references_table isnt newKey.references_table or oldKey.references_column isnt newKey.references_column
                alters.push schema.dropForeignKey(tableName, oldKey.name, options)
                alters.push schema.addForeignKey(tableName, newKey, options)
            else if oldKey.name isnt newKey.name
                alters.push schema.renameForeignKey(tableName, oldKey.name, newKey.name, options)
        else if purge
            alters.push schema.dropForeignKey(tableName, oldKey.name, options)

    if newKeys
        for column, newKey of newKeys
            alters.push schema.addForeignKey(tableName, newKey, options)

    # unique indexes
    if (indexes = oldTable.constraints['UNIQUE']) and not _.isEmpty(indexes)
        oldIndexes = _flipIndex indexes, adapter

    if (indexes = newTable.constraints['UNIQUE']) and not _.isEmpty(indexes)
        newIndexes = _flipIndex indexes, adapter

    for id, oldIndex of oldIndexes
        if newIndexes and newIndexes.hasOwnProperty(id)
            newIndex = newIndexes[id]
            delete newIndexes[id]
            if oldIndex.name isnt newIndex.name
                alters.push schema.renameUniqueIndex(tableName, oldIndex.name, newIndex.name, options)
        else if purge
            alters.push schema.dropUniqueIndex(tableName, oldIndex.name, options)

    if newIndexes
        for id, newIndex of newIndexes
            alters.push schema.addUniqueIndex(tableName, newIndex.name, newIndex.columns, options)

    oldIndexes = newIndexes = undefined

    # indexes
    if (indexes = oldTable.indexes) and not _.isEmpty(indexes)
        oldIndexes = _flipIndex indexes, adapter

    if (indexes = newTable.indexes) and not _.isEmpty(indexes)
        newIndexes = _flipIndex indexes, adapter

    for id, oldIndex of oldIndexes
        if newIndexes and newIndexes.hasOwnProperty(id)
            newIndex = newIndexes[id]
            delete newIndexes[id]
            if oldIndex.name isnt newIndex.name
                alters.push schema.renameIndex(tableName, oldIndex.name, newIndex.name, options)
        else if purge
            alters.push schema.dropIndex(tableName, oldIndex.name, options)

    if newIndexes
        for id, newIndex of newIndexes
            alters.push schema.addIndex(tableName, newIndex.name, newIndex.columns, options)

    {alters, drops}

_flipForeignKeys = (keys)->
    flip = {}
    for name, fk of keys
        fk.name = name
        flip[fk.column] = fk
    flip

_flipIndex = (keys, adapter)->
    flip = {}
    for name, columns of keys
        flip[_getIndexUniquId(columns, adapter)] = {name, columns}
    flip

_getIndexUniquId = (columns, adapter)->
    columns.map(adapter.escapeId).join(':')
