_ = require 'lodash'
tools = require '../../tools'
SchemaCompiler = require '../../schema/SchemaCompiler'
ColumnCompiler = require './ColumnCompiler'

validUpdateActions = ['no_action', 'restrict', 'cascade', 'set_null', 'set_default']

module.exports = class PgSchemaCompiler extends SchemaCompiler
    ColumnCompiler: ColumnCompiler

    # http://www.postgresql.org/docs/9.4/static/sql-createtable.html
    createTable: (table, options)->
        options = _.defaults {}, options, @options
        {words, escapeId, columnCompiler, args, indent, LF} = @

        tableName = table.name
        tableNameId = escapeId tableName
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
            columnId = escapeId(column)
            length = columnId.length
            spaceLen = 21 - length
            if spaceLen <= 0
                spaceLen = 1
                length++
            else
                length = 21

            colsql = [columnId, ' '.repeat(spaceLen)]
            args.column = column

            type = columnCompiler.getTypeString(spec)
            colsql.push type

            length += type.length
            spaceLen = 42 - length
            if spaceLen <= 0
                spaceLen = 1
            colsql.push ' '.repeat(spaceLen)

            colsql.push columnCompiler.getColumnModifier(spec)

            tablespec.push indent + colsql.join(' ')

        # primary key
        if (pk = table.constraints['PRIMARY KEY']) and not _.isEmpty(pk)
            count = 0
            for pkName, columns of pk
                if ++count is 2
                    err = new Error "#{tableName} has more than one primary key"
                    err.code = 'MULTIPLE_PK'
                    throw err
                tablespec.push indent + words.constraint + ' ' + columnCompiler.pkString(pkName, columns)

        # unique indexes
        if (uk = table.constraints.UNIQUE) and not _.isEmpty(uk)
            for ukName, columns of uk
                tablespec.push indent + words.constraint + ' ' + columnCompiler.ukString(ukName, columns)

        tablesql.push tablespec.join(',' + LF)
        tablesql.push LF
        tablesql.push ')'

        # indexes
        if table.indexes and not _.isEmpty(table.indexes)
            tablesql.push ';'
            tablesql.push LF
            count = 0
            for indexName, columns of table.indexes
                if count is 0
                    count = 1
                else
                    tablesql.push ';'
                    tablesql.push LF
                tablesql.push LF
                spaceLen = ' '.repeat(66 - 10 - indexName.length - 2)
                tablesql.push """
                /*==============================================================*/
                /* Index: #{indexName}#{spaceLen}*/
                /*==============================================================*/
                """
                tablesql.push.apply tablesql, [LF, words.create_index, ' ', columnCompiler.indexString(indexName, columns, tableNameId)]

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
                    LF, words.alter_table, ' ', escapeId(tableName)
                    LF, indent, words.add_constraint, ' ', escapeId(fkName), ' ', words.foreign_key, ' (', escapeId(column), ')'
                    LF, indent, indent, words.references, ' ', escapeId(references_table), ' (', escapeId(references_column) + ')'
                ]

                delete_rule = if delete_rule then delete_rule.toLowerCase() else 'restrict'
                update_rule = if update_rule then update_rule.toLowerCase() else 'restrict'

                if delete_rule not in validUpdateActions
                    err = new Error "unknown delete rule #{delete_rule}"
                    err.code = 'UPDATE RULE'
                    throw err

                if update_rule not in validUpdateActions
                    err = new Error "unknown update rule #{update_rule}"
                    err.code = 'UPDATE RULE'
                    throw err

                altersql.push.apply altersql, [LF, indent, indent, words.on_delete, ' ', words[delete_rule], ' ', words.on_update, ' ', words[update_rule], ';', LF]

        {create: tablesql.join(''), alter: altersql.slice(1).join('')}

    # http://www.postgresql.org/docs/9.4/static/sql-droptable.html
    # DROP TABLE [ IF EXISTS ] name [, ...] [ CASCADE | RESTRICT ]
    dropTable: (tableName, options)->
        options = _.defaults {}, options, @options
        {words, escapeId} = @

        tablesql = [words.drop_table]
        if options.if_exists
            tablesql.push words.if_exists
        tablesql.push escapeId(tableName)

        if options.cascade
            tablesql.push words.cascade
        else if options.restrict
            tablesql.push words.restrict

        tablesql.join(' ')

    # http://www.postgresql.org/docs/9.4/static/sql-altertable.html
    # ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ] ADD [ COLUMN ] column_name data_type [ COLLATE collation ] [ column_constraint [ ... ] ]
    addColumn: (tableName, column, spec, options)->
        options = _.defaults {}, options, @options
        {words, escapeId, columnCompiler, args, indent, LF} = @

        args.table = tableName
        args.column = column
        columnId = escapeId(column)

        altersql = [words.alter_table, ' ']
        if options.if_exists
            altersql.push words.if_exists
            altersql.push ' '
        altersql.push.apply altersql, [
            escapeId(tableName), LF,
            indent, words.add_column, ' ', escapeId(column), ' ', columnCompiler.getTypeString(spec), ' ', columnCompiler.getColumnModifier(spec)
        ]

        altersql.join('')

    # http://www.postgresql.org/docs/9.4/static/sql-altertable.html
    # ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ] DROP [ COLUMN ] [ IF EXISTS ] column_name [ RESTRICT | CASCADE ]
    dropColumn: (tableName, column, options)->
        options = _.defaults {}, options, @options
        {words, escapeId, args, indent, LF} = @

        args.table = tableName
        args.column = column

        altersql = [words.alter_table, ' ']
        if options.if_exists
            altersql.push words.if_exists
            altersql.push ' '
        altersql.push.apply altersql, [escapeId(tableName), LF, indent, words.drop_column, ' ']
        if options.if_exists
            altersql.push words.if_exists
            altersql.push ' '
        altersql.push escapeId(column)
        if options.cascade
            altersql.push ' '
            altersql.push words.cascade
        else if options.restrict
            altersql.push ' '
            altersql.push words.restrict

        altersql.join('')

    diffType: (tableName, column, oldSpec, newSpec)->
        options = _.defaults {}, options, @options
        {words, escapeId, columnCompiler, args, indent, LF} = @

        args.table = tableName
        args.column = column

        columnId = escapeId column

        # ALTER TABLE [ IF EXISTS ] name
        tablesql = [words.alter_table, ' ']
        if options.if_exists
            tablesql.push words.if_exists
            tablesql.push ' '
        tablesql.push.apply tablesql, [escapeId(tableName), LF]

        altersql = []
        oldTypeString = columnCompiler.getTypeString(oldSpec)
        newTypeString = columnCompiler.getTypeString(newSpec)

        oldModifier = columnCompiler.getColumnModifier(oldSpec)
        newModifier = columnCompiler.getColumnModifier(newSpec)

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
    addPrimaryKey: (tableName, newPkName, newColumns, options)->
        options = _.defaults {}, options, @options
        {words, escapeId, columnCompiler, indent, LF} = @

        altersql = [words.alter_table, ' ']
        if options.if_exists
            altersql.push words.if_exists
            altersql.push ' '
        altersql.push.apply altersql, [escapeId(tableName), LF, indent, words.add_constraint, ' ', columnCompiler.pkString(newPkName, newColumns)]

        altersql.join('')

    # http://www.postgresql.org/docs/9.4/static/sql-altertable.html
    # ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ]
    #   ADD [ constraint_name ] FOREIGN KEY ( column_name [, ... ] )
    #       REFERENCES reftable [ ( refcolumn [, ... ] ) ] [ NOT VALID ]
    #       [ MATCH FULL | MATCH PARTIAL | MATCH SIMPLE ] [ ON DELETE action ] [ ON UPDATE action ]
    #       
    #       action in [NO ACTION, RESTRICT, CASCADE, SET NULL, SET DEFAULT]
    addForeignKey: (tableName, key, options)->
        options = _.defaults {}, options, @options
        {words, escapeId, indent, LF} = @

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
            escapeId(tableName),
            LF, indent, words.add_constraint, ' ', escapeId(fkName), ' ', words.foreign_key, ' (', escapeId(column), ')'
            LF, indent, indent, words.references, ' ', escapeId(references_table), ' (', escapeId(references_column) + ')'
        ]

        delete_rule = if delete_rule then delete_rule.toLowerCase() else 'restrict'
        update_rule = if update_rule then update_rule.toLowerCase() else 'restrict'

        if delete_rule not in validUpdateActions
            err = new Error "unknown delete rule #{delete_rule}"
            err.code = 'UPDATE RULE'
            throw err

        if update_rule not in validUpdateActions
            err = new Error "unknown update rule #{update_rule}"
            err.code = 'UPDATE RULE'
            throw err

        altersql.push.apply altersql, [LF, indent, indent, words.on_delete, ' ', words[delete_rule], ' ', words.on_update, ' ', words[update_rule]]

        altersql.join('')

    # http://www.postgresql.org/docs/9.4/static/sql-altertable.html
    # ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ]
    #   ADD [ constraint_name ] UNIQUE ( column_name [, ... ] ) index_parameters
    addUniqueIndex: (tableName, indexName, columns, options)->
        options = _.defaults {}, options, @options
        {words, escapeId, indent, LF} = @

        altersql = [words.alter_table, ' ']
        if options.if_exists
            altersql.push words.if_exists
            altersql.push ' '
        altersql.push.apply altersql, [escapeId(tableName),
            LF, indent, words.add_constraint, ' ', escapeId(indexName), ' ', words.unique, ' (', columns.sort().map(escapeId).join(', '), ')'
        ]

        altersql.join('')

    # http://www.postgresql.org/docs/9.4/static/sql-altertable.html
    # ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ]
    #   RENAME CONSTRAINT constraint_name TO new_constraint_name
    renameConstraint: (tableName, oldName, newName, options)->
        options = _.defaults {}, options, @options
        {words, escapeId} = @

        altersql = [words.alter_table]

        # TODO: check declared issue
        # there seem to be a bug in 9.4
        # if options.if_exists
        #     altersql.push words.if_exists

        altersql.push.apply altersql, [escapeId(tableName), words.rename_constraint, escapeId(oldName), words.to, escapeId(newName)]
        
        altersql.join(' ')

    # http://www.postgresql.org/docs/9.4/static/sql-altertable.html
    # ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ]
    #   DROP CONSTRAINT [ IF EXISTS ]  constraint_name [ RESTRICT | CASCADE ]
    dropConstraint: (tableName, oldPkName, options)->
        options = _.defaults {}, options, @options
        {words, escapeId, indent, LF} = @

        altersql = [words.alter_table, ' ']
        if options.if_exists
            altersql.push words.if_exists
            altersql.push ' '
        altersql.push escapeId(tableName)

        altersql.push.apply altersql, [LF, indent, words.drop_constraint, ' ']
        if options.if_exists
            altersql.push words.if_exists
            altersql.push ' '

        altersql.push escapeId(oldPkName)

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
    addIndex: (tableName, indexName, columns, options)->
        options = _.defaults {}, options, @options
        {words, escapeId, columnCompiler} = @

        [words.create_index, ' ', columnCompiler.indexString(indexName, columns, escapeId(tableName))].join('')

    # http://www.postgresql.org/docs/9.4/static/sql-alterindex.html
    # ALTER INDEX [ IF EXISTS ] name RENAME TO new_name
    renameIndex: (tableName, oldName, newName, options)->
        options = _.defaults {}, options, @options
        {words, escapeId} = @

        altersql = [words.alter_index]
        if options.if_exists
            altersql.push words.if_exists
        altersql.push.apply altersql, [escapeId(oldName), words.rename_to, escapeId(newName)]
        
        altersql.join(' ')

    # http://www.postgresql.org/docs/9.4/static/sql-dropindex.html
    # DROP INDEX [ CONCURRENTLY ] [ IF EXISTS ] name [, ...] [ CASCADE | RESTRICT ]
    dropIndex: (tableName, indexName, options = {})->
        options = _.defaults {}, options, @options
        {words, escapeId} = @

        altersql = [words.drop_index]
        if options.if_exists
            altersql.push words.if_exists

        altersql.push escapeId(indexName)

        if options.cascade
            altersql.push words.cascade
        else if options.restrict
            altersql.push words.restrict

        altersql.join(' ')

PgSchemaCompiler::dropPrimaryKey = PgSchemaCompiler::dropForeignKey = PgSchemaCompiler::dropUniqueIndex = PgSchemaCompiler::dropConstraint
PgSchemaCompiler::renamePrimaryKey = PgSchemaCompiler::renameUniqueIndex = PgSchemaCompiler::renameForeignKey = PgSchemaCompiler::renameConstraint
# PgSchemaCompiler::renamePrimaryKey = PgSchemaCompiler::renameIndex
