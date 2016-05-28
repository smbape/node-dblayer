_escape = exports._escape = (opts, str)->
    switch typeof str
        when 'number'
            return str
        when 'boolean'
            str = if str then '1' else '0'
            return (opts.quoteStart or opts.quote) + str + (opts.quoteEnd or opts.quote)
        when 'string'
            # do nothing
        else
            if Array.isArray str
                ret = new Array(str.length)
                for iStr, i in str
                    ret[i] = _escape opts, iStr
                return '(' + ret.join(', ') + ')'
            str = '' + str

    str = str.replace opts.matcher, (match, _char)-> opts.replace[_char]
    return (opts.quoteStart or opts.quote) + str + (opts.quoteEnd or opts.quote)

exports.exprNotEqual = (value, columnId)->
    if value is null
        columnId + ' IS NOT NULL'
    else
        columnId + ' IS NULL OR ' + columnId + ' <> ' + @escape(value)

exports.exprEqual = (value, columnId)->
    if value is null
        columnId + ' IS NULL'
    else
        columnId + ' = ' + @escape(value)
