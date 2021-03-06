var JOIN_FUNC, PlaceHolderParser, RowMap, STATIC, _, _coerce, _createModel, _createPlainObject, _getModelValue, _getPlainObjectValue, _handleRead, _readFields, _setModelValue, _setPlainObjectValue, fieldHolderParser, guessEscapeOpts, log4js, logger, path, placeHolderParser, squel;

log4js = require('./log4js');

logger = log4js.getLogger(__filename.replace(/^(?:.+[\/\\])?([^.\/\\]+)(?:.[^.]+)?$/, '$1'));

_ = require('lodash');

path = require('path');

PlaceHolderParser = require('./PlaceHolderParser');

squel = require('squel');

({guessEscapeOpts} = require('./tools'));

STATIC = {
  PROP_SEP: ':',
  FIELD_CHAR_BEGIN: '{',
  FIELD_CHAR_END: '}',
  ROOT: 'root'
};

fieldHolderParser = new PlaceHolderParser(STATIC.FIELD_CHAR_BEGIN, STATIC.FIELD_CHAR_END);

placeHolderParser = new PlaceHolderParser();

JOIN_FUNC = {
  default: 'join',
  outer: 'outer_join',
  left: 'left_join',
  right: 'right_join'
};

_handleRead = function(value, model, propDef) {
  if (typeof propDef.read === 'function') {
    value = propDef.read(value, model);
  }
  return value;
};

_createModel = function(className = this.className) {
  var Ctor, definition;
  definition = this.manager.getDefinition(className);
  Ctor = definition.ctor;
  return new Ctor();
};

_setModelValue = function(model, prop, value, propDef) {
  return model.set(prop, _handleRead(value, model, propDef));
};

_getModelValue = function(model, prop) {
  return model.get(prop);
};

_createPlainObject = function() {
  return {};
};

_setPlainObjectValue = function(model, prop, value, propDef) {
  return model[prop] = _handleRead(value, model, propDef);
};

_getPlainObjectValue = function(model, prop) {
  return model[prop];
};

// Private Class, supposed to be used in conjunction with PersistenceManager Class
module.exports = RowMap = class RowMap {
  // Class that do the mapping between className, queries to execute and properties of className
  constructor(className1, manager, options, skip) {
    this.className = className1;
    this.manager = manager;
    this.options = guessEscapeOpts(options);
    if (skip) {
      return;
    }
    _.extend(this, {
      _infos: {},
      _tableAliases: {},
      _tabId: 0,
      _columnAliases: {},
      _colId: 0,
      _tables: {},
      _mixins: {},
      _joining: {}
    });
    this.select = options.select;
    this.values = options.values;
    delete this.options.select;
    delete this.options.values;
    this._initialize();
    this._initRootElement(this.className, this._getUniqueId());
    this._processJoins();
    this._processFields();
    this._processColumns();
    this._processBlocks();
  }

  setValues(values1) {
    this.values = values1;
  }

  setValue(key, value) {
    return this.values[key] = value;
  }

  _initialize() {
    var options;
    options = this.options;
    if (options.type === 'json' || options.count) {
      this._setValue = _setPlainObjectValue;
      this._getValue = _getPlainObjectValue;
      this._create = _createPlainObject;
    } else {
      this._setValue = _setModelValue;
      this._getValue = _getModelValue;
      this._create = _createModel;
    }
  }

  _initRootElement(className, id, options = {}) {
    var condition, definition, err, hasJoin, select, table, tableAlias, type;
    if (this._tables.hasOwnProperty(id)) {
      return;
    }
    if (!className) {
      if (!this.options.hasOwnProperty('join') || !this.options.join.hasOwnProperty(id)) {
        err = new Error(`${id} was not found in any join definitions`);
        err.code = 'TABLE_UNDEF';
        throw err;
      }
      className = this.options.join[id].entity;
      options = this.options.join[id];
    }
    definition = this.manager.getDefinition(className);
    table = definition.table;
    tableAlias = this._uniqTabAlias();
    select = this.select;
    if (options.hasOwnProperty('condition')) {
      this._tables[id] = tableAlias;
      this._infos[id] = {
        className: className
      };
      if (this._joining.hasOwnProperty(id)) {
        err = new Error(`${id} has already been joined. Look at stack to find the circular reference`);
        err.code = 'CIRCULAR_REF';
        throw err;
      }
      this._joining[id] = true;
      if (JOIN_FUNC.hasOwnProperty(options.type)) {
        hasJoin = JOIN_FUNC[options.type];
      } else if ('undefined' === typeof options.type) {
        hasJoin = JOIN_FUNC.default;
      } else if ('string' === typeof options.type) {
        type = options.type.toUpperCase();
        hasJoin = JOIN_FUNC.default;
      } else {
        err = new Error(`${id} has an invalid join type`);
        err.code = 'JOIN_TYPE';
        throw err;
      }
      // make necessary joins
      condition = _coerce.call(this, options.condition);
      select[hasJoin](this.options.escapeId(table), tableAlias, condition, type);
      // make necessary joins
      // condition = _coerce.call @, options.condition
      delete this._joining[id];
      this._infos[id].hasJoin = hasJoin;
    } else if (_.isEmpty(this._tables)) {
      select.from(this.options.escapeId(table), tableAlias);
      this._tables[id] = tableAlias;
      this._infos[id] = {
        className: className,
        hasJoin: JOIN_FUNC.default
      };
      this._rootInfo = this._infos[id];
    } else {
      err = new Error(`${id} has no joining condition`);
      err.code = 'JOIN_COND';
      throw err;
    }
  }

  _processJoins() {
    var alias, field, fields, i, join, joinDef, len;
    join = this.options.join;
    if (_.isEmpty(join)) {
      return;
    }
    for (alias in join) {
      joinDef = join[alias];
      this._initRootElement(joinDef.entity, alias, joinDef);
      fields = this._sanitizeFields(joinDef.fields);
      if (fields.length > 0) {
        this._rootInfo.properties = this._rootInfo.properties || {};
        this._rootInfo.properties[alias] = true;
        this._infos[alias].attribute = alias;
        if (!this.options.count) {
          for (i = 0, len = fields.length; i < len; i++) {
            field = fields[i];
            this._setField(this._getUniqueId(field, alias), true);
          }
        }
      }
    }
  }

  _processFields() {
    var field, fields, i, len;
    if (this.options.count) {
      this._selectCount();
      return;
    }
    fields = this._sanitizeFields(this.options.fields, ['*']);
    for (i = 0, len = fields.length; i < len; i++) {
      field = fields[i];
      this._setField(field);
    }
  }

  _processColumns() {
    var columns, field, prop;
    columns = this.options.columns;
    if (_.isEmpty(columns)) {
      return;
    }
    for (prop in columns) {
      field = columns[prop];
      this._selectCustomField(prop, field);
    }
  }

  _processBlocks() {
    var block, err, i, j, len, len1, opt, option, ref, select;
    select = this.select;
    ref = ['where', 'group', 'having', 'order', 'limit', 'offset'];
    for (i = 0, len = ref.length; i < len; i++) {
      block = ref[i];
      option = this.options[block];
      if (/^(?:string|boolean|number)$/.test(typeof option)) {
        option = [option];
      } else if (_.isEmpty(option)) {
        continue;
      }
      if (!(option instanceof Array)) {
        err = new Error(`[${this.className}]: ${block} can only be a string or an array`);
        err.code = block.toUpperCase();
        throw err;
      }
      if (block === 'limit' && option[0] < 0) {
        continue;
      }
      for (j = 0, len1 = option.length; j < len1; j++) {
        opt = option[j];
        _readFields.call(this, opt, select, block);
      }
    }
    if (this.options.distinct) {
      select.distinct();
    }
  }

  _getSetColumn(field) {
    var allAncestors, ancestors, i, id, index, info, len, parentInfo, prop;
    allAncestors = this._getAncestors(field);
    ancestors = [];
    for (index = i = 0, len = allAncestors.length; i < len; index = ++i) {
      prop = allAncestors[index];
      ancestors.push(prop);
      if (index === 0) {
        this._initRootElement(null, prop);
        continue;
      }
      id = this._getUniqueId(null, ancestors);
      this._getSetInfo(id);
      if (index === allAncestors.length - 1) {
        continue;
      }
      parentInfo = info;
      this._joinProp(id, parentInfo);
      info = this._getInfo(id);
      if (info.hasOwnProperty('properties') && !info.setted) {
        for (prop in info.properties) {
          this._setField(prop, true);
        }
        info.setted = true;
      }
    }
    return this._getColumn(id);
  }

  _sanitizeFields(fields, defaultValue) {
    var err;
    if (typeof fields === 'undefined') {
      fields = defaultValue || [];
    }
    if (typeof fields === 'string') {
      fields = [fields];
    }
    if (!(fields instanceof Array)) {
      err = new Error(`[${this.className}]: fields can only be a string or an array`);
      err.code = 'FIELDS';
      throw err;
    }
    if (fields.length === 0) {
      return [];
    }
    return fields;
  }

  // field: full field name
  _setField(field, isFull) {
    var allAncestors, ancestors, i, id, index, info, len, parentInfo, prop;
    allAncestors = this._getAncestors(field, isFull);
    ancestors = [];
    for (index = i = 0, len = allAncestors.length; i < len; index = ++i) {
      prop = allAncestors[index];
      if (index === allAncestors.length - 1) {
        this._selectProp(prop, ancestors);
        continue;
      }
      parentInfo = info;
      ancestors.push(prop);
      id = this._getUniqueId(null, ancestors);
      info = this._getSetInfo(id);
      if (parentInfo) {
        parentInfo.properties = parentInfo.properties || {};
        this._set(parentInfo.properties, id, true);
      }
      this._joinProp(id, parentInfo);
    }
  }

  _selectCount() {
    this._selectCustomField('count', {
      column: 'count(1)',
      read: function(value) {
        return parseInt(value, 10);
      }
    });
  }

  _selectCustomField(prop, field) {
    var ancestors, column, columnAlias, handlerRead, id, info, parentInfo, type;
    ancestors = [STATIC.ROOT];
    type = typeof field;
    if ('undefined' === type) {
      column = prop;
    } else if ('string' === type) {
      column = field;
    } else if (_.isPlainObject(field)) {
      column = field.column;
      handlerRead = field.read;
    }
    id = this._getUniqueId(prop, ancestors);
    info = this._getSetInfo(id, true);
    if ('function' === typeof handlerRead) {
      this._set(info, 'read', handlerRead);
    }
    if (info.hasOwnProperty('field')) {
      return;
    }
    // this property has already been selected
    columnAlias = this._uniqColAlias();
    column = _coerce.call(this, column);
    this.select.field(column, columnAlias);
    // map columnAlias to prop
    this._set(info, 'field', columnAlias);
    parentInfo = this._getInfo(this._getUniqueId(null, ancestors));
    parentInfo.properties = parentInfo.properties || {};
    // mark current prop as field of parent prop
    this._set(parentInfo.properties, id, true);
  }

  // set column alias as field of prop
  // must be called step by step
  _selectProp(prop, ancestors) {
    var column, columnAlias, id, info, isNullable, parentDef, parentId, parentInfo, parentProp, properties;
    parentId = this._getUniqueId(null, ancestors);
    parentInfo = this._getInfo(parentId);
    parentDef = this.manager.getDefinition(parentInfo.className);
    if (prop === '*') {
      if (this.options.depth < ancestors.length) {
        logger.warn('max depth reached');
        return;
      }
      this._set(parentInfo, 'selectAll', true);
      for (prop in parentDef.availableProperties) {
        this._setField(this._getUniqueId(prop, ancestors), true);
      }
      return;
    }
    id = this._getUniqueId(prop, ancestors);
    info = this._getSetInfo(id);
    if (info.hasOwnProperty('field')) {
      return;
    }
    // this property has already been selected
    column = this._getColumn(id);
    columnAlias = this._uniqColAlias();
    this.select.field(column, columnAlias); //, ignorePeriodsForFieldNameQuotes: true
    this._set(info, 'field', columnAlias);
    parentInfo = this._getInfo(this._getUniqueId(null, ancestors));
    parentInfo.properties = parentInfo.properties || {};
    this._set(parentInfo.properties, id, true);
    this._set(info, 'selectAll', parentInfo.selectAll);
    if (info.selectAll && info.hasOwnProperty('className') && !info.hasOwnProperty('selectedAll')) {
      if (parentDef.availableProperties[prop].definition.nullable === false) {
        isNullable = false;
        ancestors = ancestors.concat([prop]);
      } else {
        isNullable = true;
      }
      parentProp = prop;
      properties = this.manager.getDefinition(info.className).availableProperties;
      info.properties = {};
      for (prop in properties) {
        if (isNullable) {
          this._set(info.properties, this._getUniqueId(prop, parentProp, ancestors), true);
        } else {
          // not nullable => select all fields
          this._setField(this._getUniqueId(prop, ancestors), true);
        }
      }
      this._set(info, 'selectedAll', true);
    }
  }

  // Is called step by step .i.e. parent is supposed to be defined
  _joinProp(id, parentInfo) {
    var column, connector, err, hasJoin, idColumn, info, parentDef, prop, propDef, select, table, tableAlias;
    info = this._getInfo(id);
    if (info.hasOwnProperty('hasJoin')) {
      return;
    }
    if (!info.hasOwnProperty('className')) {
      err = new Error(`[${id}] is not a class`);
      err.code = 'FIELDS';
      throw err;
    }
    connector = this.options.connector;
    column = this._getColumn(id);
    propDef = this.manager.getDefinition(info.className);
    idColumn = this.options.escapeId(propDef.id.column);
    table = propDef.table;
    tableAlias = this._uniqTabAlias();
    select = this.select;
    if (parentInfo) {
      parentDef = this.manager.getDefinition(parentInfo.className);
      prop = info.attribute;
      if ((parentDef.availableProperties[prop].definition.nullable === false) && parentInfo.hasJoin === JOIN_FUNC.default) {
        hasJoin = JOIN_FUNC.default;
      }
    }
    if (typeof hasJoin === 'undefined') {
      hasJoin = JOIN_FUNC.left;
    }
    select[hasJoin](this.options.escapeId(table), tableAlias, this.options.escapeId(tableAlias) + '.' + idColumn + ' = ' + column);
    this._tables[id] = tableAlias;
    this._set(info, 'hasJoin', hasJoin);
  }

  // info.hasJoin = true
  _getPropAncestors(id) {
    var ancestors, prop;
    ancestors = id.split(STATIC.PROP_SEP);
    prop = ancestors.pop();
    return [prop, ancestors];
  }

  _updateInfos() {
    var ancestors, id, info, prop, ref;
    ref = this._infos;
    for (id in ref) {
      info = ref[id];
      [prop, ancestors] = this._getPropAncestors(id);
      if (ancestors.length > 0) {
        this._updateInfo(info, prop, ancestors);
      }
    }
  }

  _updateInfo(info, prop, ancestors) {
    var availableProperty, definition, parentInfo, propDef;
    if (info.asIs) {
      return;
    }
    parentInfo = this._getInfo(this._getUniqueId(null, ancestors));
    definition = this.manager.getDefinition(parentInfo.className);
    availableProperty = definition.availableProperties[prop];
    if ('undefined' === typeof availableProperty) {
      throw new Error(`Property '${prop}' is not defined for class '${parentInfo.className}'`);
    }
    propDef = availableProperty.definition;
    if (propDef.hasOwnProperty('className') && propDef !== definition.id) {
      this._set(info, 'className', propDef.className);
    }
    if (propDef.hasOwnProperty('handlers') && propDef.handlers.hasOwnProperty('read')) {
      this._set(info, 'read', propDef.handlers.read);
    }
  }

  // Is called step by step .i.e. parent is supposed to be defined
  // if _.isObject(overrides = this.options.overrides) and _.isObject(overrides = overrides[definition.className]) and _.isObject(overrides = overrides.properties) and _.isObject(overrides = overrides[prop]) and _.isObject(handlers = overrides.handlers) and 'function' is typeof handlers.read
  //     this._set info, 'read', handlers.read
  _getSetInfo(id, asIs) {
    var ancestors, info, prop;
    info = this._getInfo(id);
    if (info) {
      return info;
    }
    [prop, ancestors] = this._getPropAncestors(id);
    if (asIs) {
      return this._setInfo(id, {
        attribute: prop,
        asIs: asIs
      });
    }
    // info = _.extend {attribute: prop}, extra
    info = {
      attribute: prop
    };
    this._updateInfo(info, prop, ancestors);
    return this._setInfo(id, info);
  }

  // Get parent prop column alias, mixins join
  // Must be called step by step
  _getColumn(id) {
    var ancestors, availableProperty, className, connector, idColumn, info, joinColumn, joinFunc, mixin, mixinDef, mixinId, parentId, parentInfo, prop, propDef, select, table, tableAlias;
    info = this._getInfo(id);
    if (info.hasOwnProperty('column')) {
      return info.column;
    }
    [prop, ancestors] = this._getPropAncestors(id);
    parentId = this._getUniqueId(null, ancestors);
    availableProperty = this._getAvailableProperty(prop, ancestors, id);
    connector = this.options.connector;
    select = this.select;
    tableAlias = this._tables[parentId];
    if (availableProperty.mixin) {
      parentInfo = this._getInfo(parentId);
      if (parentInfo.hasJoin === JOIN_FUNC.left) {
        joinFunc = JOIN_FUNC.left;
      } else {
        joinFunc = JOIN_FUNC.default;
      }
    }
    // join while mixin prop
    while (mixin = availableProperty.mixin) {
      className = mixin.className;
      mixinDef = this.manager.getDefinition(className);
      mixinId = parentId + STATIC.PROP_SEP + className;
      // check if it has already been joined
      // join mixin only once even if multiple field of this mixin
      if (typeof this._mixins[mixinId] === 'undefined') {
        idColumn = this.options.escapeId(mixinDef.id.column);
        joinColumn = this.options.escapeId(tableAlias) + '.' + this.options.escapeId(mixin.column);
        table = mixinDef.table;
        tableAlias = this._uniqTabAlias();
        select[joinFunc](this.options.escapeId(table), tableAlias, this.options.escapeId(tableAlias) + '.' + idColumn + ' = ' + joinColumn);
        this._mixins[mixinId] = {
          tableAlias: tableAlias
        };
      } else {
        tableAlias = this._mixins[mixinId].tableAlias;
      }
      availableProperty = mixinDef.availableProperties[prop];
    }
    propDef = availableProperty.definition;
    this._set(info, 'column', this.options.escapeId(tableAlias) + '.' + this.options.escapeId(propDef.column));
    // info.column = this.options.escapeId(tableAlias) + '.' + this.options.escapeId(propDef.column)
    return info.column;
  }

  // Return the model initialized using row,
  initModel(row, model, tasks = []) {
    var id, info, prop;
    if (!model) {
      model = this._create();
    }
    id = this._getUniqueId();
    info = this._getInfo(id);
// init prop model with this row
    for (prop in info.properties) {
      this._initValue(prop, row, model, tasks);
    }
    return model;
  }

  // prop: full info name
  _initValue(id, row, model, tasks) {
    var childIdProp, childModel, childProp, info, prop, propClassName, value;
    info = this._getInfo(id);
    value = row[info.field];
    prop = info.attribute;
    // if value is null, no futher processing is needed
    // if Property has no sub-elements, no futher processing is needed
    if (value === null || !info.hasOwnProperty('className')) {
      this._setValue(model, prop, value, info);
      return model;
    }
    propClassName = info.className;
    childModel = this._getValue(model, prop);
    if (childModel === null || 'object' !== typeof childModel) {
      childModel = this._create(propClassName);
      this._setValue(model, prop, childModel, info);
    }
    if (info.hasOwnProperty('hasJoin')) {
// this row contains needed data
// init prop model with this row
      for (childProp in info.properties) {
        this._initValue(childProp, row, childModel, tasks);
      }
      // id is null, it means that value is null
      childIdProp = this.manager.getIdName(propClassName);
      if (null === this._getValue(childModel, childIdProp)) {
        this._setValue(model, prop, null, info);
      }
    } else {
      // a new request is needed to get properties value
      // that avoids stack overflow in case of "circular" reference with a property
      tasks.push({
        className: propClassName,
        options: {
          type: this.options.type,
          models: [childModel],
          // for nested element, value is the id
          where: STATIC.FIELD_CHAR_BEGIN + this.manager.getIdName(propClassName) + STATIC.FIELD_CHAR_END + ' = ' + value,
          // expect only one result. limit 2 is for unique checking without returning all rows
          limit: 2
        }
      });
    }
    return model;
  }

  _getUniqueId(...ancestors) {
    var ancestor, i, len, res;
    if (ancestors.length === 0) {
      return STATIC.ROOT;
    }
    res = [];
    for (i = 0, len = ancestors.length; i < len; i++) {
      ancestor = ancestors[i];
      if (typeof ancestor === 'string') {
        res.unshift(ancestor);
      } else if (ancestor instanceof Array) {
        res.unshift(ancestor.join(STATIC.PROP_SEP));
      }
    }
    return res.join(STATIC.PROP_SEP);
  }

  _uniqTabAlias() {
    var tableAlias;
    tableAlias = 'TBL_' + this._tabId++;
    // while this._tableAliases.hasOwnProperty tableAlias
    //     tableAlias = 'TBL_' + this._tabId++
    this._tableAliases[tableAlias] = true;
    return tableAlias;
  }

  _uniqColAlias() {
    var columnAlias;
    columnAlias = 'COL_' + this._colId++;
    // while this._columnAliases.hasOwnProperty columnAlias
    //     columnAlias = 'COL_' + this._colId++
    this._columnAliases[columnAlias] = true;
    return columnAlias;
  }

  // for debugging purpose
  // allow to know where a property was setted
  _set(obj, key, value) {
    return obj[key] = value;
  }

  // Return info of a property
  // id: full property name
  _getInfo(id) {
    return this._infos[id];
  }

  _setInfo(id, extra) {
    var info;
    info = this._infos[id];
    if (info) {
      _.extend(info, extra);
    } else {
      this._infos[id] = extra;
    }
    return this._infos[id];
  }

  _getAvailableProperty(prop, ancestors) {
    var definition, id, info;
    id = this._getUniqueId(null, ancestors);
    info = this._getInfo(id);
    definition = this.manager.getDefinition(info.className);
    if (prop) {
      return definition.availableProperties[prop];
    } else {
      return definition;
    }
  }

  _getAncestors(field, isFull) {
    var ancestors, err;
    if (typeof field === 'string') {
      if (isFull) {
        ancestors = field.split(STATIC.PROP_SEP);
      } else if (/^[^,]+,[^,]+$/.test(field)) {
        field = field.split(/\s*,\s*/);
        ancestors = field[1].split(STATIC.PROP_SEP);
        ancestors.unshift(field[0]);
      } else {
        ancestors = field.split(STATIC.PROP_SEP);
        ancestors.unshift(STATIC.ROOT);
      }
    } else if (!(field instanceof Array)) {
      err = new Error(`Field '${field}' is not an Array nor a string`);
      err.code = 'FIELDS';
      throw err;
    }
    return ancestors || [];
  }

  toQueryString() {
    return fieldHolderParser.replace(this.select.toString(), (field) => {
      return this._getSetColumn(field);
    });
  }

  getTemplate(force) {
    if (force !== true && this.template) {
      return this.template;
    }
    return this.template = placeHolderParser.unsafeCompile(this.toQueryString());
  }

  // this.template = placeHolderParser.safeCompile this.toQueryString()

  // replace fields by corresponding column
  toString() {
    return this.getTemplate()(this.values);
  }

};

_readFields = function(values, select, block) {
  var i, j, len, len1, ret, val, value;
  if (values instanceof Array) {
    for (i = 0, len = values.length; i < len; i++) {
      value = values[i];
      if (Array.isArray(value)) {
        for (j = 0, len1 = value.length; j < len1; j++) {
          val = value[j];
          _coerce.call(this, val);
        }
      } else {
        _coerce.call(this, value);
      }
    }
    select[block].apply(select, values);
  } else {
    ret = _coerce.call(this, values);
    select[block](values);
  }
  return ret || values;
};

_coerce = function(str) {
  if ('string' === typeof str) {
    return fieldHolderParser.replace(str, (field) => {
      return this._getSetColumn(field);
    });
  } else if (_.isObject(str) && !Array.isArray(str)) {
    return fieldHolderParser.replace(str.toString(), (field) => {
      return this._getSetColumn(field);
    });
  }
  return str;
};
