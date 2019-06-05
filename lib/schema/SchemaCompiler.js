var SchemaCompiler, _,
  indexOf = [].indexOf;

_ = require('lodash');

module.exports = SchemaCompiler = class SchemaCompiler {
  constructor(options = {}) {
    var columnCompiler, i, j, len, len1, method, prop, ref, ref1;
    columnCompiler = this.columnCompiler = new this.ColumnCompiler(options);
    this.indent = options.indent || '    ';
    this.LF = options.LF || '\n';
    this.delimiter = options.delimiter || ';';
    ref = ['adapter', 'args', 'words'];
    for (i = 0, len = ref.length; i < len; i++) {
      prop = ref[i];
      this[prop] = columnCompiler[prop];
    }
    ref1 = ['escape', 'escapeId', 'escapeSearch', 'escapeBeginWith', 'escapeEndWith'];
    for (j = 0, len1 = ref1.length; j < len1; j++) {
      method = ref1[j];
      if ('function' === typeof this.adapter[method]) {
        this[method] = this.adapter[method].bind(this.adapter);
      }
    }
    this.options = _.clone(options);
  }

};

// https://dev.mysql.com/doc/refman/5.7/en/create-table.html
// http://www.postgresql.org/docs/9.4/static/sql-createtable.html
SchemaCompiler.prototype.createTable = function(tableModel, options) {
  var LF, altersql, args, colsql, column, columnCompiler, columnId, columns, constraint, count, delete_rule, delimiter, err, escapeId, fk, fkName, indent, indexName, length, pk, pkName, ref, ref1, referenced_column, referenced_table, spaceLen, spec, tableName, tableNameId, tablespec, tablesql, type, uk, ukName, update_rule, words;
  options = _.defaults({}, options, this.options);
  ({words, escapeId, columnCompiler, args, indent, LF, delimiter} = this);
  tableName = tableModel.name;
  tableNameId = escapeId(tableName);
  args.tableModel = tableName;
  tablesql = [];
  spaceLen = ' '.repeat(66 - 10 - tableName.length - 2);
  tablesql.push(`/*==============================================================*/\n/* Table: ${tableName}${spaceLen}*/\n/*==============================================================*/`);
  tablesql.push.apply(tablesql, [LF, words.create_table, ' ']);
  if (options.if_not_exists) {
    tablesql.push(words.if_not_exists);
    tablesql.push(' ');
  }
  tablesql.push.apply(tablesql, [tableNameId, ' (', LF]);
  tablespec = [];
  ref = tableModel.columns;
  // column definition
  for (column in ref) {
    spec = ref[column];
    columnId = escapeId(column);
    length = columnId.length;
    spaceLen = 21 - length;
    if (spaceLen <= 0) {
      spaceLen = 1;
      length++;
    } else {
      length = 21;
    }
    colsql = [columnId, ' '.repeat(spaceLen)];
    args.column = column;
    type = columnCompiler.getTypeString(spec);
    colsql.push(type);
    if (!type) {
      console.log(spec);
    }
    length += type.length;
    spaceLen = 42 - length;
    if (spaceLen <= 0) {
      spaceLen = 1;
    }
    colsql.push(' '.repeat(spaceLen));
    colsql.push(columnCompiler.getColumnModifier(spec));
    tablespec.push(indent + colsql.join(' '));
  }
  // primary key
  if ((pk = tableModel.constraints['PRIMARY KEY']) && !_.isEmpty(pk)) {
    count = 0;
    for (pkName in pk) {
      columns = pk[pkName];
      if (++count === 2) {
        err = new Error(`${tableName} has more than one primary key`);
        err.code = 'MULTIPLE_PK';
        throw err;
      }
      tablespec.push(indent + words.constraint + ' ' + columnCompiler.pkString(pkName, columns));
    }
  }
  // unique indexes
  if ((uk = tableModel.constraints.UNIQUE) && !_.isEmpty(uk)) {
    for (ukName in uk) {
      columns = uk[ukName];
      tablespec.push(indent + words.constraint + ' ' + columnCompiler.ukString(ukName, columns));
    }
  }
  tablesql.push(tablespec.join(',' + LF));
  tablesql.push(LF);
  tablesql.push(')');
  // indexes
  if (tableModel.indexes && !_.isEmpty(tableModel.indexes)) {
    tablesql.push(delimiter);
    tablesql.push(LF);
    count = 0;
    ref1 = tableModel.indexes;
    for (indexName in ref1) {
      columns = ref1[indexName];
      if (count === 0) {
        count = 1;
      } else {
        tablesql.push(delimiter);
        tablesql.push(LF);
      }
      tablesql.push(LF);
      spaceLen = ' '.repeat(66 - 10 - indexName.length - 2);
      tablesql.push(`/*==============================================================*/\n/* Index: ${indexName}${spaceLen}*/\n/*==============================================================*/`);
      tablesql.push.apply(tablesql, [LF, words.create_index, ' ', columnCompiler.indexString(indexName, columns, tableNameId)]);
    }
  }
  // foreign keys
  altersql = [];
  if ((fk = tableModel.constraints['FOREIGN KEY']) && !_.isEmpty(fk)) {
    for (fkName in fk) {
      constraint = fk[fkName];
      ({column, referenced_table, referenced_column, delete_rule, update_rule} = constraint);
      altersql.push.apply(altersql, [LF, words.alter_table, ' ', escapeId(tableName), LF, indent, words.add_constraint, ' ', escapeId(fkName), ' ', words.foreign_key, ' (', escapeId(column), ')', LF, indent, indent, words.references, ' ', escapeId(referenced_table), ' (', escapeId(referenced_column) + ')']);
      delete_rule = delete_rule ? delete_rule.toLowerCase() : 'restrict';
      update_rule = update_rule ? update_rule.toLowerCase() : 'restrict';
      if (indexOf.call(this.validUpdateActions, delete_rule) < 0) {
        err = new Error(`unknown delete rule ${delete_rule}`);
        err.code = 'UPDATE RULE';
        throw err;
      }
      if (indexOf.call(this.validUpdateActions, update_rule) < 0) {
        err = new Error(`unknown update rule ${update_rule}`);
        err.code = 'UPDATE RULE';
        throw err;
      }
      altersql.push.apply(altersql, [LF, indent, indent, words.on_delete, ' ', words[delete_rule], ' ', words.on_update, ' ', words[update_rule], delimiter, LF]);
    }
  }
  return {
    create: tablesql.join(''),
    alter: altersql.slice(1).join('')
  };
};

// http://www.postgresql.org/docs/9.4/static/sql-droptable.html
// https://dev.mysql.com/doc/refman/5.7/en/drop-table.html
// DROP TABLE [ IF EXISTS ] name [, ...] [ CASCADE | RESTRICT ]
SchemaCompiler.prototype.dropTable = function(tableName, options) {
  var escapeId, tablesql, words;
  options = _.defaults({}, options, this.options);
  ({words, escapeId} = this);
  tablesql = [words.drop_table];
  if (options.if_exists) {
    tablesql.push(words.if_exists);
  }
  tablesql.push(escapeId(tableName));
  if (options.cascade) {
    tablesql.push(words.cascade);
  } else if (options.restrict) {
    tablesql.push(words.restrict);
  }
  return tablesql.join(' ');
};

// http://www.postgresql.org/docs/9.4/static/sql-altertable.html
// ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ]
//   ADD [ COLUMN ] column_name data_type [ COLLATE collation ] [ column_constraint [ ... ] ]

// https://dev.mysql.com/doc/refman/5.7/en/alter-table.html
// ALTER [IGNORE] TABLE tbl_name
//   ADD [COLUMN] (col_name column_definition,...)
SchemaCompiler.prototype.addColumn = function(tableName, column, spec, options) {
  var LF, altersql, args, columnCompiler, columnId, escapeId, indent, words;
  options = _.defaults({}, options, this.options);
  ({words, escapeId, columnCompiler, args, indent, LF} = this);
  args.table = tableName;
  args.column = column;
  columnId = escapeId(column);
  altersql = [words.alter_table, ' '];
  // if options.if_exists
  //     altersql.push words.if_exists
  //     altersql.push ' '
  altersql.push.apply(altersql, [escapeId(tableName), LF, indent, words.add_column, ' ', escapeId(column), ' ', columnCompiler.getTypeString(spec), ' ', columnCompiler.getColumnModifier(spec)]);
  return altersql.join('');
};

// http://www.postgresql.org/docs/9.4/static/sql-altertable.html
// ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ]
//   ADD [ constraint_name ] PRIMARY KEY ( column_name [, ... ] ) index_parameters [ NOT VALID ]

// https://dev.mysql.com/doc/refman/5.7/en/alter-table.html
// ALTER [IGNORE] TABLE tbl_name
//   ADD [CONSTRAINT [symbol]] PRIMARY KEY [index_type] (index_col_name,...) [index_option] ...
SchemaCompiler.prototype.addPrimaryKey = function(tableName, newPkName, newColumns, options) {
  var LF, altersql, columnCompiler, escapeId, indent, words;
  options = _.defaults({}, options, this.options);
  ({words, escapeId, columnCompiler, indent, LF} = this);
  altersql = [words.alter_table, ' '];
  // if options.if_exists
  //     altersql.push words.if_exists
  //     altersql.push ' '
  altersql.push.apply(altersql, [escapeId(tableName), LF, indent, words.add_constraint, ' ', columnCompiler.pkString(newPkName, newColumns)]);
  return altersql.join('');
};

// http://www.postgresql.org/docs/9.4/static/sql-altertable.html
// ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ]
//     ADD [ constraint_name ] FOREIGN KEY ( column_name [, ... ] )
//         REFERENCES reftable [ ( refcolumn [, ... ] ) ] [ NOT VALID ]
//         [ MATCH FULL | MATCH PARTIAL | MATCH SIMPLE ] [ ON DELETE action ] [ ON UPDATE action ]

//         action:
//             [NO ACTION | RESTRICT | CASCADE | SET NULL | SET DEFAULT]

// https://dev.mysql.com/doc/refman/5.7/en/alter-table.html
// ALTER [IGNORE] TABLE tbl_name
//     ADD [CONSTRAINT [symbol]] FOREIGN KEY [index_name] (index_col_name,...)
//         REFERENCES tbl_name (index_col_name,...)
//         [MATCH FULL | MATCH PARTIAL | MATCH SIMPLE] [ON DELETE reference_option] [ON UPDATE reference_option]

//         action:
//             [RESTRICT | CASCADE | SET NULL | NO ACTION]
SchemaCompiler.prototype.addForeignKey = function(tableModel, key, options) {
  var LF, altersql, column, delete_rule, err, escapeId, fkName, indent, referenced_column, referenced_table, update_rule, words;
  options = _.defaults({}, options, this.options);
  ({words, escapeId, indent, LF} = this);
  altersql = [words.alter_table, ' '];
  ({
    // if options.if_exists
    //     altersql.push words.if_exists
    //     altersql.push ' '
    name: fkName,
    column,
    referenced_table,
    referenced_column,
    delete_rule,
    update_rule
  } = key);
  altersql.push.apply(altersql, [escapeId(tableModel.name), LF, indent, words.add_constraint, ' ', escapeId(fkName), ' ', words.foreign_key, ' (', escapeId(column), ')', LF, indent, indent, words.references, ' ', escapeId(referenced_table), ' (', escapeId(referenced_column) + ')']);
  delete_rule = delete_rule ? delete_rule.toLowerCase() : 'restrict';
  update_rule = update_rule ? update_rule.toLowerCase() : 'restrict';
  if (indexOf.call(this.validUpdateActions, delete_rule) < 0) {
    err = new Error(`unknown delete rule ${delete_rule}`);
    err.code = 'UPDATE RULE';
    throw err;
  }
  if (indexOf.call(this.validUpdateActions, update_rule) < 0) {
    err = new Error(`unknown update rule ${update_rule}`);
    err.code = 'UPDATE RULE';
    throw err;
  }
  altersql.push.apply(altersql, [LF, indent, indent, words.on_delete, ' ', words[delete_rule], ' ', words.on_update, ' ', words[update_rule]]);
  return altersql.join('');
};

// http://www.postgresql.org/docs/9.4/static/sql-altertable.html
// ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ]
//     ADD [ constraint_name ] UNIQUE ( column_name [, ... ] ) index_parameters

// https://dev.mysql.com/doc/refman/5.7/en/alter-table.html
// ALTER [IGNORE] TABLE tbl_name
//     ADD [CONSTRAINT [symbol]] UNIQUE [INDEX|KEY] [index_name] [index_type] (index_col_name,...) [index_option]
SchemaCompiler.prototype.addUniqueIndex = function(tableName, indexName, columns, options) {
  var LF, altersql, escapeId, indent, words;
  options = _.defaults({}, options, this.options);
  ({words, escapeId, indent, LF} = this);
  altersql = [words.alter_table, ' '];
  // if options.if_exists
  //     altersql.push words.if_exists
  //     altersql.push ' '
  altersql.push.apply(altersql, [escapeId(tableName), LF, indent, words.add_constraint, ' ', escapeId(indexName), ' ', words.unique, ' (', columns.map(escapeId).join(', '), ')']);
  return altersql.join('');
};

// http://www.postgresql.org/docs/9.4/static/sql-createindex.html
// CREATE [ UNIQUE ] INDEX [ CONCURRENTLY ] [ name ] ON table_name
//   ( { column_name | ( expression ) } [ COLLATE collation ] [ opclass ] [ ASC | DESC ] [ NULLS { FIRST | LAST } ] [, ...] )

// https://dev.mysql.com/doc/refman/5.7/en/create-index.html
// CREATE [UNIQUE|FULLTEXT|SPATIAL] INDEX index_name [index_type] ON tbl_name
//     (index_col_name,...) [index_option] [algorithm_option | lock_option] ...
SchemaCompiler.prototype.addIndex = function(tableName, indexName, columns, options) {
  var columnCompiler, escapeId, words;
  options = _.defaults({}, options, this.options);
  ({words, escapeId, columnCompiler} = this);
  return [words.create_index, ' ', columnCompiler.indexString(indexName, columns, escapeId(tableName))].join('');
};

SchemaCompiler.prototype.getDatabaseModel = function(pMgr, options) {
  var className, column, dbmodel, definition, foreignKey, i, index, indexKey, j, key, len, len1, mixin, name, names, parentDef, primaryKey, prop, propDef, propToColumn, properties, ref, ref1, ref2, ref3, tableModel, tableName, unique;
  dbmodel = {};
  propToColumn = function(prop) {
    return definition.properties[prop].column;
  };
  ref = pMgr.classes;
  for (className in ref) {
    definition = ref[className];
    tableName = definition.table;
    if (options.lower_case_table_names === 1) {
      tableName = tableName.toLowerCase();
    }
    tableModel = dbmodel[tableName] = {
      name: tableName,
      columns: {},
      constraints: {
        'PRIMARY KEY': {},
        'FOREIGN KEY': {},
        'UNIQUE': {}
      },
      indexes: {}
    };
    if (definition.id && definition.id.column) {
      primaryKey = 'PK_' + (definition.id.pk || tableName);
      tableModel.constraints['PRIMARY KEY'][primaryKey] = [definition.id.column];
      column = tableModel.columns[definition.id.column] = this.getSpec(definition.id, pMgr);
      if (!column.type) {
        throw new Error(`[${className}] No type has been defined for id`);
      }
      column.nullable = false;
      // a primary key implies unique index and not null
      // indexKey = tableName + '_PK'
      // tableModel.constraints.UNIQUE[indexKey] = [definition.id.column]
      if (definition.id.className) {
        parentDef = pMgr._getDefinition(definition.id.className);
        // a primary key implies unique index and not null, no need for another index
        this.addForeignKeyConstraint('EXT', tableModel, definition.id, parentDef, _.defaults({
          fkindex: false
        }, options));
      }
    }
    if (_.isEmpty(tableModel.constraints['PRIMARY KEY'])) {
      delete tableModel.constraints['PRIMARY KEY'];
    }
    ref1 = definition.mixins;
    for (index = i = 0, len = ref1.length; i < len; index = ++i) {
      mixin = ref1[index];
      if (mixin.column === definition.id.column) {
        continue;
      }
      parentDef = pMgr._getDefinition(mixin.className);
      column = tableModel.columns[mixin.column] = this.getSpec(mixin, pMgr);
      if (!column.type) {
        throw new Error(`[${className}] No type has been defined for mixin ${mixin.className}`);
      }
      column.nullable = false;
      // a unique index will be added
      [foreignKey, indexKey] = this.addForeignKeyConstraint('EXT', tableModel, mixin, parentDef, _.defaults({
        fkindex: false
      }, options));
      // enforce unique key
      tableModel.constraints.UNIQUE[indexKey] = [mixin.column];
    }
    ref2 = definition.properties;
    for (prop in ref2) {
      propDef = ref2[prop];
      column = tableModel.columns[propDef.column] = this.getSpec(propDef, pMgr);
      if (!column.type) {
        throw new Error(`[${className}] No type has been defined for property ${prop}`);
      }
      if (propDef.className) {
        parentDef = pMgr._getDefinition(propDef.className);
        this.addForeignKeyConstraint('HAS', tableModel, propDef, parentDef, options);
      }
    }
    if (_.isEmpty(tableModel.constraints['FOREIGN KEY'])) {
      delete tableModel.constraints['FOREIGN KEY'];
    }
    ({unique, names} = definition.constraints);
    for (key in unique) {
      properties = unique[key];
      name = 'UK_' + names[key];
      tableModel.constraints.UNIQUE[name] = properties.map(propToColumn);
    }
    if (_.isEmpty(tableModel.constraints.UNIQUE)) {
      delete tableModel.constraints.UNIQUE;
    }
    ref3 = definition.indexes;
    for (properties = j = 0, len1 = ref3.length; j < len1; properties = ++j) {
      name = ref3[properties];
      tableModel.indexes[name] = properties.map(propToColumn);
    }
  }
  return dbmodel;
};

SchemaCompiler.prototype.getSpec = function(model, pMgr) {
  var spec;
  spec = _.pick(model, pMgr.specProperties);
  if (spec.defaultValue) {
    spec.defaultValue = this.escape(spec.defaultValue);
  }
  return spec;
};

SchemaCompiler.prototype.addForeignKeyConstraint = function(name, tableModel, propDef, parentDef, options = {}) {
  var foreignKey, indexKey, keyName;
  keyName = propDef.fk || `${tableModel.name}_${propDef.column}_${name}_${parentDef.table}_${parentDef.id.column}`;
  foreignKey = `FK_${keyName}`;
  tableModel.constraints['FOREIGN KEY'][foreignKey] = {
    column: propDef.column,
    referenced_table: parentDef.table,
    referenced_column: parentDef.id.column,
    update_rule: 'RESTRICT',
    delete_rule: 'RESTRICT'
  };
  // https://www.postgresql.org/docs/9.4/static/ddl-constraints.html
  // A foreign key must reference columns that either are a primary key or form a unique constraint.
  // This means that the referenced columns always have an index (the one underlying the primary key or unique constraint);
  // so checks on whether a referencing row has a match will be efficient.
  // Since a DELETE of a row from the referenced table or an UPDATE of a referenced column will require a scan of the referencing table for rows matching the old value,
  // it is often a good idea to index the referencing columns too.
  // Because this is not always needed, and there are many choices available on how to index,
  // declaration of a foreign key constraint does not automatically create an index on the referencing columns.

  // https://dev.mysql.com/doc/refman/5.7/en/create-table-foreign-keys.html
  // MySQL requires indexes on foreign keys and referenced keys so that foreign key checks can be fast and not require a table scan.
  // In the referencing table, there must be an index where the foreign key columns are listed as the first columns in the same order.
  // Such an index is created on the referencing table automatically if it does not exist.
  // This index might be silently dropped later, if you create another index that can be used to enforce the foreign key constraint.
  // index_name, if given, is used as described previously.
  indexKey = `${keyName}_FK`;
  if (!propDef.unique && propDef.fkindex !== false && options.fkindex !== false) {
    tableModel.indexes[indexKey] = [propDef.column];
  }
  return [foreignKey, indexKey];
};
