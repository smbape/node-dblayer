var CompiledMapping, LRUCache, Model, _, _addConstraints, _addIndexName, _addIndexes, _addMixins, _addProperties, _addSpecProperties, _addUniqueConstraint, _inheritType, _resolve, _setConstructor, isStringNotEmpty, log4js, logger, modelId, specProperties,
  hasProp = {}.hasOwnProperty;

log4js = require('./log4js');

logger = log4js.getLogger(__filename.replace(/^(?:.+[\/\\])?([^.\/\\]+)(?:.[^.]+)?$/, '$1'));

_ = require('lodash');

LRUCache = require('lru-cache');

isStringNotEmpty = function(str) {
  return typeof str === 'string' && str.length > 0;
};

modelId = 0;

Model = class Model {
  constructor(attributes) {
    this.cid = ++modelId;
    if (_.isPlainObject(attributes)) {
      this.attributes = _.clone(attributes);
    } else {
      this.attributes = {};
    }
  }

  clone() {
    var _clone, prop, ref;
    _clone = new this.constructor();
    ref = this;
    for (prop in ref) {
      if (!hasProp.call(ref, prop)) continue;
      if (prop !== 'cid') {
        _clone[prop] = _.clone(this[prop]);
      }
    }
    return _clone;
  }

  set(prop, value) {
    var attr;
    if (_.isPlainObject(prop)) {
      for (attr in prop) {
        this.set(attr, prop[attr]);
      }
      return this;
    }
    if (prop === 'id') {
      this.id = value;
    }
    this.attributes[prop] = value;
    return this;
  }

  get(prop) {
    return this.attributes[prop];
  }

  unset(prop) {
    return delete this.attributes[prop];
  }

  toJSON() {
    return this.attributes;
  }

};

specProperties = ['type', 'type_args', 'nullable', 'pk', 'fk', 'fkindex', 'defaultValue'];

module.exports = CompiledMapping = (function() {
  class CompiledMapping {
    constructor(mapping) {
      var classDef, className, fk, i, indexes, key, len, name, names, parentDef, prop, propDef, propToColumn, properties, ref, ref1, ref2, ref3, unique;
      ref = ['classes', 'resolved', 'unresolved', 'tables'];
      for (i = 0, len = ref.length; i < len; i++) {
        prop = ref[i];
        this[prop] = {};
      }
      this.indexNames = {
        pk: {},
        uk: {},
        fk: {},
        ix: {}
      };
// Resolve mapping
      for (className in mapping) {
        _resolve(className, mapping, this);
      }
      propToColumn = function(prop) {
        return classDef.properties[prop].column;
      };
      ref1 = this.classes;
      for (className in ref1) {
        classDef = ref1[className];
        ref2 = classDef.properties;
        // Set undefined column for className properties
        for (prop in ref2) {
          propDef = ref2[prop];
          if (propDef.hasOwnProperty('className')) {
            parentDef = this._getDefinition(propDef.className);
            _inheritType(propDef, parentDef.id);
            if (!propDef.hasOwnProperty('column')) {
              propDef.column = parentDef.id.column;
            }
          }
          this._addColumn(className, propDef.column, prop);
        }
        ref3 = classDef.properties;
        // Set undefined fk for className properties
        for (prop in ref3) {
          propDef = ref3[prop];
          if (propDef.hasOwnProperty('className')) {
            if (!propDef.hasOwnProperty('fk')) {
              parentDef = this._getDefinition(propDef.className);
              fk = `${classDef.table}_${propDef.column}_HAS_${parentDef.table}_${parentDef.id.column}`;
              propDef.fk = fk;
            }
            _addIndexName(propDef.fk, 'fk', this);
          }
        }
        ({
          // Set undefined constraint names
          indexes,
          constraints: {unique, names}
        } = classDef);
        for (key in unique) {
          properties = unique[key];
          classDef.hasUniqueConstraints = true;
          if (!names[key]) {
            name = classDef.table + '_' + properties.map(propToColumn).join('_');
            _addIndexName(name, 'uk', this);
            names[key] = name;
          }
        }
      }
      this.resolved = true;
    }

    getConstructor(className) {
      this.assertClassHasMapping(className);
      return this.classes[className].ctor;
    }

    newInstance(className, attributes) {
      this.assertClassHasMapping(className);
      return new this.classes[className].ctor(attributes);
    }

    getIdName(className) {
      this.assertClassHasMapping(className);
      return this.classes[className].id.name;
    }

    getDefinition(className) {
      return _.cloneDeep(this._getDefinition(className));
    }

    getMapping() {
      return _.cloneDeep(this.classes);
    }

    getTable(className) {
      return this._getDefinition(className).table;
    }

    getColumn(className, prop) {
      var definition;
      definition = this._getDefinition(className);
      if (definition.id.name === prop) {
        return definition.id.column;
      } else if (definition.properties.hasOwnProperty(prop)) {
        return definition.properties[prop].column;
      }
    }

    assertClassHasMapping(className) {
      var err;
      if (!this.classes.hasOwnProperty(className)) {
        err = new Error(`No mapping were found for class '${className}'`);
        err.code = 'UNDEF_CLASS';
        throw err;
      }
    }

    _getDefinition(className) {
      this.assertClassHasMapping(className);
      return this.classes[className];
    }

    _startResolving(className) {
      var classDef;
      this.unresolved[className] = true;
      classDef = {
        className: className,
        properties: {},
        availableProperties: {},
        columns: {},
        dependencies: {
          resolved: {},
          mixins: []
        },
        constraints: {
          unique: {},
          names: {}
        },
        indexes: {},
        cache: new LRUCache(10)
      };
      return this.classes[className] = classDef;
    }

    _markResolved(className) {
      delete this.unresolved[className];
      this.resolved[className] = true;
    }

    _hasResolved(className) {
      return this.resolved.hasOwnProperty(className);
    }

    _isResolving(className) {
      return this.unresolved.hasOwnProperty(className);
    }

    _hasTable(table) {
      return this.tables.hasOwnProperty(table);
    }

    _hasColumn(className, column) {
      var definition;
      definition = this.classes[className];
      return definition.columns.hasOwnProperty(column);
    }

    _getResolvedDependencies(className) {
      var definition;
      definition = this.classes[className];
      return definition.dependencies.resolved;
    }

    _setResolvedDependency(className, dependency) {
      var definition;
      definition = this.classes[className];
      definition.dependencies.resolved[dependency] = true;
    }

    _hasResolvedDependency(className, dependency) {
      var definition;
      definition = this.classes[className];
      return definition.dependencies.resolved[dependency];
    }

    _addTable(className) {
      var definition, err;
      definition = this.classes[className];
      if (this._hasTable(definition.table)) {
        err = new Error(`[${definition.className}] table '${definition.table}' already exists`);
        err.code = 'DUP_TABLE';
        throw err;
      }
      this.tables[definition.table] = true;
    }

    _addColumn(className, column, prop) {
      var definition, err;
      if (this._hasColumn(className, column)) {
        err = new Error(`[${className}.${prop}] column '${column}' already exists`);
        err.code = 'DUP_COLUMN';
        throw err;
      }
      definition = this.classes[className];
      if (isStringNotEmpty(column)) {
        definition.columns[column] = prop;
      } else {
        err = new Error(`[${className}.${prop}] column must be a not empty string`);
        err.code = 'COLUMN';
        throw err;
      }
    }

    // Returns parents of added mixin if they exist in this mapping
    _addMixin(className, mixin) {
      var definition, dependencyClassName, i, index, mixinClassName, mixins, obj, parents, ref;
      definition = this.classes[className];
      mixins = definition.dependencies.mixins;
      mixinClassName = mixin.className;
      parents = [];
      for (index = i = ref = mixins.length - 1; i >= 0; index = i += -1) {
        dependencyClassName = mixins[index].className;
        if (dependencyClassName === mixinClassName) {
          return;
        }
        // if mixinClassName already exists
        if (this._hasResolvedDependency(dependencyClassName, mixinClassName)) {
          return;
        }
        // if mixinClassName is a parent of another mixins dependencyClassName, ignore it
        // depending on child => depending on parent
        if (this._hasResolvedDependency(mixinClassName, dependencyClassName)) {
          // if mixinClassName is a child of another mixins dependencyClassName, mark it
          // it is not allowed to depend on parent and child, you must depend on child => parent
          parents.push(dependencyClassName);
        }
      }
      obj = {
        className: mixinClassName
      };
      if (isStringNotEmpty(mixin.column)) {
        obj.column = mixin.column;
      } else {
        obj.column = this.classes[mixinClassName].id.column;
      }
      mixins.push(obj);
      return parents;
    }

  };

  CompiledMapping.prototype.Model = Model;

  CompiledMapping.prototype.specProperties = specProperties;

  return CompiledMapping;

}).call(this);

_resolve = function(className, mapping, compiled) {
  var classDef, err, id, idClassDef, isIdMandatory, pk, rawDefinition;
  if (typeof className !== 'string' || className.length === 0) {
    err = new Error('class is undefined');
    err.code = 'UNDEF_CLASS';
    throw err;
  }
  if (compiled._hasResolved(className)) {
    return;
  }
  rawDefinition = mapping[className];
  if (!_.isPlainObject(rawDefinition)) {
    err = new Error(`Class '${className}' is undefined`);
    err.code = 'UNDEF_CLASS';
    throw err;
  }
  // className is computed by reading given mapping and peeking relevant properties of given mapping
  // Peeking and not copying properties allows to have only what is needed and modify our ClassDefinition without
  // altering (corrupting) given rawDefinition

  // Mark this className as being resolved. For circular reference check
  classDef = compiled._startResolving(className);
  if (!rawDefinition.hasOwnProperty('table')) {
    // default table name is className
    classDef.table = className;
  } else if (isStringNotEmpty(rawDefinition.table)) {
    classDef.table = rawDefinition.table;
  } else {
    err = new Error(`[${classDef.className}] table is not a string`);
    err.code = 'TABLE';
    throw err;
  }
  // check duplicate table and add
  compiled._addTable(classDef.className);
  if (typeof rawDefinition.id === 'string') {
    // id as string => name
    classDef.id = {
      name: rawDefinition.id
    };
  } else if (typeof rawDefinition.id !== 'undefined' && !_.isPlainObject(rawDefinition.id)) {
    err = new Error(`[${classDef.className}] id property must be a not null plain object`);
    err.code = 'ID';
    throw err;
  }
  if (classDef.hasOwnProperty('id')) {
    id = classDef.id;
    isIdMandatory = true;
  } else if (rawDefinition.hasOwnProperty('id')) {
    id = rawDefinition.id;
    isIdMandatory = true;
  } else {
    isIdMandatory = false;
    id = {};
  }
  if (!_.isPlainObject(id)) {
    err = new Error(`[${classDef.className}] id is not well defined. Expecting String|{name: String}|{className: String}. Given ${id}`);
    err.code = 'ID';
    throw err;
  }
  _.defaults(id, id.domain);
  delete id.domain;
  classDef.id = {
    name: null
  };
  if (isStringNotEmpty(id.column)) {
    classDef.id.column = id.column;
  }
  if (id.hasOwnProperty('name') && id.hasOwnProperty('className')) {
    err = new Error(`[${classDef.className}] name and className are mutally exclusive properties for id`);
    err.code = 'INCOMP_ID';
    throw err;
  }
  if (isStringNotEmpty(id.name)) {
    classDef.id.name = id.name;
    if (!id.hasOwnProperty('column')) {
      // default id column is id name
      classDef.id.column = id.name;
    } else if (!isStringNotEmpty(id.column)) {
      err = new Error(`[${classDef.className}] column must be a not empty string for id`);
      err.code = 'ID_COLUMN';
      throw err;
    }
    compiled._addColumn(className, classDef.id.column, classDef.id.name);
  } else if (isStringNotEmpty(id.className)) {
    classDef.id.className = id.className;
  } else if (isIdMandatory) {
    err = new Error(`[${classDef.className}] name xor className must be defined as a not empty string for id`);
    err.code = 'ID';
    throw err;
  }
  // =============================================================================
  //  Properties checking
  // =============================================================================
  _addProperties(compiled, classDef, rawDefinition.properties);
  // =============================================================================
  //  Properties checking - End
  // =============================================================================

  // =============================================================================
  //  Mixins checking
  // =============================================================================
  _addMixins(compiled, classDef, rawDefinition, id, mapping);
  // =============================================================================
  //  Mixins checking - End
  // =============================================================================

  // =============================================================================
  //  Constraints checking
  // =============================================================================
  _addConstraints(compiled, classDef, rawDefinition);
  // =============================================================================
  //  Constraints checking - End
  // =============================================================================

  // =============================================================================
  //  Indexes checking
  // =============================================================================
  _addIndexes(compiled, classDef, rawDefinition);
  // =============================================================================
  //  Indexes checking - End
  // =============================================================================
  if (typeof classDef.id.className === 'string') {
    // single parent inheritance => name = parent name
    idClassDef = compiled.classes[classDef.id.className];
    classDef.id.name = idClassDef.id.name;
    // single parent no column define => assume same column as parent
    if (!classDef.id.hasOwnProperty('column')) {
      classDef.id.column = idClassDef.id.column;
      compiled._addColumn(classDef.className, classDef.id.column, classDef.id.name);
    }
    _inheritType(classDef.id, idClassDef.id);
  }
  // add id as an available property
  if (typeof classDef.id.name === 'string') {
    classDef.availableProperties[classDef.id.name] = {
      definition: classDef.id
    };
  }
  _addSpecProperties(classDef.id, id);
  if (!classDef.id.pk) {
    pk = classDef.table;
    classDef.id.pk = pk;
  }
  _addIndexName(classDef.id.pk, 'pk', compiled);
  _setConstructor(classDef, rawDefinition.ctor);
  compiled._markResolved(classDef.className);
};

_addProperties = function(compiled, classDef, rawProperties) {
  var constraints, err, handler, handlerType, handlers, i, len, prop, propDef, rawPropDef, ref;
  if (!_.isPlainObject(rawProperties)) {
    return;
  }
  constraints = classDef.constraints;
  for (prop in rawProperties) {
    rawPropDef = rawProperties[prop];
    if (typeof rawPropDef === 'string') {
      rawPropDef = {
        column: rawPropDef
      };
    }
    if (!_.isPlainObject(rawPropDef)) {
      err = new Error(`[${classDef.className}] property '${prop}' must be an object or a string`);
      err.code = 'PROP';
      throw err;
    }
    _.defaults(rawPropDef, rawPropDef.domain);
    delete rawPropDef.domain;
    classDef.properties[prop] = propDef = {};
    if (isStringNotEmpty(rawPropDef.column)) {
      propDef.column = rawPropDef.column;
    }
    // add this property as available properties for this className
    // Purposes:
    //   - Fastly get property definition
    classDef.availableProperties[prop] = {
      definition: propDef
    };
    // composite element definition
    if (rawPropDef.hasOwnProperty('className')) {
      propDef.className = rawPropDef.className;
    }
    if (rawPropDef.hasOwnProperty('handlers')) {
      propDef.handlers = handlers = {};
      ref = ['insert', 'update', 'read', 'write'];
      // insert: default value if undefined
      // update: automatic value on update, don't care about setted one
      // read: from database to value. Ex: SQL Format Date String -> Javascript Date, JSON String -> JSON Object
      // write: from value to database. Ex: Javascript Date -> SQL Format Date String, JSON Object -> JSON String
      for (i = 0, len = ref.length; i < len; i++) {
        handlerType = ref[i];
        handler = rawPropDef.handlers[handlerType];
        if (typeof handler === 'function') {
          handlers[handlerType] = handler;
        }
      }
    }
    // optimistic lock definition
    // update only values where lock is the same
    // with update handler, prevents concurrent update
    if (rawPropDef.hasOwnProperty('lock')) {
      propDef.lock = typeof rawPropDef.lock === 'boolean' && rawPropDef.lock;
    }
    _addSpecProperties(propDef, rawPropDef, classDef);
    if (rawPropDef.unique) {
      propDef.unique = rawPropDef.unique;
      _addUniqueConstraint(propDef.unique, [prop], classDef, compiled);
    }
  }
};

_addMixins = function(compiled, classDef, rawDefinition, id, mapping) {
  var _mixin, className, err, fk, i, len, mixin, mixinDef, mixins, parents, prop, resolved, seenMixins;
  if (!rawDefinition.hasOwnProperty('mixins')) {
    mixins = [];
  } else if (isStringNotEmpty(rawDefinition.mixins)) {
    mixins = [rawDefinition.mixins];
  } else if (Array.isArray(rawDefinition.mixins)) {
    mixins = rawDefinition.mixins.slice(0);
  } else {
    err = new Error(`[${classDef.className}] mixins property can only be a string or an array of strings`);
    err.code = 'MIXINS';
    throw err;
  }
  classDef.mixins = [];
  if (isStringNotEmpty(id.className)) {
    mixins.unshift(id);
  }
  seenMixins = {};
  for (i = 0, len = mixins.length; i < len; i++) {
    mixin = mixins[i];
    if (typeof mixin === 'string') {
      mixin = {
        className: mixin
      };
    }
    if (!_.isPlainObject(mixin)) {
      err = new Error(`[${classDef.className}] mixin can only be a string or a not null object`);
      err.code = 'MIXIN';
      throw err;
    }
    if (!mixin.hasOwnProperty('className')) {
      err = new Error(`[${classDef.className}] mixin has no className property`);
      err.code = 'MIXIN';
      throw err;
    }
    className = mixin.className;
    if (seenMixins[className]) {
      err = new Error(`[${classDef.className}] mixin [${mixin.className}]: duplicate mixin. Make sure it's not also and id className`);
      err.code = 'DUP_MIXIN';
      throw err;
    }
    _.defaults(mixin, mixin.domain);
    delete mixin.domain;
    seenMixins[className] = true;
    _mixin = {
      className: className
    };
    if (isStringNotEmpty(mixin.column)) {
      _mixin.column = mixin.column;
    } else if (mixin.hasOwnProperty('column')) {
      err = new Error(`[${classDef.className}] mixin [${mixin.className}]: Column is not a string or is empty`);
      err.code = 'MIXIN_COLUMN';
      throw err;
    }
    classDef.mixins.push(_mixin);
    if (!compiled._hasResolved(className)) {
      if (compiled._isResolving(className)) {
        err = new Error(`[${classDef.className}] mixin [${mixin.className}]: Circular reference detected: -> '${className}'`);
        err.code = 'CIRCULAR_REF';
        throw err;
      }
      _resolve(className, mapping, compiled);
    }
    // Mark this mixin as dependency resolved
    compiled._setResolvedDependency(classDef.className, className);
    // mixin default column if miin className id column
    if (!_mixin.hasOwnProperty('column')) {
      _mixin.column = compiled.classes[_mixin.className].id.column;
    }
    // id column of mixins that are not class parent have not been added as column,
    // add them to avoid duplicate columns
    if (classDef.id.className !== _mixin.className) {
      compiled._addColumn(classDef.className, _mixin.column, compiled.classes[_mixin.className].id.name);
    }
    // Mark all resolved dependencies,
    // Used to check circular references and related mixin
    resolved = compiled._getResolvedDependencies(className);
    for (className in resolved) {
      compiled._setResolvedDependency(classDef.className, className);
    }
    // check related mixin
    parents = compiled._addMixin(classDef.className, mixin);
    if (Array.isArray(parents) && parents.length > 0) {
      err = new Error(`[${classDef.className}] mixin '${mixin}' depends on mixins ${parents}. Add only mixins with no relationship or you have a problem in your design`);
      err.code = 'RELATED_MIXIN';
      err.extend = parents;
      throw err;
    }
    // add this mixin available properties as available properties for this className
    // Purposes:
    //   - On read, to fastly check if join on this mixin is required
    mixinDef = compiled.classes[_mixin.className];
    _inheritType(_mixin, mixinDef.id);
    _addSpecProperties(_mixin, mixin);
    if (!_mixin.fk) {
      fk = `${classDef.table}_${_mixin.column}_EXT_${mixinDef.table}_${mixinDef.id.column}`;
      _mixin.fk = fk;
    }
    _addIndexName(_mixin.fk, 'fk', compiled);
    for (prop in mixinDef.availableProperties) {
      if (!classDef.availableProperties.hasOwnProperty(prop)) {
        classDef.availableProperties[prop] = {
          mixin: _mixin,
          definition: mixinDef.availableProperties[prop].definition
        };
      }
    }
  }
};

_addConstraints = function(compiled, classDef, rawDefinition) {
  var ERR_CODE, constraint, constraints, err, i, index, j, keys, len, len1, prop, propDef, properties, rawConstraints;
  constraints = classDef.constraints;
  ERR_CODE = 'CONSTRAINT';
  rawConstraints = rawDefinition.constraints;
  if (_.isPlainObject(rawConstraints)) {
    rawConstraints = [rawConstraints];
  }
  if (!Array.isArray(rawConstraints)) {
    if (rawConstraints) {
      err = new Error(`[${classDef.className}] constraints can only be a plain object or an array of plain objects`);
      err.code = ERR_CODE;
      throw err;
    }
    return;
  }
  for (index = i = 0, len = rawConstraints.length; i < len; index = ++i) {
    constraint = rawConstraints[index];
    if (!_.isPlainObject(constraint)) {
      err = new Error(`[${classDef.className}] constraint at index ${index} is not a plain object`);
      err.code = ERR_CODE;
      throw err;
    }
    if (constraint.type !== 'unique') {
      err = new Error(`[${classDef.className}] constraint at index ${index} is not supported. Supported constraint type is 'unique'`);
      err.code = ERR_CODE;
      throw err;
    }
    properties = constraint.properties;
    if (isStringNotEmpty(properties)) {
      properties = [properties];
    }
    if (!Array.isArray(properties)) {
      err = new Error(`[${classDef.className}] constraint at index ${index}: properties must be a not empty string or an array of strings`);
      err.code = ERR_CODE;
      throw err;
    }
    for (j = 0, len1 = properties.length; j < len1; j++) {
      prop = properties[j];
      if (!classDef.properties.hasOwnProperty(prop)) {
        err = new Error(`[${classDef.className}] - constraint at index ${index}: class does not owned property '${prop}'`);
        err.code = ERR_CODE;
        throw err;
      }
    }
    if (constraint.name && ('string' !== typeof constraint.name || constraint.name.length === 0)) {
      err = new Error(`[${classDef.className}] constraint at index ${index}: Name must be a string`);
      err.code = ERR_CODE;
      throw err;
    }
    keys = properties.slice(0);
    if (keys.length === 1) {
      prop = properties[0];
      propDef = classDef.properties[prop];
      propDef.unique = true;
    }
    _addUniqueConstraint(constraint.name, keys, classDef, compiled);
  }
};

_addIndexes = function(compiled, classDef, rawDefinition) {
  var ERR_CODE, constraints, err, i, indexes, key, len, name, names, prop, properties, rawIndexes;
  indexes = classDef.indexes;
  ERR_CODE = 'INDEX';
  rawIndexes = rawDefinition.indexes;
  if (!_.isPlainObject(rawIndexes)) {
    if (rawIndexes) {
      err = new Error(`[${classDef.className}] indexes can only be a plain object`);
      err.code = ERR_CODE;
      throw err;
    }
    return;
  }
  constraints = classDef.constraints;
  names = constraints.names;
  for (name in rawIndexes) {
    properties = rawIndexes[name];
    if (isStringNotEmpty(properties)) {
      properties = [properties];
    }
    if (!Array.isArray(properties)) {
      err = new Error(`[${classDef.className}] index '${name}' is not an Array`);
      err.code = ERR_CODE;
      throw err;
    }
    for (i = 0, len = properties.length; i < len; i++) {
      prop = properties[i];
      if (!classDef.properties.hasOwnProperty(prop)) {
        err = new Error(`[${classDef.className}] - index '${name}': class does not owned property '${prop}'`);
        err.code = ERR_CODE;
        throw err;
      }
    }
    properties = properties.slice(0);
    key = properties.join(':');
    if (constraints.unique.hasOwnProperty(key)) {
      err = new Error(`the unique constraint with name ${constraints.names[key]} matches ${key}. Only one index per set of properties is allowed`);
      err.code = ERR_CODE;
      throw err;
    }
    _addIndexName(name, 'ix', compiled);
    indexes[name] = properties;
  }
};

_addUniqueConstraint = function(name, properties, classDef, compiled) {
  properties;
  var constraints, err, key;
  key = properties.join(':');
  ({constraints} = classDef);
  if (constraints.unique.hasOwnProperty(key)) {
    err = new Error(`the unique constraint with name ${constraints.names[key]} matches ${key}. Only one index per set of properties is allowed`);
    err.code = 'CONSTRAINT';
    throw err;
  }
  if (name) {
    _addIndexName(name, 'uk', compiled);
    constraints.names[key] = name;
  }
  constraints.unique[key] = properties;
};

_addIndexName = function(name, type, compiled) {
  var err, indexNames;
  if (!isStringNotEmpty(name)) {
    err = new Error(`a ${type} index must be a not empty string`);
    err.code = 'INDEX';
    throw err;
  }
  indexNames = compiled.indexNames[type];
  if (indexNames.hasOwnProperty(name)) {
    err = new Error(`a ${type} index with name ${name} is already defined`);
    err.code = 'INDEX';
    throw err;
  }
  indexNames[name] = true;
};

_inheritType = function(child, parent) {
  var length, match, type, type_args;
  ({type, type_args} = parent);
  if (type && (match = type.match(/^(?:(small|big)?(?:increments|serial)|serial([248]))$/))) {
    length = match[1] || match[2];
    switch (length) {
      case 'big':
      case '8':
        type = 'bigint';
        break;
      case 'small':
      case '2':
        type = 'smallint';
        break;
      default:
        type = 'integer';
    }
  }
  if (type) {
    child.type = type;
  }
  child.type_args = type_args || [];
  // unsigned int
  child.type_args[1] = true;
  return child;
};

_addSpecProperties = function(definition, rawDefinition) {
  var err, i, len, prop, value;
  for (i = 0, len = specProperties.length; i < len; i++) {
    prop = specProperties[i];
    if (rawDefinition.hasOwnProperty(prop)) {
      value = rawDefinition[prop];
      switch (prop) {
        case 'type':
          value = value.toLowerCase();
          break;
        case 'type_args':
          if (value && !Array.isArray(value)) {
            err = new Error(`[${definition.className}] - property '${prop}': type_args must be an Array`);
            err.code = 'TYPE_ARGS';
            throw err;
          }
      }
      definition[prop] = value;
    }
  }
};

_setConstructor = function(classDef, Ctor) {
  var err;
  if ('undefined' === typeof Ctor) {
    Ctor = (function() {
      class Ctor extends Model {};

      Ctor.prototype.className = classDef.className;

      return Ctor;

    }).call(this);
  }
  if (typeof Ctor !== 'function') {
    err = new Error(`[${classDef.className}] given constructor is not a function`);
    err.code = 'CTOR';
    throw err;
  }
  classDef.ctor = Ctor;
};
