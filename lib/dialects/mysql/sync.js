var adapter;

adapter = require('./adapter');

module.exports = {
  getModel: function(connector, callback) {
    var options, query;
    options = connector.options;
    if (typeof callback !== 'function') {
      callback = (function() {});
    }
    query = "SELECT\n    inf.table_schema AS `TABLE_SCHEMA`,\n    inf.table_name AS `TABLE_NAME`,\n    inf.column_name AS `COLUMN_NAME`,\n    inf.ordinal_position AS `ORDINAL_POSITION`,\n    inf.is_nullable AS `IS_NULLABLE`,\n    inf.column_default AS `COLUMN_DEFAULT`,\n    inf.extra AS `EXTRA`,\n\n    inf.data_type AS `DATA_TYPE`,\n    inf.column_type AS `COLUMN_TYPE`,\n    inf.numeric_precision AS `NUMERIC_PRECISION`,\n    inf.numeric_scale AS `NUMERIC_SCALE`,\n    inf.character_maximum_length AS `CHARACTER_MAXIMUM_LENGTH`,\n    inf.datetime_precision AS `DATE_TIME_PRECISION`,\n    -- inf.interval_type AS `INTERVAL_TYPE`,\n    -- inf.interval_precision AS `INTERVAL_PRECISION`,\n\n    tc.constraint_name AS `CONSTRAINT_NAME`,\n    tc.constraint_type AS `CONSTRAINT_TYPE`,\n    tc.index_num AS `CONSTRAINT_INDEX_NUM`,\n    tc.update_rule AS `UPDATE_RULE`,\n    tc.delete_rule AS `DELETE_RULE`,\n    tc.referenced_table_name AS `REFERENCED_TABLE`,\n    tc.referenced_column_name AS `REFERENCED_COLUMN`,\n\n    i.index_name AS `INDEX_NAME`,\n    CASE i.seq_in_index\n        WHEN NULL THEN NULL\n        ELSE i.seq_in_index - 1\n    END AS `INDEX_NUM`\n\nFROM information_schema.columns inf\n\n    INNER JOIN information_schema.tables tabs\n        ON tabs.table_catalog = inf.table_catalog\n        AND tabs.table_schema = inf.table_schema\n        AND tabs.table_name = inf.table_name\n\n    LEFT JOIN (\n        SELECT\n            tc.constraint_catalog,\n            tc.table_schema,\n            tc.constraint_name,\n            tc.constraint_type,\n            tc.table_name,\n            kcu.column_name,\n            -- tc.is_deferrable,\n            -- tc.initially_deferred,\n            rc.match_option,\n\n            rc.update_rule,\n            rc.delete_rule,\n            kcu.referenced_table_name,\n            kcu.referenced_column_name,\n\n            CASE i.seq_in_index\n                WHEN NULL THEN NULL\n                ELSE i.seq_in_index - 1\n            END AS index_num\n\n        FROM information_schema.key_column_usage kcu\n\n        LEFT JOIN information_schema.table_constraints tc\n            ON tc.constraint_catalog = kcu.constraint_catalog\n            AND tc.constraint_schema = kcu.constraint_schema\n            AND tc.constraint_name = kcu.constraint_name\n            AND tc.table_schema = kcu.table_schema\n            AND tc.table_name = kcu.table_name\n\n        LEFT JOIN information_schema.referential_constraints rc\n            ON rc.constraint_catalog = tc.constraint_catalog\n            AND rc.constraint_schema = tc.constraint_schema\n            AND rc.constraint_name = tc.constraint_name\n\n        LEFT JOIN information_schema.STATISTICS  i\n            ON i.table_catalog = tc.constraint_catalog\n            AND i.table_schema = tc.table_schema\n            AND i.table_name = tc.table_name\n            AND i.column_name = kcu.column_name\n            AND i.index_name = tc.constraint_name\n\n        WHERE tc.constraint_type in ('PRIMARY KEY', 'FOREIGN KEY', 'UNIQUE')\n    ) AS tc\n        ON tc.constraint_catalog = inf.table_catalog\n        AND tc.table_schema = inf.table_schema\n        AND tc.table_name = inf.table_name\n        AND tc.column_name = inf.column_name\n\n    LEFT JOIN information_schema.STATISTICS  i\n        ON i.table_catalog = inf.table_catalog\n        AND i.table_schema = inf.table_schema\n        AND i.table_name = inf.table_name\n        AND i.column_name = inf.column_name\n        AND i.non_unique = 1\n\n    WHERE inf.table_schema = '" + options.database + "'\n    ORDER BY inf.table_schema, inf.table_name, inf.ordinal_position";
    connector.query(query, function(err, result) {
      var CHARACTER_MAXIMUM_LENGTH, COLUMN_DEFAULT, COLUMN_NAME, COLUMN_TYPE, CONSTRAINT_INDEX_NUM, CONSTRAINT_NAME, CONSTRAINT_TYPE, DATA_TYPE, DATE_TIME_PRECISION, DELETE_RULE, EXTRA, INDEX_NAME, INDEX_NUM, IS_NULLABLE, NUMERIC_PRECISION, NUMERIC_SCALE, REFERENCED_COLUMN, REFERENCED_TABLE, TABLE_NAME, TABLE_SCHEMA, UPDATE_RULE, column, constraint, i, index, len, match, model, ref, row, serial, table;
      if (err) {
        return callback(err);
      }
      model = {};
      ref = result.rows;
      for (i = 0, len = ref.length; i < len; i++) {
        row = ref[i];
        TABLE_SCHEMA = row.TABLE_SCHEMA, TABLE_NAME = row.TABLE_NAME, COLUMN_NAME = row.COLUMN_NAME, DATA_TYPE = row.DATA_TYPE, COLUMN_TYPE = row.COLUMN_TYPE, EXTRA = row.EXTRA, NUMERIC_PRECISION = row.NUMERIC_PRECISION, NUMERIC_SCALE = row.NUMERIC_SCALE, CHARACTER_MAXIMUM_LENGTH = row.CHARACTER_MAXIMUM_LENGTH, DATE_TIME_PRECISION = row.DATE_TIME_PRECISION, IS_NULLABLE = row.IS_NULLABLE, COLUMN_DEFAULT = row.COLUMN_DEFAULT, CONSTRAINT_NAME = row.CONSTRAINT_NAME, CONSTRAINT_TYPE = row.CONSTRAINT_TYPE, CONSTRAINT_INDEX_NUM = row.CONSTRAINT_INDEX_NUM, REFERENCED_TABLE = row.REFERENCED_TABLE, REFERENCED_COLUMN = row.REFERENCED_COLUMN, UPDATE_RULE = row.UPDATE_RULE, DELETE_RULE = row.DELETE_RULE, INDEX_NAME = row.INDEX_NAME, INDEX_NUM = row.INDEX_NUM;
        table = model[TABLE_NAME] || (model[TABLE_NAME] = {
          name: TABLE_NAME
        });
        model[TABLE_NAME].columns || (model[TABLE_NAME].columns = {});
        column = model[TABLE_NAME].columns[COLUMN_NAME] || (model[TABLE_NAME].columns[COLUMN_NAME] = {});
        if (!column.type) {
          serial = EXTRA === 'auto_increment';
          column.nullable = IS_NULLABLE === "YES";
          column.defaultValue = COLUMN_DEFAULT;
          switch (DATA_TYPE) {
            case 'bit':
              column.type = DATA_TYPE;
              column.type_args = [NUMERIC_PRECISION];
              break;
            case 'tinyint':
            case 'smallint':
            case 'mediumint':
            case 'int':
            case 'bigint':
              if (serial) {
                column.type = DATA_TYPE.replace('int', 'increments');
              } else {
                column.type = DATA_TYPE;
                match = COLUMN_TYPE.match(/int\((\d+)\)( unsigned)?( zerofill)?/);
                column.type_args = [match[1], !!match[2], !!match[3]];
              }
              break;
            case 'decimal':
              column.type = DATA_TYPE;
              column.type_args = [NUMERIC_PRECISION, NUMERIC_SCALE];
              break;
            case 'float':
            case 'double':
              column.type = DATA_TYPE;
              column.type_args = [NUMERIC_PRECISION, NUMERIC_SCALE, /\bunsigned\b/.test(COLUMN_TYPE), /\bzerofill\b/.test(COLUMN_TYPE)];
              break;
            case 'char':
            case 'varchar':
            case 'blob':
            case 'text':
              column.type = DATA_TYPE;
              column.type_args = [CHARACTER_MAXIMUM_LENGTH];
              break;
            case 'datetime':
            case 'timestamp':
            case 'time':
              column.type = DATA_TYPE;
              column.type_args = [DATE_TIME_PRECISION];
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
      connector.query("SHOW VARIABLES LIKE 'lower_case_table_names'", function(err, result) {
        var lower_case_table_names;
        if (err) {
          return callback(err);
        }
        lower_case_table_names = result.rows[0].Value;
        callback(err, model, {
          lower_case_table_names: parseInt(lower_case_table_names, 10)
        });
      });
    });
    return query;
  }
};
