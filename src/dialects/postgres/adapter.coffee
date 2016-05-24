fs = require 'fs'
sysPath = require 'path'
_ = require 'lodash'
anyspawn = require 'anyspawn'
common = require '../../schema/adapter'
{getTemp} = require '../../tools'
adapter = module.exports
_.extend adapter, common
logger = log4js.getLogger __filename.replace /^(?:.+[\/])?([^.\/]+)(?:.[^.]+)?$/, '$1'

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

pg = require('pg')
QueryStream = require 'pg-query-stream'

pg.Client::stream = (query, params, callback, done)->
        if arguments.length is 3
            done = callback
            callback = params
            params = []
        params = [] if not (params instanceof Array)
        done = (->) if typeof done isnt 'function'

        query = new PostgresQueryStream query
        stream = pg.Client::query.call @, query, params
        hasError = false
        result = rowCount: 0
        stream.once 'error', (err)->
            hasError = err
            done err
            return
        stream.on 'fields', (fields)->
            result.fields = fields
            return
        stream.on 'data', ->
            ++result.rowCount
            callback.apply null, arguments
            return
        stream.once 'end', ->
            done null, result unless hasError
            return
        stream

class PostgresQueryStream extends QueryStream
    handleRowDescription: (message) ->
        QueryStream::handleRowDescription.call this, message
        @emit 'fields', message.fields
        return
    handleError: ->
        @push null
        super

_.extend adapter,
    name: 'postgres'

    createConnection: (options, callback) ->
        callback = (->) if typeof callback isnt 'function'
        client = new pg.Client options
        client.connect (err)->
            return callback(err, null) if err
            query = "SET SCHEMA '#{options.schema}'"
            logger.trace '[query] - ' + query
            client.query query, (err)->
                callback err, client
                return
            return
        client

    squelOptions:
        replaceSingleQuotes: true
        nameQuoteCharacter: '"'
        fieldAliasQuoteCharacter: '"'
        tableAliasQuoteCharacter: '"'

    decorateInsert: (query, column)->
        if typeof column is 'string' and column.length > 0
            query += ' RETURNING "' + column + '"'
        else
            query

    insertDefaultValue: (column)->
        "(#{@escapeId(column)}) VALUES (DEFAULT)"

# http://www.postgresql.org/docs/9.4/static/libpq-envars.html
_env = _.pick process.env, [
    'PGHOST'
    'PGHOSTADDR'
    'PGPORT'
    'PGDATABASE'
    'PGUSER'
    'PGPASSWORD'
    'PGPASSFILE'
    'PGSERVICE'
    'PGSERVICEFILE'
    'PGREALM'
    'PGOPTIONS'
    'PGAPPNAME'
    'PGSSLMODE'
    'PGREQUIRESSL'
    'PGSSLCOMPRESSION'
    'PGSSLCERT'
    'PGSSLKEY'
    'PGSSLROOTCERT'
    'PGSSLCRL'
    'PGREQUIREPEER'
    'PGKRBSRVNAME'
    'PGGSSLIB'
    'PGCONNECT_TIMEOUT'
    'PGCLIENTENCODING'
    'PGDATESTYLE'
    'PGTZ'
    'PGGEQO'
    'PGSYSCONFDIR'
    'PGLOCALEDIR'
]
umask = if process.platform is 'win32' then {encoding: 'utf-8', mode: 700} else {encoding: 'utf-8', mode: 600}

# string|object|function
# string|function|object
# function|string|object
# function|object|string
# object|string|function
# object|function|string
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
        schema
        cmd: psql
        host
        port
        stdout
        stderr
        tmp
        keep
    } = options

    database or (database = 'postgres')
    schema or (schema = 'public')
    host or (host = '127.0.0.1')
    port or (port = 5432)
    psql or (psql = 'psql')
    psql or (psql = 'psql')
    stdout or (stdout isnt null and stdout = process.stdout)
    stderr or (stderr isnt null and stderr = process.stderr)
    tmp = getTemp(tmp, options.keep isnt true)

    sqlFile = sysPath.join(tmp, 'script.sql')
    fs.writeFileSync sqlFile, "SET SCHEMA '#{schema}';\n#{script}", umask

    env = _.clone _env
    if user and password
        pgpass = sysPath.join(tmp, 'pgpass.conf')
        fs.writeFileSync pgpass, "*:*:*:#{user}:#{password}", umask
        env.PGPASSFILE = pgpass

    args = ['-h', host, '-p', port, '-d', database, '-f', sqlFile]
    opts = _.defaults
        stdio: [process.stdin, stdout, stderr]
        env: env
    , options
    if user
        args.push '-U'
        args.push user

    anyspawn.exec psql, args, opts, done
    return
