_ = require 'lodash'
# tools = require '../tools'

# PersistenceManager sync method
exports.sync = (connector, callback)->
    pMgr = @
    dialect = connector.getDialect()
    sync = require('../dialects/' + dialect + '/sync')
    schema = require('../dialects/' + dialect + '/schema')

    sync.getModel connector, (err, actualModel)->
        return callback(err) if err
        model = {}

        propToColumn = (prop)-> definition.properties[prop].column

        for className, definition of pMgr.classes
            tableName = definition.table
            table = model[tableName] =
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
                column.nullable = false
                [foreignKey, indexKey] = _addOneNRelation 'EXT', table, mixin, parentDef, {index: false}

                # enforce unique key
                table.constraints['UNIQUE'][indexKey] = [mixin.column]

            for prop, propDef of definition.properties
                column = table.columns[propDef.column] = _.pick propDef, pMgr.specProperties

                if propDef.className
                    parentDef = pMgr._getDefinition propDef.className
                    _addOneNRelation 'HAS', table, propDef, parentDef

            if _.isEmpty table.constraints['FOREIGN KEY']
                delete table.constraints['FOREIGN KEY']

            {unique, names} = definition.constraints
            for key, properties of unique
                name = names[key]
                table.constraints['UNIQUE'][name] = properties.map propToColumn

            if _.isEmpty table.constraints['UNIQUE']
                delete table.constraints['UNIQUE']

            for name, properties in definition.indexes
                table.indexes[name] = properties.map propToColumn

        queries =
            creates: []
            alters: []
            drops: []

        opts = {schema, lower: false}

        for tableName of model
            if tableName isnt 'CLASS_F'
                continue

            {alters, drops} = _tableDiff actualModel[tableName], model[tableName], opts
            queries.drops.push.apply queries.drops, drops
            queries.alters.push.apply queries.alters, alters

            {create, alter} = schema.createTable model[tableName], opts

            queries.creates.push create
            queries.alters.push alter

        console.log queries.drops.join(';\n')
        console.log queries.creates.join('\n')
        console.log queries.alters.join(';\n')
        console.log '\n'

        callback()
        return

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

_tableDiff = (oldModel, newModel, options = {})->
    console.log require('util').inspect(oldModel, {colors: true, depth: null})
    console.log require('util').inspect(newModel, {colors: true, depth: null})

    oldModel = _.cloneDeep oldModel
    newModel = _.cloneDeep newModel
    {schema, renames, queries, purge} = options
    {adapter} = schema

    tableName = newModel.name
    drops = []
    alters = []

    # console.log schema.dropColumn tableName, 'VERSION'

    for column, oldSpec of oldModel.columns
        if renames and renames.hasOwnProperty(column)
            newName = renames[column]
            if newName and newModel.columns.hasOwnProperty(newName)
                newSpec = newModel.columns[newName]
                delete newModel.columns[newName]
                alter = schema.diffType tableName, column, oldSpec, newSpec, options
                if alter
                    alters.push alter
                else
                    alters.push schema.renameColumn tableName, column, newName, options
            else if purge
                drops.push schema.dropColumn tableName, column, options
        else if newModel.columns.hasOwnProperty column
            newSpec = newModel.columns[column]
            delete newModel.columns[column]
            alter = schema.diffType tableName, column, oldSpec, newSpec, options
            alters.push alter if alter
        else if purge
            drops.push schema.dropColumn tableName, column, options

    for column, newSpec of newModel.columns
        alters.push schema.addColumn tableName, column, newSpec, options

    # primary key
    if (pk = oldModel.constraints['PRIMARY KEY']) and not _.isEmpty(pk)
        count = 0
        for pkName, columns of pk
            if ++count is 2
                throw new Error "#{tableName} has more than one primary key"
            oldPkName = pkName
            oldColumns = columns.sort().map(adapter.escapeId).join(', ')
            # oldPk = _pkString(pkName, columns, typecompiler)

    if (pk = newModel.constraints['PRIMARY KEY']) and not _.isEmpty(pk)
        count = 0
        for pkName, columns of pk
            if ++count is 2
                throw new Error "#{tableName} has more than one primary key"
            newPkName = pkName
            newColumns = columns.sort().map(adapter.escapeId).join(', ')
            # newPk = _pkString(pkName, columns, typecompiler)

    alter = schema.diffPrimaryKey tableName, oldPkName, oldColumns, newPkName, newColumns, options
    alters.push alter if alter

    # foreign keys
    # unique indexes
    # indexes

    {alters, drops}

_getFkId = ({column, references_table, references_column}, adapter)->
    [column, references_table, references_column].map(adapter.escapeId).join('.')
