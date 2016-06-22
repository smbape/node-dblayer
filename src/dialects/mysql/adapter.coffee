_ = require 'lodash'
common = require '../../schema/adapter'
adapter = _.extend module.exports, common
logger = log4js.getLogger __filename.replace /^(?:.+[\/\\])?([^.\/\\]+)(?:.[^.]+)?$/, '$1'

escapeOpts =
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
escapeOpts.begin = _.clone escapeOpts.search
escapeOpts.begin.quoteStart = "'"
escapeOpts.end = _.clone escapeOpts.search
escapeOpts.end.quoteEnd = "'"

adapter.escape = common._escape.bind common, escapeOpts.literal
adapter.escapeId = common._escape.bind common, escapeOpts.id
adapter.escapeSearch = common._escape.bind common, escapeOpts.search
adapter.escapeBeginWith = common._escape.bind common, escapeOpts.begin
adapter.escapeEndWith = common._escape.bind common, escapeOpts.end

mysql = require 'mysql'
MySQLLibConnection = require 'mysql/lib/Connection'
ConnectionConfig = require 'mysql/lib/ConnectionConfig'
prependListener = require 'prepend-listener'
once = require 'once'
path = require 'path'
HWM = Math.pow 2, 7

class MySQLConnection extends MySQLLibConnection
    adapter: adapter
    constructor: (options)->
        @options = _.clone options
        super config: new ConnectionConfig options

    query: (query, params, callback)->
        stream = @_createQuery query, params, callback
        super stream.query
        stream

    stream: (query, params, callback, done)->
        if arguments.length is 3
            done = callback
            callback = params
            params = []
        params = [] if not (params instanceof Array)
        done = (->) if typeof done isnt 'function'

        stream = MySQLLibConnection::query.call(@, query, params).stream highWaterMark: HWM
        hasError = false
        result = rowCount: 0
        stream.once 'error', (err)->
            hasError = err
            done err
            return
        stream.on 'fields', (fields) ->
            result.fields = fields
            return
        stream.on 'data', (row)->
            if row.constructor.name is 'OkPacket'
                result.fieldCount = row.fieldCount
                result.affectedRows = row.affectedRows
                result.changedRows = row.changedRows
                result.lastInsertId = row.insertId
            else
                ++result.rowCount
                callback row
            return
        stream.once 'end', ->
            done undefined, result unless hasError
            return
        stream

    _createQuery: (text, values, callback)->
        if typeof callback is 'undefined' and typeof values is 'function'
            callback = values
            values = undefined

        values = values or []
        query = mysql.createQuery text, values

        stream = query.stream highWaterMark: HWM
        emitClose = once stream.emit.bind stream, 'close'
        prependListener query, 'end', emitClose

        stream.query = query
        stream.text = text
        stream.values = values
        stream.callback = callback

        if typeof callback is 'function'
            result =
                rows: []
                rowCount: 0
                lastInsertId: 0
                fields: null
                fieldCount: 0

            hasError = false
            stream.on 'error', (err)->
                emitClose()
                hasError = true
                @callback err
                return
            stream.on 'fields', (fields) ->
                result.fields = fields
                return
            stream.on 'data', (row) ->
                if row.constructor.name is 'OkPacket'
                    result.fieldCount = row.fieldCount
                    result.affectedRows = row.affectedRows
                    result.changedRows = row.changedRows
                    result.lastInsertId = row.insertId
                else
                    ++result.rowCount
                    result.rows.push(row)
                return
            stream.on 'end', ->
                @callback null, result unless hasError
                return

        stream.once 'end', ->
            delete @query
            return

        stream

_.extend adapter,
    name: 'mysql'

    squelOptions:
        nameQuoteCharacter: '`'
        fieldAliasQuoteCharacter: '`'
        tableAliasQuoteCharacter: '`'

    insertDefaultValue: (insert, column)->
        _toString = insert.toString
        insert.toString = ->
            _toString.call(insert) + ' VALUES()'
        # insert.set @escapeId(column), '', {dontQuote: true}
        return insert

    createConnection: (options, callback)->
        callback = (->) if typeof callback isnt 'function'
        client = new MySQLConnection options
        client.connect (err)->
            return callback(err) if err
            callback err, client

fs = require 'fs'
sysPath = require 'path'
anyspawn = require 'anyspawn'
{getTemp} = require '../../tools'
umask = if process.platform is 'win32' then {encoding: 'utf-8', mode: 700} else {encoding: 'utf-8', mode: 600}

adapter.exec = adapter.execute = (script, options, done)->
    if _.isPlainObject(script)
        _script = options
        options = script
        script = _script

    if 'function' is typeof options
        done = options
        options = {}

    if not _.isPlainObject(options)
        options = {}

    {
        user
        password
        database
        cmd
        host
        port
        stdout
        stderr
        tmp
        keep
        force
    } = options

    cmd or (cmd = 'mysql')
    stdout or (stdout isnt null and stdout = process.stdout)
    stderr or (stderr isnt null and stderr = process.stderr)
    tmp = getTemp(tmp, options.keep isnt true)

    if database
        script = "USE `#{database}`;\n#{script}"
    file = sysPath.join(tmp, 'script.sql')
    fs.writeFileSync file, "#{script}", umask

    if user and password?.length > 0
        my = sysPath.join tmp, 'my.conf'
        fs.writeFileSync my, "[client]\npassword=#{password}\n", umask
        args = ["--defaults-extra-file=#{my}"]
    else
        pipe = true
        args = ['-p']

    if user
        args.push '-u'
        args.push user

    if host
        args.push '-h'
        args.push host

    if port
        args.push '-P'
        args.push port

    if force
        args.push '-f'

    # args.push '-e'
    # args.push "source #{anyspawn.quoteArg(file)}"

    # console.log args.join(' ')

    opts = _.defaults
        stdio: ['pipe', stdout, stderr]
        env: process.env
    , options

    child = anyspawn.exec cmd, args, opts, done
    readable = fs.createReadStream(file)
    readable.pipe child.stdin

    if pipe
        process.stdin.pipe(child.stdin)

    return
