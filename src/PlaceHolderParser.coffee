module.exports = class PlaceHolderParser
    constructor: (beginStr = '__', endStr)->
        if 'string' isnt typeof beginStr or beginStr.length is 0
            throw new Error 'Invalid begin string'

        if arguments.length < 2
            endStr = beginStr
        else if arguments.length > 2
            throw new Error 'More than 2 arguments has been given'
        else if 'string' isnt typeof endStr or endStr.length is 0
            throw new Error 'Invalid end string'

        special = /([\\^$.|?*+()\[\]{}])/g
        beginStr = beginStr.replace special, '\\$1'
        endStr = endStr.replace special, '\\$1'

        reg = ['(?:(["\'`])|']

        if /^\\?\w/.test beginStr.substring 0, 2
            reg.push '\\b'
        reg.push beginStr

        reg.push '((?:(?!', endStr
        if endWithWordChar = /\w/.test endStr[endStr.length - 1]
            reg.push '\\b'

        reg.push ').)+)(', endStr, ')?'
        if endWithWordChar
            reg.push '\\b'

        reg.push ')'

        this.reg = new RegExp reg.join(''), 'g'

    parse: (str)->
        list = []
        indexes = {}
        cursor = 0

        quoting = false
        str.replace this.reg, (match, quote, key, end, start, str)->
            if quoting
                # placeholder match is ignored within a string
                if quote is quoting
                    # end of a quoted string
                    quoting = false
            else
                if quote
                    # begining of a quoted string
                    quoting = quote
                else if end
                    # placeholder found

                    # get string up to start of placeholder
                    if cursor < start
                        list[list.length] = str.substring cursor, start

                    # move cursor after match
                    cursor = start + match.length

                    # remeber placeholder position for replacement
                    indexes[key] or (indexes[key] = [])
                    indexes[key].push list.length
                    list[list.length] = match
            match

        if cursor < str.length
            list[list.length] = str.substring cursor, str.length

        [list, indexes]

    replace: (str, callback)->
        quoting = false
        str.replace this.reg, (match, quote, key, end)->
            if quoting
                # placeholder match is ignored within a string
                if quote is quoting
                    # end of a quoted string
                    quoting = false
            else
                if quote
                    # begining of a quoted string
                    quoting = quote
                else if end
                    # placeholder found
                    match = callback key
            match

    precompile: (str)->
        [list, indexes] = this.parse str
        except = []
        for key of indexes
            for index in indexes[key]
                except.push index
                list[index] = "' + (context['#{key}'] || '') + '"

        for str, index in list
            if -1 is except.indexOf index
                list[index] = str.replace /'/g, "\\'"

        """
        function template(context) {
            if (context === null || 'object' !== typeof context) {
                context = {};
            }
            return '#{list.join('')}';
        }
        """

    unsafeCompile: (str)->
        (new Function(this.precompile(str) + "return template;"))()

    safeCompile: (str)->
        [list, indexes] = this.parse str
        (context)->
            if context is null or 'object' isnt typeof context
                return list.join ''

            _list = list.slice()
            for key of indexes
                if context.hasOwnProperty key
                    for index in indexes[key]
                        _list[index] = context[key]

            _list.join ''
