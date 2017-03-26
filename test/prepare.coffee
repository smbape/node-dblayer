sysPath = require 'path'
_ = require 'lodash'
async = require 'async'
fs = require 'fs'
chai = require 'chai'
moment = require 'moment'
squel = require 'squel'

log4js = global.log4js = require 'log4js'
log4js.configure sysPath.resolve __dirname, 'log4js.json'
logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

global.assert = chai.assert
global.expect = chai.expect
global.globals = {}

{AdapterPool, PersistenceManager, tools} = require('../')

resources = sysPath.resolve __dirname, 'resources'
{getTemp} = require './tools'

allConfigs = require('./config')
dialect = process.env.DIALECT or 'postgres'
config = globals.config = allConfigs[dialect]
newConfig = allConfigs['new_' + dialect]
config.dialect = dialect
config.tmp = getTemp sysPath.resolve(__dirname, 'tmp'), config.keep isnt true

make = require sysPath.resolve resources, dialect, 'make'
mapping = require('./mapping')
globals.pMgr = new PersistenceManager mapping, config
adapter = globals.adapter = tools.adapter(dialect)
squelOptions = globals.squelOptions = PersistenceManager.getSquelOptions(config.dialect)

initPools = (dialect, config, newConfig)->
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
            timeout: 3600 * 1000
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
            timeout: 3600 * 1000
        }

    for name, user of newConfig.users
        pools['new_' + name] = new AdapterPool {
            name: user.name
            adapter: dialect
            host: newConfig.host
            port: newConfig.port
            database: newConfig.database
            schema: newConfig.schema
            user: user.name
            password: user.password
            minConnectio: 0
            maxConnection: 1
            timeout: 3600 * 1000
        }

    connectors = {}
    for name, pool of pools
        connectors[name] = pool.createConnector()

    return {pools, connectors}

destroyPools = (done)->
    count = Object.keys(globals.pools).length + 1

    for name, pool of globals.pools
        do (name, pool)->
            pool.destroyAll false, (err)->
                console.error(err) if err
                if --count is 0
                    done()
                return
            return

    globals.pMgr.destroyPools false, ->
        if --count is 0
            done()
        return

    return

before (done)->
    @timeout 60 * 1000
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
                next()
                return
            return
        (next)->
            logger.debug 'uninstall'
            make.uninstall newConfig, (err)->
                logger.warn(err) if err
                next()
                return
            return
        (next)->
            logger.debug 'install'
            make.install newConfig, (err)->
                logger.warn(err) if err
                {pools, connectors} = initPools(dialect, config, newConfig)
                globals.pools = pools
                globals.connectors = connectors
                next()
                return
            return
    ], done

after (done)->
    @timeout 60 * 1000
    destroyPools (err)->
        logger.warn(err) if err
        if config.keep
            done()
            return
        logger.debug 'uninstall'
        make.uninstall config, (err)->
            logger.warn(err) if err
            make.uninstall newConfig, (err)->
                logger.warn(err) if err
                done()
                return
            return
        return
    return

describe 'prepare', ->
    @timeout 60 * 1000
    concatQueries = ({drop_constraints, drops, creates, alters})->
        drop_constraints.concat(drops).concat(creates).concat(alters).join(';\n')

    it 'should create model when not existing', (done)->
        [pMgr, model, connector, Model] = setUpMapping()
        opts = _.defaults {
            connector: globals.connectors.admin
            cascade: false
            if_exists: false
            prompt: false
        }, _.pick(globals.config, ['tmp', 'keep', 'stdout', 'stderr'])

        async.waterfall [
            (next)->
                globals.pMgr.sync _.defaults({purge: true, exec: true}, opts), next
                return
            (queries, oldModel, newModel, next)->
                assert.ok concatQueries(queries).length
                assert.strictEqual _.isEmpty(oldModel), true, 'expecting oldModel to be empty'
                globals.pMgr.sync _.defaults({purge: true, exec: false}, opts), next
                return
            (queries, oldModel, newModel, next)->
                # console.log require('util').inspect oldModel.BASIC_DATA, {depth: null}
                # console.log require('util').inspect newModel.BASIC_DATA, {depth: null}
                assert.lengthOf concatQueries(queries), 0
                require('./sqlscripts') config, globals.connectors, next
                return
        ], done

        return

    return

global.twaterfall = (connector, tasks, done)->
    acquired = false
    transaction = false
    async.waterfall [
        (next)-> connector.acquire next
        (performed, next)->
            acquired = performed
            connector.begin next
            return
        (next)->
            transaction = true
            next()
            return
    ].concat(tasks), (err)->
        connector.rollback (_err)->
            logger.error(_err) if _err
            done(err)
            return
        , true
        return
    return

global.squelFields = (attributes)->
    fields = {}
    for field, value of attributes
        fields[adapter.escapeId(field)] = value
    fields

global.assertThrows = (fn, callback, msg = 'Throws and unexpected error')->
    if 'string' is typeof callback
        expected = callback
        callback = (err)->
            assert.strictEqual err.code, expected
    try
        fn()
        throw new Error "expected #{fn} to throw"
    catch err
        callback err
    return

global.assertPartialThrows = (mapping, className, given, expected)->
    mapping[className] = given
    assertThrows ->
        pMgr = new PersistenceManager mapping
        return
    , expected
    return

global.assertPartial = (mapping, className, given, expected)->
    mapping[className] = given
    pMgr = new PersistenceManager mapping
    given = pMgr.getDefinition className
    for prop, value of expected
        assert.deepEqual given[prop], value
    return

global.assertInsertQuery = (mapping, model, className, expected)->
    model.className = className
    pMgr = new PersistenceManager mapping
    query = pMgr.getInsertQuery model, {dialect: config.dialect}
    assert.strictEqual query.toString(), expected
    return

global.assertInsertQueryThrows = (mapping, model, className, expected)->
    model.className = className
    pMgr = new PersistenceManager mapping
    assertThrows ->
        pMgr.getInsertQuery model, {dialect: config.dialect}
        return
    , expected
    return

global.assertPersist = (pMgr, model, classNameLetter, id, connector, next)->
    className = 'Class' + classNameLetter
    definition = pMgr.getDefinition className
    if _.isObject id
        id = id[definition.id.column]
    query = squel
        .select pMgr.getSquelOptions connector.getDialect()
        .from connector.escapeId definition.table
        .where connector.escapeId(definition.id.column) + ' = ?', id
        .toString()
    connector.query query, (err, res)->
        return next err if err
        assert.strictEqual res.rows.length, 1
        row = res.rows[0]
        assert.strictEqual row['PROP_' + classNameLetter + '1'], model.get 'prop' + classNameLetter + '1'
        assert.strictEqual row['PROP_' + classNameLetter + '2'], model.get 'prop' + classNameLetter + '2'
        assert.strictEqual row['PROP_' + classNameLetter + '3'], model.get 'prop' + classNameLetter + '3'
        next err, row
        return
    return

global.setUpMapping = ->
    _mapping = _.cloneDeep mapping
    Model = PersistenceManager::Model
    pMgr = new PersistenceManager _mapping
    model = new Model()

    for letter in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I']
        for i in [1..3] by 1
            model.set "prop#{letter}#{i}", "prop#{letter}#{i}Value"

    connector = globals.pools.writer.createConnector()

    return [pMgr, model, connector, Model, _mapping]

global.assertList = (pMgr, options, next)->
    classNameLetter = options.classNameLetter
    listOptions = options.listOptions

    className = 'Class' + classNameLetter
    pMgr.list className, listOptions, (err, models)->
        return next err if err
        assert.ok models.length > 0
        next err, models
        return
    return

global.assertProperties = (letters, pModel, model)->
    for letter in letters
        for index in [1..3] by 1
            prop = 'prop' + letter + index
            assert.strictEqual model.get(prop), pModel.get prop
    return

global.assertListUnique = (pMgr, options, next)->
    classNameLetter = options.classNameLetter
    model = options.model
    letters = options.letters or [classNameLetter]

    assertList pMgr, options, (err, models)->
        return next err if err
        assert.strictEqual models.length, 1
        assertProperties models[0], models
        next err, models[0]
        return
    return

global.assertPropSubClass = (modelF, modelD, modelE)->
    assert.strictEqual modelF.className, 'ClassF'

    pModelD = modelF.get 'propClassD'
    assert.strictEqual pModelD.className, 'ClassD'
    for letter in ['A', 'C']
        for index in [1..3]
            prop = 'prop' + letter + index
            assert.strictEqual modelD.get(prop), pModelD.get prop

    if typeof modelE isnt 'undefined'
        pModelE = modelF.get 'propClassE'
        assert.strictEqual pModelE.className, 'ClassE'
        for letter in ['A', 'B', 'C']
            for index in [1..3]
                prop = 'prop' + letter + index
                assert.strictEqual modelE.get(prop), pModelE.get prop

    return

global.assertCount = (pMgr, expected, connector, next)->
    done = 0
    query = ''
    options = _.extend {}, pMgr.getSquelOptions(connector.getDialect()), autoQuoteFieldNames: false
    for letter in ['A', 'B', 'C', 'D', 'E', 'F']
        definition = pMgr.getDefinition 'Class' + letter
        query += ' UNION ALL ' + squel
            .select options
            .field('COUNT(1)', 'count', dontQuote: true)
            .from connector.escapeId definition.table
            .toString()

    query = query.substring 11
    connector.query query, (err, res)->
        return next err if err
        assert.strictEqual expected[0], parseInt res.rows[0].count, 10
        assert.strictEqual expected[1], parseInt res.rows[1].count, 10
        assert.strictEqual expected[2], parseInt res.rows[2].count, 10
        assert.strictEqual expected[3], parseInt res.rows[3].count, 10
        assert.strictEqual expected[4], parseInt res.rows[4].count, 10
        assert.strictEqual expected[5], parseInt res.rows[5].count, 10
        next err
        return
    return
