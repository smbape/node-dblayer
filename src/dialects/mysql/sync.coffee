adapter = require './adapter'

module.exports =
    getModel: (connector, callback)->
        options = connector.options
        callback = (->) if typeof callback isnt 'function'
        query = """
        SELECT
            inf.table_schema AS `TABLE_SCHEMA`,
            inf.table_name AS `TABLE_NAME`,
            inf.column_name AS `COLUMN_NAME`,
            inf.ordinal_position AS `ORDINAL_POSITION`,
            inf.is_nullable AS `IS_NULLABLE`,
            inf.column_default AS `COLUMN_DEFAULT`,
            inf.extra AS `EXTRA`,

            inf.data_type AS `DATA_TYPE`,
            inf.column_type AS `COLUMN_TYPE`,
            inf.numeric_precision AS `NUMERIC_PRECISION`,
            inf.numeric_scale AS `NUMERIC_SCALE`,
            inf.character_maximum_length AS `CHARACTER_MAXIMUM_LENGTH`,
            inf.datetime_precision AS `DATE_TIME_PRECISION`,
            -- inf.interval_type AS `INTERVAL_TYPE`,
            -- inf.interval_precision AS `INTERVAL_PRECISION`,

            tc.constraint_name AS `CONSTRAINT_NAME`,
            tc.constraint_type AS `CONSTRAINT_TYPE`,
            tc.index_num AS `CONSTRAINT_INDEX_NUM`,
            tc.update_rule AS `UPDATE_RULE`,
            tc.delete_rule AS `DELETE_RULE`,
            tc.referenced_table_name AS `REFERENCED_TABLE`,
            tc.referenced_column_name AS `REFERENCED_COLUMN`,

            i.index_name AS `INDEX_NAME`,
            CASE i.seq_in_index
                WHEN NULL THEN NULL
                ELSE i.seq_in_index - 1
            END AS `INDEX_NUM`

        FROM information_schema.columns inf

            INNER JOIN information_schema.tables tabs
                ON tabs.table_catalog = inf.table_catalog
                AND tabs.table_schema = inf.table_schema
                AND tabs.table_name = inf.table_name

            LEFT JOIN (
                SELECT
                    tc.constraint_catalog,
                    tc.table_schema,
                    tc.constraint_name,
                    tc.constraint_type,
                    tc.table_name,
                    kcu.column_name,
                    -- tc.is_deferrable,
                    -- tc.initially_deferred,
                    rc.match_option,

                    rc.update_rule,
                    rc.delete_rule,
                    kcu.referenced_table_name,
                    kcu.referenced_column_name,

                    CASE i.seq_in_index
                        WHEN NULL THEN NULL
                        ELSE i.seq_in_index - 1
                    END AS index_num

                FROM information_schema.key_column_usage kcu

                LEFT JOIN information_schema.table_constraints tc
                    ON tc.constraint_catalog = kcu.constraint_catalog
                    AND tc.constraint_schema = kcu.constraint_schema
                    AND tc.constraint_name = kcu.constraint_name
                    AND tc.table_schema = kcu.table_schema
                    AND tc.table_name = kcu.table_name

                LEFT JOIN information_schema.referential_constraints rc
                    ON rc.constraint_catalog = tc.constraint_catalog
                    AND rc.constraint_schema = tc.constraint_schema
                    AND rc.constraint_name = tc.constraint_name

                LEFT JOIN information_schema.STATISTICS  i
                    ON i.table_catalog = tc.constraint_catalog
                    AND i.table_schema = tc.table_schema
                    AND i.table_name = tc.table_name
                    AND i.column_name = kcu.column_name
                    AND i.index_name = tc.constraint_name

                WHERE tc.constraint_type in ('PRIMARY KEY', 'FOREIGN KEY', 'UNIQUE')
            ) AS tc
                ON tc.constraint_catalog = inf.table_catalog
                AND tc.table_schema = inf.table_schema
                AND tc.table_name = inf.table_name
                AND tc.column_name = inf.column_name

            LEFT JOIN information_schema.STATISTICS  i
                ON i.table_catalog = inf.table_catalog
                AND i.table_schema = inf.table_schema
                AND i.table_name = inf.table_name
                AND i.column_name = inf.column_name
                AND i.non_unique = 1

            WHERE inf.table_schema = '#{options.database}'
            ORDER BY inf.table_schema, inf.table_name, inf.ordinal_position
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
                    COLUMN_TYPE
                    EXTRA
                    NUMERIC_PRECISION
                    NUMERIC_SCALE
                    CHARACTER_MAXIMUM_LENGTH
                    DATE_TIME_PRECISION
                    IS_NULLABLE
                    COLUMN_DEFAULT
                    CONSTRAINT_NAME
                    CONSTRAINT_TYPE
                    CONSTRAINT_INDEX_NUM
                    REFERENCED_TABLE
                    REFERENCED_COLUMN
                    UPDATE_RULE
                    DELETE_RULE
                    INDEX_NAME
                    INDEX_NUM
                } = row

                table = model[TABLE_NAME] or (model[TABLE_NAME] = {name: TABLE_NAME})
                model[TABLE_NAME].columns or (model[TABLE_NAME].columns = {})
                column = model[TABLE_NAME].columns[COLUMN_NAME] or (model[TABLE_NAME].columns[COLUMN_NAME] = {})

                if not column.type
                    serial = EXTRA is 'auto_increment'
                    column.nullable = IS_NULLABLE is "YES"
                    column.defaultValue = COLUMN_DEFAULT

                    switch DATA_TYPE
                        when 'bit'
                            column.type = DATA_TYPE
                            column.type_args = [NUMERIC_PRECISION]
                        when 'tinyint', 'smallint', 'mediumint', 'int', 'bigint'
                            if serial
                                column.type = DATA_TYPE.replace('int', 'increments')
                            else
                                column.type = DATA_TYPE
                                match = COLUMN_TYPE.match /int\((\d+)\)( unsigned)?( zerofill)?/
                                column.type_args = [match[1], !!match[2], !!match[3]]
                        when 'decimal'
                            column.type = DATA_TYPE
                            column.type_args = [NUMERIC_PRECISION, NUMERIC_SCALE]
                        when 'float', 'double'
                            column.type = DATA_TYPE
                            column.type_args = [NUMERIC_PRECISION, NUMERIC_SCALE, /\bunsigned\b/.test(COLUMN_TYPE), /\bzerofill\b/.test(COLUMN_TYPE)]
                        when 'char', 'varchar', 'blob', 'text'
                            column.type = DATA_TYPE
                            column.type_args = [CHARACTER_MAXIMUM_LENGTH]
                        when 'datetime', 'timestamp', 'time'
                            column.type = DATA_TYPE
                            column.type_args = [DATE_TIME_PRECISION]
                        else
                            column.type = DATA_TYPE

                if CONSTRAINT_NAME
                    table.constraints or (table.constraints = {})
                    table.constraints[CONSTRAINT_TYPE] or (table.constraints[CONSTRAINT_TYPE] = {})
                    switch CONSTRAINT_TYPE
                        when 'PRIMARY KEY', 'UNIQUE'
                            constraint = table.constraints[CONSTRAINT_TYPE][CONSTRAINT_NAME] or (table.constraints[CONSTRAINT_TYPE][CONSTRAINT_NAME] = [])
                            constraint[CONSTRAINT_INDEX_NUM] = COLUMN_NAME
                        when 'FOREIGN KEY'
                            constraint = table.constraints[CONSTRAINT_TYPE][CONSTRAINT_NAME] or (table.constraints[CONSTRAINT_TYPE][CONSTRAINT_NAME] = {})
                            constraint.column = COLUMN_NAME
                            constraint.referenced_table = REFERENCED_TABLE
                            constraint.referenced_column = REFERENCED_COLUMN
                            constraint.update_rule = UPDATE_RULE
                            constraint.delete_rule = DELETE_RULE

                if INDEX_NAME
                    table.indexes or (table.indexes = {})
                    index = table.indexes[INDEX_NAME] or (table.indexes[INDEX_NAME] = [])
                    index[INDEX_NUM] = COLUMN_NAME

            connector.query "SHOW VARIABLES LIKE 'lower_case_table_names'", (err, result) ->
                return callback(err) if err
                {
                    Value: lower_case_table_names
                    # Variable_name
                } = result.rows[0]

                callback err, model, {
                    lower_case_table_names: parseInt(lower_case_table_names, 10)
                }
                return
            return
        query
