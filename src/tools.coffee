_ = require 'lodash'

exports.getExports = (name, dialect)->
    require('./dialects/' + dialect + '/' + name)

for method in ['adapter', 'sync', 'schema']
    exports[method] = exports.getExports.bind exports, method

exports.guessEscapeOpts = ->
    args = Array::slice.call(arguments)
    args.unshift {}
    options = _.defaults.apply _, args
    {connector, dialect} = options

    if 'string' isnt options.dialect and connector and 'function' is typeof connector.getDialect
        dialect = options.dialect = connector.getDialect()
    try
        adapter = exports.getAdapter(dialect)

    if connector or adapter
        for opt in ['escape', 'escapeId', 'escapeSearch', 'escapeBeginWith', 'escapeEndWith', 'exprNotEqual', 'exprEqual']
            if connector and 'function' isnt typeof options[opt] and 'function' is typeof connector[opt]
                options[opt] = connector[opt].bind connector
            else if adapter and 'function' is typeof adapter[opt]
                options[opt] = adapter[opt]
            else if 'function' is typeof exports[opt]
                options[opt] = exports[opt]

    options

exports.toUpperWords = (lowerwords)->
    words = {}
    for key, value of lowerwords
        words[key] = value.toUpperCase()
    words
