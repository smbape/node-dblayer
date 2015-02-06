log4js = global.log4js or (global.log4js = require 'log4js')
logger = log4js.getLogger 'ConnectorTest'
async = require 'async'
_ = require 'lodash'

queryCreateTable = 
    mysql: """
        create table if not exists `test` (
            `id` int(4) not null auto_increment,
            `name` varchar(255),
            constraint `PK_TEST` primary key (`id`)
        )
    """
    postgres: """
        create table if not exists "test" (
           "id" serial not null,
           "name" varchar(255) null,
           constraint "PK_TEST" primary key ("id")
        )
    """
    sqlite3: """
        create table if not exists "test" (
            "id" INTEGER,
            "name" varchar(255),
            constraint "PK_TEST" PRIMARY KEY ("id")
        )
    """

sql = require 'sql'
testTable = sql.define
    name: 'test'
    columns: ['id', 'name']

library = require '../../'
Connector = library.Connector
STATES = Connector::STATES

DBUtil = (->
    dialects = 
        postgres: new (require 'sql/lib/dialect/postgres')
        sqlite3: new (require 'sql/lib/dialect/sqlite')
        mysql : new (require 'sql/lib/dialect/mysql')

    # Return sql query string
    # @param sqlQuery [SqlQuery] query
    # @param settings [Object] optional settings
    # @param connection [SqlConnection]
    # @retun [String] query String
    getQueryString: (sqlQuery, connection, settings)->
        if arguments.length is 2
            settings = connection
            connection = undefined

        if _.isPlainObject settings
            dialect = settings.dialect
        else if typeof settings is 'string'
            dialect = settings

        dialect = dialects[dialect]
        return if not dialect
        return dialect.getString sqlQuery
)()

module.exports = (config)->
    (assert)->
        task config, assert
        return

task = (config, assert)->
    poolRead = config.poolRead
    poolWrite = config.poolWrite
    poolAdmin = config.poolAdmin

    assertResult = (res)->
        assert.ok _.isObject res
        assert.ok res.rows instanceof Array
        assert.ok res.rows.length > 0

    setUp = (next)->
        pool = poolAdmin
        dialect = pool.getDialect()
        query = queryCreateTable[dialect]
        dropQuery = DBUtil.getQueryString testTable.drop().ifExists(), dialect
        pool.acquire (err, connection)->
            assert.ifError err
            connection.query dropQuery, (err, res)->
                assert.ifError err
                connection.query query, (err, res)->
                    assert.ifError err
                    pool.release connection
                    next()
                    return
                return
            return
        return
    
    tearDown = (next)->
        pool = poolAdmin
        sqlQuery = testTable.drop().ifExists()
        query = DBUtil.getQueryString sqlQuery, pool.getDialect()
        pool.acquire (err, connection)->
            assert.ifError err
            connection.query query, (err, res)->
                assert.ifError err
                pool.release connection
                next()
    
    testConstructor = (next)->
        pool = poolRead
        connector = new Connector pool
        assert.ok connector
        assert.throws ->
            new Connector()
            return
        next()
        return

    testAcquire = (next)->
        pool = poolRead
        connector = poolRead.createConnector()
        connector.release (err)->
            assert.ifError err
            assert.strictEqual 0, connector.getSavepointsSize()
            connector.acquire (err)->
                assert.ifError err
                assert.strictEqual 1, connector.getSavepointsSize()
                connector.release (err)->
                    assert.ifError err
                    assert.strictEqual 0, connector.getSavepointsSize()
                    connector.acquire (err)->
                        assert.ifError err
                        assert.strictEqual 1, connector.getSavepointsSize()
                        connector.acquire (err)->
                            assert.ifError err
                            assert.strictEqual 1, connector.getSavepointsSize()
                            connector.release (err)->
                                assert.ifError err
                                assert.strictEqual 0, connector.getSavepointsSize()
                                next()
                                return
                            return
                        return
                    return
                return
            return
        return

    testAcquireTimeout = (next)->
        timeout = Math.pow 2, 6
        connector = poolRead.createConnector timeout: timeout / 2
        connector.acquire (err)->
            assert.ifError err
            setTimeout ->
                connector.acquire (err)->
                    assert.ok !!err
                    assert.strictEqual connector.getState(), STATES.INVALID
                    connector.release (err)->
                        assert.ok !!err
                        assert.strictEqual connector.getState(), STATES.INVALID
                        connector.query 'select 1', (err)->
                            assert.ok !!err
                            assert.strictEqual connector.getState(), STATES.INVALID
                            connector.commit (err)->
                                assert.ok !!err
                                assert.strictEqual connector.getState(), STATES.INVALID
                                connector.rollback (err)->
                                    assert.ok !!err
                                    assert.strictEqual connector.getState(), STATES.INVALID
                                    connector.begin (err)->
                                        assert.ok !!err
                                        assert.strictEqual connector.getState(), STATES.INVALID
                                        connector.acquire (err)->
                                            assert.ok !!err
                                            assert.strictEqual connector.getState(), STATES.INVALID
                                            next()
                                            return
                                        return
                                    return
                                return
                            return
                        return
                    return
                return
            , timeout
        return

    assertInsert = (connector, id, name, next)->
        query = testTable.insert {id: id, name: name}
        query = DBUtil.getQueryString query, connector.getDialect()
        connector.query query, (err, res)->
            assert.ifError err
            next()
            return
        return

    assertExist = (connector, id, name, next)->
        query = testTable.select(testTable.star()).where testTable.id.equal(id)
        query = DBUtil.getQueryString query, connector.getDialect()
        connector.query query, (err, res)->
            assert.ifError err
            assertResult res
            assert.equal res.rows[0].id, id
            assert.equal res.rows[0].name, name
            next()
            return
        return

    assertNotExist = (connector, id, name, next)->
        query = testTable.select(testTable.star()).where testTable.id.equal(id)
        query = DBUtil.getQueryString query, connector.getDialect()
        connector.query query, (err, res)->
            assert.ifError err
            assert.ok _.isObject res
            assert.ok res.rows instanceof Array
            assert.strictEqual res.rows.length, 0
            next()
            return
        return

    testTransaction = (next)->
        connector = poolWrite.createConnector()
        name = 'name'
        connector.begin (err)->
            assert.ok !!err
            assert.strictEqual err.code, 'NO_CONNECTION'
            connector.acquire (err)->
                assert.ifError err
                assert.strictEqual 1, connector.getSavepointsSize()
                connector.begin (err)->
                    assert.ifError err
                    assert.strictEqual 2, connector.getSavepointsSize()
                    assertInsert connector, 1, name, ->
                        assertExist connector, 1, name, ->
                            connector.begin (err)->
                                assert.ifError err
                                assert.strictEqual 3, connector.getSavepointsSize()
                                assertInsert connector, 2, name, ->
                                    assertExist connector, 2, name, ->
                                        connector.begin (err)->
                                            assert.ifError err
                                            assert.strictEqual 4, connector.getSavepointsSize()
                                            assertInsert connector, 3, name, ->
                                                assertExist connector, 3, name, ->
                                                    connector.query 'Not a valid sql statement', (err)->
                                                        assert.ok !!err
                                                        assert.strictEqual 3, connector.getSavepointsSize()
                                                        async.parallel [
                                                            (next)-> assertNotExist connector, 3, name, next
                                                            (next)-> assertExist connector, 2, name, next
                                                            (next)-> assertInsert connector, 4, name, next
                                                        ], ->
                                                            assertExist connector, 4, name, ->
                                                                connector.commit true, (err)->
                                                                    assert.ifError err
                                                                    assert.strictEqual 0, connector.getSavepointsSize()
                                                                    connector.acquire (err)->
                                                                    async.parallel [
                                                                        (next)-> assertExist connector, 4, name, next
                                                                        (next)-> assertNotExist connector, 3, name, next
                                                                        (next)-> assertExist connector, 2, name, next
                                                                        (next)-> assertExist connector, 1, name, next
                                                                    ], ->
                                                                        connector.release (err)->
                                                                            assert.ifError err
                                                                            assert.strictEqual 0, connector.getSavepointsSize()
                                                                            next()
                                                                            return
                                                                        return
                                                                    return
                                                                return
                                                            return
                                                        return
                                                    return
                                                return
                                            return
                                        return
                                    return
                                return
                            return
                        return
                    return
                return
            return
        return

    testStream = (next)->
        connector = poolWrite.createConnector()
        rowCount = 0
        num = Math.pow 2, 8
        treshold = 1000

        connector.acquire (err)->
            query = []
            for i in [0...num] by 1
                query.push "(#{i + treshold}, 'name_#{i}')"

            query = "INSERT INTO test (id, name) values " + query.join ', '
            connector.query query, (err, res)->
                assert.ifError err
                statement = "SELECT id as \"num\" FROM test WHERE id >= #{treshold}"
                connector.stream statement, (row)->
                    rowCount++ if row.constructor.name isnt 'OkPacket'
                , (err, result)->
                    connector.release()
                    assert.ifError err
                    assert.ok result.fields instanceof Array
                    assert.strictEqual 1, result.fields.length
                    assert.strictEqual 'num', result.fields[0].name
                    assert.strictEqual rowCount, num
                    next()
                    return
                return
            return
        return

    # test autoRollback also with stream
    # Connection timeout + stream, stream must end.
    # Connection failure test
    # 
    series = [
        setUp
        testConstructor
        testAcquire
        testAcquireTimeout
        testTransaction
        testStream
        tearDown
    ]

    async.series series, assert.done

    # passed = 0
    # async.eachSeries series, (fn, next)->
    #     fn next
    # , assert.done
    return