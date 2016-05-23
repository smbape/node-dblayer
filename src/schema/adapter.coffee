_escape = exports._escape = (opts, str)->
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
