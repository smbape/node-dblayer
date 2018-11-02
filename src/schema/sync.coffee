clone = require('lodash/clone')
cloneDeep = require('lodash/cloneDeep')
defaults = require('lodash/defaults')
isEmpty = require('lodash/isEmpty')
{guessEscapeOpts} = require '../tools'

# PersistenceManager sync method
exports.sync = (options, callback)->
    if 'function' is typeof options
        callback = options
        options = null

    options = guessEscapeOpts(options, @defaults.sync)
    {connector, dialect} = options

    sync = require('../dialects/' + dialect + '/sync')
    SchemaCompiler = require('../dialects/' + dialect + '/SchemaCompiler')
    schema = new SchemaCompiler options
    newModel = schema.getDatabaseModel(@, options)

    sync.getModel connector, (err, oldModel, oldOpts)->
        return callback(err) if err
        options = Object.assign({}, options, oldOpts)
        try
            queries = _sync oldModel, newModel, schema, options
        catch err
            callback(err)
            return

        queries.options = options

        if options.exec
            {drop_constraints, drops, creates, alters} = queries
            query = drop_constraints.concat(drops).concat(creates).concat(alters).join(';\n')
            if query.length > 0
                connector.exec (query + ';'), options, (err)->
                    callback err, queries, oldModel, newModel
                    return
                return

        callback err, queries, oldModel, newModel
        return

_sync = (oldModel, newModel, schema, options)->
    queries =
        creates: []
        alters: []
        drops: []
        drop_constraints: []

    opts = defaults {schema}, options
    {purge, lower_case_table_names} = options

    if lower_case_table_names is 1
        model = {}
        for name of newModel
            model[name.toLowerCase()] = newModel[name]
        newModel = model
    else
        newModel = clone newModel

    if oldModel

        for tableName, oldTableModel of oldModel
            # if tableName isnt 'CLASS_D'
            #     continue
            if newModel.hasOwnProperty(tableName)
                {alters, drops} = _tableDiff oldTableModel, newModel[tableName], opts
                delete newModel[tableName]
                queries.alters.push.apply queries.alters, alters
                queries.drops.push.apply queries.drops, drops
            else if purge
                # drop foreign keys
                if (keys = oldTableModel.constraints['FOREIGN KEY']) and not isEmpty(keys)
                    for fkName of keys
                        queries.drop_constraints.push schema.dropForeignKey(oldTableModel, fkName, options)

                # drop unique indexes
                if (keys = oldTableModel.constraints.UNIQUE) and not isEmpty(keys)
                    for indexName of keys
                        queries.drop_constraints.push schema.dropUniqueIndex(tableName, indexName, options)

                # drop indexes
                if not isEmpty(oldTableModel.indexes)
                    for indexName of oldTableModel.indexes
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

_tableDiff = (oldTableModel, newTableModel, options = {})->
    # console.log require('util').inspect(oldTableModel, {colors: true, depth: null})
    # console.log require('util').inspect(newTableModel, {colors: true, depth: null})

    newTableModel = cloneDeep newTableModel
    {schema, renames, queries, purge} = options
    {adapter} = schema

    tableName = newTableModel.name
    drops = []
    alters = []

    for column, oldColumnSpec of oldTableModel.columns
        if renames and renames.hasOwnProperty(column)
            newName = renames[column]
            if newName and newTableModel.columns.hasOwnProperty(newName)
                newColumnSpec = newTableModel.columns[newName]
                delete newTableModel.columns[newName]
                alter = schema.diffType(tableName, column, oldColumnSpec, newColumnSpec, options)
                if alter
                    alters.push alter
                else
                    alters.push schema.renameColumn(tableName, column, newName, options)
            else if purge
                drops.push schema.dropColumn tableName, column, options
        else if newTableModel.columns.hasOwnProperty column
            newColumnSpec = newTableModel.columns[column]
            delete newTableModel.columns[column]
            alter = schema.diffType(tableName, column, oldColumnSpec, newColumnSpec, options)
            if alter
                alters.push alter
        else if purge
            drops.push schema.dropColumn(tableName, column, options)

    for column, newColumnSpec of newTableModel.columns
        alters.push schema.addColumn(tableName, column, newColumnSpec, options)

    # primary key
    if (pk = oldTableModel.constraints['PRIMARY KEY']) and not isEmpty(pk)
        count = 0
        for pkName, columns of pk
            if ++count is 2
                throw new Error "#{tableName} oldTableModel has more than one primary key"
            oldPkName = pkName
            oldColumns = columns
            oldJoinedPkColumns = columns.map(adapter.escapeId).join(', ')

    if (pk = newTableModel.constraints['PRIMARY KEY']) and not isEmpty(pk)
        count = 0
        for pkName, columns of pk
            if ++count is 2
                throw new Error "#{tableName} newTableModel has more than one primary key"
            newPkName = pkName
            newColumns = columns
            newJoinedPkColumns = columns.map(adapter.escapeId).join(', ')

    if oldJoinedPkColumns isnt newJoinedPkColumns
        if not newJoinedPkColumns
            if purge
                alters.push schema.dropPrimaryKey(tableName, oldPkName, options)
        else if oldJoinedPkColumns
            alters.push schema.dropPrimaryKey(tableName, oldPkName, options)
            alters.push schema.addPrimaryKey(tableName, newPkName, newColumns, options)
        else
            alters.push schema.addPrimaryKey(tableName, newPkName, newColumns, options)
    else if oldPkName isnt newPkName
        if alter = schema.renamePrimaryKey(tableName, oldPkName, newPkName, options)
            alters.push alter

    # foreign keys
    if (keys = oldTableModel.constraints['FOREIGN KEY']) and not isEmpty(keys)
        oldKeys = _flipForeignKeys keys

    if (keys = newTableModel.constraints['FOREIGN KEY']) and not isEmpty(keys)
        newKeys = _flipForeignKeys keys

    for column, oldKey of oldKeys
        if newKeys and newKeys.hasOwnProperty(column)
            newKey = newKeys[column]
            delete newKeys[column]
            { referenced_table } = newKey
            if options.lower_case_table_names is 1
                referenced_table = referenced_table.toLowerCase()
            if oldKey.referenced_table isnt referenced_table or oldKey.referenced_column isnt newKey.referenced_column
                alters.push schema.dropForeignKey(oldTableModel, oldKey.name, options)
                alters.push schema.addForeignKey(newTableModel, newKey, options)
            else if oldKey.name isnt newKey.name
                if options.renameForeignKey
                    alters.push schema.renameForeignKey(newTableModel, oldKey.name, newKey, oldTableModel, options)
        else if purge
            alters.push schema.dropForeignKey(oldTableModel, oldKey.name, options)

    if newKeys
        for column, newKey of newKeys
            alters.push schema.addForeignKey(newTableModel, newKey, options)

    # unique indexes
    if (indexes = oldTableModel.constraints.UNIQUE) and not isEmpty(indexes)
        oldUniqueIndexes = _flipIndex indexes, adapter

    if (indexes = newTableModel.constraints.UNIQUE) and not isEmpty(indexes)
        newUniqueIndexes = _flipIndex indexes, adapter

    if oldUniqueIndexes
        if newUniqueIndexes
            for id, oldIndex of oldUniqueIndexes
                if newUniqueIndexes.hasOwnProperty(id)
                    newIndex = newUniqueIndexes[id]
                    delete newUniqueIndexes[id]
                    if oldIndex.name isnt newIndex.name
                        alters.push schema.renameUniqueIndex(tableName, oldIndex.name, newIndex.name, options)
                else if newJoinedPkColumns is oldIndex.columns.map(adapter.escapeId).join(', ')
                    # unique index exists as primary key
                    continue
                else if purge
                    alters.push schema.dropUniqueIndex(tableName, oldIndex.name, options)
        else if purge
            for id, oldIndex of oldUniqueIndexes
                if newJoinedPkColumns is oldIndex.columns.map(adapter.escapeId).join(', ')
                    # unique index exists as primary key
                    continue
                alters.push schema.dropUniqueIndex(tableName, oldIndex.name, options)

    if newUniqueIndexes
        for id, newIndex of newUniqueIndexes
            alters.push schema.addUniqueIndex(tableName, newIndex.name, newIndex.columns, options)

    # indexes
    if (indexes = oldTableModel.indexes) and not isEmpty(indexes)
        oldIndexes = _flipIndex indexes

    if (indexes = newTableModel.indexes) and not isEmpty(indexes)
        newIndexes = _flipIndex indexes

    if oldIndexes
        if newIndexes
            for id, oldIndex of oldIndexes
                if newIndexes.hasOwnProperty(id)
                    newIndex = newIndexes[id]
                    delete newIndexes[id]
                    if oldIndex.name isnt newIndex.name
                        alters.push schema.renameIndex(tableName, oldIndex.name, newIndex.name, options)
                else if purge
                    alters.push schema.dropIndex(tableName, oldIndex.name, options)
        else if purge
            for id, oldIndex of oldIndexes
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

_flipIndex = (keys)->
    flip = {}
    for name, columns of keys
        flip[_getIndexUniquId(columns)] = {name, columns}
    flip

_getIndexUniquId = (columns)->
    columns.join(':')
