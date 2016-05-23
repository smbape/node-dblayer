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

{AdapterPool, PersistenceManager} = require('../')
{guessEscapeOpts} = require '../src/schema/adapter'

resources = sysPath.resolve __dirname, 'resources'
{getTemp} = require './tools'

dialect = process.env.DIALECT or 'postgres'
config = global.config = require('./config')[dialect]
config.dialect = dialect
config.tmp = getTemp sysPath.resolve(__dirname, 'tmp'), config.keep isnt true

global.knex = require('knex') { dialect }

make = require sysPath.resolve resources, dialect, 'make'
global.pMgr = new PersistenceManager require './mapping'
global.escapeOpts = require '../src/dialects/' + dialect + '/adapter'
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

before (done)->
    @timeout 15 * 1000
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
                PersistenceManager::defaults.insert = PersistenceManager::defaults.update = PersistenceManager::defaults.delete = {connector: connectors.writer}
                PersistenceManager::defaults.list = {connector: connectors.reader}

                require('./sqlscripts') next
                return
            return
    ], done

after (done)->
    @timeout 15 * 1000
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
        connector.rollback done, true
        return
    return

global.squelFields = (attributes)->
    fields = {}
    for field, value of attributes
        fields[escapeOpts.escapeId(field)] = value
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
    mapping = {}
    modelId = 0
    Model = PersistenceManager::Model

    class ModelA extends Model
        className: 'ClassA'

    handlersCreation =
        insert: (model, options, extra)->
            new Date()
        read: (value, model, options)->
            moment.utc(moment(value).format 'YYYY-MM-DD HH:mm:ss.SSS').toDate()
        write: (value, model, options)->
            moment(value).utc().format 'YYYY-MM-DD HH:mm:ss.SSS'

    handlersModification = _.extend {}, handlersCreation, update: handlersCreation.insert

    mapping['ClassA'] =
        ctor: ModelA
        table: 'CLASS_A'
        id:
            name: 'idA'
            column: 'A_ID'
        properties:
            propA1: 'PROP_A1'
            propA2: 'PROP_A2'
            propA3: 'PROP_A3'
            creationDate:
                column: 'CREATION_DATE'
                handlers: handlersCreation
            modificationDate:
                lock: true
                column: 'MODIFICATION_DATE'
                handlers: handlersModification
            version:
                lock: true
                column: 'VERSION'
                handlers: insert: (model)->
                    '1.0'

    class ModelB extends Model
        className: 'ClassB'

    mapping['ClassB'] =
        ctor: ModelB
        table: 'CLASS_B'
        id: className: 'ClassA'
        properties:
            propB1: 'PROP_B1'
            propB2: 'PROP_B2'
            propB3: 'PROP_B3'

    class ModelC extends Model
        className: 'ClassC'

    mapping['ClassC'] =
        ctor: ModelC
        table: 'CLASS_C'
        id:
            name: 'idC'
            column: 'C_ID'
        properties:
            propC1: 'PROP_C1'
            propC2: 'PROP_C2'
            propC3: 'PROP_C3'

    class ModelD extends Model
        className: 'ClassD'

    mapping['ClassD'] =
        ctor: ModelD
        table: 'CLASS_D'
        id: className: 'ClassA'
        mixins: 'ClassC'
        properties:
            propD1: 'PROP_D1'
            propD2: 'PROP_D2'
            propD3: 'PROP_D3'

    class ModelE extends Model
        className: 'ClassE'

    mapping['ClassE'] =
        ctor: ModelE
        table: 'CLASS_E'
        id: className: 'ClassB'
        mixins: 'ClassC'
        properties:
            propE1: 'PROP_E1'
            propE2: 'PROP_E2'
            propE3: 'PROP_E3'

    class ModelF extends Model
        className: 'ClassF'

    mapping['ClassF'] =
        ctor: ModelF
        table: 'CLASS_F'
        id: className: 'ClassC'
        properties:
            propF1: 'PROP_F1'
            propF2: 'PROP_F2'
            propF3: 'PROP_F3'
            propClassD:
                column: 'A_ID'
                className: 'ClassD'
            propClassE:
                column: 'CLA_A_ID'
                className: 'ClassE'

    class ModelG extends Model
        className: 'ClassG'

    mapping['ClassG'] =
        ctor: ModelG
        table: 'CLASS_G'
        id:
            name: 'idG'
            column: 'G_ID'
        constraints: {type: 'unique', properties: ['propG1', 'propG2']}
        properties:
            propG1: 'PROP_G1'
            propG2: 'PROP_G2'
            propG3: 'PROP_G3'

    class ModelH extends Model
        className: 'ClassH'

    mapping['ClassH'] =
        ctor: ModelH
        table: 'CLASS_H'
        mixins: ['ClassD', 'ClassG']
        properties:
            propH1: 'PROP_H1'
            propH2: 'PROP_H2'
            propH3: 'PROP_H3'

    class ModelI extends Model
        className: 'ClassI'

    mapping['ClassI'] =
        ctor: ModelI
        table: 'CLASS_I'
        id: className: 'ClassG'

    pMgr = new PersistenceManager mapping

    model = new Model()

    for letter in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I']
        for i in [1..3] by 1
            model.set "prop#{letter}#{i}", "prop#{letter}#{i}Value"

    connector = pools.writer.createConnector()

    return [pMgr, model, connector, Model, mapping]

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
