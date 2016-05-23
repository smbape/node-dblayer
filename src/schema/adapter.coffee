# ==============
# From jQuery
# ==============
extend = ->
    target = arguments[0] or {}
    i = 1
    length = arguments.length
    deep = false
    # Handle a deep copy situation
    if typeof target == 'boolean'
        deep = target
        # skip the boolean and the target
        target = arguments[i] or {}
        i++
    # Handle case when target is a string or something (possible in deep copy)
    if typeof target != 'object' and !isFunction(target)
        target = {}
    while i < length
        # Only deal with non-null/undefined values
        if (options = arguments[i]) != null
            # Extend the base object
            for name of options
                `name = name`
                src = target[name]
                copy = options[name]
                # Prevent never-ending loop
                if target == copy
                    i++
                    continue
                # Recurse if we're merging plain objects or arrays
                if deep and copy and (isObject(copy) or (copyIsArray = Array.isArray(copy)))
                    if copyIsArray
                        copyIsArray = false
                        clone = if src and Array.isArray(src) then src else []
                    else
                        clone = if src and isObject(src) then src else {}
                    # Never move original objects, clone them
                    target[name] = extend(deep, clone, copy)
                    # Don't bring in undefined values
                else if copy != undefined
                    target[name] = copy
        i++
    # Return the modified object
    target

exports.CONSTANTS = CONSTANTS =
    MYSQL: 'mysql'
    POSTGRES: 'postgres'

exports._escapeConfigs = _escapeConfigs = {}
_escapeConfigs[CONSTANTS.MYSQL] =
    id:
        quote: '`'
        matcher: /([`\\\0\n\r\b])/g
        replace:
            '`': '\\`'
            '\\': '\\\\'
            '\0': '\\0'
            '\n': '\\n'
            '\r': '\\r'
            '\b': '\\b'
    literal:
        quote: "'"
        matcher: /(['\\\0\n\r\b])/g
        replace:
            "'": "\\'"
            '\\': '\\\\'
            '\0': '\\0'
            '\n': '\\n'
            '\r': '\\r'
            '\b': '\\b'
    search:
        quoteStart: "'%"
        quoteEnd: "%'"
        matcher: /(['\\\0\n\r\b])/g
        replace:
            "'": "''"
            '\0': '\\0'
            '\n': '\\n'
            '\r': '\\r'
            '\b': '\\b'
            '%': '!%'
            '_': '!_'
            '!': '!!'
_escapeConfigs[CONSTANTS.MYSQL].begin = extend {}, _escapeConfigs[CONSTANTS.MYSQL].search
_escapeConfigs[CONSTANTS.MYSQL].begin.quoteStart = "'"
_escapeConfigs[CONSTANTS.MYSQL].end = extend {}, _escapeConfigs[CONSTANTS.MYSQL].search
_escapeConfigs[CONSTANTS.MYSQL].end.quoteEnd = "'"

_escapeConfigs[CONSTANTS.POSTGRES] =
    id:
        quote: '"'
        matcher: /(["\\\0\n\r\b])/g
        replace:
            '"': '""'
            '\0': '\\0'
            '\n': '\\n'
            '\r': '\\r'
            '\b': '\\b'
    literal:
        quote: "'"
        matcher: /(['\\\0\n\r\b])/g
        replace:
            "'": "''"
            '\0': '\\0'
            '\n': '\\n'
            '\r': '\\r'
            '\b': '\\b'
    search:
        quoteStart: "'%"
        quoteEnd: "%'"
        matcher: /(['\\\0\n\r\b])/g
        replace:
            "'": "''"
            '\0': '\\0'
            '\n': '\\n'
            '\r': '\\r'
            '\b': '\\b'
            '%': '!%'
            '_': '!_'
            '!': '!!'
_escapeConfigs[CONSTANTS.POSTGRES].begin = extend {}, _escapeConfigs[CONSTANTS.POSTGRES].search
_escapeConfigs[CONSTANTS.POSTGRES].begin.quoteStart = "'"
_escapeConfigs[CONSTANTS.POSTGRES].end = extend {}, _escapeConfigs[CONSTANTS.POSTGRES].search
_escapeConfigs[CONSTANTS.POSTGRES].end.quoteEnd = "'"

exports._escape = _escape = (opts, str)->
    type = typeof str
    if type is 'number'
        return str
    if type is 'boolean'
        return if type then '1' else '0'
    if Array.isArray str
        ret = []
        for iStr in str
            ret[ret.length] = _escape opts, iStr
        return '(' + ret.join(', ') + ')'

    str = '' + str if 'string' isnt type
    str = str.replace opts.matcher, (match, char, index, str)->
        opts.replace[char]
    return (opts.quoteStart or opts.quote) + str + (opts.quoteEnd or opts.quote)

exports.exprNotEqual = (value, escapeColumn)->
    if value is null
        escapeColumn + ' IS NOT NULL'
    else
        escapeColumn + ' IS NULL OR ' + escapeColumn + ' <> ' + @escape value

exports.exprEqual = (value, escapeColumn)->
    if value is null
        escapeColumn + ' IS NULL'
    else
        escapeColumn + ' = ' + @escape value

exports.guessEscapeOpts = ()->
    args = Array::slice.call(arguments).reverse()
    args.unshift {}
    options = extend.apply @, args
    {connector, dialect} = options

    if 'string' isnt options.dialect and connector and 'function' is typeof connector.getDialect
        dialect = options.dialect = connector.getDialect()

    try
        adapter = require './' + dialect

    if connector or adapter
        for opt in ['escape', 'escapeId', 'escapeSearch', 'escapeBeginWith', 'escapeEndWith', 'exprNotEqual', 'exprEqual']
            if connector and 'function' isnt typeof options[opt] and 'function' is typeof connector[opt]
                options[opt] = connector[opt].bind connector
            else if adapter and 'function' is typeof adapter[opt]
                options[opt] = adapter[opt]
            else if 'function' is typeof exports[opt]
                options[opt] = exports[opt]

    options
