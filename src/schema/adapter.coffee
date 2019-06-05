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
        columnId + ' IS NULL OR ' + columnId + ' <> ' + this.escape(value)

exports.exprEqual = (value, columnId)->
    if value is null
        columnId + ' IS NULL'
    else
        columnId + ' = ' + this.escape(value)

eatLineComment = (chunck, len, pos, LF)->
    while pos < len and chunck[pos] isnt LF
        pos++

    [pos, chunck[pos] is LF]

eatBlockComment = (chunck, len, pos)->
    while pos < len and ('*' isnt chunck[pos] or '/' isnt chunck[pos + 1])
        pos++

    if done = ('*' is chunck[pos] and '/' is chunck[pos + 1])
        pos += 2

    [pos, done]

eatString = (chunck, len, pos, quote)->
    while pos < len and (chunck[pos] isnt quote or chunck[pos + 1] is quote)
        pos++

    if done = (chunck[pos] is quote and chunck[pos + 1] isnt quote)
        pos++

    [pos, done]

stack = []
states = []
quote = null

consumeChunck = (chunck, state, callback)->
    len = chunck.length
    lastPos = 0
    {pos, level, current, states} = state

    while not error and pos < len
        currChar = chunck[pos]
        switch current
            when 'initial'
                switch currChar
                    when '"', "'", '`'
                        # console.log 'quote'
                        quote = currChar
                        states.push current
                        current = 'quoting'
                        ++pos
                    when ';'
                        # console.log 'semi colon'
                        if level is 0 and lastPos < pos
                            while /\s/.test(chunck[lastPos])
                                lastPos++

                            query = chunck.substring(lastPos, pos)
                            if not /^\s*$/.test(query)
                                error = callback query
                            lastPos = pos + 1
                        ++pos
                    when '('
                        # console.log 'open'
                        level++
                        ++pos
                    when ')'
                        # console.log 'close'
                        level--
                        ++pos
                    else
                        ++pos

            when 'quoting'
                # console.log 'quoting'
                [pos, done] = eatString chunck, len, pos, quote
                if done
                    current = 'quoting-end'

            when 'quoting-end'
                # console.log 'quoting-end'
                if currChar is quote
                    current = 'quoting'
                    ++pos
                else
                    # go back to previous state
                    current = states.pop()
                    quote = null

    if lastPos < pos
        remaining = chunck.substring(lastPos, pos)

    state.pos = pos
    state.level = level
    state.current = current
    state.error = error

    return remaining

exports.split = (str, callback, done)->
    state =
        pos: 0
        level: 0
        current: 'initial'
        states: []

    switch typeof str
        when 'string'
            remaining = consumeChunck str, state, callback
            if not state.error and remaining and !/^\s*;?\s*$/.test(remaining)
                lastPos = 0
                while /\s/.test(chunck[lastPos])
                    lastPos++
                callback remaining.substring(lastPos)

            done(state.error)
            return

        when 'object'
            if str is null
                done()
                return

            remainging = null

            onData = (chunck)->
                if remaining
                    chunck = remainging + chunck.toString('utf8')
                    pos = remainging.length
                else
                    chunck = chunck.toString('utf8')
                    pos = 0
                state.pos = pos
                remaining = consumeChunck chunck, state, callback
                if state.error
                    str.removeListener 'data', onData
                    str.end()
                return

            str.on 'data', onData

            str.on 'end', (chunck)->
                if not state.error and remaining and !/^\s*;?\s*$/.test(remaining)
                    lastPos = 0
                    while /\s/.test(chunck[lastPos])
                        lastPos++
                    callback remaining.substring(lastPos)

                done(state.error)
                return
        else
            done()

    return
