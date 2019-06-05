var ColumnCompiler, LOWERWORDS, PgColumnCompiler, _, map, tools;

_ = require('lodash');

ColumnCompiler = require('../../schema/ColumnCompiler');

tools = require('../../tools');

map = Array.prototype.map;

LOWERWORDS = {
  smallserial: 'smallserial',
  serial: 'serial',
  bigserial: 'bigserial',
  bytea: 'bytea',
  text_check: 'text check',
  add_primary_key: 'add primary key',
  rename_to: 'rename to',
  no_action: 'no action',
  set_null: 'set null',
  set_default: 'set default',
  rename_constraint: 'rename constraint',
  inherits: 'inherits',
  interval: 'interval',
  real: 'real'
};

// http://www.postgresql.org/docs/9.4/static/datatype.html
module.exports = PgColumnCompiler = class PgColumnCompiler extends ColumnCompiler {};

PgColumnCompiler.prototype.adapter = require('./adapter');

// https://www.postgresql.org/docs/9.4/static/datatype-numeric.html
PgColumnCompiler.prototype.smallincrements = function() {
  return this.words.smallserial;
};

PgColumnCompiler.prototype.increments = function() {
  return this.words.serial;
};

PgColumnCompiler.prototype.bigincrements = function() {
  return this.words.bigserial;
};

PgColumnCompiler.prototype.smallint = function() {
  return this.words.smallint;
};

PgColumnCompiler.prototype.integer = function() {
  return this.words.integer;
};

PgColumnCompiler.prototype.bigint = function() {
  return this.words.bigint;
};

PgColumnCompiler.prototype.numeric = function(precision, scale) {
  return this.words.numeric + '(' + this._num(precision, 8) + ', ' + this._num(scale, 2) + ')';
};

PgColumnCompiler.prototype.float = function() {
  return this.words.real;
};

PgColumnCompiler.prototype.double = function() {
  return this.words.double;
};

// https://www.postgresql.org/docs/9.4/static/datatype-character.html
PgColumnCompiler.prototype.char = function(length) {
  return this.words.char + '(' + this._num(length, 255) + ')';
};

PgColumnCompiler.prototype.varchar = function(length) {
  return this.words.varchar + '(' + this._num(length, 255) + ')';
};

// https://www.postgresql.org/docs/9.4/static/datatype-datetime.html
PgColumnCompiler.prototype.date = function() {
  return this.words.date;
};

PgColumnCompiler.prototype.time = function(tz, precision) {
  var type;
  if ('number' === typeof tz) {
    precision = tz;
    tz = precision === true;
  }
  if (tz) {
    type = this.words.timetz;
  } else {
    type = this.words.time;
  }
  // 6 is the default precision
  precision = this._num(precision, 6);
  return `${type}(${precision})`;
};

PgColumnCompiler.prototype.timestamp = function(tz, precision) {
  var type;
  if ('number' === typeof tz) {
    precision = tz;
    tz = precision === true;
  }
  if (tz) {
    type = this.words.timestamptz;
  } else {
    type = this.words.timestamp;
  }
  precision = this._num(precision, 6);
  return `${type}(${precision})`;
};

PgColumnCompiler.prototype.interval = function(precision) {
  var type;
  precision = this._num(precision, null);
  type = this.words.interval;
  if (precision) {
    return `${type}(${precision})`;
  }
  switch (precision) {
    case 'YEAR':
    case 'MONTH':
    case 'DAY':
    case 'HOUR':
    case 'MINUTE':
    case 'SECOND':
    case 'YEAR TO MONTH':
    case 'DAY TO HOUR':
    case 'DAY TO MINUTE':
    case 'DAY TO SECOND':
    case 'HOUR TO MINUTE':
    case 'HOUR TO SECOND':
    case 'MINUTE TO SECOND':
      return `${type}(${precision})`;
    default:
      precision = 6;
      // 6 is the default precision
      return `${type}(${precision})`;
  }
};

PgColumnCompiler.prototype.binary = PgColumnCompiler.prototype.varbinary = PgColumnCompiler.prototype.bytea = function() {
  return this.words.bytea;
};

PgColumnCompiler.prototype.bool = function() {
  return this.words.boolean;
};

PgColumnCompiler.prototype.enum = function() {
  // http://stackoverflow.com/questions/10923213/postgres-enum-data-type-or-check-constraint#10984951
  return this.words.text_check + ' (' + this.adapter.escapeId(this.args.column) + ' ' + this.words.in + ' (' + map.call(arguments, this.adapter.escape).join(',') + '))';
};

PgColumnCompiler.prototype.bit = function(length) {
  length = this._num(length, null);
  if (length && length !== 1) {
    return this.words.bit + '(' + length + ')';
  } else {
    return this.words.bit;
  }
};

PgColumnCompiler.prototype.varbit = function(length) {
  length = this._num(length, null);
  if (length) {
    return this.words.varbit + '(' + length + ')';
  } else {
    return this.words.varbit;
  }
};

PgColumnCompiler.prototype.uuid = function() {
  return this.words.uuid;
};

PgColumnCompiler.prototype.xml = function() {
  return this.words.xml;
};

PgColumnCompiler.prototype.json = function() {
  return this.words.json;
};

PgColumnCompiler.prototype.jsonb = function() {
  return this.words.jsonb;
};

PgColumnCompiler.prototype.LOWERWORDS = _.defaults(LOWERWORDS, ColumnCompiler.prototype.LOWERWORDS);

PgColumnCompiler.prototype.UPPERWORDS = _.defaults(tools.toUpperWords(LOWERWORDS), ColumnCompiler.prototype.UPPERWORDS);

PgColumnCompiler.prototype.datetime = PgColumnCompiler.prototype.timestamp;

PgColumnCompiler.prototype.aliases = function() {
  var alias, i, instance, len, method, ref;
  instance = ColumnCompiler.prototype.aliases.apply(this, arguments);
  ref = ['time', 'timestamp'];
  for (i = 0, len = ref.length; i < len; i++) {
    method = ref[i];
    alias = method + 'tz';
    if ('function' !== typeof instance[alias]) {
      instance[alias] = instance[method].bind(instance, true);
    }
  }
  return instance;
};
