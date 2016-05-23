AbstractClient = require '../AbstractClient'

class OracleClient extends AbstractClient
    begin: notImplemented
    commit: notImplemented
    rollback: notImplemented
    query: notImplemented
    end: notImplemented

module.exports =
    createConnection: (options, callback)->