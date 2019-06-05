var ColumnCompiler, MysqlSchemaCompiler, SchemaCompiler, _, tools;

_ = require('lodash');

tools = require('../../tools');

SchemaCompiler = require('../../schema/SchemaCompiler');

ColumnCompiler = require('./ColumnCompiler');

module.exports = MysqlSchemaCompiler = (function() {
  class MysqlSchemaCompiler extends SchemaCompiler {
    // https://dev.mysql.com/doc/refman/5.7/en/alter-table.html
    // ALTER [IGNORE] TABLE tbl_name
    //   DROP [COLUMN] col_name
    dropColumn(tableName, column, options) {
      var LF, escapeId, indent, words;
      ({words, escapeId, indent, LF} = this);
      return words.alter_table + ' ' + escapeId(tableName) + LF + indent + words.drop_column + ' ' + escapeId(column);
    }

    diffType(tableName, column, oldColumnSpec, newColumnSpec) {
      var LF, altersql, args, columnCompiler, columnId, escapeId, indent, newModifier, newTypeString, oldModifier, oldTypeString, options, tablesql, words;
      options = _.defaults({}, options, this.options);
      ({words, escapeId, columnCompiler, args, indent, LF} = this);
      args.table = tableName;
      args.column = column;
      columnId = escapeId(column);
      // ALTER TABLE [ IF EXISTS ] name
      tablesql = [words.alter_table, ' '];
      if (options.if_exists) {
        tablesql.push(words.if_exists);
        tablesql.push(' ');
      }
      tablesql.push.apply(tablesql, [escapeId(tableName), LF]);
      altersql = [];
      oldTypeString = columnCompiler.getTypeString(oldColumnSpec);
      newTypeString = columnCompiler.getTypeString(newColumnSpec);
      oldModifier = columnCompiler.getColumnModifier(oldColumnSpec);
      newModifier = columnCompiler.getColumnModifier(newColumnSpec);
      if (oldTypeString !== newTypeString) {
        if (oldColumnSpec.type === 'enum' && newColumnSpec.type === 'enum') {
          return;
        }
        // CHANGE [COLUMN] old_col_name new_col_name column_definition
        // TODO: find a way to compare enum
        tablesql.push.apply(tablesql, [indent, words.change_column, ' ', columnId, ' ', columnId, ' ', newTypeString, ' ', newModifier]);
      } else if (oldModifier !== newModifier) {
        return;
      } else {
        return;
      }
      // TODO: more tests to be able to do a proper default value comparaison
      // console.log oldModifier, newModifier
      return tablesql.join('');
    }

    // Rename primary key does not exist in MySQL 5.7
    // we may drop the old one and create a new one,
    // but it will probably cause mess with foreign keys
    renamePrimaryKey() {}

    // https://dev.mysql.com/doc/refman/5.7/en/alter-table.html
    // ALTER [IGNORE] TABLE tbl_name
    //   DROP PRIMARY KEY
    dropPrimaryKey(tableName, oldName, options) {
      var LF, escapeId, indent, words;
      options = _.defaults({}, options, this.options);
      ({words, escapeId, indent, LF} = this);
      return words.alter_table + ' ' + escapeId(tableName) + LF + indent + words.drop_primary_key;
    }

    // Rename foreign key does not exist in MySQL 5.7
    // drop the old one and create a new one
    renameForeignKey(newTableModel, oldName, newKey, oldTableModel, options) {
      return this.dropForeignKey(oldTableModel, oldName, options) + ';\n' + this.addForeignKey(newTableModel, newKey, options);
    }

    // https://dev.mysql.com/doc/refman/5.7/en/alter-table.html
    // ALTER [IGNORE] TABLE tbl_name
    //   DROP FOREIGN KEY fk_symbol
    dropForeignKey(oldTableModel, oldName, options) {
      var LF, escapeId, indent, ref, ref1, sql, words;
      options = _.defaults({}, options, this.options);
      ({words, escapeId, indent, LF} = this);
      sql = words.alter_table + ' ' + escapeId(oldTableModel.name) + LF + indent + words.drop_foreign_key + ' ' + escapeId(oldName);
      // MySQL also drops the index with the same name
      if ((ref = oldTableModel.indexes) != null ? ref.hasOwnProperty(oldName) : void 0) {
        delete oldTableModel.indexes[oldName];
      }
      if ((ref1 = oldTableModel.constraints.UNIQUE) != null ? ref1.hasOwnProperty(oldName) : void 0) {
        delete oldTableModel.constraints.UNIQUE[oldName];
      }
      return sql;
    }

    // https://dev.mysql.com/doc/refman/5.7/en/alter-table.html
    // ALTER [IGNORE] TABLE tbl_name
    //   RENAME {INDEX|KEY} old_index_name TO new_index_name
    renameIndex(tableName, oldName, newName, options) {
      var LF, escapeId, indent, words;
      ({words, escapeId, indent, LF} = this);
      return words.alter_table + ' ' + escapeId(tableName) + LF + indent + words.rename_index + ' ' + escapeId(oldName) + ' ' + words.to + ' ' + escapeId(newName);
    }

    // https://dev.mysql.com/doc/refman/5.7/en/alter-table.html
    // ALTER [IGNORE] TABLE tbl_name
    //   DROP {INDEX|KEY} index_name
    dropIndex(tableName, indexName, options = {}) {
      var LF, escapeId, indent, words;
      options = _.defaults({}, options, this.options);
      ({words, escapeId, indent, LF} = this);
      return words.alter_table + ' ' + escapeId(tableName) + LF + indent + words.drop_index + ' ' + escapeId(indexName);
    }

  };

  MysqlSchemaCompiler.prototype.ColumnCompiler = ColumnCompiler;

  // https://dev.mysql.com/doc/refman/5.7/en/create-table-foreign-keys.html
  MysqlSchemaCompiler.prototype.validUpdateActions = ['no_action', 'restrict', 'cascade', 'set_null'];

  return MysqlSchemaCompiler;

}).call(this);

MysqlSchemaCompiler.prototype.renameUniqueIndex = MysqlSchemaCompiler.prototype.renameIndex;

MysqlSchemaCompiler.prototype.dropUniqueIndex = MysqlSchemaCompiler.prototype.dropIndex;
