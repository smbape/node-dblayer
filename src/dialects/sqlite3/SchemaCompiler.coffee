_ = require 'lodash'
tools = require '../../tools'
SchemaCompiler = require '../../schema/SchemaCompiler'
ColumnCompiler = require './ColumnCompiler'

module.exports = class Sqlite3SchemaCompiler extends SchemaCompiler
    ColumnCompiler: ColumnCompiler
    validUpdateActions: ['no_action', 'restrict', 'cascade', 'set_null', 'set_default']

    # https://www.sqlite.org/faq.html#q11
    # How do I add or delete columns from an existing table in SQLite.
