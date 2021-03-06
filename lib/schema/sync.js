var _flipForeignKeys, _flipIndex, _getIndexUniquId, _sync, _tableDiff, clone, cloneDeep, defaults, guessEscapeOpts, isEmpty;

clone = require('lodash/clone');

cloneDeep = require('lodash/cloneDeep');

defaults = require('lodash/defaults');

isEmpty = require('lodash/isEmpty');

({guessEscapeOpts} = require('../tools'));

// PersistenceManager sync method
exports.sync = function(options, callback) {
  var SchemaCompiler, connector, dialect, newModel, schema, sync;
  if ('function' === typeof options) {
    callback = options;
    options = null;
  }
  options = guessEscapeOpts(options, this.defaults.sync);
  ({connector, dialect} = options);
  sync = require('../dialects/' + dialect + '/sync');
  SchemaCompiler = require('../dialects/' + dialect + '/SchemaCompiler');
  schema = new SchemaCompiler(options);
  newModel = schema.getDatabaseModel(this, options);
  return sync.getModel(connector, function(err, oldModel, oldOpts) {
    var alters, creates, drop_constraints, drops, queries, query;
    if (err) {
      return callback(err);
    }
    options = Object.assign({}, options, oldOpts);
    try {
      queries = _sync(oldModel, newModel, schema, options);
    } catch (error) {
      err = error;
      callback(err);
      return;
    }
    queries.options = options;
    if (options.exec) {
      ({drop_constraints, drops, creates, alters} = queries);
      query = drop_constraints.concat(drops).concat(creates).concat(alters).join(';\n');
      if (query.length > 0) {
        connector.exec(query + ';', options, function(err) {
          callback(err, queries, oldModel, newModel);
        });
        return;
      }
    }
    callback(err, queries, oldModel, newModel);
  });
};

_sync = function(oldModel, newModel, schema, options) {
  var alter, alters, create, drops, fkName, indexName, keys, lower_case_table_names, model, name, oldTableModel, opts, purge, queries, tableName;
  queries = {
    creates: [],
    alters: [],
    drops: [],
    drop_constraints: []
  };
  opts = defaults({schema}, options);
  ({purge, lower_case_table_names} = options);
  if (lower_case_table_names === 1) {
    model = {};
    for (name in newModel) {
      model[name.toLowerCase()] = newModel[name];
    }
    newModel = model;
  } else {
    newModel = clone(newModel);
  }
  if (oldModel) {
    for (tableName in oldModel) {
      oldTableModel = oldModel[tableName];
      // if tableName isnt 'CLASS_D'
      //     continue
      if (newModel.hasOwnProperty(tableName)) {
        ({alters, drops} = _tableDiff(oldTableModel, newModel[tableName], opts));
        delete newModel[tableName];
        queries.alters.push.apply(queries.alters, alters);
        queries.drops.push.apply(queries.drops, drops);
      } else if (purge) {
        // drop foreign keys
        if ((keys = oldTableModel.constraints['FOREIGN KEY']) && !isEmpty(keys)) {
          for (fkName in keys) {
            queries.drop_constraints.push(schema.dropForeignKey(oldTableModel, fkName, options));
          }
        }
        // drop unique indexes
        if ((keys = oldTableModel.constraints.UNIQUE) && !isEmpty(keys)) {
          for (indexName in keys) {
            queries.drop_constraints.push(schema.dropUniqueIndex(tableName, indexName, options));
          }
        }
        // drop indexes
        if (!isEmpty(oldTableModel.indexes)) {
          for (indexName in oldTableModel.indexes) {
            queries.drop_constraints.push(schema.dropIndex(tableName, indexName, options));
          }
        }
        // drop table
        queries.drops.push(schema.dropTable(tableName, options));
      }
    }
  }
  for (tableName in newModel) {
    // if tableName isnt 'CLASS_D'
    //     continue
    ({create, alter} = schema.createTable(newModel[tableName], opts));
    queries.creates.push(create);
    queries.alters.push(alter);
  }
  return queries;
};

_tableDiff = function(oldTableModel, newTableModel, options = {}) {
  var adapter, alter, alters, column, columns, count, drops, id, indexes, keys, newColumnSpec, newColumns, newIndex, newIndexes, newJoinedPkColumns, newKey, newKeys, newName, newPkName, newUniqueIndexes, oldColumnSpec, oldColumns, oldIndex, oldIndexes, oldJoinedPkColumns, oldKey, oldKeys, oldPkName, oldUniqueIndexes, pk, pkName, purge, queries, ref, ref1, referenced_table, renames, schema, tableName;
  // console.log require('util').inspect(oldTableModel, {colors: true, depth: null})
  // console.log require('util').inspect(newTableModel, {colors: true, depth: null})
  newTableModel = cloneDeep(newTableModel);
  ({schema, renames, queries, purge} = options);
  ({adapter} = schema);
  tableName = newTableModel.name;
  drops = [];
  alters = [];
  ref = oldTableModel.columns;
  for (column in ref) {
    oldColumnSpec = ref[column];
    if (renames && renames.hasOwnProperty(column)) {
      newName = renames[column];
      if (newName && newTableModel.columns.hasOwnProperty(newName)) {
        newColumnSpec = newTableModel.columns[newName];
        delete newTableModel.columns[newName];
        alter = schema.diffType(tableName, column, oldColumnSpec, newColumnSpec, options);
        if (alter) {
          alters.push(alter);
        } else {
          alters.push(schema.renameColumn(tableName, column, newName, options));
        }
      } else if (purge) {
        drops.push(schema.dropColumn(tableName, column, options));
      }
    } else if (newTableModel.columns.hasOwnProperty(column)) {
      newColumnSpec = newTableModel.columns[column];
      delete newTableModel.columns[column];
      alter = schema.diffType(tableName, column, oldColumnSpec, newColumnSpec, options);
      if (alter) {
        alters.push(alter);
      }
    } else if (purge) {
      drops.push(schema.dropColumn(tableName, column, options));
    }
  }
  ref1 = newTableModel.columns;
  for (column in ref1) {
    newColumnSpec = ref1[column];
    alters.push(schema.addColumn(tableName, column, newColumnSpec, options));
  }
  // primary key
  if ((pk = oldTableModel.constraints['PRIMARY KEY']) && !isEmpty(pk)) {
    count = 0;
    for (pkName in pk) {
      columns = pk[pkName];
      if (++count === 2) {
        throw new Error(`${tableName} oldTableModel has more than one primary key`);
      }
      oldPkName = pkName;
      oldColumns = columns;
      oldJoinedPkColumns = columns.map(adapter.escapeId).join(', ');
    }
  }
  if ((pk = newTableModel.constraints['PRIMARY KEY']) && !isEmpty(pk)) {
    count = 0;
    for (pkName in pk) {
      columns = pk[pkName];
      if (++count === 2) {
        throw new Error(`${tableName} newTableModel has more than one primary key`);
      }
      newPkName = pkName;
      newColumns = columns;
      newJoinedPkColumns = columns.map(adapter.escapeId).join(', ');
    }
  }
  if (oldJoinedPkColumns !== newJoinedPkColumns) {
    if (!newJoinedPkColumns) {
      if (purge) {
        alters.push(schema.dropPrimaryKey(tableName, oldPkName, options));
      }
    } else if (oldJoinedPkColumns) {
      alters.push(schema.dropPrimaryKey(tableName, oldPkName, options));
      alters.push(schema.addPrimaryKey(tableName, newPkName, newColumns, options));
    } else {
      alters.push(schema.addPrimaryKey(tableName, newPkName, newColumns, options));
    }
  } else if (oldPkName !== newPkName) {
    if (alter = schema.renamePrimaryKey(tableName, oldPkName, newPkName, options)) {
      alters.push(alter);
    }
  }
  // foreign keys
  if ((keys = oldTableModel.constraints['FOREIGN KEY']) && !isEmpty(keys)) {
    oldKeys = _flipForeignKeys(keys);
  }
  if ((keys = newTableModel.constraints['FOREIGN KEY']) && !isEmpty(keys)) {
    newKeys = _flipForeignKeys(keys);
  }
  for (column in oldKeys) {
    oldKey = oldKeys[column];
    if (newKeys && newKeys.hasOwnProperty(column)) {
      newKey = newKeys[column];
      delete newKeys[column];
      ({referenced_table} = newKey);
      if (options.lower_case_table_names === 1) {
        referenced_table = referenced_table.toLowerCase();
      }
      if (oldKey.referenced_table !== referenced_table || oldKey.referenced_column !== newKey.referenced_column) {
        alters.push(schema.dropForeignKey(oldTableModel, oldKey.name, options));
        alters.push(schema.addForeignKey(newTableModel, newKey, options));
      } else if (oldKey.name !== newKey.name) {
        if (options.renameForeignKey) {
          alters.push(schema.renameForeignKey(newTableModel, oldKey.name, newKey, oldTableModel, options));
        }
      }
    } else if (purge) {
      alters.push(schema.dropForeignKey(oldTableModel, oldKey.name, options));
    }
  }
  if (newKeys) {
    for (column in newKeys) {
      newKey = newKeys[column];
      alters.push(schema.addForeignKey(newTableModel, newKey, options));
    }
  }
  // unique indexes
  if ((indexes = oldTableModel.constraints.UNIQUE) && !isEmpty(indexes)) {
    oldUniqueIndexes = _flipIndex(indexes, adapter);
  }
  if ((indexes = newTableModel.constraints.UNIQUE) && !isEmpty(indexes)) {
    newUniqueIndexes = _flipIndex(indexes, adapter);
  }
  if (oldUniqueIndexes) {
    if (newUniqueIndexes) {
      for (id in oldUniqueIndexes) {
        oldIndex = oldUniqueIndexes[id];
        if (newUniqueIndexes.hasOwnProperty(id)) {
          newIndex = newUniqueIndexes[id];
          delete newUniqueIndexes[id];
          if (oldIndex.name !== newIndex.name) {
            alters.push(schema.renameUniqueIndex(tableName, oldIndex.name, newIndex.name, options));
          }
        } else if (newJoinedPkColumns === oldIndex.columns.map(adapter.escapeId).join(', ')) {
          // unique index exists as primary key
          continue;
        } else if (purge) {
          alters.push(schema.dropUniqueIndex(tableName, oldIndex.name, options));
        }
      }
    } else if (purge) {
      for (id in oldUniqueIndexes) {
        oldIndex = oldUniqueIndexes[id];
        if (newJoinedPkColumns === oldIndex.columns.map(adapter.escapeId).join(', ')) {
          // unique index exists as primary key
          continue;
        }
        alters.push(schema.dropUniqueIndex(tableName, oldIndex.name, options));
      }
    }
  }
  if (newUniqueIndexes) {
    for (id in newUniqueIndexes) {
      newIndex = newUniqueIndexes[id];
      alters.push(schema.addUniqueIndex(tableName, newIndex.name, newIndex.columns, options));
    }
  }
  // indexes
  if ((indexes = oldTableModel.indexes) && !isEmpty(indexes)) {
    oldIndexes = _flipIndex(indexes);
  }
  if ((indexes = newTableModel.indexes) && !isEmpty(indexes)) {
    newIndexes = _flipIndex(indexes);
  }
  if (oldIndexes) {
    if (newIndexes) {
      for (id in oldIndexes) {
        oldIndex = oldIndexes[id];
        if (newIndexes.hasOwnProperty(id)) {
          newIndex = newIndexes[id];
          delete newIndexes[id];
          if (oldIndex.name !== newIndex.name) {
            alters.push(schema.renameIndex(tableName, oldIndex.name, newIndex.name, options));
          }
        } else if (purge) {
          alters.push(schema.dropIndex(tableName, oldIndex.name, options));
        }
      }
    } else if (purge) {
      for (id in oldIndexes) {
        oldIndex = oldIndexes[id];
        alters.push(schema.dropIndex(tableName, oldIndex.name, options));
      }
    }
  }
  if (newIndexes) {
    for (id in newIndexes) {
      newIndex = newIndexes[id];
      alters.push(schema.addIndex(tableName, newIndex.name, newIndex.columns, options));
    }
  }
  return {alters, drops};
};

_flipForeignKeys = function(keys) {
  var fk, flip, name;
  flip = {};
  for (name in keys) {
    fk = keys[name];
    fk.name = name;
    flip[fk.column] = fk;
  }
  return flip;
};

_flipIndex = function(keys) {
  var columns, flip, name;
  flip = {};
  for (name in keys) {
    columns = keys[name];
    flip[_getIndexUniquId(columns)] = {name, columns};
  }
  return flip;
};

_getIndexUniquId = function(columns) {
  return columns.join(':');
};
