factory = (require)->
    toString = ({}).toString;
    hasOwnProperty = Object::hasOwnProperty
    GenericUtil =
        
        # Based on jQuery 1.11
        isNumeric: (obj) ->
            !Array.isArray( obj ) and (obj - parseFloat( obj ) + 1) >= 0

        isObject: (obj) ->
            typeof obj is 'object' and obj isnt null

        notEmptyString: (str)->
            typeof str is 'string' and str.length > 0

    ((sql)->
        STATIC =
            MYSQL: 'mysql'
            POSTGRES: 'postgres'

        _escapeMap = {}
        _escapeMap[STATIC.MYSQL] =
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

        _escapeMap[STATIC.POSTGRES] =
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

        _escape = (str, map)->
            type = typeof str
            if type is 'number'
                return str
            if type is 'boolean'
                return if type then '1' else '0'
            if Array.isArray str
                ret = []
                for iStr in str
                    ret[ret.length] = _escape iStr, map
                return '(' + ret.join(', ') + ')'
            
            if 'string' isnt type
                # console.warn("escape - Bad string", str)
                str = '' + str
            str = str.replace map.matcher, (match, char, index, str)->
                map.replace[char]
            return map.quote + str + map.quote

        sql.escapeId = (str, dialect = STATIC.POSTGRES)->
            return _escape str, _escapeMap[dialect].id

        sql.escape = (str, dialect = STATIC.POSTGRES)->
            return _escape str, _escapeMap[dialect].literal

        return
    )(GenericUtil.sql = {})

    return GenericUtil

module.exports = factory require