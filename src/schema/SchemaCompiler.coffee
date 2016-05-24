_ = require 'lodash'

module.exports = class SchemaCompiler
	constructor: (options = {})->
        @columnCompiler = new @ColumnCompiler options

        @indent = options.indent or '    '
        @LF = options.LF or '\n'

        for prop in ['adapter', 'args', 'words']
            @[prop] = @columnCompiler[prop]

        for method in ['escape', 'escapeId', 'escapeSearch', 'escapeBeginWith', 'escapeEndWith']
            if 'function' is typeof @adapter[method]
                @[method] = @adapter[method].bind @adapter

        @options = _.clone options
