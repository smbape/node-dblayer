var ColumnCompiler, SchemaCompiler, Sqlite3SchemaCompiler, _, tools;

_ = require('lodash');

tools = require('../../tools');

SchemaCompiler = require('../../schema/SchemaCompiler');

ColumnCompiler = require('./ColumnCompiler');

module.exports = Sqlite3SchemaCompiler = (function() {
  class Sqlite3SchemaCompiler extends SchemaCompiler {};

  Sqlite3SchemaCompiler.prototype.ColumnCompiler = ColumnCompiler;

  Sqlite3SchemaCompiler.prototype.validUpdateActions = ['no_action', 'restrict', 'cascade', 'set_null', 'set_default'];

  return Sqlite3SchemaCompiler;

}).call(this);

// https://www.sqlite.org/faq.html#q11
// How do I add or delete columns from an existing table in SQLite.
