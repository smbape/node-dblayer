factory = (require)->
    hasOwnProperty = Object::hasOwnProperty
    GenericUtil =
        isNumeric: (obj) ->
            not isNaN(parseFloat(obj)) and isFinite obj

        isWindow: (obj) ->
            # jshint eqnull: true, eqeqeq: false 
            obj? and obj is obj.window

        isObject: (obj) ->
            typeof obj is "object" and obj isnt null

        notEmptyString: (str)->
            typeof str is 'string' and str.length > 0

    GenericUtil.StringUtil =
        capitalize: (str) ->
            str.charAt(0).toUpperCase() + str.slice(1).toLowerCase()

        firstUpper: (str) ->
            str.charAt(0).toUpperCase() + str.slice 1

        toCamelDash: (str) ->
            str.replace /\-([a-z])/g, (match) ->
                match[1].toUpperCase()

        toCapitalCamelDash: (str) ->
            GenericUtil.StringUtil.toCamelDash GenericUtil.StringUtil.capitalize str

        toCamelSpaceDash: (str) ->
            str.replace /\-([a-z])/g, (match) ->
                " " + match[1].toUpperCase()

        toCapitalCamelSpaceDash: (str) ->
            GenericUtil.StringUtil.toCamelSpaceDash GenericUtil.StringUtil.capitalize str

        firstSubstring: (str, n) ->
            return str if typeof str isnt "string"
            return "" if n >= str.length
            str.substring 0, str.length - n

        lastSubstring: (str, n) ->
            return str if typeof str isnt "string"
            return str if n >= str.length
            str.substring str.length - n, str.length

    ((StringUtil)->
        _entityMap =
            "&": "&amp;"
            "<": "&lt;"
            ">": "&gt;"
            '"': '&quot;'
            "'": '&#39;'
            "/": '&#x2F;'
        
        StringUtil.escape = (html) ->
            if typeof html is 'string'
                html.replace /[&<>"'\/]/g, (s) ->
                    _entityMap[s]
            else
                html
        return
    )(GenericUtil.StringUtil)

    GenericUtil.ArrayUtil =
        clone: (arr) ->
            Array::slice.call arr, 0

        backIndex: (arr, n) ->
            arr[arr.length - 1 - n]

        flip: (arr) ->
            key = undefined
            tmp_ar = undefined
            tmp_ar = {}
            for key of arr
                tmp_ar[arr[key]] = key if arr.hasOwnProperty key
            tmp_ar

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
            if /^(?:numeric|boolean)$/.test typeof str
                return ('' + str).toUpperCase()
            else if str instanceof Array
                ret = []
                for iStr in str
                    ret[ret.length] = _escape iStr, map
                return '(' + ret.join(', ') + ')'
            else if 'string' isnt typeof str
                # console.warn("escape - Bad string", str)
                str = '' + str
            str = str.replace map.matcher, (match, char, index, str)->
                map.replace[char]
            return map.quote + str + map.quote

        sql.escapeId = (str, dialect = 'postgres')->
            return _escape str, _escapeMap[dialect].id

        sql.escape = (str, dialect = 'postgres')->
            return _escape str, _escapeMap[dialect].literal

        return
    )(GenericUtil.sql = {})
    
    return GenericUtil

module.exports = factory require