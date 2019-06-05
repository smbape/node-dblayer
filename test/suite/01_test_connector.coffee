logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{AdapterPool, Connector} = require '../../'
{STATES} = Connector::

knex = require('knex') { client: globals.config.dialect }

describe 'test connector', ->
    before (done)->
        query = knex.schema.withSchema(globals.config.schema).createTable '_users', (table)->
            table.increments()
            table.string('name')
            return
        globals.connectors.admin.query query.toString(), done
        return

    after (done)->
        query = knex.schema.withSchema(globals.config.schema).dropTableIfExists('_users')
        globals.connectors.admin.query query.toString(), done
        return

    it 'should instantiate AdapterPool', (done)->
        assertThrows ->
            new AdapterPool()
            return
        , 'INVALID_ARGUMENTS'

        assertThrows ->
            new AdapterPool 'url'
            return
        , 'BAD_ADAPTER'

        assertThrows ->
            new AdapterPool 'url', adapter: null
            return
        , 'BAD_ADAPTER'

        assertThrows ->
            new AdapterPool 'url', adapter: ''
            return
        , 'BAD_ADAPTER'

        assertThrows ->
            new AdapterPool 'url', adapter: 1
            return
        , 'BAD_ADAPTER'

        user = encodeURIComponent globals.config.users.reader.name
        password = encodeURIComponent globals.config.users.reader.password
        url = "#{globals.config.dialect}://#{user}:#{password}@#{globals.config.host}:#{globals.config.port}/#{globals.config.database}"
        pool = new AdapterPool "#{url}?schema=schema&minConnection=0&maxConnection=1&idleTimeout=1800"

        options = ['adapter', 'user', 'password', 'host', 'port', 'database', 'schema', 'minConnection', 'maxConnection', 'idleTimeout']
        expected = _.pick(globals.config, options)
        expected.adapter = globals.config.dialect
        expected.user = globals.config.users.reader.name
        expected.password = globals.config.users.reader.password
        expected.adapter = globals.config.dialect
        expected.schema = 'schema'
        expected.minConnection = 0
        expected.maxConnection = 1
        expected.idleTimeout = 1800
        assert.deepEqual _.pick(pool.options, options), _.pick(expected, options)

        tasks = []
        for type in ['admin', 'writer', 'reader']
            ((pool)->
                tasks.push (next)-> pool.check next
                return
            )(globals.pools[type])

        async.series tasks, done
        return

    it 'should instantiate Connector', (done)->
        assert.throws ->
            new Connector()
            return

        connector = new Connector globals.pools.reader
        assert.ok connector
        connector.query 'select 1', done
        return

    it 'should acquire', (done)->
        connector = globals.pools.reader.createConnector()
        async.waterfall [
            (next)->
                assert.strictEqual 0, connector.getSavepointsSize()
                connector.release next
                return
            (next)->
                assert.strictEqual 0, connector.getSavepointsSize()
                connector.acquire next
                return
            (performed, next)->
                assert.strictEqual 1, connector.getSavepointsSize()
                connector.release next
                return
            (next)->
                assert.strictEqual 0, connector.getSavepointsSize()
                connector.acquire next
                return
            (performed, next)->
                assert.strictEqual 1, connector.getSavepointsSize()
                connector.acquire next
                return
            (performed, next)->
                assert.strictEqual 1, connector.getSavepointsSize()
                connector.release next
                return
            (next)->
                assert.strictEqual 0, connector.getSavepointsSize()
                next()
                return
        ], done
        return

    it 'should timeout acquire', (done)->
        timeout = Math.pow 2, 6
        connector = globals.pools.reader.createConnector timeout: timeout / 2
        async.series async.reflectAll([
            (next)-> connector.acquire next
            (next)-> setTimeout next, timeout
            (next)-> connector.acquire next
            (next)->
                assert.strictEqual connector.getState(), STATES.INVALID
                connector.release next
                return
            (next)->
                assert.strictEqual connector.getState(), STATES.INVALID
                connector.query 'select 1', next
                return
            (next)->
                assert.strictEqual connector.getState(), STATES.INVALID
                connector.commit next
                return
            (next)->
                assert.strictEqual connector.getState(), STATES.INVALID
                connector.rollback next
                return
            (next)->
                assert.strictEqual connector.getState(), STATES.INVALID
                connector.begin next
                return
            (next)->
                assert.strictEqual connector.getState(), STATES.INVALID
                connector.acquire next
                return
            (next)->
                assert.strictEqual connector.getState(), STATES.INVALID
                next()
                return
        ]), (err, results)->
            for index in [0...2] by 1
                result = results[index]
                if result.error
                    throw new Error "expected task #{index} to have no error"

            for index in [2...(results.length - 1)] by 1
                result = results[index]
                if !result.error
                    throw new Error "expected task #{index} to have an error"

            done()
            return
        return

    it 'should handle transactions', (done)->
        connector = globals.pools.writer.createConnector()
        name = 'name'
        async.waterfall [
            (next)->
                connector.begin (err)->
                    assert.ok !!err
                    assert.strictEqual err.code, 'NO_CONNECTION'
                    connector.acquire next
                    return
                return
            (performed, next)->
                assert.strictEqual 1, connector.getSavepointsSize()
                connector.begin next
                return
            (next)->
                assert.strictEqual 2, connector.getSavepointsSize()
                connector.commit next
            (next)->
                assert.strictEqual 1, connector.getSavepointsSize()
                connector.begin next
                return
            (next)->
                assert.strictEqual 2, connector.getSavepointsSize()
                connector.release (err)->
                    assert.ok !!err
                    assert.strictEqual err.code, 'NO_RELEASE'
                    assertInsert connector, {id: 1, name}, next
                    return
                return
            (res, next)-> assertExist connector, {id: 1, name}, next
            (next)-> connector.begin next
            (next)->
                assert.strictEqual 3, connector.getSavepointsSize()
                assertInsert connector, {id: 2, name}, next
                return
            (res, next)-> assertExist connector, {id: 2, name}, next
            (next)-> connector.begin next
            (next)->
                assert.strictEqual 4, connector.getSavepointsSize()
                assertInsert connector, {id: 3, name}, next
                return
            (res, next)-> assertExist connector, {id: 3, name}, next
            (next)->
                connector.query 'Not a valid sql statement', (err)->
                    assert.ok !!err
                    assert.strictEqual 3, connector.getSavepointsSize()
                    next()
                return
            (next)-> assertNotExist connector, {id: 3, name}, next
            (next)-> assertExist connector, {id: 2, name}, next
            (next)-> assertInsert connector, {id: 4, name}, next
            (res, next)-> assertExist connector, {id: 4, name}, next
            (next)-> connector.commit true, next
            (next)->
                assert.strictEqual 0, connector.getSavepointsSize()
                connector.acquire next
                return
            (performed, next)-> assertExist connector, {id: 4, name}, next
            (next)-> assertNotExist connector, {id: 3, name}, next
            (next)-> assertExist connector, {id: 2, name}, next
            (next)-> assertExist connector, {id: 1, name}, next
            (next)-> connector.release next
            (next)->
                assert.strictEqual 0, connector.getSavepointsSize()
                next()
                return
        ], done

        return

    it 'should stream', (done)->
        connector = globals.pools.writer.createConnector()
        rowCount = 0
        num = Math.pow 2, 8
        offset = 1000

        values = []
        for i in [0...num] by 1
            values.push
                id: i + offset
                name: 'name_' + i

        async.waterfall [
            (next)->
                connector.stream 'select 1 as num', (row)->
                    assert.strictEqual row.num, 1
                    return
                , next
            (result, next)->
                connector.acquire next
                return
            (performed, next)->
                query = knex('_users').insert(values)
                connector.query query.toString(), next
                return
            (res, next)->
                query = knex('_users').select('id as num').where('id', '>=', offset)
                connector.query query.toString(), next
                return
            (res, next)->
                assert.strictEqual res.rows.length, values.length
                query = knex('_users').select('id as num').where('id', '>=', offset)
                connector.stream query.toString(), (row)->
                    if row.constructor.name isnt 'OkPacket'
                        assert.strictEqual row.num, values[rowCount++].id
                    return
                , next
                return
            (result, next)->
                assert.ok result.fields instanceof Array
                assert.strictEqual 1, result.fields.length
                assert.strictEqual 'num', result.fields[0].name
                assert.strictEqual rowCount, num
                connector.release next
                return
        ], done

        # it 'should escape', ->
        #     connector = globals.pools.reader.createConnector()
        #     connector.escape 'toto'
        #     connector.escapeId 'toto'
        #     connector.escapeSearch 'toto'
        #     connector.escapeBeginWith 'toto'
        #     connector.escapeEndWith 'toto'
        #     connector.exprEqual 'toto'
        #     connector.exprNotEqual 'toto'
        #     return

    return

assertInsert = (connector, attributes, done)->
    query = knex('_users').insert(attributes).returning('id')
    connector.query query.toString(), (err, res)->
        return done(err) if err
        if res.hasOwnProperty 'lastInsertId'
            id = res.lastInsertId
        else
            id = Array.isArray(res.rows) and res.rows.length > 0 and res.rows[0].id

        assert.strictEqual id, attributes.id
        done err, id
        return
    return

assertExist = (connector, {id, name}, done)->
    query = knex.select().from('_users').where({id})
    connector.query query.toString(), (err, res)->
        return done(err) if err
        assert.equal res.rows[0].id, id
        assert.equal res.rows[0].name, name
        done()
        return
    return

assertNotExist = (connector, {id, name}, done)->
    query = knex.select().from('_users').where({id})
    connector.query query.toString(), (err, res)->
        return done(err) if err
        assert.strictEqual res.rows.length, 0
        done()
        return
    return
