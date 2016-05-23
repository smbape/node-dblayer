AbstractClient = require '../AbstractClient'

class PSqlServerClient extends AbstractClient
    begin: notImplemented
    commit: notImplemented
    rollback: notImplemented
    query: notImplemented
    end: notImplemented

module.exports =
    createConnection: (options, callback)->