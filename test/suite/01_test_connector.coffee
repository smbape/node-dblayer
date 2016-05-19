logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{AdapterPool, Connector} = require '../../'
{STATES} = Connector::

describe 'test connector', ->

    before (done)->
        query = knex.schema.withSchema(config.schema).createTable 'users', (table)->
            table.increments()
            table.string('name')
            return
        connectors.admin.query query.toString(), done
        return

    after (done)->
        query = knex.schema.withSchema(config.schema).dropTableIfExists('users')
        connectors.admin.query query.toString(), done
        return

    it 'should instantiate AdapterPool', (done)->
        assertThrows ->
            new AdapterPool()
            return
        , (err)->
            return  err.code is 'INVALID_ARGUMENTS'
        , 'unexpected error'

        assertThrows ->
            new AdapterPool 'url'
            return
        , (err)->
            err.code is 'BAD_ADAPTER'
        , 'unexpected error'

        assertThrows ->
            new AdapterPool 'url', adapter: null
            return
        , (err)->
            err.code is 'BAD_ADAPTER'
        , 'unexpected error'

        assertThrows ->
            new AdapterPool 'url', adapter: ''
            return
        , (err)->
            err.code is 'BAD_ADAPTER'
        , 'unexpected error'

        assertThrows ->
            new AdapterPool 'url', adapter: 1
            return
        , (err)->
            err.code is 'BAD_ADAPTER'
        , 'unexpected error'

        tasks = []
        for type in ['admin', 'writer', 'reader']
            ((pool)->
                tasks.push (next)-> pool.check next
                return
            )(pools[type])

        async.series tasks, done
        return

    it 'should instantiate Connector', (done)->
        assert.throws ->
            new Connector()
            return

        connector = new Connector pools.reader
        assert.ok connector
        connector.query 'select 1', done
        return

    it 'should acquire', (done)->
        connector = pools.reader.createConnector()
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
        connector = pools.reader.createConnector timeout: timeout / 2
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
        connector = pools.writer.createConnector()
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
                assertInsert connector, {id: 1, name}, next
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
        connector = pools.writer.createConnector()
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
                query = knex('users').insert(values)
                connector.query query.toString(), next
                return
            (res, next)->
                query = knex('users').select('id as num').where('id', '>=', offset)
                connector.query query.toString(), next
                return
            (res, next)->
                assert.strictEqual res.rows.length, values.length
                query = knex('users').select('id as num').where('id', '>=', offset)
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

        return

    return

assertInsert = (connector, attributes, done)->
    query = knex('users').insert(attributes).returning('id')
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
    query = knex.select().from('users').where({id})
    connector.query query.toString(), (err, res)->
        return done(err) if err
        assert.equal res.rows[0].id, id
        assert.equal res.rows[0].name, name
        done()
        return
    return

assertNotExist = (connector, {id, name}, done)->
    query = knex.select().from('users').where({id})
    connector.query query.toString(), (err, res)->
        return done(err) if err
        assert.strictEqual res.rows.length, 0
        done()
        return
    return
