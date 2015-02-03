_ = require 'lodash'
GenericUtil = require '../GenericUtil'
sqlite3 = require 'sqlite3'
EventEmitter = require('events').EventEmitter

MODES =
    READ: [Math.pow 2, 0, sqlite3.OPEN_READONLY]
    WRITE: [Math.pow 2, 1, sqlite3.OPEN_READWRITE]
    CREATE: [Math.pow 2, 2, sqlite3.OPEN_CREATE]

adapter = module.exports
_.extend adapter, require './common', GenericUtil.sql,
    name: 'sqlite3'
    createConnection: (options, callback)->
        if options.host
            filename = options.host + (options.database or '')
        else
            filename = options.database
        if not filename or filename is '/:memory'
            filename = ':memory:'

        if not isNaN options.mode
            mode = 0
            opt_mode = parseInt options.mode, 10
            for name of MODES
                value = MODES[name]
                if value[0] is value[0] & opt_mode
                    mode |= value[1]

        if not mode
            mode = sqlite3.OPEN_READWRITE | sqlite3.OPEN_CREATE

        new SQLite3Connection filename, mode, callback
    createQuery: (text, values, callback)->
        new SQLite3Query text, values, callback

class SQLite3Connection extends EventEmitter
    adapter: adapter
    constructor: (filename, mode, callback)->
        super()
        
        @db = new sqlite3.Database filename, mode

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

    query: (query, values, callback)->
        query = adapter.createQuery query, params, callback
        query.execute @db
        query

    stream: (query, values, callback, done)->
        stream = new SQLite3Stream query, values, callback, done
        stream.execute @db
        stream
    end:->

class SQLite3Query extends EventEmitter
    constructor: (query, values, callback)->
        if typeof callback is 'undefined' and typeof values is 'function'
            callback = values
            values = []
        values or (values = [])
        @text = query
        @values = values

    execute: (db)->
        query = @text
        values = @values

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

ArrayStream = require 'sm-array-stream'
class SQLite3Stream extends ArrayStream
    constructor: (query, values, callback, done)->
        super null, {duplex: true}
# Stream: error, fields, data, end
