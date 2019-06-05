_ = require 'lodash'
tools = require '../../tools'
SchemaCompiler = require '../../schema/SchemaCompiler'
ColumnCompiler = require './ColumnCompiler'

module.exports = class MysqlSchemaCompiler extends SchemaCompiler
    ColumnCompiler: ColumnCompiler

    # https://dev.mysql.com/doc/refman/5.7/en/create-table-foreign-keys.html
    validUpdateActions: ['no_action', 'restrict', 'cascade', 'set_null']

    # https://dev.mysql.com/doc/refman/5.7/en/alter-table.html
    # ALTER [IGNORE] TABLE tbl_name
    #   DROP [COLUMN] col_name
    dropColumn: (tableName, column, options)->
        {words, escapeId, indent, LF} = @
        words.alter_table + ' ' + escapeId(tableName) + LF + indent + words.drop_column + ' ' + escapeId(column)

    diffType: (tableName, column, oldColumnSpec, newColumnSpec)->
        options = _.defaults {}, options, this.options
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
        oldTypeString = columnCompiler.getTypeString(oldColumnSpec)
        newTypeString = columnCompiler.getTypeString(newColumnSpec)

        oldModifier = columnCompiler.getColumnModifier(oldColumnSpec)
        newModifier = columnCompiler.getColumnModifier(newColumnSpec)

        if oldTypeString isnt newTypeString
            if oldColumnSpec.type is 'enum' and newColumnSpec.type is 'enum'
                # TODO: find a way to compare enum
                return
            # CHANGE [COLUMN] old_col_name new_col_name column_definition
            tablesql.push.apply tablesql, [indent, words.change_column, ' ', columnId, ' ', columnId, ' ', newTypeString, ' ', newModifier]
        else if oldModifier isnt newModifier
            # TODO: more tests to be able to do a proper default value comparaison
            # console.log oldModifier, newModifier
            return
        else
            return

        tablesql.join('')

    # Rename primary key does not exist in MySQL 5.7
    # we may drop the old one and create a new one,
    # but it will probably cause mess with foreign keys
    renamePrimaryKey: ->

    # https://dev.mysql.com/doc/refman/5.7/en/alter-table.html
    # ALTER [IGNORE] TABLE tbl_name
    #   DROP PRIMARY KEY
    dropPrimaryKey: (tableName, oldName, options)->
        options = _.defaults {}, options, this.options
        {words, escapeId, indent, LF} = @

        words.alter_table + ' ' + escapeId(tableName) +
            LF + indent + words.drop_primary_key

    # Rename foreign key does not exist in MySQL 5.7
    # drop the old one and create a new one
    renameForeignKey: (newTableModel, oldName, newKey, oldTableModel, options)->
        this.dropForeignKey(oldTableModel, oldName, options) + ';\n' + this.addForeignKey(newTableModel, newKey, options)

    # https://dev.mysql.com/doc/refman/5.7/en/alter-table.html
    # ALTER [IGNORE] TABLE tbl_name
    #   DROP FOREIGN KEY fk_symbol
    dropForeignKey: (oldTableModel, oldName, options)->
        options = _.defaults {}, options, this.options
        {words, escapeId, indent, LF} = @

        sql = words.alter_table + ' ' + escapeId(oldTableModel.name) +
            LF + indent + words.drop_foreign_key + ' ' + escapeId(oldName)

        # MySQL also drops the index with the same name
        if oldTableModel.indexes?.hasOwnProperty oldName
            delete oldTableModel.indexes[oldName]

        if oldTableModel.constraints.UNIQUE?.hasOwnProperty oldName
            delete oldTableModel.constraints.UNIQUE[oldName]

        sql

    # https://dev.mysql.com/doc/refman/5.7/en/alter-table.html
    # ALTER [IGNORE] TABLE tbl_name
    #   RENAME {INDEX|KEY} old_index_name TO new_index_name
    renameIndex: (tableName, oldName, newName, options)->
        {words, escapeId, indent, LF} = @
        words.alter_table + ' ' + escapeId(tableName) +
            LF + indent + words.rename_index + ' ' + escapeId(oldName) + ' ' + words.to + ' ' + escapeId(newName)

    # https://dev.mysql.com/doc/refman/5.7/en/alter-table.html
    # ALTER [IGNORE] TABLE tbl_name
    #   DROP {INDEX|KEY} index_name
    dropIndex: (tableName, indexName, options = {})->
        options = _.defaults {}, options, this.options
        {words, escapeId, indent, LF} = @

        words.alter_table + ' ' + escapeId(tableName) +
            LF + indent + words.drop_index + ' ' + escapeId(indexName)

MysqlSchemaCompiler::renameUniqueIndex = MysqlSchemaCompiler::renameIndex
MysqlSchemaCompiler::dropUniqueIndex = MysqlSchemaCompiler::dropIndex
