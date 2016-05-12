_clone = (dst, src)->
    for prop of src
        dst[prop] = src[prop]
    dst

module.exports.CONSTANTS = CONSTANTS =
    MYSQL: 'mysql'
    POSTGRES: 'postgres'

_escapeConfigs = {}
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
_escapeConfigs[CONSTANTS.MYSQL].begin = _clone {}, _escapeConfigs[CONSTANTS.MYSQL].search
_escapeConfigs[CONSTANTS.MYSQL].begin.quoteStart = "'"
_escapeConfigs[CONSTANTS.MYSQL].end = _clone {}, _escapeConfigs[CONSTANTS.MYSQL].search
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
_escapeConfigs[CONSTANTS.POSTGRES].begin = _clone {}, _escapeConfigs[CONSTANTS.POSTGRES].search
_escapeConfigs[CONSTANTS.POSTGRES].begin.quoteStart = "'"
_escapeConfigs[CONSTANTS.POSTGRES].end = _clone {}, _escapeConfigs[CONSTANTS.POSTGRES].search
_escapeConfigs[CONSTANTS.POSTGRES].end.quoteEnd = "'"

module.exports._escapeConfigs = _escapeConfigs
module.exports._escape = _escape = (str, opts)->
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

# module.exports.escapeId = (str, dialect = CONSTANTS.POSTGRES)->
#     return _escape str, _escapeConfigs[dialect].id

# module.exports.escape = (str, dialect = CONSTANTS.POSTGRES)->
#     return _escape str, _escapeConfigs[dialect].literal

module.exports.exprNotEqual = (value, escapeColumn)->
    if value is null
        escapeColumn + ' IS NOT NULL'
    else
        escapeColumn + ' IS NULL OR ' + escapeColumn + ' <> ' + @escape value

module.exports.exprEqual = (value, escapeColumn)->
    if value is null
        escapeColumn + ' IS NULL'
    else
        escapeColumn + ' = ' + @escape value
