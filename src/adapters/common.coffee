_extend = (dst, src)->
    for prop of src
        dst[prop] = src[prop]
    dst

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
_escapeConfigs[CONSTANTS.MYSQL].begin = _extend {}, _escapeConfigs[CONSTANTS.MYSQL].search
_escapeConfigs[CONSTANTS.MYSQL].begin.quoteStart = "'"
_escapeConfigs[CONSTANTS.MYSQL].end = _extend {}, _escapeConfigs[CONSTANTS.MYSQL].search
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
_escapeConfigs[CONSTANTS.POSTGRES].begin = _extend {}, _escapeConfigs[CONSTANTS.POSTGRES].search
_escapeConfigs[CONSTANTS.POSTGRES].begin.quoteStart = "'"
_escapeConfigs[CONSTANTS.POSTGRES].end = _extend {}, _escapeConfigs[CONSTANTS.POSTGRES].search
_escapeConfigs[CONSTANTS.POSTGRES].end.quoteEnd = "'"

exports._escape = _escape = (str, opts)->
    type = typeof str
    if type is 'number'
        return str
    if type is 'boolean'
        return if type then '1' else '0'
    if Array.isArray str
        ret = []
        for iStr in str
            ret[ret.length] = _escape iStr, opts
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

exports.guessEscapeOpts = (options)->
    options = _extend {}, options
    {connector, dialect} = options

    if 'string' isnt options.dialect and connector and 'function' is typeof connector.getDialect
        dialect = options.dialect = connector.getDialect()

    try
        adapter = require './' + dialect

    if connector or adapter
        for opt in ['escape', 'escapeId', 'escapeSearch', 'escapeBeginWith', 'escapeEndWith']
            if connector and 'function' isnt typeof options[opt] and 'function' is typeof connector[opt]
                options[opt] = connector[opt].bind connector
            else if adapter and 'function' is typeof adapter[opt]
                options[opt] = adapter[opt]
    options
