module.exports =
    getModel: (connector, callback)->
        options = connector.options
        callback = (->) if typeof callback isnt 'function'
        query = """
        SELECT
            inf.table_catalog AS "TABLE_DATABASE",
            inf.table_schema AS "TABLE_SCHEMA",
            inf.table_name AS "TABLE_NAME",
            inf.column_name AS "COLUMN_NAME",
            inf.ordinal_position AS "ORDINAL_POSITION",
            inf.is_nullable AS "IS_NULLABLE",
            inf.column_default AS "COLUMN_DEFAULT",

            inf.udt_name AS "DATA_TYPE",
            inf.numeric_precision AS "NUMERIC_PRECISION",
            inf.numeric_scale AS "NUMERIC_SCALE",
            inf.character_maximum_length AS "CHARACTER_MAXIMUM_LENGTH",
            inf.datetime_precision AS "DATE_TIME_PRECISION",
            inf.interval_type AS "INTERVAL_TYPE",
            inf.interval_precision AS "INTERVAL_PRECISION",

            tc.constraint_name AS "CONSTRAINT_NAME",
            tc.constraint_type AS "CONSTRAINT_TYPE",
            tc.on_update AS "UPDATE_RULE",
            tc.on_delete AS "DELETE_RULE",
            tc.referenced_table AS "REFERENCED_TABLE",
            tc.referenced_column AS "REFERENCED_COLUMN",

            i.relname AS "INDEX_NAME"

        FROM information_schema.columns inf
            INNER JOIN pg_class c ON c.relname = inf.table_name
            INNER JOIN pg_attribute a
                ON a.attrelid = c.oid
                AND a.attname = inf.column_name
            INNER JOIN pg_type t ON a.atttypid = t.oid

            LEFT JOIN (
                SELECT
                    tc.table_catalog,
                    tc.table_schema,
                    tc.constraint_name,
                    tc.constraint_type,
                    tc.table_name,
                    kcu.column_name,
                    tc.is_deferrable,
                    tc.initially_deferred,
                    rc.match_option AS match_type,

                    rc.update_rule AS on_update,
                    rc.delete_rule AS on_delete,
                    ccu.table_name AS referenced_table,
                    ccu.column_name AS referenced_column

                FROM information_schema.table_constraints tc

                LEFT JOIN information_schema.key_column_usage kcu
                    ON tc.constraint_catalog = kcu.constraint_catalog
                    AND tc.constraint_schema = kcu.constraint_schema
                    AND tc.constraint_name = kcu.constraint_name

                LEFT JOIN information_schema.referential_constraints rc
                    ON tc.constraint_catalog = rc.constraint_catalog
                    AND tc.constraint_schema = rc.constraint_schema
                    AND tc.constraint_name = rc.constraint_name

                LEFT JOIN information_schema.constraint_column_usage ccu
                    ON rc.unique_constraint_catalog = ccu.constraint_catalog
                    AND rc.unique_constraint_schema = ccu.constraint_schema
                    AND rc.unique_constraint_name = ccu.constraint_name

                WHERE tc.constraint_type in ('PRIMARY KEY', 'FOREIGN KEY', 'UNIQUE')
            ) AS tc
                ON tc.table_catalog = inf.table_catalog
                AND tc.table_schema = inf.table_schema
                AND tc.table_name = inf.table_name
                AND tc.column_name = inf.column_name

            LEFT JOIN (
                SELECT
                    i.indrelid,
                    c.relname,
                    am.amname,
                    i.indkey,
                    i.indpred
                FROM pg_index i
                INNER JOIN pg_class c ON c.oid = i.indexrelid
                INNER JOIN pg_am am ON am.oid = c.relam
                WHERE i.indisunique = FALSE AND i.indisprimary = FALSE
            ) AS i ON i.indrelid  = c.oid AND a.attnum = ANY(i.indkey)

        WHERE
            inf.table_catalog = '#{options.database}'
            AND inf.table_schema = '#{options.schema}'
        ORDER BY inf.table_catalog, inf.table_schema, "TABLE_NAME", "ORDINAL_POSITION", "COLUMN_NAME" DESC
        """

        connector.query query, (err, result)->
            return callback(err) if err

            model = {}
            for row in result.rows
                {
                    TABLE_SCHEMA
                    TABLE_NAME
                    COLUMN_NAME
                    DATA_TYPE
                    NUMERIC_PRECISION
                    NUMERIC_SCALE
                    CHARACTER_MAXIMUM_LENGTH
                    IS_NULLABLE
                    COLUMN_DEFAULT
                    CONSTRAINT_NAME
                    CONSTRAINT_TYPE
                    REFERENCED_TABLE
                    REFERENCED_COLUMN
                    UPDATE_RULE
                    DELETE_RULE
                    INDEX_NAME
                } = row

                table = model[TABLE_NAME] or (model[TABLE_NAME] = {name: TABLE_NAME})
                model[TABLE_NAME].columns or (model[TABLE_NAME].columns = {})
                column = model[TABLE_NAME].columns[COLUMN_NAME] or (model[TABLE_NAME].columns[COLUMN_NAME] = {})

                if not column.type
                    sequences = [
                        "nextval('\"#{TABLE_NAME}_#{COLUMN_NAME}_seq\"'::regclass)"
                        "nextval('\"#{TABLE_SCHEMA}\".\"#{TABLE_NAME}_#{COLUMN_NAME}_seq\"'::regclass)"
                    ]
                    column.defaultValue = COLUMN_DEFAULT
                    if COLUMN_DEFAULT in sequences
                        serial = true
                    else
                        serial = false

                    column.nullable = IS_NULLABLE is "YES"

                    switch DATA_TYPE
                        when 'int2'
                            column.type = 'smallint'
                        when 'int4'
                            if serial
                                column.type = 'increments'
                            else
                                column.type = 'integer'
                        when 'int8'
                            if serial
                                column.type = 'bigincrements'
                            else
                                column.type = 'bigint'
                        when 'numeric'
                            column.type = DATA_TYPE
                            column.type_args = [NUMERIC_PRECISION, NUMERIC_SCALE]
                        when 'float4'
                            column.type = 'float'
                        when 'float8'
                            column.type = 'double'
                        when 'bpchar'
                            column.type = 'char'
                            column.type_args = [CHARACTER_MAXIMUM_LENGTH]
                        when 'bit', 'varbit', 'varchar'
                            column.type = DATA_TYPE
                            column.type_args = [CHARACTER_MAXIMUM_LENGTH]
                        else
                            column.type = DATA_TYPE

                if CONSTRAINT_NAME
                    table.constraints or (table.constraints = {})
                    table.constraints[CONSTRAINT_TYPE] or (table.constraints[CONSTRAINT_TYPE] = {})
                    switch CONSTRAINT_TYPE
                        when 'PRIMARY KEY', 'UNIQUE'
                            constraint = table.constraints[CONSTRAINT_TYPE][CONSTRAINT_NAME] or (table.constraints[CONSTRAINT_TYPE][CONSTRAINT_NAME] = [])
                            if -1 is constraint.indexOf COLUMN_NAME
                                constraint.push COLUMN_NAME
                        when 'FOREIGN KEY'
                            constraint = table.constraints[CONSTRAINT_TYPE][CONSTRAINT_NAME] or (table.constraints[CONSTRAINT_TYPE][CONSTRAINT_NAME] = {})
                            constraint.column = COLUMN_NAME
                            constraint.references_table = REFERENCED_TABLE
                            constraint.references_column = REFERENCED_COLUMN
                            constraint.update_rule = UPDATE_RULE
                            constraint.delete_rule = DELETE_RULE

                if INDEX_NAME
                    table.indexes or (table.indexes = {})
                    index = table.indexes[INDEX_NAME] or (table.indexes[INDEX_NAME] = [])
                    if -1 is index.indexOf COLUMN_NAME
                        index.push COLUMN_NAME

            callback err, model
            return
        query
