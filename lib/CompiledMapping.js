// Generated by CoffeeScript 1.9.2
var CompiledMapping, GenericUtil, Model, _, _addConstraints, _addMixins, _addProperties, _resolve, _setConstructor, log4js, logger, modelId,
  hasProp = {}.hasOwnProperty;

log4js = global.log4js || (global.log4js = require('log4js'));

logger = log4js.getLogger('CompiledMapping');

_ = require('lodash');

GenericUtil = require('./GenericUtil');

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
    var _clone, prop;
    _clone = new this.constructor();
    for (prop in this) {
      if (!hasProp.call(this, prop)) continue;
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

  Model.prototype.remove = function(prop) {
    return delete this.attributes[prop];
  };

  Model.prototype.toJSON = function() {
    return this.attributes;
  };

  return Model;

})();

module.exports = CompiledMapping = (function() {
  function CompiledMapping(mapping) {
    var classDef, className, definition, i, len, prop, ref, ref1, ref2, value;
    ref = ['classes', 'resolved', 'unresolved', 'tables'];
    for (i = 0, len = ref.length; i < len; i++) {
      prop = ref[i];
      this[prop] = {};
    }
    for (className in mapping) {
      _resolve(className, mapping, this);
    }
    ref1 = this.classes;
    for (className in ref1) {
      classDef = ref1[className];
      ref2 = classDef.properties;
      for (prop in ref2) {
        value = ref2[prop];
        if (value.hasOwnProperty('className') && !value.hasOwnProperty('column')) {
          definition = this._getDefinition(value.className);
          value.column = definition.id.column;
        }
        this._addColumn(className, value.column, prop);
      }
    }
    this.resolved = true;
  }

  CompiledMapping.prototype.Model = Model;

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
      }
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
      err = new Error("[" + className + "] column '" + column + "' already exists");
      err.code = 'DUP_COLUMN';
      throw err;
    }
    definition = this.classes[className];
    if (GenericUtil.notEmptyString(column)) {
      definition.columns[column] = prop;
    } else {
      err = new Error("[" + className + "] column must be a not empty string");
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
    if (GenericUtil.notEmptyString(mixin.column)) {
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
  var classDef, err, id, idClassDef, idIsMandatory, rawDefinition;
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
    err = new Error("Class '" + className + "'' is undefined");
    err.code = 'UNDEF_CLASS';
    throw err;
  }
  classDef = compiled._startResolving(className);
  if (!rawDefinition.hasOwnProperty('table')) {
    classDef.table = className;
  } else if (GenericUtil.notEmptyString(rawDefinition.table)) {
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
  idIsMandatory = true;
  if (classDef.hasOwnProperty('id')) {
    id = classDef.id;
  } else if (rawDefinition.hasOwnProperty('id')) {
    id = rawDefinition.id;
  } else {
    idIsMandatory = false;
    id = {};
  }
  if (!_.isPlainObject(id)) {
    err = new Error("[" + classDef.className + "] id is not well defined. Expecting String|{name: String}|{className: String}. Given " + id);
    err.code = 'ID';
    throw err;
  }
  classDef.id = {
    name: null
  };
  if (GenericUtil.notEmptyString(id.column)) {
    classDef.id.column = id.column;
  }
  if (id.hasOwnProperty('name') && id.hasOwnProperty('className')) {
    err = new Error("[" + classDef.className + "] name and className are mutally exclusive properties for id");
    err.code = 'INCOMP_ID';
    throw err;
  }
  if (GenericUtil.notEmptyString(id.name)) {
    classDef.id.name = id.name;
    if (!id.hasOwnProperty('column')) {
      classDef.id.column = id.name;
    } else if (!GenericUtil.notEmptyString(id.column)) {
      err = new Error("[" + classDef.className + "] column must be a not empty string for id");
      err.code = 'ID_COLUMN';
      throw err;
    }
    compiled._addColumn(className, classDef.id.column, classDef.id.name);
  } else if (GenericUtil.notEmptyString(id.className)) {
    classDef.id.className = id.className;
  } else if (idIsMandatory) {
    err = new Error("[" + classDef.className + "] name xor className must be defined as a not empty string for id");
    err.code = 'ID';
    throw err;
  }
  _addProperties(classDef, rawDefinition.properties);
  _addMixins(compiled, classDef, rawDefinition, id, mapping);
  _addConstraints(classDef, rawDefinition);
  if (typeof classDef.id.className === 'string') {
    idClassDef = compiled.classes[classDef.id.className];
    classDef.id.name = idClassDef.id.name;
    if (!classDef.id.hasOwnProperty('column')) {
      classDef.id.column = idClassDef.id.column;
      compiled._addColumn(classDef.className, classDef.id.column, classDef.id.name);
    }
  }
  if (typeof classDef.id.name === 'string') {
    classDef.availableProperties[classDef.id.name] = {
      definition: classDef.id
    };
  }
  _setConstructor(classDef, rawDefinition.ctor);
  compiled._markResolved(classDef.className);
};

_addProperties = function(classDef, rawProperties) {
  var err, handler, handlerType, handlers, i, len, prop, propDef, rawPropDef, ref;
  if (!_.isPlainObject(rawProperties)) {
    return;
  }
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
    classDef.properties[prop] = propDef = {};
    if (GenericUtil.notEmptyString(rawPropDef.column)) {
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
  }
};

_addMixins = function(compiled, classDef, rawDefinition, id, mapping) {
  var _mixin, className, err, i, len, mixin, mixinDef, mixins, parents, prop, resolved, seenMixins;
  if (!rawDefinition.hasOwnProperty('mixins')) {
    mixins = [];
  } else if (GenericUtil.notEmptyString(rawDefinition.mixins)) {
    mixins = [rawDefinition.mixins];
  } else if (Array.isArray(rawDefinition.mixins)) {
    mixins = rawDefinition.mixins.slice(0);
  } else {
    err = new Error("[" + classDef.className + "] mixins property can only be a string or an array of strings");
    err.code = 'MIXINS';
    throw err;
  }
  classDef.mixins = [];
  if (GenericUtil.notEmptyString(id.className)) {
    mixins.unshift(id.className);
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
    seenMixins[className] = true;
    _mixin = {
      className: className
    };
    if (GenericUtil.notEmptyString(mixin.column)) {
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

_addConstraints = function(classDef, rawDefinition) {
  var ERR_CODE, constraint, constraints, err, i, index, j, len, len1, prop, properties, rawConstraints;
  classDef.constraints = constraints = {
    unique: []
  };
  rawConstraints = rawDefinition.constraints;
  if (_.isPlainObject(rawConstraints)) {
    rawConstraints = [rawConstraints];
  }
  if (!Array.isArray(rawConstraints)) {
    return;
  }
  ERR_CODE = 'CONSTRAINT';
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
    if (GenericUtil.notEmptyString(properties)) {
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
        err = new Error("[" + classDef.className + "] - constraint at index " + index + ": property " + prop + " is not owned");
        err.code = ERR_CODE;
        throw err;
      }
    }
    constraints.unique.push(properties.slice(0));
  }
};

_setConstructor = function(classDef, Ctor) {
  var err;
  if ('undefined' === typeof Ctor) {
    Ctor = Model;
  }
  if (typeof Ctor !== 'function') {
    err = new Error("[" + classDef.className + "] given constructor is not a function");
    err.code = 'CTOR';
    throw err;
  }
  classDef.ctor = Ctor;
};