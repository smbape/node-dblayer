var ColumnCompiler, LOWERWORDS, Sqlite3ColumnCompiler, _, map, tools;

_ = require('lodash');

ColumnCompiler = require('../../schema/ColumnCompiler');

tools = require('../../tools');

map = Array.prototype.map;

LOWERWORDS = {};

// https://www.sqlite.org/datatype3.html
module.exports = Sqlite3ColumnCompiler = class Sqlite3ColumnCompiler extends ColumnCompiler {};

Sqlite3ColumnCompiler.prototype.adapter = require('./adapter');

// https://www.sqlite.org/lang_createtable.html
LOWERWORDS.autoincrement = 'autoincrement';

Sqlite3ColumnCompiler.prototype.smallincrements = Sqlite3ColumnCompiler.prototype.mediumincrements = Sqlite3ColumnCompiler.prototype.bigincrements = Sqlite3ColumnCompiler.prototype.increments = function() {
  return [this.words.integer, this.words.primary_key, this.words.autoincrement].join(' ');
};

Sqlite3ColumnCompiler.prototype.tinyint = Sqlite3ColumnCompiler.prototype.smallint = Sqlite3ColumnCompiler.prototype.mediumint = Sqlite3ColumnCompiler.prototype.bigint = Sqlite3ColumnCompiler.prototype.int2 = Sqlite3ColumnCompiler.prototype.int8 = Sqlite3ColumnCompiler.prototype.integer = function() {
  return this.words.integer;
};

LOWERWORDS.character = 'character';

Sqlite3ColumnCompiler.prototype.char = function(m) {
  return this.words.character + '(' + this._num(m, 255) + ')';
};

Sqlite3ColumnCompiler.prototype.varchar = function(m) {
  return this.words.varchar + '(' + this._num(m, 255) + ')';
};

Sqlite3ColumnCompiler.prototype.text = function() {
  return this.words.text;
};

LOWERWORDS.blob = 'blob';

Sqlite3ColumnCompiler.prototype.blob = this.words.blob;

LOWERWORDS.real = 'real';

Sqlite3ColumnCompiler.prototype.real = function() {
  return this.words.real;
};

Sqlite3ColumnCompiler.prototype.double = function() {
  return this.words.double;
};

Sqlite3ColumnCompiler.prototype.float = function() {
  return this.words.float;
};

Sqlite3ColumnCompiler.prototype.numeric = Sqlite3ColumnCompiler.prototype.decimal = function(precision, scale) { // -> this.words.numeric
  return this.words.decimal + '(' + this._num(precision, 8) + ', ' + this._num(scale, 2) + ')';
};

Sqlite3ColumnCompiler.prototype.bool = function() {
  return this.words.boolean;
};

Sqlite3ColumnCompiler.prototype.date = function() {
  return this.words.date;
};

Sqlite3ColumnCompiler.prototype.datetime = function() {
  return this.words.date;
};

PgColumnCompiler.prototype.enum = function() {
  // http://stackoverflow.com/questions/10923213/postgres-enum-data-type-or-check-constraint#10984951
  return this.words.text_check + ' (' + this.adapter.escapeId(this.args.column) + ' ' + this.words.in + ' (' + map.call(arguments, this.adapter.escape).join(',') + '))';
};

Sqlite3ColumnCompiler.prototype.LOWERWORDS = _.defaults(LOWERWORDS, ColumnCompiler.prototype.LOWERWORDS);

Sqlite3ColumnCompiler.prototype.UPPERWORDS = _.defaults(tools.toUpperWords(LOWERWORDS), ColumnCompiler.prototype.UPPERWORDS);

Sqlite3ColumnCompiler.prototype.getColumnModifier = function(spec) {
  if (/^(?:(small|big)?(?:increments|serial)|serial([248]))$/.test(spec.type)) {
    return '';
  }
  return ColumnCompiler.prototype.getColumnModifier.call(this, spec);
};
