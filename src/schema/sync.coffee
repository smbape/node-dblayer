_ = require 'lodash'
# tools = require '../tools'

# PersistenceManager sync method
exports.sync = (connector, options, callback)->
    newModel = @getDatabaseModel()
    dialect = connector.getDialect()
    sync = require('../dialects/' + dialect + '/sync')

    sync.getModel connector, (err, oldModel)->
        return callback(err) if err
        try
            SchemaCompiler = require('../dialects/' + dialect + '/SchemaCompiler')
            schema = new SchemaCompiler options
            queries = _sync oldModel, newModel, schema, options
        catch err
            callback(err)
            return

        {drop_constraints, drops, creates, alters} = queries
        queries = drop_constraints.concat(drops).concat(creates).concat(alters).join(';\n')
        if options.exec and queries.length > 0
            connector.exec (queries + ';'), options, (err)->
                callback err, queries, oldModel, newModel
                return
            return

        callback err, queries, oldModel, newModel
        return

_sync = (oldModel, newModel, schema, options)->
    newModel = _.clone newModel
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
            {alters, drops} = _tableDiff oldTable, newModel[tableName], opts
            delete newModel[tableName]
            queries.alters.push.apply queries.alters, alters
            queries.drops.push.apply queries.drops, drops
        else if purge
            # drop foreign keys
            if (keys = oldTable.constraints['FOREIGN KEY']) and not _.isEmpty(keys)
                for fkName of keys
                    queries.drop_constraints.push schema.dropForeignKey(tableName, fkName, options)

            # drop unique indexes
            if (keys = oldTable.constraints.UNIQUE) and not _.isEmpty(keys)
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

_tableDiff = (oldTable, newTable, options = {})->
    # console.log require('util').inspect(oldTable, {colors: true, depth: null})
    # console.log require('util').inspect(newTable, {colors: true, depth: null})

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
    if (indexes = oldTable.constraints.UNIQUE) and not _.isEmpty(indexes)
        oldIndexes = _flipIndex indexes, adapter

    if (indexes = newTable.constraints.UNIQUE) and not _.isEmpty(indexes)
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
    columns.sort().map(adapter.escapeId).join(':')
