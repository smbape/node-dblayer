sysPath = require 'path'
_ = require 'lodash'
async = require 'async'
fs = require 'fs'
anyspawn = require 'anyspawn'
chai = require 'chai'

log4js = global.log4js = require 'log4js'
log4js.configure sysPath.resolve __dirname, 'log4js.json'
logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

global.assert = chai.assert
global.expect = chai.expect

{AdapterPool, PersistenceManager, adapters} = require('../')
{guessEscapeOpts} = adapters.common

resources = sysPath.resolve __dirname, 'resources'
{getTemp} = require './tools'

dialect = process.env.DIALECT or 'postgres'
config = global.config = require('./config')[dialect]
config.dialect = dialect
config.tmp = getTemp sysPath.resolve(__dirname, 'tmp'), config.keep isnt true

global.knex = require('knex') {
    dialect
}

make = require sysPath.resolve resources, dialect, 'make'
global.pMgr = new PersistenceManager require './mapping'
global.escapeOpts = guessEscapeOpts { dialect }
global.squelOptions = PersistenceManager.getSquelOptions(config.dialect)

initPools = ->
    pools =
        owner: new AdapterPool {
            name: 'owner'
            adapter: dialect
            host: config.host
            port: config.port
            database: config.database
            schema: config.schema
            user: config.owner
            password: config.password
            minConnectio: 0
            maxConnection: 1
        }

    for name, user of config.users
        pools[name] = new AdapterPool {
            name: user.name
            adapter: dialect
            host: config.host
            port: config.port
            database: config.database
            schema: config.schema
            user: user.name
            password: user.password
            minConnectio: 0
            maxConnection: 1
        }

    connectors = {}
    for name, pool of pools
        connectors[name] = pool.createConnector()

    return {pools, connectors}

destroyPools = (done)->
    count = Object.keys(global.pools).length
    for name, pool of global.pools
        do (name, pool)->
            pool.destroyAll true, (err)->
                console.error(err) if err
                if --count is 0
                    done()
                return
            return
    return

global.squelFields = (attributes)->
    fields = {}
    for field, value of attributes
        fields[escapeOpts.escapeId(field)] = value
    fields

global.assertThrows = (fn, callback)->
    try
        fn()
        throw new Error "expected #{fn} to throw"
    catch err
        callback err
    return

before (done)->
    @timeout 5 * 1000
    async.waterfall [
        (next)->
            logger.debug 'uninstall'
            make.uninstall config, (err)->
                logger.warn(err) if err
                next()
                return
            return
        (next)->
            logger.debug 'install'
            make.install config, (err)->
                logger.warn(err) if err
                {pools: global.pools, connectors: global.connectors} = initPools()
                pMgr.defaults.insert = pMgr.defaults.update = pMgr.defaults.delete = {connector: connectors.writer}
                pMgr.defaults.list = {connector: connectors.reader}
                next()
                return
            return
    ], done

global.assertPartialThrows = (mapping, className, given, expected)->
    mapping[className] = given
    assertThrows ->
        pMgr = new PersistenceManager mapping
        return
    , (err)->
        err.code is expected
    , 'unexpected error'
    return

global.assertPartial = (mapping, className, given, expected)->
    mapping[className] = given
    pMgr = new PersistenceManager mapping
    given = pMgr.getDefinition className
    for prop, value of expected
        assert.ok _.isEqual given[prop], value
    return

global.assertInsertQuery = (mapping, model, className, expected)->
    model.className = className
    pMgr = new PersistenceManager mapping, {dialect: config.dialect}
    query = pMgr.getInsertQuery model
    assert.strictEqual query.toString(), expected
    return

global.assertInsertQueryThrows = (mapping, model, className, expected)->
    model.className = className
    pMgr = new PersistenceManager mapping
    assertThrows ->
        pMgr.getInsertQuery model, {dialect: config.dialect}
        return
    , (err)->
        err.code is expected
    , 'unexpected error'
    return

after (done)->
    @timeout 5 * 1000
    destroyPools (err)->
        logger.warn(err) if err
        if config.keep
            done()
            return
        logger.debug 'uninstall'
        make.uninstall config, (err)->
            logger.warn(err) if err
            done()
            return
        return
    return
