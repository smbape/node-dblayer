_ = require 'lodash'
tools = require '../../tools'
SchemaCompiler = require '../../schema/SchemaCompiler'
ColumnCompiler = require './ColumnCompiler'

module.exports = class PgSchemaCompiler extends SchemaCompiler
    ColumnCompiler: ColumnCompiler
    validUpdateActions: ['no_action', 'restrict', 'cascade', 'set_null', 'set_default']

    # https://dev.mysql.com/doc/refman/5.7/en/alter-table.html
    # ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ]
    #   DROP [ COLUMN ] [ IF EXISTS ] column_name [ RESTRICT | CASCADE ]
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

    # TODO : change column type with index
    #     => need for oldTableSpec, newTableSpec
    #     => drop all affected indexes. Diff on indexes will recreate it
    diffType: (tableName, column, oldColumnSpec, newColumnSpec)->
        options = _.defaults {}, options, @options
        {words, escapeId, escape, columnCompiler, args, indent, LF} = @

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
        oldTypeString = columnCompiler.getTypeString(oldColumnSpec)
        newTypeString = columnCompiler.getTypeString(newColumnSpec)

        oldModifier = columnCompiler.getColumnModifier(oldColumnSpec)
        newModifier = columnCompiler.getColumnModifier(newColumnSpec)

        if oldTypeString isnt newTypeString
            if oldColumnSpec.type is 'text' and newColumnSpec.type is 'enum'
                # TODO: find a way to compare enum
                return

            spec = newColumnSpec
            # ALTER COLUMN column_name TYPE data_type
            altersql.push [indent, words.alter_column, ' ', columnId, ' ', words.type, ' ', newTypeString].join('')

            if spec.defaultValue isnt undefined and spec.defaultValue isnt null
                # ALTER COLUMN column_name SET DEFAULT expression
                altersql.push [indent, words.alter_column, ' ', columnId, ' ', words.set_default, ' ', escape(spec.defaultValue)].join('')
            else if spec.nullable is false
                # ALTER COLUMN column_name SET NOT NULL
                altersql.push [indent, words.alter_column, ' ', columnId, ' ', words.set, ' ', words.not_null].join('')
            else
                # ALTER COLUMN column_name DROP NOT NULL
                altersql.push [indent, words.alter_column, ' ', columnId, ' ', words.drop, ' ', words.not_null].join('')

            tablesql.push altersql.join(',' + LF)
        else if oldModifier isnt newModifier
            # TODO: more tests to be able to do a proper default value comparaison
            # console.log oldModifier, newModifier
            return
        else
            return

        tablesql.join('')

    # http://www.postgresql.org/docs/9.4/static/sql-altertable.html
    # ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ]
    #   RENAME CONSTRAINT constraint_name TO new_constraint_name
    renameConstraint: (tableName, oldName, newName, oldTableModel, options)->
        if _.isObject(tableName)
            tableName = tableName.name

        if _.isObject(newName)
            newName = newName.name

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
        if _.isObject(tableName)
            tableName = tableName.name

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
