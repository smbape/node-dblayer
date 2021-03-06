var adapter,
  indexOf = [].indexOf;

adapter = require('./adapter');

module.exports = {
  getModel: function(connector, callback) {
    var options, query;
    options = connector.options;
    if (typeof callback !== 'function') {
      callback = (function() {});
    }
    query = `SELECT\n    inf.table_catalog AS "TABLE_DATABASE",\n    inf.table_schema AS "TABLE_SCHEMA",\n    inf.table_name AS "TABLE_NAME",\n    inf.column_name AS "COLUMN_NAME",\n    inf.ordinal_position AS "ORDINAL_POSITION",\n    inf.is_nullable AS "IS_NULLABLE",\n    inf.column_default AS "COLUMN_DEFAULT",\n\n    inf.udt_name AS "DATA_TYPE",\n    inf.numeric_precision AS "NUMERIC_PRECISION",\n    inf.numeric_scale AS "NUMERIC_SCALE",\n    inf.character_maximum_length AS "CHARACTER_MAXIMUM_LENGTH",\n    inf.datetime_precision AS "DATE_TIME_PRECISION",\n    inf.interval_type AS "INTERVAL_TYPE",\n    inf.interval_precision AS "INTERVAL_PRECISION",\n\n    tc.constraint_name AS "CONSTRAINT_NAME",\n    tc.constraint_type AS "CONSTRAINT_TYPE",\n    CASE tc.ordinal_position\n        WHEN NULL THEN NULL\n        ELSE tc.ordinal_position - 1\n    END AS "CONSTRAINT_INDEX_NUM",\n    tc.update_rule AS "UPDATE_RULE",\n    tc.delete_rule AS "DELETE_RULE",\n    tc.referenced_table AS "REFERENCED_TABLE",\n    tc.referenced_column AS "REFERENCED_COLUMN",\n\n    i.relname AS "INDEX_NAME",\n    i.s AS "INDEX_NUM"\n\nFROM information_schema.columns inf\n    INNER JOIN pg_namespace ns ON ns.nspname = inf.table_schema\n    INNER JOIN pg_class c ON c.relname = inf.table_name AND c.relnamespace = ns.oid\n    INNER JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = inf.column_name\n\n    LEFT JOIN (\n        SELECT\n            tc.table_catalog,\n            tc.table_schema,\n            tc.table_name,\n            kcu.column_name,\n            tc.constraint_name,\n            tc.constraint_type,\n            kcu.ordinal_position,\n            tc.is_deferrable,\n            tc.initially_deferred,\n            rc.match_option,\n\n            rc.update_rule,\n            rc.delete_rule,\n            ccu.table_name AS referenced_table,\n            ccu.column_name AS referenced_column\n\n        FROM information_schema.table_constraints tc\n\n        LEFT JOIN information_schema.key_column_usage kcu\n            ON tc.constraint_catalog = kcu.constraint_catalog\n            AND tc.constraint_schema = kcu.constraint_schema\n            AND tc.constraint_name = kcu.constraint_name\n\n        LEFT JOIN information_schema.referential_constraints rc\n            ON tc.constraint_catalog = rc.constraint_catalog\n            AND tc.constraint_schema = rc.constraint_schema\n            AND tc.constraint_name = rc.constraint_name\n\n        LEFT JOIN information_schema.constraint_column_usage ccu\n            ON rc.unique_constraint_catalog = ccu.constraint_catalog\n            AND rc.unique_constraint_schema = ccu.constraint_schema\n            AND rc.unique_constraint_name = ccu.constraint_name\n\n        WHERE tc.constraint_type in ('PRIMARY KEY', 'FOREIGN KEY', 'UNIQUE')\n    ) AS tc\n        ON tc.table_catalog = inf.table_catalog\n        AND tc.table_schema = inf.table_schema\n        AND tc.table_name = inf.table_name\n        AND tc.column_name = inf.column_name\n\n    LEFT JOIN (\n        SELECT\n            i.*,\n            c.relname,\n            am.amname,\n            generate_subscripts(i.indkey, 1) AS s\n        FROM pg_index i\n        INNER JOIN pg_class c ON c.oid = i.indexrelid\n        INNER JOIN pg_am am ON am.oid = c.relam\n        WHERE i.indisunique = FALSE AND i.indisprimary = FALSE\n    ) AS i ON i.indrelid  = c.oid AND a.attnum = i.indkey[i.s]\n\nWHERE inf.table_catalog = '${options.database}' AND inf.table_schema = '${options.schema}'\nORDER BY inf.table_catalog, inf.table_schema, inf.table_name, inf.ordinal_position`;
    connector.query(query, function(err, result) {
      var CHARACTER_MAXIMUM_LENGTH, COLUMN_DEFAULT, COLUMN_NAME, CONSTRAINT_INDEX_NUM, CONSTRAINT_NAME, CONSTRAINT_TYPE, DATA_TYPE, DATE_TIME_PRECISION, DELETE_RULE, INDEX_NAME, INDEX_NUM, INTERVAL_PRECISION, INTERVAL_TYPE, IS_NULLABLE, NUMERIC_PRECISION, NUMERIC_SCALE, REFERENCED_COLUMN, REFERENCED_TABLE, TABLE_NAME, TABLE_SCHEMA, UPDATE_RULE, column, constraint, escape, escapeId, i, index, len, model, ref, row, seq, sequences, serial, table;
      if (err) {
        return callback(err);
      }
      ({escapeId, escape} = adapter);
      model = {};
      ref = result.rows;
      for (i = 0, len = ref.length; i < len; i++) {
        row = ref[i];
        ({TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, DATA_TYPE, NUMERIC_PRECISION, NUMERIC_SCALE, CHARACTER_MAXIMUM_LENGTH, DATE_TIME_PRECISION, INTERVAL_PRECISION, INTERVAL_TYPE, IS_NULLABLE, COLUMN_DEFAULT, CONSTRAINT_NAME, CONSTRAINT_TYPE, CONSTRAINT_INDEX_NUM, REFERENCED_TABLE, REFERENCED_COLUMN, UPDATE_RULE, DELETE_RULE, INDEX_NAME, INDEX_NUM} = row);
        table = model[TABLE_NAME] || (model[TABLE_NAME] = {
          name: TABLE_NAME
        });
        model[TABLE_NAME].columns || (model[TABLE_NAME].columns = {});
        column = model[TABLE_NAME].columns[COLUMN_NAME] || (model[TABLE_NAME].columns[COLUMN_NAME] = {});
        if (!column.type) {
          seq = `${TABLE_NAME}_${COLUMN_NAME}_seq`;
          if (/[A-Z]/.test(seq)) {
            seq = escapeId(seq);
          }
          sequences = [`nextval(${escape(seq)}::regclass)`, `nextval(${escapeId(TABLE_SCHEMA)}.${escape(seq)}::regclass)`];
          column.defaultValue = COLUMN_DEFAULT;
          if (indexOf.call(sequences, COLUMN_DEFAULT) >= 0) {
            serial = true;
          } else {
            serial = false;
          }
          column.nullable = IS_NULLABLE === "YES";
          switch (DATA_TYPE) {
            case 'int2':
              if (serial) {
                column.type = 'smallincrements';
              } else {
                column.type = 'smallint';
              }
              break;
            case 'int4':
              if (serial) {
                column.type = 'increments';
              } else {
                column.type = 'integer';
              }
              break;
            case 'int8':
              if (serial) {
                column.type = 'bigincrements';
              } else {
                column.type = 'bigint';
              }
              break;
            case 'numeric':
              column.type = DATA_TYPE;
              column.type_args = [NUMERIC_PRECISION, NUMERIC_SCALE];
              break;
            case 'float4':
              column.type = 'float';
              break;
            case 'float8':
              column.type = 'double';
              break;
            case 'bpchar':
              column.type = 'char';
              column.type_args = [CHARACTER_MAXIMUM_LENGTH];
              break;
            case 'bit':
            case 'varbit':
            case 'varchar':
              column.type = DATA_TYPE;
              column.type_args = [CHARACTER_MAXIMUM_LENGTH];
              break;
            case 'timestamp':
            case 'timestampz':
            case 'time':
            case 'timez':
            case 'interval':
              column.type = DATA_TYPE;
              column.type_args = [INTERVAL_TYPE || DATE_TIME_PRECISION];
              break;
            default:
              column.type = DATA_TYPE;
          }
        }
        if (CONSTRAINT_NAME) {
          table.constraints || (table.constraints = {});
          table.constraints[CONSTRAINT_TYPE] || (table.constraints[CONSTRAINT_TYPE] = {});
          switch (CONSTRAINT_TYPE) {
            case 'PRIMARY KEY':
            case 'UNIQUE':
              constraint = table.constraints[CONSTRAINT_TYPE][CONSTRAINT_NAME] || (table.constraints[CONSTRAINT_TYPE][CONSTRAINT_NAME] = []);
              constraint[CONSTRAINT_INDEX_NUM] = COLUMN_NAME;
              break;
            case 'FOREIGN KEY':
              constraint = table.constraints[CONSTRAINT_TYPE][CONSTRAINT_NAME] || (table.constraints[CONSTRAINT_TYPE][CONSTRAINT_NAME] = {});
              constraint.column = COLUMN_NAME;
              constraint.referenced_table = REFERENCED_TABLE;
              constraint.referenced_column = REFERENCED_COLUMN;
              constraint.update_rule = UPDATE_RULE;
              constraint.delete_rule = DELETE_RULE;
          }
        }
        if (INDEX_NAME) {
          table.indexes || (table.indexes = {});
          index = table.indexes[INDEX_NAME] || (table.indexes[INDEX_NAME] = []);
          index[INDEX_NUM] = COLUMN_NAME;
        }
      }
      callback(err, model);
    });
    return query;
  }
};
