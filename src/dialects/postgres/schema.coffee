_ = require 'lodash'
tools = require '../../tools'
TypeCompiler = require './TypeCompiler'

LOWERWORDS =
    inherits: 'inherits'

_.extend TypeCompiler::LOWERWORDS, LOWERWORDS
_.extend TypeCompiler::UPPERWORDS, tools.toUpperWords LOWERWORDS

module.exports =
    adapter: require('./adapter')

    # http://www.postgresql.org/docs/9.4/static/sql-createtable.html
    createTable: (table, options = {})->
        # console.log require('util').inspect(table, {colors: true, depth: null})
        indent = options.indent or '    '
        LF = '\n'
        typecompiler = new TypeCompiler options
        {words, args, adapter} = typecompiler

        tableName = table.name
        tableNameId = adapter.escapeId tableName
        args.table = tableName
        tablesql = []

        spaceLen = ' '.repeat(66 - 10 - tableName.length - 2)
        tablesql.push """
        /*==============================================================*/
        /* Table: #{tableName}#{spaceLen}*/
        /*==============================================================*/
        """
        tablesql.push.apply tablesql, [LF, words.create_table, ' ']

        if options.if_not_exists
            tablesql.push words.if_not_exists
            tablesql.push ' '

        tablesql.push.apply tablesql, [tableNameId, ' (', LF]

        tablespec = []

        # column definition
        for column, spec of table.columns
            columnId = adapter.escapeId(column)
            length = columnId.length
            spaceLen = 21 - length
            if spaceLen <= 0
                spaceLen = 1
                length++
            else
                length = 21

            colsql = [columnId, ' '.repeat(spaceLen)]
            args.column = column

            type = _getTypeString spec, typecompiler
            colsql.push type

            length += type.length
            spaceLen = 42 - length
            if spaceLen <= 0
                spaceLen = 1
            colsql.push ' '.repeat(spaceLen)

            colsql.push _getColumnModifier spec, typecompiler

            tablespec.push indent + colsql.join(' ')

        # primary key
        if (pk = table.constraints['PRIMARY KEY']) and not _.isEmpty(pk)
            count = 0
            for pkName, columns of pk
                if ++count is 2
                    throw new Error "#{tableName} has more than one primary key"
                tablespec.push indent + words.constraint + ' ' + _pkString(pkName, columns, typecompiler)

        # unique indexes
        if (uk = table.constraints['UNIQUE']) and not _.isEmpty(uk)
            for ukName, columns of uk
                tablespec.push indent + words.constraint + ' ' + _ukString(ukName, columns, typecompiler)

        tablesql.push tablespec.join(',' + LF)
        tablesql.push LF
        tablesql.push ');'

        # indexes
        if table.indexes and not _.isEmpty(table.indexes)
            tablesql.push LF
            for indexName, columns of table.indexes
                tablesql.push LF
                spaceLen = ' '.repeat(66 - 10 - indexName.length - 2)
                tablesql.push """
                /*==============================================================*/
                /* Index: #{indexName}#{spaceLen}*/
                /*==============================================================*/
                """
                tablesql.push.apply tablesql, [LF, words.create_index, ' ', _indexString(indexName, columns, tableNameId, typecompiler)]
                tablesql.push LF

        # foreign keys
        altersql = []
        if (fk = table.constraints['FOREIGN KEY']) and not _.isEmpty(fk)
            for fkName, constraint of fk
                {
                    column
                    references_table
                    references_column
                    delete_rule
                    update_rule
                } = constraint

                altersql.push.apply altersql, [
                    LF, words.alter_table, ' ', adapter.escapeId(tableName)
                    LF, indent, words.add_constraint, ' ', adapter.escapeId(fkName), ' ', words.foreign_key, ' (', adapter.escapeId(column), ')'
                    LF, indent, indent, words.references, ' ', adapter.escapeId(references_table), ' (', adapter.escapeId(references_column) + ')'
                ]

                delete_rule = if delete_rule then delete_rule.toLowerCase() else 'restrict'
                update_rule = if update_rule then update_rule.toLowerCase() else 'restrict'

                if not words[delete_rule]
                    throw new Error "unknown delete rule #{delete_rule}"

                if not words[update_rule]
                    throw new Error "unknown update rule #{update_rule}"

                altersql.push.apply altersql, [LF, indent, indent, words.on_delete, ' ', words[delete_rule], ' ', words.on_update, ' ', words[update_rule], ';', LF]

        {create: tablesql.join(''), alter: altersql.slice(1).join('')}

    # http://www.postgresql.org/docs/9.4/static/sql-droptable.html
    # DROP TABLE [ IF EXISTS ] name [, ...] [ CASCADE | RESTRICT ]
    dropTable: (tableName, options = {})->
        typecompiler = new TypeCompiler options
        {words, args, adapter} = typecompiler

        tablesql = [words.drop_table]
        if options.if_exists
            tablesql.push words.if_exists
        tablesql.push adapter.escapeId(tableName)

        if options.cascade
            tablesql.push words.cascade
        else if options.restrict
            tablesql.push words.restrict

        tablesql.join(' ')

    # http://www.postgresql.org/docs/9.4/static/sql-altertable.html
    # ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ] ADD [ COLUMN ] column_name data_type [ COLLATE collation ] [ column_constraint [ ... ] ]
    addColumn: (tableName, column, spec, options = {})->
        typecompiler = new TypeCompiler options
        {words, args, adapter} = typecompiler
        LF = '\n'
        indent = '    '

        args.table = tableName
        args.column = column
        columnId = adapter.escapeId(column)

        altersql = [words.alter_table, ' ']
        if options.if_exists
            altersql.push words.if_exists
            altersql.push ' '
        altersql.push.apply altersql, [
            adapter.escapeId(tableName), LF,
            indent, words.add_column, ' ', adapter.escapeId(column), ' ', _getTypeString(spec, typecompiler), ' ', _getColumnModifier(spec, typecompiler)
        ]

        altersql.join('')

    # http://www.postgresql.org/docs/9.4/static/sql-altertable.html
    # ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ] DROP [ COLUMN ] [ IF EXISTS ] column_name [ RESTRICT | CASCADE ]
    dropColumn: (tableName, column, options = {})->
        typecompiler = new TypeCompiler options
        {words, args, adapter} = typecompiler
        LF = '\n'
        indent = '    '
        args.table = tableName
        args.column = column

        altersql = [words.alter_table, ' ']
        if options.if_exists
            altersql.push words.if_exists
            altersql.push ' '
        altersql.push.apply altersql, [adapter.escapeId(tableName), LF, indent, words.drop_column, ' ']
        if options.if_exists
            altersql.push words.if_exists
            altersql.push ' '
        altersql.push adapter.escapeId(column)
        if options.cascade
            altersql.push ' '
            altersql.push words.cascade
        else if options.restrict
            altersql.push ' '
            altersql.push words.restrict

        altersql.join('')

    diffType: (tableName, column, oldSpec, newSpec, options = {})->
        typecompiler = new TypeCompiler options
        {words, args, adapter} = typecompiler
        LF = '\n'
        indent = '    '

        columnId = adapter.escapeId column

        # ALTER TABLE [ IF EXISTS ] name
        tablesql = [words.alter_table, ' ']
        if options.if_exists
            tablesql.push words.if_exists
            tablesql.push ' '
        tablesql.push.apply tablesql, [adapter.escapeId(tableName), LF]

        altersql = []
        oldTypeString = _getTypeString(oldSpec, typecompiler)
        newTypeString = _getTypeString(newSpec, typecompiler)

        oldModifier = _getColumnModifier oldSpec, typecompiler
        newModifier = _getColumnModifier newSpec, typecompiler

        if oldTypeString isnt newTypeString
            spec = newSpec
            # ALTER COLUMN column_name TYPE data_type
            altersql.push [indent, words.alter_column, ' ', columnId, ' ', words.type, ' ', newTypeString].join('')

            if spec.nullable is false
                # ALTER COLUMN column_name SET NOT NULL
                altersql.push [indent, words.alter_column, ' ', columnId, ' ', words.set, ' ', words.not_null].join('')
            else if spec.defaultValue isnt undefined and spec.defaultValue isnt null
                # ALTER COLUMN column_name SET DEFAULT expression
                altersql.push [indent, words.alter_column, ' ', columnId, ' ', words.set_default, ' ', spec.defaultValue].join('')
            else
                # ALTER COLUMN column_name DROP NOT NULL
                altersql.push [indent, words.alter_column, ' ', columnId, ' ', words.drop, ' ', words.not_null].join('')

            tablesql.push altersql.join(',' + LF)
        else if oldModifier isnt newModifier
            spec = newSpec

            if spec.nullable is false
                # ALTER COLUMN column_name SET NOT NULL
                tablesql.push.apply tablesql, [indent, words.alter_column, ' ', columnId, ' ', words.set, ' ', words.not_null]
            else if spec.defaultValue isnt undefined and spec.defaultValue isnt null
                # ALTER COLUMN column_name SET DEFAULT expression
                tablesql.push.apply tablesql, [indent, words.alter_column, ' ', columnId, ' ', words.set_default, ' ', spec.defaultValue]
            else
                # ALTER COLUMN column_name DROP NOT NULL
                tablesql.push.apply tablesql, [indent, words.alter_column, ' ', columnId, ' ', words.drop, ' ', words.not_null]
        else
            return

        tablesql.join('')

    # http://www.postgresql.org/docs/9.4/static/sql-altertable.html
    # ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ]
    #   ADD [ constraint_name ] PRIMARY KEY ( column_name [, ... ] ) index_parameters [ NOT VALID ]
    addPrimaryKey: (tableName, newPkName, newColumns, options = {})->
        typecompiler = new TypeCompiler options
        {words, args, adapter} = typecompiler
        LF = '\n'
        indent = '    '

        altersql = [words.alter_table, ' ']
        if options.if_exists
            altersql.push words.if_exists
            altersql.push ' '
        altersql.push.apply altersql, [adapter.escapeId(tableName), LF, indent, words.add_constraint, ' ', _pkString(newPkName, newColumns, typecompiler)]

        altersql.join('')

    # http://www.postgresql.org/docs/9.4/static/sql-altertable.html
    # ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ]
    #   ADD [ constraint_name ] FOREIGN KEY ( column_name [, ... ] )
    #       REFERENCES reftable [ ( refcolumn [, ... ] ) ] [ NOT VALID ]
    #       [ MATCH FULL | MATCH PARTIAL | MATCH SIMPLE ] [ ON DELETE action ] [ ON UPDATE action ]
    #       
    #       action in [NO ACTION, RESTRICT, CASCADE, SET NULL, SET DEFAULT]
    addForeignKey: (tableName, key, options = {})->
        typecompiler = new TypeCompiler options
        {words, args, adapter} = typecompiler
        LF = '\n'
        indent = '    '

        altersql = [words.alter_table, ' ']
        if options.if_exists
            altersql.push words.if_exists
            altersql.push ' '

        {
            name: fkName,
            column,
            references_table,
            references_column,
            delete_rule,
            update_rule
        } = key

        altersql.push.apply altersql, [
            adapter.escapeId(tableName),
            LF, indent, words.add_constraint, ' ', adapter.escapeId(fkName), ' ', words.foreign_key, ' (', adapter.escapeId(column), ')'
            LF, indent, indent, words.references, ' ', adapter.escapeId(references_table), ' (', adapter.escapeId(references_column) + ')'
        ]

        delete_rule = if delete_rule then delete_rule.toLowerCase() else 'restrict'
        update_rule = if update_rule then update_rule.toLowerCase() else 'restrict'

        if delete_rule not in ['no_action', 'restrict', 'cascade', 'set_null', 'set_default']
            throw new Error "unknown delete rule #{delete_rule}"

        if update_rule not in ['no_action', 'restrict', 'cascade', 'set_null', 'set_default']
            throw new Error "unknown update rule #{update_rule}"

        altersql.push.apply altersql, [LF, indent, indent, words.on_delete, ' ', words[delete_rule], ' ', words.on_update, ' ', words[update_rule]]

        altersql.join('')

    # http://www.postgresql.org/docs/9.4/static/sql-altertable.html
    # ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ]
    #   ADD [ constraint_name ] UNIQUE ( column_name [, ... ] ) index_parameters
    addUniqueIndex: (tableName, indexName, columns, options = {})->
        typecompiler = new TypeCompiler options
        {words, args, adapter} = typecompiler
        LF = '\n'
        indent = '    '

        altersql = [words.alter_table, ' ']
        if options.if_exists
            altersql.push words.if_exists
            altersql.push ' '
        altersql.push.apply altersql, [adapter.escapeId(tableName),
            LF, indent, words.add_constraint, ' ', adapter.escapeId(indexName), ' ', words.unique, ' (', columns.sort().map(adapter.escapeId).join(', '), ')'
        ]

        altersql.join('')

    # http://www.postgresql.org/docs/9.4/static/sql-altertable.html
    # ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ]
    #   RENAME CONSTRAINT constraint_name TO new_constraint_name
    renameConstraint: (tableName, oldName, newName, options = {})->
        typecompiler = new TypeCompiler options
        {words, args, adapter} = typecompiler
        LF = '\n'
        indent = '    '

        altersql = [words.alter_table]

        # TODO: check declared issue
        # there seem to be a bug in 9.4
        # if options.if_exists
        #     altersql.push words.if_exists

        altersql.push.apply altersql, [adapter.escapeId(tableName), words.rename_constraint, adapter.escapeId(oldName), words.to, adapter.escapeId(newName)]
        
        altersql.join(' ')

    # http://www.postgresql.org/docs/9.4/static/sql-altertable.html
    # ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ]
    #   DROP CONSTRAINT [ IF EXISTS ]  constraint_name [ RESTRICT | CASCADE ]
    dropConstraint: (tableName, oldPkName, options = {})->
        typecompiler = new TypeCompiler options
        {words, args, adapter} = typecompiler
        LF = '\n'
        indent = '    '

        altersql = [words.alter_table, ' ']
        if options.if_exists
            altersql.push words.if_exists
            altersql.push ' '
        altersql.push adapter.escapeId(tableName)

        altersql.push.apply altersql, [LF, indent, words.drop_constraint, ' ']
        if options.if_exists
            altersql.push words.if_exists
            altersql.push ' '

        altersql.push adapter.escapeId(oldPkName)

        if options.cascade
            altersql.push ' '
            altersql.push words.cascade

        else if options.restrict
            altersql.push ' '
            altersql.push words.restrict

        altersql.join('')

    # http://www.postgresql.org/docs/9.4/static/sql-createindex.html
    # CREATE [ UNIQUE ] INDEX [ CONCURRENTLY ] [ name ] ON table_name
    #   ( { column_name | ( expression ) } [ COLLATE collation ] [ opclass ] [ ASC | DESC ] [ NULLS { FIRST | LAST } ] [, ...] )
    addIndex: (tableName, indexName, columns, options = {})->
        typecompiler = new TypeCompiler options
        {words, args, adapter} = typecompiler
        [words.create_index, ' ', _indexString(indexName, columns, adapter.escapeId(tableName), typecompiler)].join('')

    # http://www.postgresql.org/docs/9.4/static/sql-alterindex.html
    # ALTER INDEX [ IF EXISTS ] name RENAME TO new_name
    renameIndex: (tableName, oldName, newName, options = {})->
        typecompiler = new TypeCompiler options
        {words, args, adapter} = typecompiler
        LF = '\n'
        indent = '    '

        altersql = [words.alter_index]
        if options.if_exists
            altersql.push words.if_exists
        altersql.push.apply altersql, [adapter.escapeId(oldName), words.rename_to, adapter.escapeId(newName)]
        
        altersql.join(' ')

    # http://www.postgresql.org/docs/9.4/static/sql-dropindex.html
    # DROP INDEX [ CONCURRENTLY ] [ IF EXISTS ] name [, ...] [ CASCADE | RESTRICT ]
    dropIndex: (tableName, indexName, options = {})->
        typecompiler = new TypeCompiler options
        {words, args, adapter} = typecompiler
        LF = '\n'
        indent = '    '

        altersql = [words.drop_index]
        if options.if_exists
            altersql.push words.if_exists

        altersql.push adapter.escapeId(indexName)

        if options.cascade
            altersql.push words.cascade
        else if options.restrict
            altersql.push words.restrict

        altersql.join(' ')

module.exports.dropPrimaryKey = module.exports.dropForeignKey = module.exports.dropUniqueIndex = module.exports.dropConstraint
module.exports.renamePrimaryKey = module.exports.renameUniqueIndex = module.exports.renameForeignKey = module.exports.renameConstraint
# module.exports.renamePrimaryKey = module.exports.renameIndex

_pkString = (pkName, columns, typecompiler)->
    {words, adapter} = typecompiler
    adapter.escapeId(pkName) + ' ' + words.primary_key + ' (' + columns.sort().map(adapter.escapeId).join(', ') + ')'

_ukString = (ukName, columns, typecompiler)->
    {words, adapter} = typecompiler
    adapter.escapeId(ukName) + ' ' + words.unique + ' (' + columns.sort().map(adapter.escapeId).join(', ') + ')'

_indexString = (indexName, columns, tableNameId, typecompiler)->
    {adapter, words} = typecompiler
    adapter.escapeId(indexName) + ' ' + words.on + ' ' + tableNameId + '(' + columns.sort().map(adapter.escapeId).join(', ') + ')'

_getTypeString = (spec, typecompiler)->
    type = spec.type
    type_args = if Array.isArray(spec.type_args) then spec.type_args else []
    if 'function' is typeof typecompiler[type]
        type = typecompiler[type].apply typecompiler, type_args
    else
        type_args.unshift type
        type = type_args.join(' ')

    type

_getColumnModifier = (spec, typecompiler)->
    {words} = typecompiler
    if spec.nullable is false
        return words.not_null
    else if spec.defaultValue isnt undefined and spec.defaultValue isnt null
        return words.default + ' ' + spec.defaultValue
    else
        return words.null
