var CompiledMapping, LRU, Model, _, _addConstraints, _addIndexName, _addIndexes, _addMixins, _addProperties, _addSpecProperties, _addUniqueConstraint, _inheritType, _resolve, _setConstructor, isStringNotEmpty, log4js, logger, modelId, specProperties,
  hasProp = {}.hasOwnProperty,
  extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

log4js = require('./log4js');

logger = log4js.getLogger(__filename.replace(/^(?:.+[\/\\])?([^.\/\\]+)(?:.[^.]+)?$/, '$1'));

_ = require('lodash');

LRU = require('lru-cache');

isStringNotEmpty = function(str) {
  return typeof str === 'string' && str.length > 0;
};

modelId = 0;

Model = (function() {
  function Model(attributes) {
    this.cid = ++modelId;
    if (_.isPlainObject(attributes)) {
      this.attributes = _.clone(attributes);
    } else {
      this.attributes = {};
    }
  }

  Model.prototype.clone = function() {
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
  };

  Model.prototype.set = function(prop, value) {
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
  };

  Model.prototype.get = function(prop) {
    return this.attributes[prop];
  };

  Model.prototype.unset = function(prop) {
    return delete this.attributes[prop];
  };

  Model.prototype.toJSON = function() {
    return this.attributes;
  };

  return Model;

})();

specProperties = ['type', 'type_args', 'nullable', 'pk', 'fk', 'fkindex', 'defaultValue'];

module.exports = CompiledMapping = (function() {
  function CompiledMapping(mapping) {
    var classDef, className, fk, i, indexes, key, len, name, names, parentDef, prop, propDef, propToColumn, properties, ref, ref1, ref2, ref3, ref4, unique;
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
      for (prop in ref3) {
        propDef = ref3[prop];
        if (propDef.hasOwnProperty('className')) {
          if (!propDef.hasOwnProperty('fk')) {
            parentDef = this._getDefinition(propDef.className);
            fk = classDef.table + "_" + propDef.column + "_HAS_" + parentDef.table + "_" + parentDef.id.column;
            propDef.fk = fk;
          }
          _addIndexName(propDef.fk, 'fk', this);
        }
      }
      indexes = classDef.indexes, (ref4 = classDef.constraints, unique = ref4.unique, names = ref4.names);
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

  CompiledMapping.prototype.Model = Model;

  CompiledMapping.prototype.specProperties = specProperties;

  CompiledMapping.prototype.getConstructor = function(className) {
    this.assertClassHasMapping(className);
    return this.classes[className].ctor;
  };

  CompiledMapping.prototype.newInstance = function(className, attributes) {
    this.assertClassHasMapping(className);
    return new this.classes[className].ctor(attributes);
  };

  CompiledMapping.prototype.getIdName = function(className) {
    this.assertClassHasMapping(className);
    return this.classes[className].id.name;
  };

  CompiledMapping.prototype.getDefinition = function(className) {
    return _.cloneDeep(this._getDefinition(className));
  };

  CompiledMapping.prototype.getMapping = function() {
    return _.cloneDeep(this.classes);
  };

  CompiledMapping.prototype.getTable = function(className) {
    return this._getDefinition(className).table;
  };

  CompiledMapping.prototype.getColumn = function(className, prop) {
    var definition;
    definition = this._getDefinition(className);
    if (definition.id.name === prop) {
      return definition.id.column;
    } else if (definition.properties.hasOwnProperty(prop)) {
      return definition.properties[prop].column;
    }
  };

  CompiledMapping.prototype.assertClassHasMapping = function(className) {
    var err;
    if (!this.classes.hasOwnProperty(className)) {
      err = new Error("No mapping were found for class '" + className + "'");
      err.code = 'UNDEF_CLASS';
      throw err;
    }
  };

  CompiledMapping.prototype._getDefinition = function(className) {
    this.assertClassHasMapping(className);
    return this.classes[className];
  };

  CompiledMapping.prototype._startResolving = function(className) {
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
      cache: LRU(10)
    };
    return this.classes[className] = classDef;
  };

  CompiledMapping.prototype._markResolved = function(className) {
    delete this.unresolved[className];
    this.resolved[className] = true;
  };

  CompiledMapping.prototype._hasResolved = function(className) {
    return this.resolved.hasOwnProperty(className);
  };

  CompiledMapping.prototype._isResolving = function(className) {
    return this.unresolved.hasOwnProperty(className);
  };

  CompiledMapping.prototype._hasTable = function(table) {
    return this.tables.hasOwnProperty(table);
  };

  CompiledMapping.prototype._hasColumn = function(className, column) {
    var definition;
    definition = this.classes[className];
    return definition.columns.hasOwnProperty(column);
  };

  CompiledMapping.prototype._getResolvedDependencies = function(className) {
    var definition;
    definition = this.classes[className];
    return definition.dependencies.resolved;
  };

  CompiledMapping.prototype._setResolvedDependency = function(className, dependency) {
    var definition;
    definition = this.classes[className];
    definition.dependencies.resolved[dependency] = true;
  };

  CompiledMapping.prototype._hasResolvedDependency = function(className, dependency) {
    var definition;
    definition = this.classes[className];
    return definition.dependencies.resolved[dependency];
  };

  CompiledMapping.prototype._addTable = function(className) {
    var definition, err;
    definition = this.classes[className];
    if (this._hasTable(definition.table)) {
      err = new Error("[" + definition.className + "] table '" + definition.table + "' already exists");
      err.code = 'DUP_TABLE';
      throw err;
    }
    this.tables[definition.table] = true;
  };

  CompiledMapping.prototype._addColumn = function(className, column, prop) {
    var definition, err;
    if (this._hasColumn(className, column)) {
      err = new Error("[" + className + "." + prop + "] column '" + column + "' already exists");
      err.code = 'DUP_COLUMN';
      throw err;
    }
    definition = this.classes[className];
    if (isStringNotEmpty(column)) {
      definition.columns[column] = prop;
    } else {
      err = new Error("[" + className + "." + prop + "] column must be a not empty string");
      err.code = 'COLUMN';
      throw err;
    }
  };

  CompiledMapping.prototype._addMixin = function(className, mixin) {
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
      if (this._hasResolvedDependency(dependencyClassName, mixinClassName)) {
        return;
      }
      if (this._hasResolvedDependency(mixinClassName, dependencyClassName)) {
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
  };

  return CompiledMapping;

})();

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
    err = new Error("Class '" + className + "' is undefined");
    err.code = 'UNDEF_CLASS';
    throw err;
  }
  classDef = compiled._startResolving(className);
  if (!rawDefinition.hasOwnProperty('table')) {
    classDef.table = className;
  } else if (isStringNotEmpty(rawDefinition.table)) {
    classDef.table = rawDefinition.table;
  } else {
    err = new Error("[" + classDef.className + "] table is not a string");
    err.code = 'TABLE';
    throw err;
  }
  compiled._addTable(classDef.className);
  if (typeof rawDefinition.id === 'string') {
    classDef.id = {
      name: rawDefinition.id
    };
  } else if (typeof rawDefinition.id !== 'undefined' && !_.isPlainObject(rawDefinition.id)) {
    err = new Error("[" + classDef.className + "] id property must be a not null plain object");
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
    err = new Error("[" + classDef.className + "] id is not well defined. Expecting String|{name: String}|{className: String}. Given " + id);
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
    err = new Error("[" + classDef.className + "] name and className are mutally exclusive properties for id");
    err.code = 'INCOMP_ID';
    throw err;
  }
  if (isStringNotEmpty(id.name)) {
    classDef.id.name = id.name;
    if (!id.hasOwnProperty('column')) {
      classDef.id.column = id.name;
    } else if (!isStringNotEmpty(id.column)) {
      err = new Error("[" + classDef.className + "] column must be a not empty string for id");
      err.code = 'ID_COLUMN';
      throw err;
    }
    compiled._addColumn(className, classDef.id.column, classDef.id.name);
  } else if (isStringNotEmpty(id.className)) {
    classDef.id.className = id.className;
  } else if (isIdMandatory) {
    err = new Error("[" + classDef.className + "] name xor className must be defined as a not empty string for id");
    err.code = 'ID';
    throw err;
  }
  _addProperties(compiled, classDef, rawDefinition.properties);
  _addMixins(compiled, classDef, rawDefinition, id, mapping);
  _addConstraints(compiled, classDef, rawDefinition);
  _addIndexes(compiled, classDef, rawDefinition);
  if (typeof classDef.id.className === 'string') {
    idClassDef = compiled.classes[classDef.id.className];
    classDef.id.name = idClassDef.id.name;
    if (!classDef.id.hasOwnProperty('column')) {
      classDef.id.column = idClassDef.id.column;
      compiled._addColumn(classDef.className, classDef.id.column, classDef.id.name);
    }
    _inheritType(classDef.id, idClassDef.id);
  }
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
      err = new Error("[" + classDef.className + "] property '" + prop + "' must be an object or a string");
      err.code = 'PROP';
      throw err;
    }
    _.defaults(rawPropDef, rawPropDef.domain);
    delete rawPropDef.domain;
    classDef.properties[prop] = propDef = {};
    if (isStringNotEmpty(rawPropDef.column)) {
      propDef.column = rawPropDef.column;
    }
    classDef.availableProperties[prop] = {
      definition: propDef
    };
    if (rawPropDef.hasOwnProperty('className')) {
      propDef.className = rawPropDef.className;
    }
    if (rawPropDef.hasOwnProperty('handlers')) {
      propDef.handlers = handlers = {};
      ref = ['insert', 'update', 'read', 'write'];
      for (i = 0, len = ref.length; i < len; i++) {
        handlerType = ref[i];
        handler = rawPropDef.handlers[handlerType];
        if (typeof handler === 'function') {
          handlers[handlerType] = handler;
        }
      }
    }
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
    err = new Error("[" + classDef.className + "] mixins property can only be a string or an array of strings");
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
      err = new Error("[" + classDef.className + "] mixin can only be a string or a not null object");
      err.code = 'MIXIN';
      throw err;
    }
    if (!mixin.hasOwnProperty('className')) {
      err = new Error("[" + classDef.className + "] mixin has no className property");
      err.code = 'MIXIN';
      throw err;
    }
    className = mixin.className;
    if (seenMixins[className]) {
      err = new Error("[" + classDef.className + "] mixin [" + mixin.className + "]: duplicate mixin. Make sure it's not also and id className");
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
      err = new Error("[" + classDef.className + "] mixin [" + mixin.className + "]: Column is not a string or is empty");
      err.code = 'MIXIN_COLUMN';
      throw err;
    }
    classDef.mixins.push(_mixin);
    if (!compiled._hasResolved(className)) {
      if (compiled._isResolving(className)) {
        err = new Error("[" + classDef.className + "] mixin [" + mixin.className + "]: Circular reference detected: -> '" + className + "'");
        err.code = 'CIRCULAR_REF';
        throw err;
      }
      _resolve(className, mapping, compiled);
    }
    compiled._setResolvedDependency(classDef.className, className);
    if (!_mixin.hasOwnProperty('column')) {
      _mixin.column = compiled.classes[_mixin.className].id.column;
    }
    if (classDef.id.className !== _mixin.className) {
      compiled._addColumn(classDef.className, _mixin.column, compiled.classes[_mixin.className].id.name);
    }
    resolved = compiled._getResolvedDependencies(className);
    for (className in resolved) {
      compiled._setResolvedDependency(classDef.className, className);
    }
    parents = compiled._addMixin(classDef.className, mixin);
    if (Array.isArray(parents) && parents.length > 0) {
      err = new Error("[" + classDef.className + "] mixin '" + mixin + "' depends on mixins " + parents + ". Add only mixins with no relationship or you have a problem in your design");
      err.code = 'RELATED_MIXIN';
      err.extend = parents;
      throw err;
    }
    mixinDef = compiled.classes[_mixin.className];
    _inheritType(_mixin, mixinDef.id);
    _addSpecProperties(_mixin, mixin);
    if (!_mixin.fk) {
      fk = classDef.table + "_" + _mixin.column + "_EXT_" + mixinDef.table + "_" + mixinDef.id.column;
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
      err = new Error("[" + classDef.className + "] constraints can only be a plain object or an array of plain objects");
      err.code = ERR_CODE;
      throw err;
    }
    return;
  }
  for (index = i = 0, len = rawConstraints.length; i < len; index = ++i) {
    constraint = rawConstraints[index];
    if (!_.isPlainObject(constraint)) {
      err = new Error("[" + classDef.className + "] constraint at index " + index + " is not a plain object");
      err.code = ERR_CODE;
      throw err;
    }
    if (constraint.type !== 'unique') {
      err = new Error("[" + classDef.className + "] constraint at index " + index + " is not supported. Supported constraint type is 'unique'");
      err.code = ERR_CODE;
      throw err;
    }
    properties = constraint.properties;
    if (isStringNotEmpty(properties)) {
      properties = [properties];
    }
    if (!Array.isArray(properties)) {
      err = new Error("[" + classDef.className + "] constraint at index " + index + ": properties must be a not empty string or an array of strings");
      err.code = ERR_CODE;
      throw err;
    }
    for (j = 0, len1 = properties.length; j < len1; j++) {
      prop = properties[j];
      if (!classDef.properties.hasOwnProperty(prop)) {
        err = new Error("[" + classDef.className + "] - constraint at index " + index + ": class does not owned property '" + prop + "'");
        err.code = ERR_CODE;
        throw err;
      }
    }
    if (constraint.name && ('string' !== typeof constraint.name || constraint.name.length === 0)) {
      err = new Error("[" + classDef.className + "] constraint at index " + index + ": Name must be a string");
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
      err = new Error("[" + classDef.className + "] indexes can only be a plain object");
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
      err = new Error("[" + classDef.className + "] index '" + name + "' is not an Array");
      err.code = ERR_CODE;
      throw err;
    }
    for (i = 0, len = properties.length; i < len; i++) {
      prop = properties[i];
      if (!classDef.properties.hasOwnProperty(prop)) {
        err = new Error("[" + classDef.className + "] - index '" + name + "': class does not owned property '" + prop + "'");
        err.code = ERR_CODE;
        throw err;
      }
    }
    properties = properties.slice(0);
    key = properties.join(':');
    if (constraints.unique.hasOwnProperty(key)) {
      err = new Error("the unique constraint with name " + constraints.names[key] + " matches " + key + ". Only one index per set of properties is allowed");
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
  constraints = classDef.constraints;
  if (constraints.unique.hasOwnProperty(key)) {
    err = new Error("the unique constraint with name " + constraints.names[key] + " matches " + key + ". Only one index per set of properties is allowed");
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
    err = new Error("a " + type + " index must be a not empty string");
    err.code = 'INDEX';
    throw err;
  }
  indexNames = compiled.indexNames[type];
  if (indexNames.hasOwnProperty(name)) {
    err = new Error("a " + type + " index with name " + name + " is already defined");
    err.code = 'INDEX';
    throw err;
  }
  indexNames[name] = true;
};

_inheritType = function(child, parent) {
  var length, match, type, type_args;
  type = parent.type, type_args = parent.type_args;
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
            err = new Error("[" + definition.className + "] - property '" + prop + "': type_args must be an Array");
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
    Ctor = (function(superClass) {
      extend(Ctor, superClass);

      function Ctor() {
        return Ctor.__super__.constructor.apply(this, arguments);
      }

      Ctor.prototype.className = classDef.className;

      return Ctor;

    })(Model);
  }
  if (typeof Ctor !== 'function') {
    err = new Error("[" + classDef.className + "] given constructor is not a function");
    err.code = 'CTOR';
    throw err;
  }
  classDef.ctor = Ctor;
};
