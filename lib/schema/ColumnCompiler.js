var ColumnCompiler, LOWERWORDS, _, tools;

_ = require('lodash');

tools = require('../tools');

module.exports = ColumnCompiler = (function() {
  class ColumnCompiler {
    constructor(options) {
      var i, len, method, ref;
      options = this.options = _.clone(options);
      this.args = {};
      if (!!options.lower) {
        this.words = this.LOWERWORDS;
      } else {
        this.words = this.UPPERWORDS;
      }
      ref = ['escape', 'escapeId', 'escapeSearch', 'escapeBeginWith', 'escapeEndWith'];
      for (i = 0, len = ref.length; i < len; i++) {
        method = ref[i];
        if ('function' === typeof this.adapter[method]) {
          this[method] = this.adapter[method].bind(this.adapter);
        }
      }
      this.aliases();
    }

  };

  ColumnCompiler.prototype.adapter = require('./adapter');

  return ColumnCompiler;

}).call(this);

LOWERWORDS = ColumnCompiler.prototype.LOWERWORDS = {
  add: 'add',
  add_column: 'add column',
  add_constraint: 'add constraint',
  alter: 'alter',
  alter_column: 'alter column',
  alter_index: 'alter index',
  alter_table: 'alter table',
  cascade: 'cascade',
  check: 'check',
  column: 'column',
  constraint: 'constraint',
  create: 'create',
  create_index: 'create index',
  create_table: 'create table',
  create_unique_index: 'create unique index',
  default: 'default',
  drop: 'drop',
  drop_column: 'drop column',
  drop_constraint: 'drop constraint',
  drop_index: 'drop index',
  drop_table: 'drop table',
  enum: 'enum',
  foreign_key: 'foreign key',
  if_exists: 'if exists',
  if_not_exists: 'if not exists',
  in: 'in',
  index: 'index',
  not: 'not',
  not_null: 'not null',
  null: 'null',
  on: 'on',
  on_delete: 'on delete',
  on_update: 'on update',
  primary_key: 'primary key',
  references: 'references',
  restrict: 'restrict',
  set: 'set',
  set_default: 'set default',
  table: 'table',
  to: 'to',
  type: 'type',
  unique: 'unique'
};

// ================================================================
// Numeric Types
// ================================================================
// ColumnCompiler::smallincrements = -> throw new Error 'smallincrements type is not defined'
// ColumnCompiler::increments = -> throw new Error 'increments type is not defined'
// ColumnCompiler::bigincrements = -> throw new Error 'bigincrements type is not defined'
_.extend(LOWERWORDS, {
  tinyint: 'tinyint',
  smallint: 'smallint',
  integer: 'integer',
  bigint: 'bigint'
});

ColumnCompiler.prototype.tinyint = ColumnCompiler.prototype.smallint = function() {
  return this.words.smallint;
};

// ColumnCompiler::integer = -> this.words.integer
// ColumnCompiler::bigint = -> this.words.bigint
_.extend(LOWERWORDS, {
  decimal: 'decimal',
  numeric: 'numeric',
  float: 'float',
  double: 'double precision',
  real: 'real'
});

// ColumnCompiler::decimal =
// ColumnCompiler::numeric = (precision, scale) ->
//     this.words.numeric + '(' + this._num(precision, 8) + ', ' + this._num(scale, 2) + ')'

// ColumnCompiler::float = (precision, scale) ->
//     this.words.float + '(' + this._num(precision, 8) + ', ' + this._num(scale, 2) + ')'

// ColumnCompiler::double = -> this.words.double

// ================================================================
// Character Types
// ================================================================
_.extend(LOWERWORDS, {
  char: 'char',
  varchar: 'varchar',
  tinytext: 'tinytext',
  mediumtext: 'mediumtext',
  text: 'text'
});

// ColumnCompiler::char = (length)->
//     this.words.char + '(' + this._num(length, 255) + ')'

// ColumnCompiler::varchar = (length)->
//     this.words.varchar + '(' + this._num(length, 255) + ')'
ColumnCompiler.prototype.tinytext = ColumnCompiler.prototype.mediumtext = ColumnCompiler.prototype.text = function() {
  return this.words.text;
};

// ================================================================
// Date/Time Types
// ================================================================
_.extend(LOWERWORDS, {
  date: 'date',
  datetime: 'datetime',
  time: 'time',
  timestamp: 'timestamp',
  timetz: 'timetz',
  timestamptz: 'timestamptz'
});

// ColumnCompiler::date = -> this.words.date
// ColumnCompiler::datetime = -> this.words.datetime
// ColumnCompiler::time = -> this.words.time
// ColumnCompiler::timestamp = -> this.words.timestamp

// ================================================================
// Other Types
// ================================================================
_.extend(LOWERWORDS, {
  bool: 'bool',
  boolean: 'boolean',
  enum: 'enum'
});

// ColumnCompiler::bool = -> this.words.boolean
// ColumnCompiler::enum = -> throw new Error 'enum type is not defined'
_.extend(LOWERWORDS, {
  binary: 'binary',
  bit: 'bit',
  varbinary: 'varbinary',
  varbit: 'varbit'
});

// ColumnCompiler::binary =
// ColumnCompiler::bit = (length)->
//     length = this._num(length, null)
//     if length then this.words.bit + '(' + length + ')' else this.words.bit
ColumnCompiler.prototype.varbinary = ColumnCompiler.prototype.varbit = function(length) {
  length = this._num(length, null);
  if (length) {
    return this.words.bit + '(' + length + ')';
  } else {
    return this.words.bit;
  }
};

_.extend(LOWERWORDS, {
  xml: 'xml',
  json: 'json',
  jsonb: 'jsonb',
  uuid: 'uuid'
});

ColumnCompiler.prototype.xml = ColumnCompiler.prototype.json = ColumnCompiler.prototype.jsonb = function() {
  return this.words.text;
};

ColumnCompiler.prototype.uuid = function() {
  return this.words.char + '(63)';
};

ColumnCompiler.prototype._num = function(val, fallback) {
  var number;
  if (val === void 0 || val === null) {
    return fallback;
  }
  number = parseInt(val, 10);
  if (isNaN(number)) {
    return fallback;
  } else {
    return number;
  }
};

ColumnCompiler.prototype.ALIASES = {
  smallincrements: ['serial2', 'smallserial'],
  increments: ['serial', 'serial4'],
  bigincrements: ['serial8', 'bigserial'],
  bigint: ['biginteger', 'int8'],
  bool: ['boolean'],
  double: ['float8'],
  integer: ['int', 'int4', 'mediumint'],
  decimal: ['numeric'],
  float: ['real', 'float4'],
  mediumint: ['mediuminteger'],
  numeric: ['decimal'],
  smallint: ['int2', 'smallinteger']
};

ColumnCompiler.prototype.aliases = function() {
  var alias, aliases, i, instance, len, ref, type;
  instance = this;
  ref = this.ALIASES;
  for (type in ref) {
    aliases = ref[type];
    for (i = 0, len = aliases.length; i < len; i++) {
      alias = aliases[i];
      if ('function' !== typeof instance[alias]) {
        instance[alias] = instance[type];
      }
    }
  }
  return instance;
};

ColumnCompiler.prototype.pkString = function(pkName, columns) {
  return this.adapter.escapeId(pkName) + ' ' + this.words.primary_key + ' (' + columns.map(this.adapter.escapeId).join(', ') + ')';
};

ColumnCompiler.prototype.ukString = function(ukName, columns) {
  return this.adapter.escapeId(ukName) + ' ' + this.words.unique + ' (' + columns.map(this.adapter.escapeId).join(', ') + ')';
};

ColumnCompiler.prototype.indexString = function(indexName, columns, tableNameId) {
  return this.adapter.escapeId(indexName) + ' ' + this.words.on + ' ' + tableNameId + '(' + columns.map(this.adapter.escapeId).join(', ') + ')';
};

ColumnCompiler.prototype.getTypeString = function(spec) {
  var err, type, type_args;
  type = spec.type.toLowerCase();
  type_args = Array.isArray(spec.type_args) ? spec.type_args : [];
  if ('function' === typeof this[type]) {
    type = this[type].apply(this, type_args);
  } else {
    err = new Error(`Unknown type '${type}'`);
    err.code = 'UNKNOWN_TYPE';
    throw err;
  }
  // type_args.unshift type
  // type = type_args.join(' ')
  return type;
};

ColumnCompiler.prototype.getColumnModifier = function(spec) {
  if (spec.defaultValue !== void 0 && spec.defaultValue !== null) {
    return this.words.default + ' ' + spec.defaultValue;
  } else if (spec.nullable === false) {
    return this.words.not_null;
  } else {
    return this.words.null;
  }
};

ColumnCompiler.prototype.UPPERWORDS = tools.toUpperWords(ColumnCompiler.prototype.LOWERWORDS);
