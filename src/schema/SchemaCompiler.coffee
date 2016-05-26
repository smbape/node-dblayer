_ = require 'lodash'

module.exports = class SchemaCompiler
	constructor: (options = {})->
        columnCompiler = @columnCompiler = new @ColumnCompiler options

        @indent = options.indent or '    '
        @LF = options.LF or '\n'

        for prop in ['adapter', 'args', 'words']
            @[prop] = columnCompiler[prop]

        for method in ['escape', 'escapeId', 'escapeSearch', 'escapeBeginWith', 'escapeEndWith']
            if 'function' is typeof @adapter[method]
                @[method] = @adapter[method].bind @adapter

        @options = _.clone options

# https://dev.mysql.com/doc/refman/5.7/en/create-table.html
# http://www.postgresql.org/docs/9.4/static/sql-createtable.html
SchemaCompiler::createTable = (tableModel, options)->
    options = _.defaults {}, options, @options
    {words, escapeId, columnCompiler, args, indent, LF} = @

    tableName = tableModel.name
    tableNameId = escapeId tableName
    args.tableModel = tableName
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
    for column, spec of tableModel.columns
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
    if (pk = tableModel.constraints['PRIMARY KEY']) and not _.isEmpty(pk)
        count = 0
        for pkName, columns of pk
            if ++count is 2
                err = new Error "#{tableName} has more than one primary key"
                err.code = 'MULTIPLE_PK'
                throw err
            tablespec.push indent + words.constraint + ' ' + columnCompiler.pkString(pkName, columns)

    # unique indexes
    if (uk = tableModel.constraints.UNIQUE) and not _.isEmpty(uk)
        for ukName, columns of uk
            tablespec.push indent + words.constraint + ' ' + columnCompiler.ukString(ukName, columns)

    tablesql.push tablespec.join(',' + LF)
    tablesql.push LF
    tablesql.push ')'

    # indexes
    if tableModel.indexes and not _.isEmpty(tableModel.indexes)
        tablesql.push ';'
        tablesql.push LF
        count = 0
        for indexName, columns of tableModel.indexes
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
    if (fk = tableModel.constraints['FOREIGN KEY']) and not _.isEmpty(fk)
        for fkName, constraint of fk
            {
                column
                referenced_table
                referenced_column
                delete_rule
                update_rule
            } = constraint

            altersql.push.apply altersql, [
                LF, words.alter_table, ' ', escapeId(tableName)
                LF, indent, words.add_constraint, ' ', escapeId(fkName), ' ', words.foreign_key, ' (', escapeId(column), ')'
                LF, indent, indent, words.references, ' ', escapeId(referenced_table), ' (', escapeId(referenced_column) + ')'
            ]

            delete_rule = if delete_rule then delete_rule.toLowerCase() else 'restrict'
            update_rule = if update_rule then update_rule.toLowerCase() else 'restrict'

            if delete_rule not in @validUpdateActions
                err = new Error "unknown delete rule #{delete_rule}"
                err.code = 'UPDATE RULE'
                throw err

            if update_rule not in @validUpdateActions
                err = new Error "unknown update rule #{update_rule}"
                err.code = 'UPDATE RULE'
                throw err

            altersql.push.apply altersql, [LF, indent, indent, words.on_delete, ' ', words[delete_rule], ' ', words.on_update, ' ', words[update_rule], ';', LF]

    {create: tablesql.join(''), alter: altersql.slice(1).join('')}

# http://www.postgresql.org/docs/9.4/static/sql-droptable.html
# https://dev.mysql.com/doc/refman/5.7/en/drop-table.html
# DROP TABLE [ IF EXISTS ] name [, ...] [ CASCADE | RESTRICT ]
SchemaCompiler::dropTable = (tableName, options)->
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
# ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ]
#   ADD [ COLUMN ] column_name data_type [ COLLATE collation ] [ column_constraint [ ... ] ]
# 
# https://dev.mysql.com/doc/refman/5.7/en/alter-table.html
# ALTER [IGNORE] TABLE tbl_name
#   ADD [COLUMN] (col_name column_definition,...)
SchemaCompiler::addColumn = (tableName, column, spec, options)->
    options = _.defaults {}, options, @options
    {words, escapeId, columnCompiler, args, indent, LF} = @

    args.table = tableName
    args.column = column
    columnId = escapeId(column)

    altersql = [words.alter_table, ' ']
    # if options.if_exists
    #     altersql.push words.if_exists
    #     altersql.push ' '
    altersql.push.apply altersql, [
        escapeId(tableName), LF,
        indent, words.add_column, ' ', escapeId(column), ' ', columnCompiler.getTypeString(spec), ' ', columnCompiler.getColumnModifier(spec)
    ]

    altersql.join('')

# http://www.postgresql.org/docs/9.4/static/sql-altertable.html
# ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ]
#   ADD [ constraint_name ] PRIMARY KEY ( column_name [, ... ] ) index_parameters [ NOT VALID ]
# 
# https://dev.mysql.com/doc/refman/5.7/en/alter-table.html
# ALTER [IGNORE] TABLE tbl_name
#   ADD [CONSTRAINT [symbol]] PRIMARY KEY [index_type] (index_col_name,...) [index_option] ...
SchemaCompiler::addPrimaryKey = (tableName, newPkName, newColumns, options)->
    options = _.defaults {}, options, @options
    {words, escapeId, columnCompiler, indent, LF} = @

    altersql = [words.alter_table, ' ']
    # if options.if_exists
    #     altersql.push words.if_exists
    #     altersql.push ' '
    altersql.push.apply altersql, [escapeId(tableName), LF, indent, words.add_constraint, ' ', columnCompiler.pkString(newPkName, newColumns)]

    altersql.join('')

# http://www.postgresql.org/docs/9.4/static/sql-altertable.html
# ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ]
#     ADD [ constraint_name ] FOREIGN KEY ( column_name [, ... ] )
#         REFERENCES reftable [ ( refcolumn [, ... ] ) ] [ NOT VALID ]
#         [ MATCH FULL | MATCH PARTIAL | MATCH SIMPLE ] [ ON DELETE action ] [ ON UPDATE action ]

#         action:
#             [NO ACTION | RESTRICT | CASCADE | SET NULL | SET DEFAULT]

# https://dev.mysql.com/doc/refman/5.7/en/alter-table.html
# ALTER [IGNORE] TABLE tbl_name
#     ADD [CONSTRAINT [symbol]] FOREIGN KEY [index_name] (index_col_name,...)
#         REFERENCES tbl_name (index_col_name,...)
#         [MATCH FULL | MATCH PARTIAL | MATCH SIMPLE] [ON DELETE reference_option] [ON UPDATE reference_option]

#         action:
#             [RESTRICT | CASCADE | SET NULL | NO ACTION]
SchemaCompiler::addForeignKey = (tableModel, key, options)->
    options = _.defaults {}, options, @options
    {words, escapeId, indent, LF} = @

    altersql = [words.alter_table, ' ']
    # if options.if_exists
    #     altersql.push words.if_exists
    #     altersql.push ' '

    {
        name: fkName,
        column,
        referenced_table,
        referenced_column,
        delete_rule,
        update_rule
    } = key

    altersql.push.apply altersql, [
        escapeId(tableModel.name),
        LF, indent, words.add_constraint, ' ', escapeId(fkName), ' ', words.foreign_key, ' (', escapeId(column), ')'
        LF, indent, indent, words.references, ' ', escapeId(referenced_table), ' (', escapeId(referenced_column) + ')'
    ]

    delete_rule = if delete_rule then delete_rule.toLowerCase() else 'restrict'
    update_rule = if update_rule then update_rule.toLowerCase() else 'restrict'

    if delete_rule not in @validUpdateActions
        err = new Error "unknown delete rule #{delete_rule}"
        err.code = 'UPDATE RULE'
        throw err

    if update_rule not in @validUpdateActions
        err = new Error "unknown update rule #{update_rule}"
        err.code = 'UPDATE RULE'
        throw err

    altersql.push.apply altersql, [LF, indent, indent, words.on_delete, ' ', words[delete_rule], ' ', words.on_update, ' ', words[update_rule]]

    altersql.join('')

# http://www.postgresql.org/docs/9.4/static/sql-altertable.html
# ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ]
#     ADD [ constraint_name ] UNIQUE ( column_name [, ... ] ) index_parameters

# https://dev.mysql.com/doc/refman/5.7/en/alter-table.html
# ALTER [IGNORE] TABLE tbl_name
#     ADD [CONSTRAINT [symbol]] UNIQUE [INDEX|KEY] [index_name] [index_type] (index_col_name,...) [index_option]
SchemaCompiler::addUniqueIndex = (tableName, indexName, columns, options)->
    options = _.defaults {}, options, @options
    {words, escapeId, indent, LF} = @

    altersql = [words.alter_table, ' ']
    # if options.if_exists
    #     altersql.push words.if_exists
    #     altersql.push ' '
    altersql.push.apply altersql, [escapeId(tableName),
        LF, indent, words.add_constraint, ' ', escapeId(indexName), ' ', words.unique, ' (', columns.map(escapeId).join(', '), ')'
    ]

    altersql.join('')

# http://www.postgresql.org/docs/9.4/static/sql-createindex.html
# CREATE [ UNIQUE ] INDEX [ CONCURRENTLY ] [ name ] ON table_name
#   ( { column_name | ( expression ) } [ COLLATE collation ] [ opclass ] [ ASC | DESC ] [ NULLS { FIRST | LAST } ] [, ...] )
#
# https://dev.mysql.com/doc/refman/5.7/en/create-index.html
# CREATE [UNIQUE|FULLTEXT|SPATIAL] INDEX index_name [index_type] ON tbl_name
#     (index_col_name,...) [index_option] [algorithm_option | lock_option] ...
SchemaCompiler::addIndex = (tableName, indexName, columns, options)->
    options = _.defaults {}, options, @options
    {words, escapeId, columnCompiler} = @

    [words.create_index, ' ', columnCompiler.indexString(indexName, columns, escapeId(tableName))].join('')

SchemaCompiler::getDatabaseModel = (pMgr, options)->
    dbmodel = {}

    propToColumn = (prop)-> definition.properties[prop].column

    for className, definition of pMgr.classes
        tableName = definition.table
        tableMdel = dbmodel[tableName] =
            name: tableName
            columns: {}
            constraints:
                'PRIMARY KEY': {}
                'FOREIGN KEY': {}
                'UNIQUE': {}
            indexes: {}

        if definition.id and definition.id.column
            primaryKey = 'PK_' + (definition.id.pk or tableName)
            tableMdel.constraints['PRIMARY KEY'][primaryKey] = [definition.id.column]
            column = tableMdel.columns[definition.id.column] = @getSpec definition.id, pMgr
            if not column.type
                throw new Error "[#{className}] No type has been defined for id"

            column.nullable = false
            # a primary key implies unique index and not null
            # indexKey = tableName + '_PK'
            # tableMdel.constraints.UNIQUE[indexKey] = [definition.id.column]

            if definition.id.className
                parentDef = pMgr._getDefinition definition.id.className
                # a primary key implies unique index and not null, no need for another index
                @addForeignKeyConstraint 'EXT', tableMdel, definition.id, parentDef, _.defaults({fkindex: false}, options)

        if _.isEmpty tableMdel.constraints['PRIMARY KEY']
            delete tableMdel.constraints['PRIMARY KEY']

        for mixin, index in definition.mixins
            if mixin.column is definition.id.column
                continue

            parentDef = pMgr._getDefinition mixin.className

            column = tableMdel.columns[mixin.column] = @getSpec mixin, pMgr
            if not column.type
                throw new Error "[#{className}] No type has been defined for mixin #{mixin.className}"

            column.nullable = false
            # a unique index will be added
            [foreignKey, indexKey] = @addForeignKeyConstraint 'EXT', tableMdel, mixin, parentDef, _.defaults({fkindex: false}, options)

            # enforce unique key
            tableMdel.constraints.UNIQUE[indexKey] = [mixin.column]

        for prop, propDef of definition.properties
            column = tableMdel.columns[propDef.column] = @getSpec propDef, pMgr
            if not column.type
                throw new Error "[#{className}] No type has been defined for property #{prop}"

            if propDef.className
                parentDef = pMgr._getDefinition propDef.className
                @addForeignKeyConstraint 'HAS', tableMdel, propDef, parentDef, options

        if _.isEmpty tableMdel.constraints['FOREIGN KEY']
            delete tableMdel.constraints['FOREIGN KEY']

        {unique, names} = definition.constraints
        for key, properties of unique
            name = 'UK_' + names[key]
            tableMdel.constraints.UNIQUE[name] = properties.map propToColumn

        if _.isEmpty tableMdel.constraints.UNIQUE
            delete tableMdel.constraints.UNIQUE

        for name, properties in definition.indexes
            tableMdel.indexes[name] = properties.map propToColumn

    dbmodel

SchemaCompiler::getSpec = (model, pMgr)->
    spec = _.pick model, pMgr.specProperties
    if spec.defaultValue
        spec.defaultValue = @escape spec.defaultValue
    spec

SchemaCompiler::addForeignKeyConstraint = (name, tableMdel, propDef, parentDef, options = {})->
    keyName = propDef.fk or "#{tableMdel.name}_#{propDef.column}_#{name}_#{parentDef.table}_#{parentDef.id.column}"

    foreignKey = "FK_#{keyName}"
    tableMdel.constraints['FOREIGN KEY'][foreignKey] =
        column: propDef.column
        referenced_table: parentDef.table
        referenced_column: parentDef.id.column
        update_rule: 'RESTRICT'
        delete_rule: 'RESTRICT'

    # https://www.postgresql.org/docs/9.4/static/ddl-constraints.html
    # A foreign key must reference columns that either are a primary key or form a unique constraint.
    # This means that the referenced columns always have an index (the one underlying the primary key or unique constraint);
    # so checks on whether a referencing row has a match will be efficient.
    # Since a DELETE of a row from the referenced table or an UPDATE of a referenced column will require a scan of the referencing table for rows matching the old value,
    # it is often a good idea to index the referencing columns too.
    # Because this is not always needed, and there are many choices available on how to index,
    # declaration of a foreign key constraint does not automatically create an index on the referencing columns.
    # 
    # https://dev.mysql.com/doc/refman/5.7/en/create-table-foreign-keys.html
    # MySQL requires indexes on foreign keys and referenced keys so that foreign key checks can be fast and not require a table scan.
    # In the referencing table, there must be an index where the foreign key columns are listed as the first columns in the same order.
    # Such an index is created on the referencing table automatically if it does not exist.
    # This index might be silently dropped later, if you create another index that can be used to enforce the foreign key constraint.
    # index_name, if given, is used as described previously.
    indexKey = "#{keyName}_FK"
    if ! propDef.unique and propDef.fkindex isnt false and options.fkindex isnt false
        tableMdel.indexes[indexKey] = [propDef.column]

    [foreignKey, indexKey]
