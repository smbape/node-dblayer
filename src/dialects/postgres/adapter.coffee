_ = require 'lodash'
common = require '../../schema/adapter'
adapter = _.extend module.exports, common
logger = log4js.getLogger __filename.replace /^(?:.+[\/\\])?([^.\/\\]+)(?:.[^.]+)?$/, '$1'

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

class PgClient extends pg.Client
    stream: (query, params, callback, done)->
        if arguments.length is 3
            done = callback
            callback = params
            params = []
        params = [] if not (params instanceof Array)
        done = (->) if typeof done isnt 'function'

        query = new PgQueryStream query
        stream = @query query, params
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

class PgQueryStream extends QueryStream
    handleRowDescription: (message) ->
        QueryStream::handleRowDescription.call this, message
        @emit 'fields', message.fields
        return
    handleError: ->
        @push null
        super

_.extend adapter,
    name: 'postgres'

    squelOptions:
        nameQuoteCharacter: '"'
        fieldAliasQuoteCharacter: '"'
        tableAliasQuoteCharacter: '"'

    decorateInsert: (insert, column)->
        insert.returning @escapeId(column)
        return insert

    insertDefaultValue: (insert, column)->
        insert.set @escapeId(column), 'DEFAULT', {dontQuote: true}
        return insert

    createConnection: (options, callback) ->
        callback = (->) if typeof callback isnt 'function'
        client = new PgClient options
        client.connect (err)->
            return callback(err, null) if err
            query = "SET SCHEMA '#{options.schema}'"
            logger.trace '[query] -', query
            client.query query, (err)->
                callback err, client
                return
            return
        client

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
        schema
        cmd: psql
        host
        port
        stdout
        stderr
        tmp
        keep
    } = options

    psql or (psql = 'psql')
    stdout or (stdout isnt null and stdout = process.stdout)
    stderr or (stderr isnt null and stderr = process.stderr)
    tmp = getTemp(tmp, options.keep isnt true)

    if schema
        script = "SET SCHEMA '#{schema}';\n#{script}"
    file = sysPath.join(tmp, 'script.sql')
    fs.writeFileSync file, script, umask

    env = _.clone _env
    if user and password?.length > 0
        pgpass = sysPath.join(tmp, 'pgpass.conf')
        fs.writeFileSync pgpass, "*:*:*:#{user}:#{password}", umask
        env.PGPASSFILE = pgpass

    args = []

    if user
        args.push '-U'
        args.push user

    if host
        args.push '-h'
        args.push host

    if port
        args.push '-p'
        args.push port

    if database
        args.push '-d'
        args.push database

    args.push '-f'
    args.push file

    opts = _.defaults
        stdio: [process.stdin, stdout, stderr]
        env: env
    , options

    anyspawn.exec psql, args, opts, done
    return
