var AdapterPool, CompiledMapping, DefaultQueryBuilderOptions, DeleteQuery, InsertQuery, PRIMITIVE_TYPES, PersistenceManager, RowMap, SelectQuery, UpdateQuery, _, _addUpdateOrDeleteCondition, _addWhereAttr, _getCacheId, _getInitializeCondition, _toInsertLine, assertValidModelInstance, async, delegateMethod, flavours, getAdapter, getSquel, guessEscapeOpts, hasProp, isValidModelInstance, log4js, logger, semLib, squel, tools;

log4js = require('./log4js');

logger = log4js.getLogger(__filename.replace(/^(?:.+[\/\\])?([^.\/\\]+)(?:.[^.]+)?$/, '$1'));

_ = require('lodash');

squel = require('squel');

RowMap = require('./RowMap');

CompiledMapping = require('./CompiledMapping');

AdapterPool = require('./AdapterPool');

async = require('async');

semLib = require('sem-lib');

tools = require('./tools');

({
  adapter: getAdapter,
  guessEscapeOpts
} = tools);

hasProp = Object.prototype.hasOwnProperty;

flavours = {};

(function() {
  var _squel, dialect;
  for (dialect in squel.flavours) {
    _squel = squel.useFlavour(dialect);
    _squel.cls.Expression = squel.cls.Expression;
    flavours[dialect] = _squel;
  }
  return flavours;
})();

getSquel = function(dialect) {
  if (hasProp.call(flavours, dialect)) {
    return flavours[dialect];
  } else {
    return squel;
  }
};

DefaultQueryBuilderOptions = _.defaults({
  replaceSingleQuotes: true
}, squel.cls.DefaultQueryBuilderOptions);

delegateMethod = function(self, className, method, target = method) {
  if (method === 'new') {
    self[method + className] = self.newInstance.bind(self, className);
    return;
  }
  self[method + className] = function(model, options, done) {
    if (_.isPlainObject(model)) {
      model = self.newInstance(className, model);
    }
    if ('function' === typeof options) {
      done = options;
      options = {};
    }
    return self[target](model, _.extend({className}, options), done);
  };
};

module.exports = PersistenceManager = (function() {
  class PersistenceManager extends CompiledMapping {
    constructor(...args) {
      var className, connectors, j, k, len, len1, mapping, method, name, options, pool, pools, ref, ref1, users;
      super(...args);
      [mapping, options] = args;
      this.defaults = _.cloneDeep(this.defaults);
      for (className in this.classes) {
        ref = ['insert', 'update', 'save', 'delete'];
        for (j = 0, len = ref.length; j < len; j++) {
          method = ref[j];
          delegateMethod(this, className, method);
        }
        delegateMethod(this, className, 'new');
        this['list' + className] = this.list.bind(this, className);
        this['remove' + className] = this['delete' + className];
      }
      pools = this.pools = {};
      connectors = this.connectors = {};
      if (options && _.isObject(users = options.users)) {
        ref1 = ['admin', 'writer', 'reader'];
        for (k = 0, len1 = ref1.length; k < len1; k++) {
          name = ref1[k];
          if (hasProp.call(users, name)) {
            pool = pools[name] = new AdapterPool(users[name]);
            connectors[name] = pool.createConnector();
          }
        }
        this.defaults.sync = _.defaults({
          connector: connectors.admin
        }, this.defaults.sync);
        this.defaults.insert = _.defaults({
          connector: connectors.writer || connectors.admin
        }, this.defaults.insert);
        this.defaults.update = _.defaults({
          connector: connectors.writer || connectors.admin
        }, this.defaults.update);
        this.defaults.delete = _.defaults({
          connector: connectors.writer || connectors.admin
        }, this.defaults.delete);
        this.defaults.save = _.defaults({
          connector: connectors.writer || connectors.admin
        }, this.defaults.save);
        this.defaults.list = _.defaults({
          connector: connectors.reader || connectors.writer || connectors.admin
        }, this.defaults.list);
      }
    }

    destroyPools(safe = true, done) {
      var count, name, pool, ref;
      if ('function' === typeof safe) {
        done = safe;
        safe = true;
      }
      count = Object.keys(this.pools).length;
      if (count === 0) {
        if ('function' === typeof done) {
          done();
        }
        return;
      }
      ref = this.pools;
      for (name in ref) {
        pool = ref[name];
        (function(name, pool) {
          pool.destroyAll(safe, function(err) {
            if (err) {
              console.error(err);
            }
            if (--count === 0) {
              if ('function' === typeof done) {
                done();
              }
            }
          });
        })(name, pool);
      }
    }

  };

  PersistenceManager.prototype.defaults = {
    list: {
      depth: 10
    },
    insert: {},
    update: {},
    save: {},
    delete: {},
    sync: {}
  };

  return PersistenceManager;

}).call(this);

isValidModelInstance = function(model) {
  var err, j, len, method, ref;
  if (!model || 'object' !== typeof model) {
    err = new Error('Invalid model');
    err.code = 'INVALID_MODEL';
    return err;
  }
  ref = ['get', 'set', 'unset', 'toJSON'];
  for (j = 0, len = ref.length; j < len; j++) {
    method = ref[j];
    if ('function' !== typeof model[method]) {
      err = new Error(`method ${method} was not found`);
      err.code = 'INVALID_MODEL';
      return err;
    }
  }
  return true;
};

assertValidModelInstance = function(model) {
  var err;
  err = isValidModelInstance(model);
  if (err instanceof Error) {
    throw err;
  }
};

PersistenceManager.getSquelQuery = PersistenceManager.prototype.getSquelQuery = function(type, dialect) {
  var options;
  options = _.defaults(getAdapter(dialect).squelOptions, DefaultQueryBuilderOptions);
  return getSquel(dialect)[type](options);
};

PersistenceManager.getSquelOptions = PersistenceManager.prototype.getSquelOptions = function(dialect) {
  return _.defaults(getAdapter(dialect).squelOptions, DefaultQueryBuilderOptions);
};

PersistenceManager.decorateInsert = PersistenceManager.prototype.decorateInsert = function(dialect, insert, column) {
  var adapter;
  adapter = getAdapter(dialect);
  if ('function' === typeof adapter.decorateInsert) {
    adapter.decorateInsert(insert, column);
  }
  return insert;
};

PersistenceManager.insertDefaultValue = PersistenceManager.prototype.insertDefaultValue = function(dialect, insert, column) {
  var adapter;
  adapter = getAdapter(dialect);
  if ('function' === typeof adapter.insertDefaultValue) {
    adapter.insertDefaultValue(insert, column, getSquel(dialect));
  }
  return insert;
};

PersistenceManager.prototype.insert = function(model, options, callback, guess = true) {
  var connector, err, query;
  if (guess) {
    options = _.defaults({
      autoRollback: false
    }, guessEscapeOpts(options, this.defaults.insert));
  }
  try {
    query = this.getInsertQuery(model, options, false);
  } catch (error) {
    err = error;
    return callback(err);
  }
  connector = options.connector;
  connector.acquire(function(err, performed) {
    if (err) {
      return callback(err);
    }
    connector.begin(function(err) {
      if (err) {
        if (performed) {
          connector.release(function(_err) {
            callback(_err ? [err, _err] : err);
          });
          return;
        }
        callback(err);
        return;
      }
      query.execute(connector, function(...args) {
        var method;
        method = args[0] ? 'rollback' : 'commit';
        connector[method](function(err) {
          if (err) {
            if (args[0]) {
              args[0] = [err, args[0]];
            } else {
              args[0] = err;
            }
          }
          if (performed) {
            connector.release(function(err) {
              if (err) {
                logger.error(err);
              }
              callback.apply(null, args);
            });
          } else {
            callback.apply(null, args);
          }
        });
      });
    });
  });
};

PersistenceManager.prototype.getInsertQuery = function(model, options, guess = true) {
  if (guess) {
    options = guessEscapeOpts(options, this.defaults.insert);
  }
  return new InsertQuery(this, model, options, false);
};

PersistenceManager.prototype.list = function(className, options, callback, guess = true) {
  var connector, err, query;
  if ('function' === typeof options) {
    callback = options;
    options = {};
  }
  if (guess) {
    options = guessEscapeOpts(options, this.defaults.list);
  }
  try {
    query = this.getSelectQuery(className, options, false);
  } catch (error) {
    err = error;
    return callback(err);
  }
  connector = options.connector;
  return query.list(connector, callback);
};

PersistenceManager.prototype.stream = function(className, options, callback, done) {
  var connector, err, listConnector, query;
  options = guessEscapeOpts(options, this.defaults.list);
  try {
    query = this.getSelectQuery(className, options, false);
  } catch (error) {
    err = error;
    return done(err);
  }
  connector = options.connector;
  listConnector = options.listConnector || connector.clone();
  return query.stream(connector, listConnector, callback, done);
};

PersistenceManager.prototype.getSelectQuery = function(className, options, guess = true) {
  var definition;
  if (guess) {
    options = guessEscapeOpts(options, this.defaults.list);
  }
  if (_.isPlainObject(options.where)) {
    options.attributes = options.where;
    options.where = void 0;
  }
  if (!options.where && _.isPlainObject(options.attributes)) {
    definition = this._getDefinition(className);
    ({
      where: options.where
    } = _getInitializeCondition(this, null, definition, _.defaults({
      useDefinitionColumn: false
    }, options)));
  }
  return new SelectQuery(this, className, options, false);
};

PersistenceManager.prototype.update = function(model, options, callback, guess = true) {
  var connector, err, query;
  if (guess) {
    options = _.defaults({
      autoRollback: false
    }, guessEscapeOpts(options, this.defaults.update, PersistenceManager.prototype.defaults.update));
  }
  try {
    query = this.getUpdateQuery(model, options, false);
  } catch (error) {
    err = error;
    return callback(err);
  }
  connector = options.connector;
  connector.acquire(function(err, performed) {
    if (err) {
      return callback(err);
    }
    connector.begin(function(err) {
      if (err) {
        if (performed) {
          connector.release(function(_err) {
            callback(_err ? [err, _err] : err);
          });
          return;
        }
        callback(err);
        return;
      }
      query.execute(connector, function(...args) {
        var method;
        method = args[0] ? 'rollback' : 'commit';
        connector[method](function(err) {
          if (err) {
            if (args[0]) {
              args[0] = [err, args[0]];
            } else {
              args[0] = err;
            }
          }
          if (performed) {
            connector.release(function(err) {
              if (err) {
                logger.error(err);
              }
              callback.apply(null, args);
            });
          } else {
            callback.apply(null, args);
          }
        });
      });
    });
  });
};

PersistenceManager.prototype.getUpdateQuery = function(model, options, guess = true) {
  if (guess) {
    options = guessEscapeOpts(options, this.defaults.update, PersistenceManager.prototype.defaults.update);
  }
  return new UpdateQuery(this, model, options, false);
};

PersistenceManager.prototype.delete = PersistenceManager.prototype.remove = function(model, options, callback) {
  var connector, err, query;
  if ('function' === typeof options) {
    callback = options;
    options = {};
  }
  options = _.defaults({
    autoRollback: false
  }, guessEscapeOpts(options, this.defaults.delete, PersistenceManager.prototype.defaults.delete));
  try {
    query = this.getDeleteQuery(model, options, false);
  } catch (error) {
    err = error;
    return callback(err);
  }
  connector = options.connector;
  query.execute(connector, callback);
};

PersistenceManager.prototype.getDeleteQuery = function(model, options, guess = true) {
  if (guess) {
    options = guessEscapeOpts(options, this.defaults.delete, PersistenceManager.prototype.defaults.delete);
  }
  return new DeleteQuery(this, model, options, false);
};

PersistenceManager.prototype.save = function(model, options, callback) {
  var backup, className, definition, err, fields, where;
  if ((err = isValidModelInstance(model)) instanceof Error) {
    return callback(err);
  }
  options = guessEscapeOpts(options, this.defaults.save, PersistenceManager.prototype.defaults.save);
  if ('function' !== typeof callback) {
    // if arguments.length is 2 and 'function' is typeof options
    //     callback = options
    // options = {} if not _.isPlainObject options
    (callback = function() {});
  }
  className = options.className || model.className;
  definition = this._getDefinition(className);
  try {
    ({fields, where} = _getInitializeCondition(this, model, definition, _.defaults({
      useDefinitionColumn: false,
      useAttributes: false
    }, options)));
  } catch (error) {
    err = error;
    callback(err);
    return;
  }
  if (where.length === 0) {
    this.insert(model, _.defaults({
      reflect: true
    }, options), function(err, id) {
      callback(err, id, 'insert');
    }, false);
  } else {
    backup = options;
    options = _.defaults({
      fields: fields,
      where: where,
      limit: 2 // Expecting one result. Limit is for unique checking without getting all results
    }, options);
    this.list(className, options, (err, models) => {
      if (err) {
        return callback(err);
      }
      if (models.length === 1) {
        // update properties
        model.set(_.defaults(model.toJSON(), models[0].toJSON()));
        this.update(model, backup, callback, false);
      } else {
        this.insert(model, _.defaults({
          reflect: true
        }, backup), function(err, id) {
          callback(err, id, 'insert');
        }, false);
      }
    }, false);
  }
};

PersistenceManager.prototype.initialize = function(model, options, callback, guess = true) {
  var className, definition, err;
  if ((err = isValidModelInstance(model)) instanceof Error) {
    return callback(err);
  }
  if (guess) {
    options = guessEscapeOpts(options);
  }
  if ('function' !== typeof callback) {
    (callback = function() {});
  }
  if (!_.isObject(model)) {
    err = new Error('No model');
    err.code = 'NO_MODEL';
    return callback(err);
  }
  className = options.className || model.className;
  definition = this._getDefinition(className);
  options = _.extend({}, options, {
    models: [model]
  });
  try {
    ({
      where: options.where
    } = _getInitializeCondition(this, model, definition, _.defaults({
      useDefinitionColumn: false
    }, options)));
  } catch (error) {
    err = error;
    callback(err);
    return;
  }
  return this.list(className, options, callback, false);
};

// return where condition to be parsed by RowMap
_getInitializeCondition = function(pMgr, model, definition, options) {
  var attr, attributes, constraint, constraintKey, fields, isSetted, j, k, len, len1, prop, ref, value, where;
  where = [];
  if (typeof options.where === 'undefined') {
    if (!model) {
      attributes = options.attributes;
    } else if (_.isPlainObject(definition.id) && (value = model.get(definition.id.name))) {
      // id is defined
      attributes = {};
      attributes[definition.id.name] = value;
      fields = [definition.id.name];
    } else {
      if (definition.hasUniqueConstraints && (options.useAttributes === false || !options.attributes)) {
        attributes = {};
        ref = definition.constraints.unique;
        // check unique constraints properties
        for (constraintKey in ref) {
          constraint = ref[constraintKey];
          isSetted = true;
          for (j = 0, len = constraint.length; j < len; j++) {
            prop = constraint[j];
            value = model.get(prop);
            // null and undefined are not allowed values for unique columns
            // 0 is a falsy value but a valid value for  unique columns
            if (value === null || 'undefined' === typeof value) {
              isSetted = false;
              break;
            }
            attributes[prop] = value;
          }
          if (isSetted) {
            break;
          }
        }
        if (!isSetted) {
          // the model cannot be initialized using it's attributes
          return {fields, where};
        }
        fields = Object.keys(attributes);
      }
      if (!isSetted && options.useAttributes !== false) {
        attributes = options.attributes || model.toJSON();
      }
    }
    if (_.isPlainObject(attributes)) {
      for (attr in attributes) {
        value = attributes[attr];
        _addWhereAttr(pMgr, model, attr, value, definition, where, options);
      }
    } else if (Array.isArray(attributes)) {
      for (k = 0, len1 = attributes.length; k < len1; k++) {
        attr = attributes[k];
        value = model.get(attr);
        _addWhereAttr(pMgr, model, attr, value, definition, where, options);
      }
    }
  } else {
    where = options.where;
  }
  if (isSetted) {
    _.isPlainObject(options.result) || (options.result = {});
    options.result.constraint = constraint;
  }
  return {fields, where};
};

PRIMITIVE_TYPES = /^(?:string|boolean|number)$/;

_addWhereAttr = function(pMgr, model, attr, value, definition, where, options) {
  var column, propClassName, propDef;
  if (typeof value === 'undefined') {
    return;
  }
  if (options.useDefinitionColumn) {
    // ignore not defined properties
    if (!hasProp.call(definition.properties, attr)) {
      return;
    }
    column = options.escapeId(definition.properties[attr].column);
  } else {
    // ignore not defined properties
    if (!hasProp.call(definition.availableProperties, attr)) {
      return;
    }
    column = '{' + attr + '}';
  }
  propDef = definition.availableProperties[attr].definition;
  if (_.isPlainObject(propDef.handlers) && typeof propDef.handlers.write === 'function') {
    value = propDef.handlers.write(value, model, options);
  }
  if (PRIMITIVE_TYPES.test(typeof value)) {
    where.push(column + ' = ' + options.escape(value));
  } else if (_.isObject(value)) {
    propClassName = propDef.className;
    value = value.get(pMgr.getIdName(propClassName));
    if (typeof value !== 'undefined') {
      if (value === null) {
        where.push(column + ' IS NULL');
      } else if (PRIMITIVE_TYPES.test(typeof value)) {
        where.push(column + ' = ' + options.escape(value));
      }
    }
  }
};

PersistenceManager.InsertQuery = InsertQuery = class InsertQuery {
  constructor(pMgr, model, options, guess = true) {
    var className, column, definition, err, fields, handlers, id, idName, index, insert, insertHandler, j, k, l, len, len1, len2, mixin, nested, parentModel, prop, propDef, props, ref, ref1, root, table, value, values, writeHandler;
    assertValidModelInstance(model);
    if (guess) {
      options = guessEscapeOpts(options, pMgr.defaults.insert, PersistenceManager.prototype.defaults.insert);
    }
    this.options = options;
    this.model = model;
    this.pMgr = pMgr;
    this.options = options;
    root = options.root || this;
    //  for mysql when lastInsertId is not available because there is no autoincrement
    fields = this.fields = {};
    this.set = function(column, value) {
      insert.set(this.options.escapeId(column), value);
      return fields[column] = value;
    };
    this.toString = this.oriToString = function() {
      return insert.toString();
    };
    this.toParam = function() {
      return insert.toParam();
    };
    this.toQuery = function() {
      return insert;
    };
    this.className = className = options.className || model.className;
    definition = this.definition = pMgr._getDefinition(className);
    table = definition.table;
    insert = pMgr.getSquelQuery('insert', options.dialect).into(this.options.escapeId(table));
    // ids of mixins will be setted at execution
    if (definition.mixins.length > 0) {
      this.toString = function() {
        return insert.toParam().text;
      };
      this.toParam = function() {
        var index, j, len, param, value;
        param = insert.toParam();
        for (index = j = 0, len = values.length; j < len; index = ++j) {
          value = values[index];
          param.values[index] = values[index];
        }
        return param;
      };
      values = insert.toParam().values;
      ref = definition.mixins;
      for (index = j = 0, len = ref.length; j < len; index = ++j) {
        mixin = ref[index];
        nested = options.nested || 0;
        values[index] = new InsertQuery(pMgr, model, _.defaults({
          className: mixin.className,
          dialect: options.dialect,
          nested: ++nested,
          root,
          allowEmpty: true
        }, options), false);
      }
      ref1 = definition.mixins;
      for (k = 0, len1 = ref1.length; k < len1; k++) {
        mixin = ref1[k];
        insert.set(this.options.escapeId(mixin.column), '$id');
      }
    }
    idName = pMgr.getIdName(className);
    if (idName !== null) {
      id = model.get(idName);
    }
    props = Object.keys(definition.properties);
    if (id) {
      insert.set(this.options.escapeId(definition.id.column), id);
      if (props.length === 0) {
        this.hasData = true;
      }
    }
    for (l = 0, len2 = props.length; l < len2; l++) {
      prop = props[l];
      propDef = definition.properties[prop];
      column = propDef.column;
      if (hasProp.call(propDef, 'className')) {
        parentModel = model.get(prop);
        if (typeof parentModel === 'undefined') {
          continue;
        }
        prop = pMgr._getDefinition(propDef.className);
        // # If column is not setted assume it has the same name as the column id
        // if typeof column is 'undefined'
        //     column = prop.id.column
        if (parentModel === null || typeof parentModel === 'number') {
          // assume it is the id
          value = parentModel;
        } else if (typeof parentModel === 'string') {
          if (parentModel.length === 0) {
            value = null;
          } else {
            // assume it is the id
            value = parentModel;
          }
        } else {
          value = parentModel.get(prop.id.name);
        }
        // Throw if id of property class is not set
        if (typeof value === 'undefined') {
          err = new Error(`[${className}] - [${propDef.className}]: id is not defined. Save property value before saving model`);
          err.code = 'NO_ID';
          throw err;
        }
      } else {
        value = model.get(prop);
      }
      // Handlers
      handlers = propDef.handlers;
      insertHandler = null;
      writeHandler = null;
      if (typeof handlers !== 'undefined') {
        insertHandler = handlers.insert;
        writeHandler = handlers.write;
      }
      // Insert handler
      if (typeof value === 'undefined' && typeof insertHandler === 'function') {
        value = insertHandler(value, model, _.defaults({table, column}, options));
      }
      // Only set defined values
      if (typeof value === 'undefined') {
        continue;
      }
      // Write handler
      if (typeof writeHandler === 'function') {
        value = writeHandler(value, model, options);
      }
      // Only set defined values
      if (typeof value === 'undefined') {
        continue;
      }
      root.hasData = this.hasData = true;
      insert.set(this.options.escapeId(column), value);
    }
    // check
    this.toString();
  }

  execute(connector, callback) {
    var _addTask, definition, index, j, len, params, ref, self, tasks, value;
    if (this.toString === this.oriToString) {
      this._execute(connector, callback);
      return;
    }
    self = this;
    definition = this.definition;
    params = this.toParam();
    tasks = [];
    _addTask = function(query, connector, index) {
      if (query.hasData && !self.hasData) {
        self.hasData = query.hasData;
      }
      tasks.push(function(next) {
        query.execute(connector, function(err, id) {
          var column;
          if (err) {
            return next(err);
          }
          column = definition.mixins[index].column;
          self.set(column, id);
          next();
        });
      });
    };
    ref = params.values;
    for (index = j = 0, len = ref.length; j < len; index = ++j) {
      value = ref[index];
      if (value instanceof InsertQuery) {
        _addTask(value, connector, index);
      } else {
        break;
      }
    }
    async.series(tasks, function(err) {
      if (err) {
        return callback(err);
      }
      self._execute(connector, callback);
    });
  }

  _execute(connector, callback) {
    var column, definition, fields, model, options, pMgr, prop, propDef, query, ref;
    pMgr = this.pMgr;
    query = this.toQuery();
    definition = this.definition;
    model = this.model;
    fields = this.fields;
    options = this.options;
    // empty objects are not inserted by default
    if (!this.hasData) {
      if (!options.allowEmpty) {
        callback(new Error('no data to insert'));
        return;
      }
      if (definition.id.column) {
        pMgr.insertDefaultValue(options.dialect, query, definition.id.column);
      } else {
        ref = definition.properties;
        for (prop in ref) {
          propDef = ref[prop];
          column = propDef.column;
          pMgr.insertDefaultValue(options.dialect, query, column);
          break;
        }
      }
    }
    if (definition.id.column) {
      pMgr.decorateInsert(options.dialect, query, definition.id.column);
    }
    connector.query(query.toString(), function(err, res) {
      var id, where;
      if (err) {
        return callback(err);
      }
      if (hasProp.call(definition.id, 'column')) {
        // On sqlite, lastInsertId is only valid on autoincremented id's
        // Therefor, always take setted field when possible
        if (fields[definition.id.column]) {
          id = fields[definition.id.column];
        } else if (hasProp.call(res, 'lastInsertId')) {
          id = res.lastInsertId;
        } else {
          id = Array.isArray(res.rows) && res.rows.length > 0 && res.rows[0][definition.id.column];
        }
      }
      logger.debug('[', definition.className, '] - INSERT', id);
      if (options.reflect) {
        if (hasProp.call(definition.id, 'column')) {
          where = '{' + pMgr.getIdName(definition.className) + '} = ' + id;
        }
        pMgr.initialize(model, _.defaults({connector, where}, options), function(err) {
          callback(err, id);
        }, false);
      } else {
        callback(err, id);
      }
    }, options.executeOptions);
  }

  toSingleQuery() {
    var line, query, withs;
    query = this;
    withs = [];
    line = _toInsertLine.call(query, 0, withs);
    if (withs.length === 0) {
      return line;
    }
    return 'WITH ' + _.map(withs, function([column, line], index) {
      return `insert_${index} (${query.options.escapeId(column)}) AS (\n${line}\n)`;
    }).join(',\n') + '\n' + line;
  }

};

_toInsertLine = function(level, withs) {
  var blocks, column, definition, indent, index, j, len, line, ref, returning, tables, value, values;
  if (level > 0) {
    indent = '    ';
  } else {
    indent = '';
  }
  definition = this.definition;
  ({blocks} = this.toQuery());
  ({values} = this.toParam());
  if ((ref = definition.id) != null ? ref.column : void 0) {
    returning = `${indent}RETURNING ${this.options.escapeId(definition.id.column)}`;
  } else {
    returning = '';
  }
  if (this.toString === this.oriToString) {
    return `${indent}INSERT INTO ${blocks[1].table} (${blocks[2].fields.join(', ')})\n${indent}VALUES (${_.map(values, this.options.escape).join(', ')})\n${returning}`;
  }
  tables = [];
  for (index = j = 0, len = values.length; j < len; index = ++j) {
    value = values[index];
    if (value instanceof InsertQuery) {
      line = _toInsertLine.call(value, ++level, withs);
      column = definition.mixins[index].column;
      tables.push(`insert_${withs.length}`);
      values[index] = `insert_${withs.length}.${this.options.escapeId(column)}`;
      withs.push([column, line]);
    } else {
      values[index] = this.options.escape(value);
    }
  }
  return `${indent}INSERT INTO ${blocks[1].table} (${blocks[2].fields.join(', ')})\n${indent}SELECT ${values.join(', ')}\n${indent}FROM ${tables.join(', ')}\n${returning}`;
};

_getCacheId = function(options) {
  var arr, item, j, json, k, l, len, len1, len2, opt, ref, ref1, val;
  json = {};
  ref = ['dialect', 'type', 'count', 'attributes', 'fields', 'join', 'where', 'group', 'having', 'order', 'limit', 'offset'];
  for (j = 0, len = ref.length; j < len; j++) {
    opt = ref[j];
    if (hasProp.call(options, opt)) {
      if (Array.isArray(options[opt])) {
        json[opt] = [];
        ref1 = options[opt];
        for (k = 0, len1 = ref1.length; k < len1; k++) {
          val = ref1[k];
          if (Array.isArray(val)) {
            arr = [];
            json[opt].push(arr);
            for (l = 0, len2 = val.length; l < len2; l++) {
              item = val[l];
              arr.push(JSON.stringify(item));
            }
          } else {
            json[opt].push(JSON.stringify(val));
          }
        }
      } else {
        json[opt] = JSON.stringify(options[opt]);
      }
    }
  }
  return JSON.stringify(json);
};

PersistenceManager.prototype.addCachedRowMap = function(cacheId, className, rowMap) {
  var json, value;
  // keeping references of complex object makes the hole process slow
  // don't know why
  logger.trace('add cache"', className, '"', cacheId);
  // serialize = (key, value)->
  //     _serialize cacheId, key, value
  json = _.pick(rowMap, ['_infos', '_tableAliases', '_tabId', '_columnAliases', '_colId', '_tables', '_mixins', '_joining']);
  value = {
    rowMap: JSON.stringify(json),
    template: rowMap.getTemplate(),
    select: JSON.stringify(rowMap.select)
  };
  this.classes[className].cache.set(cacheId, value);
  return value;
};

PersistenceManager.prototype.getCachedRowMap = function(cacheId, className, options) {
  var cached, rowMap, select;
  cached = this.classes[className].cache.get(cacheId);
  if (!cached) {
    return;
  }
  logger.trace('read cache', className, cacheId);
  rowMap = new RowMap(className, this, options, true);
  select = new squel.select.constructor();
  // desirialize = (key, value)->
  //     _desirialize cacheId, key, value
  _.extend(select, JSON.parse(cached.select));
  _.extend(rowMap, JSON.parse(cached.rowMap));
  rowMap.template = cached.template;
  rowMap.select = select;
  rowMap.values = options.values;
  rowMap._initialize();
  rowMap._processColumns();
  if (options.count) {
    rowMap._selectCount();
  }
  rowMap._updateInfos();
  return rowMap;
};

PersistenceManager.SelectQuery = SelectQuery = class SelectQuery {
  constructor(pMgr, className, options, guess = true) {
    var cacheId, rowMap, select, useCache;
    if (arguments.length === 1) {
      if (arguments[0] instanceof RowMap) {
        this.rowMap = arguments[0];
        return this;
      } else {
        throw new Error('Given parameter do not resolve to a RowMap');
      }
    }
    if (guess) {
      options = guessEscapeOpts(options, pMgr.defaults.list);
    }
    useCache = options.cache !== false;
    if (useCache) {
      cacheId = _getCacheId(options);
    }
    if (!useCache || !(rowMap = pMgr.getCachedRowMap(cacheId, className, options))) {
      select = pMgr.getSquelQuery('select', options.dialect);
      rowMap = new RowMap(className, pMgr, _.extend({}, options, {
        select: select
      }));
      // check
      select.toParam();
      select.toString();
      if (useCache) {
        this.cacheId = cacheId;
        pMgr.addCachedRowMap(cacheId, className, rowMap);
      }
    }
    this.rowMap = rowMap;
    return this;
  }

  toString() {
    return this.rowMap.toString();
  }

  stream(streamConnector, listConnector, callback, done) {
    var doneSem, hasError, models, options, pMgr, query, ret, rowMap, timeout;
    if ('function' !== typeof callback) {
      (callback = function() {});
    }
    if ('function' !== typeof done) {
      (done = function() {});
    }
    rowMap = this.rowMap;
    query = rowMap.toString();
    pMgr = rowMap.manager;
    options = rowMap.options;
    models = options.models || [];
    doneSem = semLib.semCreate();
    doneSem.semGive();
    timeout = 60 * 1000;
    hasError = false;
    ret = function(err, fields) {
      doneSem.semTake({
        timeout: timeout,
        onTake: function() {
          if (hasError) {
            if (_.isObject(err)) {
              err.subError = hasError;
            } else {
              err = hasError;
            }
          }
          done(err, fields);
        }
      });
    };
    return streamConnector.stream(query, function(row, stream) {
      var err, model, tasks;
      tasks = [];
      model = rowMap.initModel(row, null, tasks);
      if (tasks.length > 0) {
        if (listConnector === streamConnector || (listConnector.getPool() === streamConnector.getPool() && listConnector.getMaxConnection() < 2)) {
          // preventing dead block
          err = new Error('List connector and stream connector are the same. To retrieve nested data, listConnector must be different from streamConnector and if used pools are the same, they must admit more than 1 connection');
          err.code = 'STREAM_CONNECTION';
          stream.emit('error', err);
          return;
        }
        stream.pause();
        doneSem.semTake({
          priority: 1,
          timeout: timeout
        });
        async.eachSeries(tasks, function(task, next) {
          pMgr.list(task.className, _.extend({
            connector: listConnector,
            dialect: options.dialect
          }, task.options), function(err, models) {
            var msg;
            if (err) {
              return next(err);
            }
            if (models.length !== 1) {
              msg = 'Expecting one result. Given ' + models.length + '.';
              if (models.length === 0) {
                msg += '\n    You are most likely querying uncomitted data. listConnector has it\'s own transaction. Therefore, only committed changes will be seen.';
              }
              msg += '\n    Checks those cases: database error, library bug, something else.';
              err = new Error(msg);
              err.code = 'UNKNOWN';
              return next(err);
            }
            next();
          });
        }, function(err) {
          doneSem.semGive();
          stream.resume();
          if (err) {
            hasError = err;
            stream.emit('error', err);
          } else {
            callback(model, stream);
          }
        });
        return;
      }
      callback(model, stream);
    }, ret, options.executeOptions);
  }

  toQueryString() {
    return this.toString();
  }

  list(connector, callback) {
    var options, pMgr, query, rowMap;
    if ('function' !== typeof callback) {
      (callback = function() {});
    }
    rowMap = this.rowMap;
    query = rowMap.toString();
    pMgr = rowMap.manager;
    options = rowMap.options;
    connector.query(query, function(err, res) {
      var index, j, len, model, models, ret, row, rows, tasks;
      if (err) {
        return callback(err);
      }
      rows = res.rows;
      if (rows.length === 0) {
        return callback(err, rows);
      }
      ret = [];
      if (Array.isArray(options.models)) {
        models = options.models;
        if (models.length !== rows.length) {
          err = new Error('Returned rows and given number of models doesn\'t match');
          err.extend = [models.length, rows.length];
          err.code = 'OPT_MODELS';
          return callback(err);
        }
      } else {
        models = [];
      }
      tasks = [];
      for (index = j = 0, len = rows.length; j < len; index = ++j) {
        row = rows[index];
        model = rowMap.initModel(row, models[index], tasks);
        ret.push(model);
      }
      if (tasks.length > 0) {
        async.eachSeries(tasks, function(task, next) {
          pMgr.list(task.className, _.defaults({connector}, task.options), function(err, models) {
            if (err) {
              return next(err);
            }
            if (models.length !== 1) {
              err = new Error('database is corrupted or there is bug');
              err.code = 'UNKNOWN';
              return next(err);
            }
            next();
          });
        }, function(err) {
          if (err) {
            return callback(err);
          }
          callback(null, ret);
        });
        return;
      }
      if (options.count) {
        callback(null, ret[0].count);
      } else {
        callback(null, ret);
      }
    }, options, options.executeOptions);
    return this;
  }

};

_addUpdateOrDeleteCondition = function(action, name, pMgr, model, className, definition, options) {
  var condition, err, hasNoCondition, hasNoId, id, idName, j, len, result, where;
  idName = pMgr.getIdName(className);
  if (typeof idName !== 'string' || idName.length === 0) {
    idName = null;
  }
  if (!definition.hasUniqueConstraints && idName === null) {
    err = new Error(`Cannot ${name} ${className} models because id has not been defined`);
    err.code = name.toUpperCase();
    throw err;
  }
  if (idName !== null) {
    id = model.get(idName);
  }
  hasNoCondition = hasNoId = id === null || 'undefined' === typeof id;
  if (hasNoId) {
    options = _.extend({}, options, {
      useDefinitionColumn: true
    });
    ({where} = _getInitializeCondition(pMgr, model, definition, options));
    result = options.result;
    hasNoCondition = where.length === 0;
    for (j = 0, len = where.length; j < len; j++) {
      condition = where[j];
      action.where(condition);
    }
  } else {
    action.where(options.escapeId(definition.id.column) + ' = ' + options.escape(id));
  }
  if (hasNoCondition) {
    err = new Error(`Cannot ${name} ${className} model because id is null or undefined`);
    err.code = name.toUpperCase();
    throw err;
  }
  return result;
};

PersistenceManager.UpdateQuery = UpdateQuery = class UpdateQuery {
  constructor(pMgr, model, options, guess = true) {
    var changeCondition, className, column, definition, dontLock, dontQuote, handlers, lock, lockCondition, parentModel, prop, propDef, ref, result, table, update, updateHandler, value, writeHandler;
    assertValidModelInstance(model);
    if (guess) {
      options = guessEscapeOpts(options, pMgr.defaults.insert, PersistenceManager.prototype.defaults.insert);
    }
    this.options = options;
    this.model = model;
    this.pMgr = pMgr;
    this.toQuery = function() {
      return update;
    };
    this.toParam = function() {
      return update.toParam();
    };
    this.toString = this.oriToString = function() {
      return update.toString();
    };
    // this.getClassName = -> className
    this.getDefinition = function() {
      return definition;
    };
    this.setChangeCondition = function() {
      update.where(changeCondition);
      return this;
    };
    className = options.className || model.className;
    definition = this.definition = pMgr._getDefinition(className);
    table = definition.table;
    update = pMgr.getSquelQuery('update', options.dialect).table(options.escapeId(table));
    result = _addUpdateOrDeleteCondition(update, 'update', pMgr, model, className, definition, options);
    // condition to track changes
    changeCondition = squel.expr();
    this.lockCondition = lockCondition = squel.expr();
    ref = definition.properties;
    // update owned properties
    for (prop in ref) {
      propDef = ref[prop];
      if (result && result.constraint) {
        // constraint used as discriminator must not be update
        // causes an error on postgres
        if (-1 !== result.constraint.indexOf(prop)) {
          continue;
        }
      }
      if (hasProp.call(propDef, 'className') && typeof (parentModel = model.get(prop)) !== 'undefined') {
        // Class property
        if (parentModel === null || typeof parentModel === 'number') {
          // assume it is the id
          value = parentModel;
        } else if (typeof parentModel === 'string') {
          if (parentModel.length === 0) {
            value = null;
          } else {
            // assume it is the id
            value = parentModel;
          }
        } else {
          value = parentModel.get(pMgr._getDefinition(propDef.className).id.name);
        }
      } else {
        value = model.get(prop);
      }
      column = propDef.column;
      // Handlers
      handlers = propDef.handlers;
      if (_.isObject(options.overrides) && _.isObject(options.overrides[prop])) {
        if (_.isObject(options.overrides[prop].handlers)) {
          handlers = _.extend({}, handlers, options.overrides[prop].handlers);
        }
        dontQuote = options.overrides[prop].dontQuote;
        dontLock = options.overrides[prop].dontLock;
      }
      writeHandler = void 0;
      updateHandler = void 0;
      if (typeof handlers !== 'undefined') {
        // Write handler
        if (typeof handlers.write === 'function') {
          writeHandler = handlers.write;
        }
        // Update handler
        if (typeof handlers.update === 'function') {
          updateHandler = handlers.update;
        }
      }
      if (!dontLock && propDef.lock) {
        lock = value;
        if (typeof writeHandler === 'function') {
          lock = writeHandler(lock, model, _.defaults({table, column}, options));
          lockCondition.and(options.exprEqual(lock, options.escapeId(column)));
        }
      }
      if (typeof updateHandler === 'function') {
        value = updateHandler(value, model, _.defaults({table, column}, options));
      }
      // Only set defined values
      if (typeof value === 'undefined') {
        continue;
      }
      // Value handler
      if (typeof writeHandler === 'function') {
        value = writeHandler(value, model, _.defaults({table, column}, options));
      }
      // Only set defined values
      if (typeof value === 'undefined') {
        continue;
      }
      update.set(options.escapeId(column), value, {
        dontQuote: !!dontQuote
      });
      this.hasData = true;
      if (!dontLock && !propDef.lock) {
        changeCondition.or(options.exprNotEqual(value, options.escapeId(column)));
      }
    }
    update.where(lockCondition);
    // update mixin properties
    if (definition.mixins.length === 0) {
      this.setChangeCondition();
    } else {
      if (this.hasData) {
        this.toString = function() {
          return update.toString();
        };
      } else {
        this.toString = function() {
          return '';
        };
      }
      this.toParam = function() {
        var index, j, len, mixin, nested, params, ref1;
        if (this.hasData) {
          params = update.toParam();
        } else {
          params = {
            values: []
          };
        }
        ref1 = definition.mixins;
        for (index = j = 0, len = ref1.length; j < len; index = ++j) {
          mixin = ref1[index];
          nested = options.nested || 0;
          params.values.push(new UpdateQuery(pMgr, model, _.defaults({
            className: mixin.className,
            dialect: options.dialect,
            nested: ++nested
          }, options), false));
        }
        return params;
      };
    }
    if (this.hasData) {
      this.toString();
    }
  }

  execute(connector, callback) {
    var _addTask, definition, hasUpdate, idIndex, index, j, params, ref, tasks, value;
    if (this.toString === this.oriToString) {
      return this._execute(connector, callback);
    }
    params = this.toParam();
    idIndex = 0;
    tasks = [];
    _addTask = function(query, connector) {
      tasks.push(function(next) {
        return query.execute(connector, next);
      });
    };
    for (index = j = ref = params.values.length - 1; j >= 0; index = j += -1) {
      value = params.values[index];
      if (value instanceof UpdateQuery && value.hasData) {
        _addTask(value, connector);
      } else {
        break;
      }
    }
    hasUpdate = false;
    definition = this.definition;
    async.series(tasks, (err, results) => {
      var id, k, len, msg, result;
      if (err) {
        return callback(err);
      }
      // Check if parent mixin has been updated
      if (Array.isArray(results) && results.length > 0) {
        for (k = 0, len = results.length; k < len; k++) {
          result = results[k];
          if (Array.isArray(result) && result.length > 0) {
            [id, msg] = result;
            if (msg === 'update') {
              logger.debug('[', definition.className, '] - UPDATE: has update', id);
              hasUpdate = true;
              break;
            }
          }
        }
        if (Array.isArray(results[results.length - 1])) {
          id = results[results.length - 1][0];
        }
      }
      if (!this.hasData) {
        callback(err, id, !hasUpdate);
        return;
      }
      // If parent mixin has been update, child must be considered as being updated
      if (!hasUpdate) {
        logger.debug('[', definition.className, '] - UPDATE: has no update', id);
        this.setChangeCondition();
      }
      this._execute(connector, function(err, id, msg) {
        hasUpdate = hasUpdate || msg === 'update';
        callback(err, id, hasUpdate ? 'update' : 'no-update');
      });
    });
  }

  _execute(connector, callback) {
    var definition, model, options, pMgr, query;
    pMgr = this.pMgr;
    query = this.toQuery();
    definition = this.definition;
    model = this.model;
    options = this.options;
    if (definition.id.column) {
      query = pMgr.decorateInsert(options.dialect, query, definition.id.column);
    }
    connector.query(query.toString(), function(err, res) {
      var field, fields, hasNoUpdate, i, id, j, len, msg, propDef, where;
      if (err) {
        return callback(err);
      }
      if (hasProp.call(res, 'affectedRows')) {
        hasNoUpdate = res.affectedRows === 0;
      } else if (hasProp.call(definition.id, 'column') && res.rows) {
        hasNoUpdate = res.rows.length === 0;
      } else if (hasProp.call(res, 'rowCount')) {
        hasNoUpdate = res.rowCount === 0;
      }
      id = model.get(definition.id.name);
      msg = hasNoUpdate ? 'no-update' : 'update';
      if (options.nested !== void 0 && options.nested !== 0) {
        callback(err, id, msg);
        return;
      }
      if ('undefined' === typeof id) {
        try {
          ({where} = _getInitializeCondition(pMgr, model, definition, _.defaults({
            connector,
            useDefinitionColumn: false
          }, options)));
        } catch (error) {
          err = error;
          callback(err);
          return;
        }
      } else if (hasProp.call(definition.id, 'column')) {
        where = '{' + pMgr.getIdName(definition.className) + '} = ' + id;
      }
      // only initialize owned properties
      // parent and mixins will initialized their owned properties
      fields = Object.keys(definition.availableProperties);
      for (i = j = 0, len = fields.length; j < len; i = ++j) {
        field = fields[i];
        propDef = definition.availableProperties[field];
        if (definition.id !== propDef.definition && !propDef.mixin && hasProp.call(propDef.definition, 'className')) {
          fields[i] = field + ':*';
        }
      }
      options = _.defaults({connector, fields, where}, options);
      logger.debug('[', definition.className, '] - UPDATE initializing', where);
      pMgr.initialize(model, options, function(err, models) {
        if (err) {
          return callback(err);
        }
        id = model.get(definition.id.name);
        if (hasNoUpdate) {
          if (models.length === 0) {
            err = new Error('id or lock condition');
            err.code = 'NO_UPDATE';
            logger.debug('[', definition.className, '] - NO UPDATE', id);
          }
        } else {
          logger.debug('[', definition.className, '] - UPDATE', id);
        }
        logger.debug('[', definition.className, '] - UPDATE initialized', id);
        callback(err, id, msg);
      }, false);
    }, options.executeOptions);
  }

};

PersistenceManager.DeleteQuery = DeleteQuery = class DeleteQuery {
  constructor(pMgr, model, options, guess = true) {
    var className, column, definition, handlers, prop, propDef, ref, remove, value, writeHandler;
    assertValidModelInstance(model);
    if (guess) {
      options = guessEscapeOpts(options, pMgr.defaults.insert, PersistenceManager.prototype.defaults.insert);
    }
    this.options = options;
    this.toParam = function() {
      return remove.toParam();
    };
    this.toString = this.oriToString = function() {
      return remove.toString();
    };
    this.options = options;
    className = options.className || model.className;
    definition = this.definition = pMgr._getDefinition(className);
    remove = pMgr.getSquelQuery('delete', options.dialect).from(options.escapeId(definition.table));
    _addUpdateOrDeleteCondition(remove, 'delete', pMgr, model, className, definition, options);
    ref = definition.properties;
    // optimistic lock
    for (prop in ref) {
      propDef = ref[prop];
      if (hasProp.call(propDef, 'className')) {
        // cascade delete is not yet defined
        continue;
      }
      if (propDef.lock) {
        column = propDef.column;
        value = model.get(prop);
        // Handlers
        handlers = propDef.handlers;
        writeHandler = null;
        if (typeof handlers !== 'undefined') {
          writeHandler = handlers.write;
        }
        // Write handler
        if (typeof writeHandler === 'function') {
          value = writeHandler(value, model, options);
        }
        remove.where(options.escapeId(column) + ' = ' + options.escape(value));
      }
    }
    // delete mixins lines
    if (definition.mixins.length > 0) {
      this.toString = function() {
        return remove.toString();
      };
      this.toParam = function() {
        var index, j, len, mixin, nested, params, ref1;
        params = remove.toParam();
        ref1 = definition.mixins;
        for (index = j = 0, len = ref1.length; j < len; index = ++j) {
          mixin = ref1[index];
          nested = options.nested || 0;
          params.values.push(new DeleteQuery(pMgr, model, _.defaults({
            className: mixin.className,
            dialect: options.dialect,
            nested: ++nested
          }, options), false));
        }
        return params;
      };
    }
    // check
    this.toString();
  }

  execute(connector, callback) {
    var _addTask, index, j, next, params, ref, tasks, value;
    next = function(err, res) {
      if (err) {
        return callback(err);
      }
      if (!res.affectedRows && hasProp.call(res, 'rowCount')) {
        res.affectedRows = res.rowCount;
      }
      callback(err, res);
    };
    if (this.toString === this.oriToString) {
      return this._execute(connector, next);
    }
    params = this.toParam();
    _addTask = function(query, connector) {
      tasks.push(function(next) {
        return query.execute(connector, next);
      });
    };
    tasks = [];
    for (index = j = ref = params.values.length - 1; j >= 0; index = j += -1) {
      value = params.values[index];
      if (value instanceof DeleteQuery) {
        _addTask(value, connector);
      } else {
        break;
      }
    }
    this._execute(connector, function(err, res) {
      if (err) {
        return next(err);
      }
      async.series(tasks, function(err, results) {
        var k, len, result;
        if (err) {
          return next(err);
        }
        for (k = 0, len = results.length; k < len; k++) {
          result = results[k];
          if (result.affectedRows === 0) {
            return next(new Error('sub class has not been deleted'));
          }
        }
        next(err, res);
      });
    });
  }

  _execute(connector, callback) {
    var query;
    query = this.oriToString();
    connector.query(query, callback, this.options.executeOptions);
  }

};

PersistenceManager.prototype.getInsertQueryString = function(className, entries, options) {
  var attributes, blocks, column, columns, i, j, k, len, len1, query, row, rows, table, values;
  table = this.getTable(className);
  rows = [];
  for (j = 0, len = entries.length; j < len; j++) {
    attributes = entries[j];
    row = {};
    query = this.getInsertQuery(this.newInstance(className, attributes), options);
    ({blocks} = query.toQuery());
    ({
      fields: columns,
      values: [values]
    } = blocks[2]);
    for (i = k = 0, len1 = columns.length; k < len1; i = ++k) {
      column = columns[i];
      row[column] = values[i];
    }
    rows.push(row);
  }
  return this.getSquelQuery('insert', query.options.dialect).into(query.options.escapeId(this.getTable(className))).setFieldsRows(rows).toString();
};

PersistenceManager.prototype.sync = require('./schema/sync').sync;

// error codes abstraction
// check: database and mapping are compatible
// collection
// stream with inherited =>
//   2 connections?
// stream with collections?
//   two connections?
// decision: manually set joins, stream only do one request, charge to you to recompute records
