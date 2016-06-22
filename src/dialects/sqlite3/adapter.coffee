path = require 'path'
_ = require 'lodash'
sqlite3 = require 'sqlite3'
EventEmitter = require('events').EventEmitter
log4js = global.log4js or (global.log4js = require 'log4js')
logger = log4js.getLogger __filename.replace /^(?:.+[\/\\])?([^.\/\\]+)(?:.[^.]+)?$/, '$1'

MODES =
    READ: [Math.pow(2, 0), sqlite3.OPEN_READONLY]
    WRITE: [Math.pow(2, 1), sqlite3.OPEN_READWRITE]
    CREATE: [Math.pow(2, 2), sqlite3.OPEN_CREATE]

adapter = exports

common = require '../../schema/adapter'
_.extend adapter, common,
    name: 'sqlite3'

    createConnection: (options, callback)->
        database = options.database or ''
        if options.host
            filename = path.join options.host, database
        else
            filename = database

        if options.workdir
            filename = path.join options.workdir, filename

        if not filename or filename is '/:memory'
            filename = ':memory:'

        if not isNaN options.mode
            mode = 0
            opt_mode = parseInt options.mode, 10
            for name of MODES
                value = MODES[name]
                if value[0] is (value[0] & opt_mode)
                    mode |= value[1]

        if not mode
            mode = sqlite3.OPEN_READWRITE | sqlite3.OPEN_CREATE

        new SQLite3Connection filename, mode, (err, client)->
            return callback(err) if err
            # https://www.sqlite.org/faq.html#q22
            # Does SQLite support foreign keys?
            # As of version 3.6.19, SQLite supports foreign key constraints.
            # But enforcement of foreign key constraints is turned off by default (for backwards compatibility).
            # To enable foreign key constraint enforcement, run PRAGMA foreign_keys=ON or compile with -DSQLITE_DEFAULT_FOREIGN_KEYS=1.
            client.query 'PRAGMA foreign_keys = ON', (err)->
                return callback(err) if err
                callback err, client
                return
            return

    squelOptions:
        replaceSingleQuotes: true
        nameQuoteCharacter: '"'
        fieldAliasQuoteCharacter: '"'
        tableAliasQuoteCharacter: '"'

escapeOpts =
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
escapeOpts.begin = _.clone escapeOpts.search
escapeOpts.begin.quoteStart = "'"
escapeOpts.end = _.clone escapeOpts.search
escapeOpts.end.quoteEnd = "'"

adapter.escape = common._escape.bind common, escapeOpts.literal
adapter.escapeId = common._escape.bind common, escapeOpts.id
adapter.escapeSearch = common._escape.bind common, escapeOpts.search
adapter.escapeBeginWith = common._escape.bind common, escapeOpts.begin
adapter.escapeEndWith = common._escape.bind common, escapeOpts.end

class SQLite3Connection extends EventEmitter
    adapter: adapter
    constructor: (filename, mode, callback)->
        super()

        # mkdirp do not throw on invalid path
        # mkdirp = require 'mkdirp'
        # mkdirp.sync path.dirname filename

        logger.debug 'SQLite3Connection', filename
        @db = new sqlite3.Database filename, mode

        # always perform series write
        # parallel read write may lead to errors if not well controlled
        @db.serialize()

        @db.on 'error', (err)=>
            @emit 'error', err
            return

        @db.once 'error', callback

        @db.once 'open', =>
            @db.removeListener 'error', callback
            callback null, @
            return
        @db.on 'close', =>
            @emit 'end'
            return

        return

    query: ->
        query = new SQLite3Query arguments
        query.execute @db
        query

    stream: ->
        stream = new SQLite3Stream arguments
        stream.execute @db
        stream

    end:->
        logger.debug 'close connection'
        @db.close()
        return

class SQLite3Query extends EventEmitter
    constructor: (args)->
        @init.apply @, args

    init: (@text, values, callback)->
        if Array.isArray values
            @values = values
        else
            @values = []
            if arguments.length is 2 and 'function' is typeof values
                callback = values

        @callback = if 'function' is typeof callback then callback else ->
        return

    execute: (db)->
        query = @text
        values = @values
        callback = @callback

        # Quick falsy test to determine if insert|update|delete or else
        # falsy because (insert toto ...) will not be recognise as insert because of bracket
        # Real parser needed, but may be heavy for marginal cases
        # https://github.com/mapbox/node-sqlite3/wiki/API#databaserunsql-param--callback
        if query.match /^\s*insert\s+/i
            db.run query, values, (err)->
                return callback(err) if err
                callback err, lastInsertId: @lastID
                return
            return

        if query.match /^\s*(?:update|delete)\s+/i
            db.run query, values, (err)->
                return callback(err) if err
                callback err, {changedRows: @changes, affectedRows: @changes}
                return
            return

        result = rows: []
        hasError = false

        db.each query, values, (err, row)->
            if err
                if not hasError
                    hasError = true
                    callback err

                return
            result.rows.push row
            return
        , (err, rowCount)->
            return if hasError
            return callback(err) if err
            result.rowCount = rowCount
            if rowCount > 0
                result.fields = Object.keys(result.rows[0]).map (name)-> name: name
            else
                result.fields = []
            callback err, result
            return
        return

ArrayStream = require 'duplex-arraystream'
class SQLite3Stream extends ArrayStream
    constructor: (args)->
        super [], duplex: true
        @init.apply @, args

    init: (@text, values, callback, done)->
        if Array.isArray values
            @values = values
        else
            @values = []
            if arguments.length is 2
                done = values if 'function' is typeof values
            else if arguments.length is 3
                done = callback if 'function' is typeof callback
                callback = values if 'function' is typeof values

        @callback = if 'function' is typeof callback then callback else ->
        @done = if 'function' is typeof done then done else ->
        return

    execute: (db)->
        query = @text
        values = @values
        done = @done

        result = {}
        hasError = false

        @on 'data', @callback
        @once 'error', (err)->
            hasError = true
            done err
            return

        @once 'end', =>
            @removeListener 'data', @callback
            return if hasError
            # return done(err) if err
            if not result.fields
                result.fields = []
            done null, result
            return

        db.each query, values, (err, row)=>
            if err
                @emit 'error', err
                return

            if not result.fields
                result.fields = Object.keys(row).map (name)-> name: name
                @emit 'fields', result.fields

            @write row, 'item'
            return
        , (err)=>
            @end()
            if err
                @emit 'error', err
            return
        return

# Stream: error, fields, data, end

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
        database
        cmd
        stdout
        stderr
        tmp
        keep
    } = options

    cmd or (cmd = 'sqlite3')

    if cmd and 'object' is typeof cmd
        error = null
        callback = (err, res)->
            error = err
            return

        @split script, (query)->
            if not error
                cmd.query query, callback
            return
        , (err)->
            done err or error
            return
        return

    stdout or (stdout isnt null and stdout = process.stdout)
    stderr or (stderr isnt null and stderr = process.stderr)
    tmp = getTemp(tmp, options.keep isnt true)

    file = sysPath.join(tmp, 'script.sql')
    fs.writeFileSync file, script, umask

    args = [database]

    args.push '-f'
    args.push file

    opts = _.defaults
        stdio: ['pipe', stdout, stderr]
    , options

    child = anyspawn.exec cmd, args, opts, done
    readable = fs.createReadStream(file)
    readable.pipe child.stdin
    return
