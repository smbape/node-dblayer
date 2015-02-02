_ = require 'lodash'
GenericUtil = require '../GenericUtil'
sqlite3 = require 'sqlite3'

adapter = module.exports
_.extend adapter, require './common', GenericUtil.sql,
    createConnection: (options, callback)->


class SQLLite3Connection
    query: (query, params, callback)->
    stream: (query, params, callback, done)->
        if arguments.length is 3
            done = callback
            callback = params
            params = []
        params = [] if not (params instanceof Array)
    end:->

# Stream: error, fields, data, end
