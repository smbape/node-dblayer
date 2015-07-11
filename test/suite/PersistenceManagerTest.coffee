log4js = global.log4js or (global.log4js = require 'log4js')
logger = log4js.getLogger 'PersistenceManagerTest'
async = require 'async'
_ = require 'lodash'
moment = require 'moment'
squel = require 'squel'

library = require '../../'
PersistenceManager = library.PersistenceManager

module.exports = (config)->
    (assert)->
        task config, assert
        return

task = (config, assert)->
    poolRead = config.poolRead
    poolWrite = config.poolWrite
    poolAdmin = config.poolAdmin

    setUp = (next)->
        [pMgr, model, connector, Model] = setUpMapping()
        tasks = [
            # clean every thing that has been created
            (next)-> connector.acquire next
            (next)-> connector.begin next
            (next)->connector.query 'DELETE FROM ' + connector.escapeId(pMgr.getDefinition('ClassI').table), next
            (next)-> connector.query 'DELETE FROM ' + connector.escapeId(pMgr.getDefinition('ClassH').table), next
            (next)-> connector.query 'DELETE FROM ' + connector.escapeId(pMgr.getDefinition('ClassG').table), next
            (next)-> connector.query 'DELETE FROM ' + connector.escapeId(pMgr.getDefinition('ClassF').table), next
            (next)-> connector.query 'DELETE FROM ' + connector.escapeId(pMgr.getDefinition('ClassE').table), next
            (next)-> connector.query 'DELETE FROM ' + connector.escapeId(pMgr.getDefinition('ClassD').table), next
            (next)-> connector.query 'DELETE FROM ' + connector.escapeId(pMgr.getDefinition('ClassC').table), next
            (next)-> connector.query 'DELETE FROM ' + connector.escapeId(pMgr.getDefinition('ClassB').table), next
            (next)-> connector.query 'DELETE FROM ' + connector.escapeId(pMgr.getDefinition('ClassA').table), next
            (next)-> connector.commit next
            (next)-> connector.release next
        ]

        async.series tasks, (err)->
            assert.ifError err
            next()
            return
        return

    tearDown = setUp

    assertPartialThrows = (mapping, className, given, expected)->
        mapping[className] = given
        assert.throws ->
            pMgr = new PersistenceManager mapping
            return
        , (err)->
            err.code is expected
        , 'unexpected error'
        return

    assertPartial = (mapping, className, given, expected)->
        mapping[className] = given
        pMgr = new PersistenceManager mapping
        given = pMgr.getDefinition className
        for prop, value of expected
            assert.ok _.isEqual given[prop], value
        return

    testBasicMapping = (next)->
        logger.debug 'begin testBasicMapping'
        _next = next
        next = ->
            logger.debug 'finish testBasicMapping'
            _next()

        mapping = {}

        # Check consistency
        assertPartial mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'
        ,
            className: 'ClassA'
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'

        # String id is for name and column
        assertPartial mapping, 'ClassA',
            table: 'TableA'
            id: 'idA'
        ,
            table: 'TableA'
            id:
                name: 'idA'
                column: 'idA'

        # Empty id column is replaced by id name
        assertPartial mapping, 'ClassA',
            table: 'TableA'
            id: name: 'idA'
        ,
            table: 'TableA'
            id:
                name: 'idA'
                column: 'idA'

        # Column cannot be setted as undefined
        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'idA'
                column: undefined
        , 'ID_COLUMN'

        # Column cannot be setted as null
        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'idA'
                column: null
        , 'ID_COLUMN'

        # Column cannot be setted as not string
        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'idA'
                column: {}
        , 'ID_COLUMN'

        # Column cannot be setted as empty string
        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'idA'
                column: ''
        , 'ID_COLUMN'

        # default table name is className
        assertPartial mapping, 'ClassA',
            id:
                name: 'id'
                column: 'colIdA'
        ,
            table: 'ClassA'
            id:
                name: 'id'
                column: 'colIdA'

        next()
        return

    testBasicMapping2 = (next)->
        logger.debug 'begin testBasicMapping2'
        _next = next
        next = ->
            logger.debug 'finish testBasicMapping2'
            _next()

        mapping = {}

        # Check consistency
        assertPartial mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'
            properties:
                propA1:
                    column: 'colPropA1'
        ,
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'
            properties:
                propA1:
                    column: 'colPropA1'

        # Property as string => column name
        assertPartial mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'
            properties:
                propA1: 'colPropA1'
        ,
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'
            properties:
                propA1:
                    column: 'colPropA1'

        # Column key is mandatory for setted properties
        assertPartialThrows mapping, 'ClassA',
            id:
                name: 'id'
            properties:
                propA1:
                    toto: 'colPropA'
                propA2:
                    column: 'colPropA'
        , 'COLUMN'

        # Property cannot be null
        assertPartialThrows mapping, 'ClassA',
            id:
                name: 'id'
            properties:
                propA1: null
                propA2:
                    column: 'colPropA'
        , 'PROP'

        # Property cannot be undefined
        assertPartialThrows mapping, 'ClassA',
            id:
                name: 'id'
            properties:
                propA1: undefined
                propA2:
                    column: 'colPropA'
        , 'PROP'

        # Duplicate columns in id and properties
        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'
            properties:
                propA1:
                    column: 'colIdA'
        , 'DUP_COLUMN'

        # Duplicate columns, in properties
        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'
            properties:
                propA1:
                    column: 'colPropA'
                propA2:
                    column: 'colPropA'
        , 'DUP_COLUMN'

        next()
        return

    testInheritance = (next)->
        logger.debug 'begin testInheritance'
        _next = next
        next = ->
            logger.debug 'finish testInheritance'
            _next()

        mapping = {}

        # Parent is undefined
        assertPartialThrows mapping, 'ClassB',
            id:
                className: 'ClassA'
            properties:
                propB1: 'colPropB1'
                propB2: 'colPropB2'
        , 'UNDEF_CLASS'

        mapping['ClassA'] =
            id:
                name: 'idA'
                column: 'colIdA'

        # omitted id column becomes parent id column
        assertPartial mapping, 'ClassB',
            id:
                className: 'ClassA'
        ,
            className: 'ClassB'
            id:
                name: 'idA'
                className: 'ClassA'
                column: 'colIdA'

        # Check consitency
        assertPartial mapping, 'ClassB',
            id:
                className: 'ClassA'
                column: 'colIdB'
        ,
            id:
                name: 'idA'
                className: 'ClassA'
                column: 'colIdB'

        # Deep child, inherits it ancestor first setted properties
        mapping['ClassB'] =
            id:
                className: 'ClassA'
        assertPartial mapping, 'ClassC',
            id:
                className: 'ClassB'
        ,
            id:
                name: 'idA'
                className: 'ClassB'
                column: 'colIdA'

        # Deep child, inherits it ancestor first setted properties
        mapping['ClassB'] =
            id:
                column: 'colIdB'
                className: 'ClassA'
        assertPartial mapping, 'ClassC',
            id:
                className: 'ClassB'
        ,
            id:
                name: 'idA'
                className: 'ClassB'
                column: 'colIdB'
        delete mapping['ClassC']

        # Parent is considered as a mixin. Cannot appear as a mixin
        assertPartialThrows mapping, 'ClassB',
            id:
                className: 'ClassA'
            mixins: 'ClassA'
        , 'DUP_MIXIN'

        # mixin as string
        assertPartial mapping, 'ClassB',
            id:
                name: 'ClassB'
            mixins: 'ClassA'
        ,
            mixins: [
                className: 'ClassA'
                column: 'colIdA'
            ]

        # mixin as Array
        assertPartial mapping, 'ClassB',
            id:
                name: 'ClassB'
            mixins: ['ClassA']
        ,
            mixins: [
                className: 'ClassA'
                column: 'colIdA'
            ]

        # mixin as Array of object
        assertPartial mapping, 'ClassB',
            id:
                name: 'ClassB'
            mixins: [
                className: 'ClassA'
            ]
        ,
            mixins: [
                className: 'ClassA'
                column: 'colIdA'
            ]

        # Duplicate table
        assertPartialThrows mapping, 'ClassC',
            table: 'ClassA'
            id:
                name: 'idC'
            mixins: ['ClassB']
            properties:
                propC1: 'colPropC1'
        , 'DUP_TABLE'

        # mixin column take class id column
        mapping['ClassB'] =
            id:
                className: 'ClassA'
        assertPartial mapping, 'ClassC',
            id:
                name: 'idC'
            mixins: ['ClassB']
        ,
            mixins: [
                className: 'ClassB'
                column: 'colIdA'
            ]
        
        # Check consistency
        assertPartial mapping, 'ClassC',
            id:
                name: 'idC'
            mixins: [
                className: 'ClassB'
                column: 'colMixB'
            ]
        ,
            mixins: [
                className: 'ClassB'
                column: 'colMixB'
            ]
        
        # prop className, if no column, use id column
        assertPartial mapping, 'ClassC',
            id:
                name: 'idB'
            properties:
                propB1:
                    className: 'ClassB'
        ,
            properties:
                propB1:
                    column: 'colIdA'
                    className: 'ClassB'

        # if prop column name is given, it is preserved
        delete mapping['ClassC']
        assertPartial mapping, 'ClassB',
            id:
                name: 'idB'
            properties:
                propB1:
                    column: 'colPropB1'
                    className: 'ClassA'
        ,
            properties:
                propB1:
                    column: 'colPropB1'
                    className: 'ClassA'

        # test that, if not only normalize class are given in the mixins, 
        # throws an error, telling what class depends on which one
        mapping['ClassB'] = 
            id:
                className: 'ClassA'
        assertPartialThrows mapping, 'ClassC',
            id:
                className: 'ClassA'
            mixins: ['ClassB']
        , 'RELATED_MIXIN'

        assertPartialThrows mapping, 'ClassC',
            table: 'TableC'
            id:
                name: 'idC'
            mixins: [{
                className: 'ClassA'
                column: 'colIdA'
            },{ 
                className: 'ClassB'
                column: 'colIdB'
            }]
        , 'RELATED_MIXIN'

        next()
        return

    testCircularReference = (next)->
        logger.debug 'begin testCircularReference'
        _next = next
        next = ->
            logger.debug 'finish testCircularReference'
            _next()

        mapping = {}

        # A <- B <- C <- C
        mapping['ClassA'] =
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'

        mapping['ClassB'] =
            table: 'TableB'
            id:
                className: 'ClassA'

        assertPartialThrows mapping, 'ClassC',
            table: 'TableC'
            id:
                name: 'ClassC'
            mixins: ['ClassC']
        , 'CIRCULAR_REF'

        # A <- B + D <- C <- D
        mapping['ClassC'] =
            table: 'TableC'
            id:
                className: 'ClassD'
            mixins: ['ClassB']

        assertPartialThrows mapping, 'ClassD',
            table: 'TableD'
            id:
                className: 'ClassC'
        , 'CIRCULAR_REF'

        # D <- C <- D
        mapping['ClassC'] =
            table: 'TableC'
            id:
                name: 'ClassC'
            mixins: 'ClassD'

        assertPartialThrows mapping, 'ClassD',
            table: 'TableD'
            id:
                name: 'ClassD'
            mixins: 'ClassC'
        , 'CIRCULAR_REF'

        # A <- B <- C <- A
        mapping['ClassC'] =
            table: 'TableC'
            id:
                name: 'ClassC'
            mixins: 'ClassB'

        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'ClassA'
            mixins: 'ClassC'
        , 'CIRCULAR_REF'

        next()
        return

    testThrows = (next)->
        logger.debug 'begin testThrows'
        _next = next
        next = ->
            logger.debug 'finish testThrows'
            _next()

        mapping = {}

        # Undefined class in properties
        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'
            properties: 
                propA2:
                    className: 'colPropA2'
                propA3:
                    className: 'colPropA3'
                propA1: 'colPropA1'
        , 'UNDEF_CLASS'

        mapping['ClassA'] =
            id: 'idA'

        # Mixin column cannot be undefined
        assertPartialThrows mapping, 'ClassB',
            id: 'idB'
            mixins: [
                className: 'ClassA'
                column: undefined
            ]
        , 'MIXIN_COLUMN'

        # Mixin column cannot be null
        assertPartialThrows mapping, 'ClassB',
            id: 'idB'
            mixins: [
                className: 'ClassA'
                column: null
            ]
        , 'MIXIN_COLUMN'

        # Mixin column cannot be not a string
        assertPartialThrows mapping, 'ClassB',
            id: 'idB'
            mixins: [
                className: 'ClassA'
                column: {}
            ]
        , 'MIXIN_COLUMN'

        # Mixin column cannot be an empty string
        assertPartialThrows mapping, 'ClassB',
            id: 'idB'
            mixins: [
                className: 'ClassA'
                column: ''
            ]
        , 'MIXIN_COLUMN'

        # Table cannot be undefined
        assertPartialThrows mapping, 'ClassB',
            table: undefined
            id:
                name: 'id'
        , 'TABLE'

        # Table cannot be null
        assertPartialThrows mapping, 'ClassB',
            table: null
            id:
                name: 'id'
        , 'TABLE'

        # Table cannot be not a string
        assertPartialThrows mapping, 'ClassB',
            table: {}
            id:
                name: 'id'
        , 'TABLE'

        # Table cannot be an empty string
        assertPartialThrows mapping, 'ClassB',
            table: ''
            id:
                name: 'id'
        , 'TABLE'

        # Id Cannot be undefined
        assertPartialThrows mapping, 'ClassB',
            id: undefined
        , 'ID'
        
        # Id Cannot be null
        assertPartialThrows mapping, 'ClassB',
            id: null
        , 'ID'
        
        # Id Cannot be an empty string
        assertPartialThrows mapping, 'ClassB',
            id: ''
        , 'ID'
        
        # Mixins cannot be undefined
        assertPartialThrows mapping, 'ClassB',
            id:
                name: 'id'
            mixins: undefined
        , 'MIXINS'

        # Mixins cannot be null
        assertPartialThrows mapping, 'ClassB',
            id:
                name: 'id'
            mixins: null
        , 'MIXINS'

        # Mixins cannot be not a string and not an Array
        assertPartialThrows mapping, 'ClassB',
            id:
                name: 'id'
            mixins: {}
        , 'MIXINS'

        # Mixin must have a className prop if as Array
        assertPartialThrows mapping, 'ClassB',
            id:
                name: 'id'
            mixins: [
                id: 'toto'
            ]
        , 'MIXIN'

        # name and className cannot be both setted
        assertPartialThrows mapping, 'ClassB',
            id:
                name: 'id'
                className: 'toto'
        , 'INCOMP_ID'

        next()
        return

    assertInsertQuery = (mapping, model, className, expected)->
        model.className = className
        pMgr = new PersistenceManager mapping
        query = pMgr.getInsertQuery model
        assert.strictEqual query.toString(), expected
        return

    assertInsertQueryThrows = (mapping, model, className, expected, options)->
        model.className = className
        pMgr = new PersistenceManager mapping
        assert.throws ->
            pMgr.getInsertQuery model, options
            return
        , (err)->
            err.code is expected
        , 'unexpected error'
        return

    testInsertQuery = (next)->
        logger.debug 'begin testInsertQuery'
        _next = next
        next = ->
            logger.debug 'finish testInsertQuery'
            _next()

        mapping = {}

        class Model
            get: (prop)->
                return prop + 'Value'
            set: ->
            unset: ->
            toJSON: ->

        model = new Model()

        # id + properties
        mapping['ClassA'] =
            table: 'TableA'
            id:
                name: 'idA'
                column: 'colIdA'
            properties:
                propA1: 'colPropA1'
        assertInsertQuery mapping, model, 'ClassA', 'INSERT INTO TableA (colIdA, colPropA1) VALUES (\'idAValue\', \'propA1Value\')'

        # id + properties class
        class Model
            get: (prop)->
                if prop.substring(0, 9) is 'propClass'
                    return new Model()
                return prop + 'Value'
            set: ->
            unset: ->
            toJSON: ->

        model = new Model()

        mapping['ClassB'] =
            table: 'TableB'
            id:
                name: 'idB'
                column: 'colIdB'
            properties:
                propClassB1:
                    className: 'ClassA'
                propB2: 'colPropB2'
        
        assertInsertQuery mapping, model, 'ClassB', 'INSERT INTO TableB (colIdB, colIdA, colPropB2) VALUES (\'idBValue\', \'idAValue\', \'propB2Value\')'

        mapping['ClassB'] =
            table: 'TableB'
            id:
                name: 'idB'
                column: 'colIdB'
            properties:
                propClassB1:
                    column: 'colPropB1'
                    className: 'ClassA'
                propB2: 'colPropB2'
        
        assertInsertQuery mapping, model, 'ClassB', 'INSERT INTO TableB (colIdB, colPropB1, colPropB2) VALUES (\'idBValue\', \'idAValue\', \'propB2Value\')'

        # prop.className -> id.className -> id.className
        mapping['ClassB'] =
            table: 'TableB'
            id:
                className: 'ClassA'
        mapping['ClassC'] =
            table: 'TableC'
            id:
                name: 'idC'
            properties:
                propClassB1:
                    className: 'ClassB'
        assertInsertQuery mapping, model, 'ClassC', 'INSERT INTO TableC (idC, colIdA) VALUES (\'idCValue\', \'idAValue\')'
        
        # prop.className -> id.className -> id.className
        # 
        mapping['ClassB'] =
            table: 'TableB'
            id:
                column: 'colIdB'
                className: 'ClassA'
        mapping['ClassC'] =
            table: 'TableC'
            id:
                name: 'idC'
            properties:
                propClassB1:
                    className: 'ClassB'
        assertInsertQuery mapping, model, 'ClassC', 'INSERT INTO TableC (idC, colIdB) VALUES (\'idCValue\', \'idAValue\')'
        
        # prop.className -> id.className -> id.className
        mapping['ClassB'] =
            table: 'TableB'
            id:
                className: 'ClassA'
        mapping['ClassC'] =
            table: 'TableC'
            id:
                className: 'ClassB'
        mapping['ClassD'] =
            table: 'TableD'
            id:
                name: 'idD'
            properties:
                propClassC1:
                    className: 'ClassC'
        assertInsertQuery mapping, model, 'ClassD', 'INSERT INTO TableD (idD, colIdA) VALUES (\'idDValue\', \'idAValue\')'
        
        # prop.className -> id.className -> id.className
        mapping['ClassB'] =
            table: 'TableB'
            id:
                column: 'colIdB'
                className: 'ClassA'
        mapping['ClassC'] =
            table: 'TableC'
            id:
                className: 'ClassB'
        mapping['ClassD'] =
            table: 'TableD'
            id:
                name: 'idD'
            properties:
                propClassC1:
                    className: 'ClassC'
        assertInsertQuery mapping, model, 'ClassD', 'INSERT INTO TableD (idD, colIdB) VALUES (\'idDValue\', \'idAValue\')'
        
        # prop.className -> id.className -> id.className
        mapping['ClassB'] =
            table: 'TableB'
            id:
                column: 'colIdB'
                className: 'ClassA'
        mapping['ClassC'] =
            table: 'TableC'
            id:
                column: 'colIdC'
                className: 'ClassB'
        mapping['ClassD'] =
            table: 'TableD'
            id:
                name: 'idD'
            properties:
                propClassC1:
                    className: 'ClassC'
        assertInsertQuery mapping, model, 'ClassD', 'INSERT INTO TableD (idD, colIdC) VALUES (\'idDValue\', \'idAValue\')'
        
        # throw error if no id is setted for sub-element
        class Model
            get: (prop)->
                if prop is 'idA'
                    return
                if prop.substring(0, 9) is 'propClass'
                    return new Model()
                return prop + 'Value'
            set: ->
            unset: ->
            toJSON: ->
        model = new Model()
        assertInsertQueryThrows mapping, model, 'ClassD', 'NO_ID'
        
        # only save setted properties
        class Model
            get: (prop)->
                if prop.charAt(prop.length - 1) is '2'
                    return
                if prop.substring(0, 9) is 'propClass'
                    return new Model()
                return prop + 'Value'
            set: ->
            unset: ->
            toJSON: ->
        model = new Model()

        mapping['ClassD'] =
            table: 'TableD'
            id:
                name: 'idD'
            properties:
                propClassC1:
                    className: 'ClassC'
                propD1: 'colPropD1'
                propD2: 'colPropD2'
                propD3: 'colPropD3'
        assertInsertQuery mapping, model, 'ClassD', 'INSERT INTO TableD (idD, colIdC, colPropD1, colPropD3) VALUES (\'idDValue\', \'idAValue\', \'propD1Value\', \'propD3Value\')'
        
        # id className
        class Model
            constructor: (@preffix = '')->
            get: (prop)->
                if prop.charAt(prop.length - 1) is '2'
                    return
                if prop.substring(0, 9) is 'propClass'
                    return new Model prop.substring 9
                return prop + @preffix + 'Value'
            set: ->
            unset: ->
            toJSON: ->
        model = new Model()
        model.className = 'ClassB'

        delete mapping['ClassC']
        delete mapping['ClassD']
        mapping['ClassA'] =
            table: 'TableA'
            id:
                name: 'idA'
                column: 'colIdA'
            properties:
                propA1: 'colPropA1'
                propA2: 'colPropA2'
                propA3: 'colPropA3'

        mapping['ClassB'] =
            table: 'TableB'
            id:
                className: 'ClassA'
            properties:
                propClassB0:
                    column: 'colPropB0'
                    className: 'ClassA'
                propB1: 'colPropB1'
                propB2: 'colPropB2'
                propB3: 'colPropB3'

        pMgr = new PersistenceManager mapping
        query = pMgr.getInsertQuery model
        query = query.toParam()
        assert.strictEqual query.text, 'INSERT INTO TableB (colIdA, colPropB0, colPropB1, colPropB3) VALUES (?, ?, ?, ?)'
        assert.strictEqual query.values[1], 'idAB0Value'
        assert.strictEqual query.values[2], 'propB1Value'
        assert.strictEqual query.values[3], 'propB3Value'
        query = query.values[0]
        assert.strictEqual query.toString(), 'INSERT INTO TableA (colIdA, colPropA1, colPropA3) VALUES (\'idAValue\', \'propA1Value\', \'propA3Value\')'
        
        # id, mixin
        mapping['ClassB'] =
            table: 'TableB'
            id:
                name: 'idB'
                column: 'colIdB'
            mixins: 'ClassA'
            properties:
                propClassB0:
                    column: 'colPropB0'
                    className: 'ClassA'
                propB1: 'colPropB1'
                propB2: 'colPropB2'
                propB3: 'colPropB3'
        pMgr = new PersistenceManager mapping
        query = pMgr.getInsertQuery model
        query = query.toParam()
        assert.strictEqual query.text, 'INSERT INTO TableB (colIdA, colIdB, colPropB0, colPropB1, colPropB3) VALUES (?, ?, ?, ?, ?)'
        assert.strictEqual query.values[1], 'idBValue'
        assert.strictEqual query.values[2], 'idAB0Value'
        assert.strictEqual query.values[3], 'propB1Value'
        assert.strictEqual query.values[4], 'propB3Value'
        query2 = query.values[0]
        assert.strictEqual query2.toString(), 'INSERT INTO TableA (colIdA, colPropA1, colPropA3) VALUES (\'idAValue\', \'propA1Value\', \'propA3Value\')'
        
        # id, mixins
        mapping['ClassB'] =
            table: 'TableB'
            id:
                name: 'idB'
                column: 'colIdB'
            properties:
                propClassB0:
                    column: 'colPropB0'
                    className: 'ClassA'
                propB1: 'colPropB1'
                propB2: 'colPropB2'
                propB3: 'colPropB3'

        mapping['ClassC'] =
            table: 'TableC'
            id:
                name: 'idC'
                column: 'colIdC'
            mixins: ['ClassA', 'ClassB']
            properties:
                propClassC0:
                    column: 'colPropC0'
                    className: 'ClassA'
                propC1: 'colPropC1'
                propC2: 'colPropC2'
                propC3: 'colPropC3'
        pMgr = new PersistenceManager mapping
        model.className = 'ClassC'
        query = pMgr.getInsertQuery model
        query = query.toParam()
        assert.strictEqual query.text, 'INSERT INTO TableC (colIdA, colIdB, colIdC, colPropC0, colPropC1, colPropC3) VALUES (?, ?, ?, ?, ?, ?)'
        assert.strictEqual query.values[2], 'idCValue'
        assert.strictEqual query.values[3], 'idAC0Value'
        assert.strictEqual query.values[4], 'propC1Value'
        assert.strictEqual query.values[5], 'propC3Value'
        query2 = query.values[0]
        assert.strictEqual query2.toString(), 'INSERT INTO TableA (colIdA, colPropA1, colPropA3) VALUES (\'idAValue\', \'propA1Value\', \'propA3Value\')'
        query2 = query.values[1]
        assert.strictEqual query2.toString(), 'INSERT INTO TableB (colIdB, colPropB0, colPropB1, colPropB3) VALUES (\'idBValue\', \'idAB0Value\', \'propB1Value\', \'propB3Value\')'

        next()
        return

    assertPersist = (pMgr, model, classNameLetter, id, connector, next)->
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

    setUpMapping = ->
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

        connector = poolWrite.createConnector()

        return [pMgr, model, connector, Model, mapping]

    testGetColumn = (next)->
        logger.debug 'begin testGetColumn'
        _next = next
        next = ->
            logger.debug 'finish testGetColumn'
            _next()

        # check get column names

        [pMgr, model, connector, Model] = setUpMapping()
        assert.strictEqual pMgr.getColumn('ClassA', 'idA'), 'A_ID'
        assert.strictEqual pMgr.getColumn('ClassA', 'propA1'), 'PROP_A1'
        assert.strictEqual pMgr.getColumn('ClassA', 'propA2'), 'PROP_A2'
        assert.strictEqual pMgr.getColumn('ClassA', 'propA3'), 'PROP_A3'
        next()
        return

    testInsertBasic = (next)->
        logger.debug 'begin testInsertBasic'
        _next = next
        next = ->
            logger.debug 'finish testInsertBasic'
            _next()

        # insert on class with no relation should work
        
        [pMgr, model, connector] = setUpMapping()
        model.className = 'ClassA'

        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.insert model, {connector: connector}, next
            (id, next)-> assertPersist pMgr, model, 'A', id, connector, next
            (row, next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return
        return

    testInsertSubClass = (next)->
        logger.debug 'begin testInsertSubClass'
        _next = next
        next = ->
            logger.debug 'finish testInsertSubClass'
            _next()

        # insert on class with parent should also insert in parent table with the correct id
        
        [pMgr, model, connector] = setUpMapping()
        model.className = 'ClassB'
        query = pMgr.getInsertQuery model, {connector: connector, dialect: connector.getDialect()}

        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> query.execute connector, next
            (id, next)-> assertPersist pMgr, model, 'B', id, connector, next
            (row, next)-> assertPersist pMgr, model, 'A', row, connector, next
            (row, next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return
        return

    testInsertMixin = (next)->
        logger.debug 'begin testInsertMixin'
        _next = next
        next = ->
            logger.debug 'finish testInsertMixin'
            _next()

        # insert on class with mixins should also insert in mixins table with the correct id
        # one final parent and one final mixin

        [pMgr, model, connector] = setUpMapping()
        model.className = 'ClassD'
        rowD = null

        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.insert model, {connector: connector}, next
            (id, next)-> assertPersist pMgr, model, 'D', id, connector, next
            (row, next)->
                rowD = row
                # Mixin must have the correct id
                assertPersist pMgr, model, 'C', row, connector, next
                return
            # Inherited parent must have the correct id
            (row, next)-> assertPersist pMgr, model, 'A', rowD, connector, next
            (row, next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return

        return

    testInsertMixin2 = (next)->
        logger.debug 'begin testInsertMixin2'
        _next = next
        next = ->
            logger.debug 'finish testInsertMixin2'
            _next()

        # insert on class with mixins should also insert in mixins table with the correct id
        # one parent that has inheritance and one final mixin

        [pMgr, model, connector] = setUpMapping()
        model.className = 'ClassE'

        rowE = null
        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.insert model, {connector: connector}, next
            (id, next)-> assertPersist pMgr, model, 'E', id, connector, next
            (row, next)->
                rowE = row
                # Mixin must have the correct id
                assertPersist pMgr, model, 'C', row, connector, next
                return

            # Inherited parent must have the correct id
            (row, next)-> assertPersist pMgr, model, 'B', rowE, connector, next

            # Inherited parent of inherited parent must have the correct id
            (row, next)-> assertPersist pMgr, model, 'A', row, connector, next
            (row, next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return

        return

    assertList = (pMgr, options, next)->
        classNameLetter = options.classNameLetter
        listOptions = options.listOptions

        className = 'Class' + classNameLetter
        pMgr.list className, listOptions, (err, models)->
            return next err if err
            assert.ok models.length > 0
            next err, models
            return
        return

    assertProperties = (letters, pModel, model)->
        for letter in letters
            for index in [1..3] by 1
                prop = 'prop' + letter + index
                assert.strictEqual model.get(prop), pModel.get prop
        return

    assertListUnique = (pMgr, options, next)->
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

    testListBasic = (next)->
        logger.debug 'begin testListBasic'
        _next = next
        next = ->
            logger.debug 'finish testListBasic'
            _next()

        # Test list of inserted items in a with no relations
        # Test where condition
        
        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassA'

        options =
            classNameLetter: 'A'
            model: model
            listOptions:
                connector: connector

        id1 = id2 = null
        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.insert model, {connector: connector}, next
            (id, next)->
                id1 = id
                # The inserted item should be the only one in database
                assertListUnique pMgr, options, next
                return
            (_model, next)->
                # The inserted item id should be the returned one by insert method
                options.listOptions.where = '{idA} = ' + id1
                assertListUnique pMgr, options, next
                return
            (_model, next)->
                # Properties must have been saved
                options.listOptions.where = '{propA1} = ' + connector.escape model.get 'propA1'
                assertListUnique pMgr, options, next
                return
            (_model, next)->
                model.set 'propA1', 'value'
                pMgr.insert model, {connector: connector}, next
                return
            (id, next)->
                id2 = id
                options.listOptions.where = [
                    '{idA} = __idA__'
                    '{propA1} = __propA1__'
                ]
                options.listOptions.values =
                    idA: id
                    propA1: connector.escape model.get 'propA1'
                # Inserting new items should not changed properties of existing items
                assertListUnique pMgr, options, next
                return
            (_model, next)->
                # Test where condition
                column = '{propA1}'
                condition1 = column + ' = __val1__' 
                condition2 = column +  ' = __val2__'
                options.listOptions.where = [
                    squel.expr().and( condition1 ).or condition2 
                ]
                options.listOptions.values =
                    val1: connector.escape 'propA1Value'
                    val2: connector.escape 'value'
                assertList pMgr, options, next
                return
            (models, next)->
                # query should returned both inserted items
                assert.strictEqual models.length, 2

                # returned properties must be correct
                assert.strictEqual 'propA1Value', models[0].get 'propA1'
                assert.strictEqual 'value', models[1].get 'propA1'
                assert.strictEqual id1, models[0].get 'idA'
                assert.strictEqual id2, models[1].get 'idA'

                # Inertiing new items should not insert other items
                options.listOptions.where = '{propA1} = ' + connector.escape model.get 'propA1'
                assertListUnique pMgr, options, next
                return
            (_model, next)->
                # Insert new item with propA2 changed
                model.set 'propA2', 'value'
                pMgr.insert model, {connector: connector}, next
                return
            (id, next)-> assertList pMgr, options, next
            (models, next)->
                # There should be only 2 items with the same propA1 value
                assert.strictEqual models.length, 2
                assert.strictEqual 'propA2Value', models[0].get 'propA2'
                assert.strictEqual 'value', models[1].get 'propA2'

                delete options.listOptions.where
                assertList pMgr, options, next
                return
            (models, next)->
                # There should be only 3 items
                assert.strictEqual models.length, 3

                # insert class with no id
                model.className = 'ClassH'
                pMgr.insert model, {connector: connector}, next
                return
            (id, next)->
                # H has no id
                assert.ok !id
                options.classNameLetter = 'H'
                assertListUnique pMgr, options, next
                return
            (_model, next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return
        return

    testListSubClass = (next)->
        logger.debug 'begin testListSubClass'
        _next = next
        next = ->
            logger.debug 'finish testListSubClass'
            _next()

        # Test list on a class that has an inherited parent

        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassB'

        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.insert model, {connector: connector}, next
            (id, next)->
                options =
                    classNameLetter: 'B'
                    model: model
                    letters: ['A', 'B']
                    listOptions:
                        where: '{idA} = ' + id
                        connector: connector

                # Listing  classB should returned properties of ClassA and ClassB
                assertListUnique pMgr, options, next
                return
            (models, next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return

        return

    testListMixin = (next)->
        logger.debug 'begin testListMixin'
        _next = next
        next = ->
            logger.debug 'finish testListMixin'
            _next()

        # Test list on a class with parent and mixins

        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassD'

        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.insert model, {connector: connector}, next
            (id, next)->
                options =
                    classNameLetter: 'D'
                    model: model
                    letters: ['A', 'C', 'D']
                    listOptions:
                        where: '{idA} = ' + id
                        connector: connector

                # Listing  classD should returned properties of ClassA, ClassC and ClassD
                assertListUnique pMgr, options, next
                return
            (models, next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return

        return

    testListMixin2 = (next)->
        logger.debug 'begin testListMixin2'
        _next = next
        next = ->
            logger.debug 'finish testListMixin2'
            _next()

        # Test list of class with nested parent inheritance

        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassE'

        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.insert model, {connector: connector}, next
            (id, next)->
                options =
                    classNameLetter: 'E'
                    model: model
                    letters: ['A', 'B', 'C', 'E']
                    listOptions:
                        where: '{idA} = ' + id
                        connector: connector

                # Listing classD should returned properties of all related classes
                assertListUnique pMgr, options, next
                return
            (models, next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return

        return

    assertPropSubClass = (modelF, modelD, modelE)->
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

    testListPropSubClass = (next)->
        logger.debug 'begin testListPropSubClass'
        _next = next
        next = ->
            logger.debug 'finish testListPropSubClass'
            _next()

        # Test listing properties that are classes

        [pMgr, model, connector, Model] = setUpMapping()
        modelF = model.clone()
        modelF.className = 'ClassF'
        modelE = model.clone()
        modelE.className = 'ClassE'
        modelD = model.clone()
        modelD.className = 'ClassD'
        modelF.set 'propClassD', modelD
        modelF.set 'propClassE', modelE

        newE1Value = 'value1'
        newFC1Value = 'value2'

        options = null
        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.insert modelD, {connector: connector, reflect: true}, next
            (id, next)->
                pMgr.insert modelE, {connector: connector}, next
                return
            (id, next)->
                # modelE will be used for multiple insert.
                # Using reflect will cause every related class to have an id, therefore preventing new insertion of the same object
                modelE.set pMgr.getIdName('ClassE'), id
                pMgr.insert modelF, {connector: connector}, next
                return
            (id, next)->
                options =
                    classNameLetter: 'F'
                    model: modelF
                    letters: ['C', 'F']
                    listOptions:
                        where: '{' + pMgr.getIdName('ClassF') + '} = ' + id
                        connector: connector
                assertListUnique pMgr, options, next
                return
            (model, next)->
                # List must returned property class properties
                assertPropSubClass model, modelD, modelE
                modelE.set 'propA1', newE1Value
                modelF.set 'propC1', newFC1Value
                modelE.unset pMgr.getIdName 'ClassE'
                pMgr.insert modelE, {connector: connector}, next
                return
            (id, next)->
                modelE.set pMgr.getIdName('ClassE'), id
                pMgr.insert modelF, {connector: connector}, next
                return
            (id, next)->
                options.listOptions.where = '{propC1} = ' + connector.escape newFC1Value
                assertListUnique pMgr, options, next
                return
            (model, next)->
                # Check persistence of new values
                assertPropSubClass model, modelD, modelE

                # Test filter on property class sub property
                options.listOptions.where = '{propClassE:propA1} = ' + connector.escape newE1Value
                assertListUnique pMgr, options, next
                return
            (model, next)->
                assertPropSubClass model, modelD, modelE

                # Test filter on property class sub property
                options.listOptions.where = [
                    '{propClassE:propA1} = ' + connector.escape newE1Value
                    '{propC1} = ' + connector.escape newFC1Value
                ]
                assertListUnique pMgr, options, next
                return
            (model, next)->
                assertPropSubClass model, modelD, modelE

                # Test filter on property class sub property
                options.listOptions.where = [
                    '{propClassE:propA1} = ' + connector.escape 'propA1Value'
                    '{propC1} = ' + connector.escape newFC1Value
                ]
                pMgr.list 'ClassF', options.listOptions, next
                return
            (models, next)->
                assert.strictEqual models.length, 0
                pMgr.insert modelF, {connector: connector}, next
                return
            (id, next)-> pMgr.insert modelF, {connector: connector}, next
            (id, next)-> pMgr.list 'ClassF', {
                connector: connector
                where: '{propC1} = ' + connector.escape modelF.get 'propC1'
            }, next
            (models, next)->
                assert.strictEqual models.length, 3
                for model in models
                    assertProperties options.letters, model, modelF
                    assertPropSubClass model, modelD, modelE
                next()
                return
            (next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return
        return

    testHandlersAndListField = (next)->
        logger.debug 'begin testHandlersAndListField'
        _next = next
        next = ->
            logger.debug 'finish testHandlersAndListField'
            _next()

        # Test listing with only selected fields
        # Test handlers

        [pMgr, model, connector, Model] = setUpMapping()
        modelF = model.clone()
        modelF.className = 'ClassF'
        modelE = model.clone()
        modelE.className = 'ClassE'
        modelD = model.clone()
        modelD.className = 'ClassD'
        modelF.set 'propClassD', modelD
        modelF.set 'propClassE', modelE

        newD1Value = 'value0'
        newE1Value = 'value1'
        newF1Value = 'value2'

        id0 = null
        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.insert modelD, {connector: connector, reflect: true}, next
            (id, next)->
                idName = pMgr.getIdName 'ClassD'
                id0 = id

                assert.strictEqual id, modelD.get idName
                creationDate = modelD.get 'creationDate'
                modificationDate = modelD.get 'modificationDate'
                assert.ok creationDate instanceof Date
                assert.ok modificationDate instanceof Date
                creationDate = moment creationDate
                modificationDate = moment modificationDate
                assert.ok Math.abs(modificationDate.diff(creationDate)) < 2

                now = moment()

                # give less than 1500ms to save data
                assert.ok Math.abs(now.diff(creationDate)) < 1500
                assert.ok Math.abs(now.diff(modificationDate)) < 1500

                # initialize using attribute with handler write
                model = new Model()
                model.className = 'ClassD'
                options =
                    connector: connector
                    attributes: creationDate: modelD.get 'creationDate'
                pMgr.initialize model, options, next
                return
            (models, next)->
                assert.strictEqual models.length, 1
                creationDate = moment models[0].get 'creationDate'
                assert.ok 1500 > Math.abs creationDate.diff modelD.get 'creationDate'

                # list using attribute with handler write
                options =
                    connector: connector
                    attributes: creationDate: modelD.get 'creationDate'
                pMgr.list 'ClassD', options, next
                return
            (models, next)->
                assert.strictEqual models.length, 1
                creationDate = moment models[0].get 'creationDate'
                assert.ok 1500 > Math.abs creationDate.diff modelD.get 'creationDate'
                pMgr.insert modelE, {connector: connector, reflect: true}, next
                return
            (id, next)->
                assert.strictEqual id, modelE.get pMgr.getIdName 'ClassE'
                modificationDate = moment modelE.get 'modificationDate'
                creationDate = moment modelE.get 'creationDate'
                assert.ok Math.abs(modificationDate.diff(creationDate)) < 2
                now = moment()
                assert.ok Math.abs(now.diff(creationDate)) < 1500
                assert.ok Math.abs(now.diff(modificationDate)) < 1500
                pMgr.insert modelF, {connector: connector, reflect: true}, next
                return
            (id, next)->
                assert.strictEqual id, modelF.get pMgr.getIdName 'ClassF'
                modelD.unset pMgr.getIdName 'ClassC'
                modelD.unset pMgr.getIdName 'ClassD'
                modelE.unset pMgr.getIdName 'ClassC'
                modelE.unset pMgr.getIdName 'ClassE'
                modelF.unset pMgr.getIdName 'ClassF'
                modelD.set 'propA1', newD1Value
                modelE.set 'propA1', newE1Value
                modelF.set 'propC1', newF1Value
                pMgr.insert modelD, {connector: connector, reflect: true}, next
                return
            (id, next)-> pMgr.insert modelE, {connector: connector, reflect: true}, next
            (id, next)-> pMgr.insert modelF, {connector: connector, reflect: true}, next
            (id, next)->
                options =
                    classNameLetter: 'F'
                    model: modelF
                    letters: ['C', 'F']
                    listOptions:
                        type: 'json'
                        fields: [
                            'propC1'
                            'propClassD:propA1'
                            'propClassE:propA1'
                        ]
                        where: [
                            '{propClassD:propA1} = ' + connector.escape newD1Value
                            '{propClassE:propA1} = ' + connector.escape newE1Value
                            '{propC1} = ' + connector.escape newF1Value
                        ]
                        connector: connector

                assertList pMgr, options, next
                return
            (models, next)->
                assert.strictEqual models.length, 1
                model = models[0]
                assert.ok _.isPlainObject model
                assert.strictEqual model.propClassD.propA1, modelD.get 'propA1'
                assert.strictEqual model.propClassE.propA1, modelE.get 'propA1'
                assert.strictEqual model.propC1, modelF.get 'propC1'
                next()
                return
            (next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return

        return

    testUpdate = (next)->
        logger.debug 'begin testUpdate'
        _next = next
        next = ->
            logger.debug 'finish testUpdate'
            _next()

        [pMgr, model, connector, Model] = setUpMapping()
        modelF = model.clone()
        modelF.className = 'ClassF'
        modelE = model.clone()
        modelE.className = 'ClassE'
        modelD = model.clone()
        modelD.className = 'ClassD'
        modelF.set 'propClassD', modelD
        modelF.set 'propClassE', modelE

        newD1Value = 'value0'
        newE1Value = 'value1'
        newF1Value = 'value2'

        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.insert modelD, {connector: connector, reflect: true}, next
            (id, next)-> pMgr.insert modelE, {connector: connector, reflect: true}, next
            (id, next)-> pMgr.insert modelF, {connector: connector, reflect: true}, next
            (id, next)->
                modelD.unset pMgr.getIdName 'ClassC'
                modelD.unset pMgr.getIdName 'ClassD'
                modelE.unset pMgr.getIdName 'ClassC'
                modelE.unset pMgr.getIdName 'ClassE'
                modelF.unset pMgr.getIdName 'ClassF'
                pMgr.insert modelD, {connector: connector, reflect: true}, next
                return
            (id, next)-> pMgr.insert modelE, {connector: connector, reflect: true}, next
            (id, next)-> pMgr.insert modelF, {connector: connector, reflect: true}, next
            (id, next)->
                modelD.set 'propA1', newD1Value
                modelE.set 'propA1', newE1Value
                modelF.set 'propC1', newF1Value
                pMgr.update modelD, {connector: connector}, next
                return
            (id, msg, next)-> pMgr.update modelE, {connector: connector}, next
            (id, msg, next)-> pMgr.update modelF, {connector: connector}, next
            (id, msg, next)->
                assert.strictEqual typeof msg, 'undefined'
                pMgr.update modelF, {connector: connector}, next
                return
            (id, msg, next)->
                assert.strictEqual msg, 'no-update'
                options =
                    classNameLetter: 'F'
                    model: modelF
                    letters: ['C', 'F']
                    listOptions:
                        where: [
                            '{propClassD:propA1} = ' + connector.escape newD1Value
                            '{propClassE:propA1} = ' + connector.escape newE1Value
                            '{propC1} = ' + connector.escape newF1Value
                        ]
                        connector: connector
                assertListUnique pMgr, options, next
                return
            (model, next)->
                assertPropSubClass model, modelD, modelE
                next()
                return
            (next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return

        return

    assertCount = (pMgr, expected, connector, next)->
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

    testDelete = (next)->
        logger.debug 'begin testDelete'
        _next = next
        next = ->
            logger.debug 'finish testDelete'
            _next()

        [pMgr, model, connector, Model] = setUpMapping()
        modelF = model.clone()
        modelF.className = 'ClassF'
        modelE = model.clone()
        modelE.className = 'ClassE'
        modelD = model.clone()
        modelD.className = 'ClassD'
        modelF.set 'propClassD', modelD
        modelF.set 'propClassE', modelE

        # F -> C
        # E -> (B -> A), C
        # D -> A, C

        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.insert modelD, {connector: connector, reflect: true}, next
            (id, next)-> pMgr.insert modelE, {connector: connector, reflect: true}, next
            (id, next)-> pMgr.insert modelF, {connector: connector}, next
            (id, next)-> assertCount pMgr, [2, 1, 3, 1, 1, 1], connector, next
            (next)->
                modelD.unset pMgr.getIdName 'ClassC'
                modelD.unset pMgr.getIdName 'ClassD'
                modelE.unset pMgr.getIdName 'ClassC'
                modelE.unset pMgr.getIdName 'ClassE'
                pMgr.insert modelD, {connector: connector, reflect: true}, next
                return
            (id, next)-> pMgr.insert modelE, {connector: connector, reflect: true}, next
            (id, next)-> pMgr.insert modelF, {connector: connector, reflect: true}, next
            (id, next)-> assertCount pMgr, [4, 2, 6, 2, 2, 2], connector, next
            (next)-> pMgr.delete modelF, {connector: connector}, next
            (res, next)->
                assert.strictEqual res.affectedRows, 1
                assertCount pMgr, [4, 2, 5, 2, 2, 1], connector, next
                return
            (next)-> pMgr.delete modelE, {connector: connector}, next
            (res, next)->
                assert.strictEqual res.affectedRows, 1
                assertCount pMgr, [3, 1, 4, 2, 1, 1], connector, next
                return
            (next)-> pMgr.delete modelD, {connector: connector}, next
            (res, next)->
                assert.strictEqual res.affectedRows, 1
                assertCount pMgr, [2, 1, 3, 1, 1, 1], connector, next
                return
            (next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return

        return

    testSave = (next)->
        logger.debug 'begin testSave'
        _next = next
        next = ->
            logger.debug 'finish testSave'
            _next()

        [pMgr, model, connector, Model] = setUpMapping()
        modelF = model.clone()
        modelF.className = 'ClassF'
        modelE = model.clone()
        modelE.className = 'ClassE'
        modelD = model.clone()
        modelD.className = 'ClassD'
        modelF.set 'propClassD', modelD
        modelF.set 'propClassE', modelE

        newD1Value = 'value0'
        newE1Value = 'value1'
        newF1Value = 'value2'

        # F -> C
        # E -> (B -> A), C
        # D -> A, C

        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.save modelD, {connector: connector}, next
            (id, next)->
                assert.strictEqual id, modelD.get pMgr.getIdName modelD.className
                pMgr.save modelE, {connector: connector}, next
                return
            (id, next)->
                assert.strictEqual id, modelE.get pMgr.getIdName modelE.className
                pMgr.save modelF, {connector: connector}, next
                return
            (id, next)->
                assert.strictEqual id, modelF.get pMgr.getIdName modelF.className
                modelD.unset pMgr.getIdName 'ClassC'
                modelD.unset pMgr.getIdName 'ClassD'
                modelE.unset pMgr.getIdName 'ClassC'
                modelE.unset pMgr.getIdName 'ClassE'
                modelF.unset pMgr.getIdName 'ClassF'
                pMgr.save modelD, {connector: connector}, next
                return
            (id, next)->
                assert.strictEqual id, modelD.get pMgr.getIdName modelD.className
                modelD.prevId = modelD.get pMgr.getIdName modelD.className
                pMgr.save modelE, {connector: connector}, next
                return
            (id, next)->
                assert.strictEqual id, modelE.get pMgr.getIdName modelE.className
                modelE.prevId = modelE.get pMgr.getIdName modelE.className
                pMgr.save modelF, {connector: connector}, next
                return
            (id, next)->
                modelF.prevId = modelF.get pMgr.getIdName modelF.className
                modelD.set 'propA1', newD1Value
                modelE.set 'propA1', newE1Value
                modelF.set 'propC1', newF1Value
                pMgr.save modelD, {connector: connector}, next
                return
            (id, msg, next)->
                assert.strictEqual 'function', typeof next
                assert.strictEqual newD1Value, modelD.get 'propA1'
                assert.strictEqual id, modelD.get pMgr.getIdName modelD.className
                assert.strictEqual id, modelD.prevId
                pMgr.save modelE, {connector: connector}, next
                return
            (id, msg, next)->
                assert.strictEqual 'function', typeof next
                assert.strictEqual newE1Value, modelE.get 'propA1'
                assert.strictEqual id, modelE.get pMgr.getIdName modelE.className
                assert.strictEqual id, modelE.prevId
                pMgr.save modelF, {connector: connector}, next
                return
            (id, msg, next)->
                assert.strictEqual 'function', typeof next
                assert.strictEqual newF1Value, modelF.get 'propC1'
                assert.strictEqual id, modelF.get pMgr.getIdName modelF.className
                assert.strictEqual id, modelF.prevId
                options =
                    classNameLetter: 'F'
                    model: modelF
                    letters: ['C', 'F']
                    listOptions:
                        where: [
                            '{propClassD:propA1} = ' + connector.escape newD1Value
                            '{propClassE:propA1} = ' + connector.escape newE1Value
                            '{propC1} = ' + connector.escape newF1Value
                        ]
                        connector: connector
                assertListUnique pMgr, options, next
                return
            (model, next)->
                assertPropSubClass model, modelD, modelE
                next()
                return
            (next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return

        return

    testIssue1 = (next)->
        logger.debug 'begin testIssue1'
        _next = next
        next = ->
            logger.debug 'finish testIssue1'
            _next()

        # Saving model with an unset propClass throws exception
        
        [pMgr, model, connector, Model] = setUpMapping()
        modelF = model.clone()
        modelF.className = 'ClassF'
        modelD = model.clone()
        modelD.className = 'ClassD'
        modelF.set 'propClassD', modelD
        modelF.set 'propClassE', null

        # F -> C
        # E -> (B -> A), C
        # D -> A, C

        options = null
        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.save modelD, {connector: connector}, next
            (id, next)-> pMgr.insert modelF, {connector: connector}, next
            (id, next)->
                options =
                    classNameLetter: 'F'
                    model: modelF
                    letters: ['C', 'F']
                    listOptions:
                        connector: connector
                assertListUnique pMgr, options, next
                return
            (model, next)->
                assertPropSubClass model, modelD
                assert.strictEqual model.get('propClassE'), null
                _options = _.clone options
                _options.listOptions =
                    connector: connector
                    attributes:
                        propClassE: null
                assertListUnique pMgr, _options, next
                return
            (model, next)-> pMgr.delete model, {connector: connector}, next
            (res, next)->
                modelF.set 'propClassE', ''
                pMgr.insert modelF, {connector: connector}, next
                return
            (id, next)-> assertListUnique pMgr, options, next
            (model, next)->
                assertPropSubClass model, modelD
                assert.strictEqual model.get('propClassE'), null
                pMgr.delete model, {connector: connector}, next
                return
            (res, next)->
                modelF.set 'propClassD', modelD.get pMgr.getIdName 'ClassD'
                modelF.unset 'propClassE'
                pMgr.insert modelF, {connector: connector}, next
                return
            (id, next)-> assertListUnique pMgr, options, next
            (model, next)->
                assertPropSubClass model, modelD
                assert.strictEqual model.get('propClassE'), null
                pMgr.delete model, {connector: connector}, next
                return
            (res, next)-> 
                modelF.set 'propClassD', parseInt modelD.get(pMgr.getIdName 'ClassD'), 10
                modelF.unset 'propClassE'
                pMgr.insert modelF, {connector: connector}, next
                return
            (id, next)-> assertListUnique pMgr, options, next
            (model, next)->
                assertPropSubClass model, modelD
                assert.strictEqual model.get('propClassE'), null
                pMgr.save modelF, {connector: connector}, next
                return
            (id, next)->
                assert.strictEqual id, modelF.get pMgr.getIdName modelF.className
                options.listOptions.where = [
                    '{idC} = ' + id
                ]
                pMgr.list 'ClassF', {connector: connector, count: true}, next
                return
            (count, next)->
                assert.strictEqual count, 2
                assertListUnique pMgr, options, next
                return
            (model, next)->
                assertPropSubClass model, modelD
                next()
                return
            (next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return

        return

    testIssue2 = (next)->
        logger.debug 'begin testIssue2'
        _next = next
        next = ->
            logger.debug 'finish testIssue2'
            _next()

        # Combination of where and fields throws on certain circumstances
        
        [pMgr, model, connector, Model] = setUpMapping()
        modelF = model.clone()
        modelF.className = 'ClassF'
        modelD = model.clone()
        modelD.className = 'ClassD'
        modelF.set 'propClassD', modelD

        # F -> C
        # E -> (B -> A), C
        # D -> A, C

        idD = null
        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.save modelD, {connector: connector}, next
            (id, next)->
                idD = id
                pMgr.save modelF, {connector: connector}, next
                return
            (id, next)->
                assert.strictEqual id, modelF.get pMgr.getIdName modelF.className
                options =
                    classNameLetter: 'F'
                    model: modelF
                    letters: ['C', 'F']
                    listOptions:
                        fields: [
                            'propC1'
                            'propClassD:propA1'
                        ]
                        where: [
                            '{idC} = ' + id
                            '{propClassD} = ' + idD
                        ]
                        connector: connector
                        type: 'json'
                assertList pMgr, options, next
            (models, next)->
                assert.strictEqual models.length, 1
                model = models[0]
                assert.strictEqual model.propClassD.propA1, modelD.get 'propA1'
                assert.strictEqual model.propC1, modelF.get 'propC1'
                next()
                return
            (next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return

        return

    streamList = (pMgr, className, options, next)->
        models = []

        pMgr.stream className, options, (model)->
            models.push model
            return
        , (err, fields)->
            assert.ifError err
            next err, models
            return
        return

    assertStream = (pMgr, options, callback, next)->
        classNameLetter = options.classNameLetter
        listOptions = options.listOptions

        className = 'Class' + classNameLetter
        pMgr.stream className, listOptions, callback, (err, fields)->
            assert.ifError err
            next err, fields
            return
        return

    assertStreamUnique = (pMgr, options, next)->
        classNameLetter = options.classNameLetter
        model = options.model
        letters = options.letters or [classNameLetter]
        pModel = null
        count = 0
        assertStream pMgr, options, (model)->
            count++
            pModel = model
            assert.strictEqual count, 1
            return
        , (err, fields)->
            return next err if err
            assert.strictEqual count, 1
            for letter in letters
                for index in [1..3]
                    assert.strictEqual model.get('prop' + letter + index), pModel.get 'prop' + letter + index
            next err, pModel
            return
        return

    testStreamBasic = (next)->
        logger.debug 'begin testStreamBasic'
        _next = next
        next = ->
            logger.debug 'finish testStreamBasic'
            _next()

        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassA'

        options =
            classNameLetter: 'A'
            model: model
            listOptions:
                connector: connector

        id1 = id2 = null
        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.insert model, {connector: connector}, next
            (id, next)->
                id1 = id
                assertStreamUnique pMgr, options, next
                return
            (_model, next)->
                options.listOptions.where = '{idA} = ' + id1
                assertStreamUnique pMgr, options, next
                return
            (_model, next)->
                options.listOptions.where = '{propA1} = ' + connector.escape model.get 'propA1'
                assertStreamUnique pMgr, options, next
                return
            (_model, next)->
                model.set 'propA1', 'value'
                pMgr.insert model, {connector: connector}, next
                return
            (id, next)->
                id2 = id
                options.listOptions.where = [
                    '{idA} = ' + id
                    '{propA1} = ' + connector.escape model.get 'propA1'
                ]
                assertStreamUnique pMgr, options, next
                return
            (_model, next)->
                column = '{propA1}'
                condition1 = column + ' = ' + connector.escape 'propA1Value'
                condition2 = column +  ' = ' + connector.escape 'value'
                options.listOptions.where = [squel.expr().and(condition1).or(condition2)]
                count = 0
                assertStream pMgr, options, (pModel)->
                    count++
                    if count is 1
                        assert.strictEqual 'propA1Value', pModel.get 'propA1'
                        assert.strictEqual id1, pModel.get 'idA'
                    else if count is 2
                        assert.strictEqual 'value', pModel.get 'propA1'
                        assert.strictEqual id2, pModel.get 'idA'
                    else
                        # Make sure not more than 2 rows have been saved
                        assert.strictEqual count, 2
                , next
                return
            (fields, next)->
                options.listOptions.where = '{propA1} = ' + connector.escape model.get 'propA1'
                assertStreamUnique pMgr, options, next
                return
            (_model, next)->
                model.set 'propA2', 'value'
                pMgr.insert model, {connector: connector}, next
                return
            (id, next)->
                count = 0
                assertStream pMgr, options, (pModel)->
                    if count is 0
                        assert.strictEqual 'propA2Value', pModel.get 'propA2'
                    else if count is 1
                        assert.strictEqual 'value', pModel.get 'propA2'
                        assert.strictEqual id, pModel.get 'idA'
                    else
                        assert.strictEqual count, 1
                    count++
                , next
                return
            (fields, next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return

        return

    testStreamSubClass = (next)->
        logger.debug 'begin testStreamSubClass'
        _next = next
        next = ->
            logger.debug 'finish testStreamSubClass'
            _next()

        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassB'

        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.insert model, {connector: connector}, next
            (id, next)->
                options =
                    classNameLetter: 'B'
                    model: model
                    letters: ['A', 'B']
                    listOptions:
                        where: '{idA} = ' + id
                        connector: connector
                assertStreamUnique pMgr, options, next
                return
            (model, next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return

        return

    testStreamMixin = (next)->
        logger.debug 'begin testStreamMixin'
        _next = next
        next = ->
            logger.debug 'finish testStreamMixin'
            _next()

        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassD'

        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.insert model, {connector: connector}, next
            (id, next)->
                options =
                    classNameLetter: 'D'
                    model: model
                    letters: ['A', 'C', 'D']
                    listOptions:
                        where: '{idA} = ' + id
                        connector: connector
                assertStreamUnique pMgr, options, next
                return
            (model, next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return

        return

    testStreamMixin2 = (next)->
        logger.debug 'begin testStreamMixin2'
        _next = next
        next = ->
            logger.debug 'finish testStreamMixin2'
            _next()

        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassE'

        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.insert model, {connector: connector}, next
            (id, next)->
                options =
                    classNameLetter: 'E'
                    model: model
                    letters: ['A', 'B', 'C', 'E']
                    listOptions:
                        where: '{idA} = ' + id
                        connector: connector
                assertStreamUnique pMgr, options, next
                return
            (model, next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return

        return

    testStreamPropSubClass = (next)->
        logger.debug 'begin testStreamPropSubClass'
        _next = next
        next = ->
            logger.debug 'finish testStreamPropSubClass'
            _next()

        [pMgr, model, connector, Model] = setUpMapping()
        modelF = model.clone()
        modelF.className = 'ClassF'
        modelE = model.clone()
        modelE.className = 'ClassE'
        modelD = model.clone()
        modelD.className = 'ClassD'
        modelF.set 'propClassD', modelD
        modelF.set 'propClassE', modelE

        newE1Value = 'value1'
        newF1Value = 'value2'

        # Every modification needs to be committed
        listConnector = poolRead.createConnector()

        options = listOptions = null
        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> pMgr.insert modelD, {connector: connector, reflect: true}, next
            (id, next)->
                pMgr.insert modelE, {connector: connector}, next
                return
            (id, next)->
                # modelE will be used for multiple insert.
                # Using reflect will cause every related class to have an id, therefore preventing new insertion of the same object
                modelE.set pMgr.getIdName('ClassE'), id
                pMgr.insert modelF, {connector: connector}, next
                return
            (id, next)->
                options =
                    classNameLetter: 'F'
                    model: modelF
                    letters: ['C', 'F']
                    listOptions:
                        where: '{' + pMgr.getIdName('ClassF') + '} = ' + id
                        connector: connector
                        listConnector: listConnector
                assertStreamUnique pMgr, options, next
                return
            (model, next)->
                # List must returned property class properties
                assertPropSubClass model, modelD, modelE
                modelE.set 'propA1', newE1Value
                modelF.set 'propC1', newF1Value
                modelE.unset pMgr.getIdName 'ClassE'
                modelF.unset pMgr.getIdName 'ClassF'
                pMgr.insert modelE, {connector: connector}, next
                return
            (id, next)->
                modelE.set pMgr.getIdName('ClassE'), id
                pMgr.insert modelF, {connector: connector}, next
                return
            (id, next)->
                options.listOptions.where = '{propC1} = ' + connector.escape newF1Value
                assertStreamUnique pMgr, options, next
                return
            (model, next)->
                # Check persistence of new values
                assertPropSubClass model, modelD, modelE

                # Test filter on property class sub property
                options.listOptions.where = '{propClassE:propA1} = ' + connector.escape newE1Value
                assertStreamUnique pMgr, options, next
                return
            (model, next)->
                assertPropSubClass model, modelD, modelE

                # Test filter on property class sub property
                options.listOptions.where = [
                    '{propClassE:propA1} = ' + connector.escape newE1Value
                    '{propC1} = ' + connector.escape newF1Value
                ]
                assertStreamUnique pMgr, options, next
                return
            (model, next)->
                assertPropSubClass model, modelD, modelE

                # Test filter on property class sub property
                options.listOptions.where = [
                    '{propClassE:propA1} = ' + connector.escape 'propA1Value'
                    '{propC1} = ' + connector.escape newF1Value
                ]
                streamList pMgr, 'ClassF', options.listOptions, next
                return
            (models, next)->
                assert.strictEqual models.length, 0
                pMgr.insert modelF, {connector: connector}, next
                return
            (id, next)-> pMgr.insert modelF, {connector: connector, listConnector: listConnector}, next
            (id, next)->
                listOptions = 
                    connector: connector
                    listConnector: listConnector
                    where: '{propC1} = ' + connector.escape modelF.get 'propC1'
                    count: true

                pMgr.list 'ClassF', listOptions, next
                return
            (count, next)->
                # Sqlite mess with stream
                assert.strictEqual count, 3
                delete listOptions.count

                streamList pMgr, 'ClassF', listOptions, next
                return
            (models, next)->
                assert.strictEqual models.length, 3
                for model in models
                    assertProperties options.letters, model, modelF
                    assertPropSubClass model, modelD, modelE
                next()
                return
            
            # clean every thing that has been created
            (next)-> connector.begin next
            (next)-> connector.query 'DELETE FROM ' + connector.escapeId(pMgr.getDefinition('ClassF').table), next
            (res, next)-> connector.query 'DELETE FROM ' + connector.escapeId(pMgr.getDefinition('ClassE').table), next
            (res, next)-> connector.query 'DELETE FROM ' + connector.escapeId(pMgr.getDefinition('ClassD').table), next
            (res, next)-> connector.query 'DELETE FROM ' + connector.escapeId(pMgr.getDefinition('ClassC').table), next
            (res, next)-> connector.query 'DELETE FROM ' + connector.escapeId(pMgr.getDefinition('ClassB').table), next
            (res, next)-> connector.query 'DELETE FROM ' + connector.escapeId(pMgr.getDefinition('ClassA').table), next
            (res, next)-> connector.commit next
            (next)-> connector.release next
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return
        return

        return

    testStarAndInitialize = (next)->
        logger.debug 'begin testStarAndInitialize'
        _next = next
        next = ->
            logger.debug 'finish testStarAndInitialize'
            _next()

        [pMgr, model, connector, Model] = setUpMapping()
        modelF = model.clone()
        modelF.className = 'ClassF'
        modelE = model.clone()
        modelE.className = 'ClassE'
        modelD = model.clone()
        modelD.className = 'ClassD'
        modelF.set 'propClassD', modelD
        modelF.set 'propClassE', modelE

        newE1Value = 'value1'
        newF1Value = 'value2'

        options = id0 = null
        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.insert modelD, {connector: connector}, next
            (id, next)->
                modelD.set pMgr.getIdName('ClassD'), id
                pMgr.insert modelE, {connector: connector}, next
                return
            (id, next)->
                modelE.set pMgr.getIdName('ClassE'), id
                pMgr.insert modelF, {connector: connector}, next
                return
            (id, next)->
                options =
                    classNameLetter: 'F'
                    model: modelF
                    letters: ['C', 'F']
                    listOptions:
                        fields: ['propClassD:*', '*', 'propClassE:*']
                        where: '{' + pMgr.getIdName('ClassF') + '} = ' + id
                        connector: connector
                # TODO: make sure only one query is sent .i.e all join done, no sub-queries to get composite elements
                assertListUnique pMgr, options, next
                return
            (model, next)->
                assertPropSubClass model, modelD, modelE

                # test initialize using where clause
                idName = pMgr.getIdName 'ClassF'
                id0 = model.get idName
                model = new Model()
                model.className = 'ClassF'
                pMgr.initialize model, options.listOptions, next
                return
            (models, next)->
                assert.strictEqual models.length, 1
                idName = pMgr.getIdName 'ClassF'
                assert.strictEqual models[0].get(idName), id0

                # test initialize using Array attributes
                listOptions = _.clone options.listOptions
                delete listOptions.where
                listOptions.attributes = ['propClassD']
                model = new Model()
                # model.set idName, id0
                model.className = 'ClassF'
                pMgr.initialize model, listOptions, next
                return
            (models, next)->
                assert.strictEqual models.length, 1
                idName = pMgr.getIdName 'ClassF'
                assert.strictEqual models[0].get(idName), id0
                
                # test initialize using propClass attribute
                listOptions = _.clone options.listOptions
                delete listOptions.where
                model = new Model propClassD: modelD
                model.className = 'ClassF'
                pMgr.initialize model, listOptions, next
                return
            (models, next)->
                assert.strictEqual models.length, 1
                idName = pMgr.getIdName 'ClassF'
                assert.strictEqual models[0].get(idName), id0

                modelE.set 'propA1', newE1Value
                modelF.set 'propC1', newF1Value
                modelE.unset pMgr.getIdName 'ClassE'
                modelF.unset pMgr.getIdName 'ClassF'
                pMgr.insert modelE, {connector: connector}, next
                return
            (id, next)->
                modelE.set pMgr.getIdName('ClassE'), id
                pMgr.insert modelF, {connector: connector}, next
                return
            (id, next)->
                options.listOptions.where = '{propC1} = ' + connector.escape newF1Value
                assertListUnique pMgr, options, next
                return
            (model, next)->
                assertPropSubClass model, modelD, modelE
                options.listOptions.where = '{propClassE:propA1} = ' + connector.escape newE1Value
                assertListUnique pMgr, options, next
                return
            (model, next)->
                assertPropSubClass model, modelD, modelE
                options.listOptions.where = [
                    '{propClassE:propA1} = ' + connector.escape newE1Value
                    '{propC1} = ' + connector.escape newF1Value
                ]
                assertListUnique pMgr, options, next
                return
            (model, next)->
                assertPropSubClass model, modelD, modelE

                # test count with where block
                options.listOptions.count = true
                pMgr.list 'ClassF', options.listOptions, next
                return
            (count, next)->
                assert.strictEqual count, 1
                options.listOptions.count = false
                options.listOptions.where = [
                    '{propClassE:propA1} = ' + connector.escape 'propA1Value'
                    '{propC1} = ' + connector.escape newF1Value
                ]
                pMgr.list 'ClassF', options.listOptions, next
            (models, next)->
                assert.strictEqual models.length, 0
                # test count with where block
                options.listOptions.count = true
                pMgr.list 'ClassF', options.listOptions, next
                return
            (count, next)->
                assert.strictEqual count, 0
                next()
                return
            (next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return

    testIssue3 = (next)->
        logger.debug 'begin testIssue3'
        _next = next
        next = ->
            logger.debug 'finish testIssue3'
            _next()

        # Nested condition on non selected field cause crash
        # Mixin parent causes inner join instead of left join for left join on child
        # Select a was select a:*
        
        dbMap = require '../lib/test-map'
        
        pMgr = new PersistenceManager dbMap
        connector = poolWrite.createConnector()

        options =
            connector: connector
            fields: 'id'
            where: [
                '{author:country:property:code} = ' + connector.escape 'country.CAMEROUN'
            ]
            order: '{id}' # Important. For an unknown reason, second query is ordered

        pModels = null
        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.list 'User', options, next
            (models, next)-> 
                assert.ok models.length > 0
                pModels = models
                options.fields = [
                    'id'
                    'author:country:property:*'
                    'author:language:property:*'
                ]

                pMgr.list 'User', options, next
                return
            (models, next)->
                for model, index in models
                    assert.strictEqual 'country.CAMEROUN', model.get('author').get('country').get('property').get('code')
                    assert.strictEqual model.get('id'), pModels[index].get('id')
                next()
                return
            (next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return
        return

    testJoin = (next)->
        logger.debug 'begin testJoin'
        _next = next
        next = ->
            logger.debug 'finish testJoin'
            _next()

        dbMap = require '../lib/test-map'
        
        pMgr = new PersistenceManager dbMap
        connector = poolWrite.createConnector()

        strCode = 'country.CAMEROUN'

        options =
            connector: connector
            fields: [
                'id'
                'country:property:code'
            ]
            where: [
                '{LNG, key} = ' + connector.escape 'FR'
                '{country:property:code} = ' + connector.escape strCode
            ]
            join:
                translation:
                    entity: 'Translation'
                    condition: squel.expr().and '{translation, property} = {country:property}'
                    fields: [
                        'value'
                        'property:code'
                    ]
                LNG:
                    entity: 'Language'
                    type: 'left'
                    condition: '{LNG, id} = {translation, language}'
                    fields: [
                        'code'
                        'key'
                    ]
            limit: 5

        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.list 'User', options, next
            (models, next)->
                assert.ok models.length > 0
                assert.ok models.length <= options.limit
                for model in models
                    assert.strictEqual strCode, model.get('country').get('property').get('code')
                    assert.strictEqual strCode, model.get('translation').get('property').get('code')

                # test count with fields and join
                # Using LIMIT you will not limit the count or sum but only the returned rows
                # http://stackoverflow.com/questions/17020842/mysql-count-with-limit#answers-header
                options.count = true
                pMgr.list 'User', options, next
                return
            (count, next)->
                # There are supposed to be 25 users matching the where field
                assert.strictEqual count, 25
                next()
                return
            (next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return
        return

    testIssue4 = (next)->
        logger.debug 'begin testIssue4'
        _next = next
        next = ->
            logger.debug 'finish testIssue4'
            _next()

        # no field was considered as *
        dbMap = require '../lib/test-map'
        
        pMgr = new PersistenceManager dbMap
        connector = poolWrite.createConnector()

        strCode = 'country.CAMEROUN'

        options =
            type: 'json'
            connector: connector
            fields: [
                'name'
                'firstName'
                'occupation'
                'email'
                'country:property:code'
            ]
            where: [
                '{LNG, key} = ' + connector.escape 'FR'
                '{country:property:code} = ' + connector.escape strCode
            ]
            join:
                ctry:
                    entity: 'Translation'
                    condition: '{ctry, property} = {country:property}'
                    fields: [
                        'property:code'
                    ]
                LNG:
                    entity: 'Language'
                    type: 'left'
                    condition: '{LNG, id} = {ctry, language}'

        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.list 'User', options, next
            (models, next)->
                assert.ok models.length > 0
                for model in models
                    assert.strictEqual strCode, model.country.property.code
                    assert.strictEqual strCode, model.ctry.property.code
                next()
                return
            (next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return
        return

    # order, group, having, limit, offset
    testSelectBlocks = (next)->
        logger.debug 'begin testSelectBlocks'
        _next = next
        next = ->
            logger.debug 'finish testSelectBlocks'
            _next()

        # no field was considered as *
        dbMap = require '../lib/test-map'
        
        pMgr = new PersistenceManager dbMap
        connector = poolWrite.createConnector()

        strCode = 'country.CAMEROUN'

        options =
            type: 'json'
            connector: connector
            fields: [
                'id'
                'country:property:code'
            ]
            join:
                ctry:
                    entity: 'Translation'
                    type: 'left'
                    condition: '{ctry, property} = {country:property}'
                    fields: 'property:code'
                LNG:
                    entity: 'Language'
                    type: 'left'
                    condition: '{LNG, id} = {ctry, language}'
            order: [['{id}', true]]
            group: [
                '{id}'
                '{country}'
                '{country:property}'
                '{country:property:code}'
                '{ctry, property}'
                '{ctry, property:code}'
                '{LNG, key}'
            ]
            having: [
                '{LNG, key} = __fr__'
                [
                    '{LNG, key} IN ?', ['FR']
                ]
                squel.expr().and '{LNG, key} <> __en__'
                [
                    '{country:property:code} = ?', strCode
                ]
            ]
            limit: 10
            offset: 0
            values:
                fr: connector.escape 'FR'
                en: connector.escape 'EN'

        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.list 'User', options, next
            (models, next)->
                assert.ok models.length > 0
                for model in models
                    assert.strictEqual strCode, model.country.property.code
                    assert.strictEqual strCode, model.ctry.property.code
                next()
                return
            (next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return
        return

    testUniqueConstraint = (next)->
        logger.debug 'begin testUniqueConstraint'
        _next = next
        next = ->
            logger.debug 'finish testUniqueConstraint'
            _next()

        # unique constraint used on initialize, update, delete => where must be on properties
        # For performance concern, even if an entry has a unique constraint, add a primary key column
        # initialize goes with list => where is handled
        # update and delete, for each unique constraint, take the first one that has all it's fields not null
        
        [pMgr, model, connector, Model] = setUpMapping()
        _model = null

        id0 = id1 = id2 = 0
        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)->
                model.className = 'ClassG'
                _model = model.clone()
                model.set 'propG1', 'valueG10'
                model.set 'propG2', 'valueG20'
                model.set 'propG3', 'valueG30'
                pMgr.insert model, {connector: connector}, next
                return
            (id, next)->
                id0 = id
                model.set 'propG1', 'valueG11'
                model.set 'propG2', 'valueG21'
                model.set 'propG3', 'valueG31'
                pMgr.save model.clone(), {connector: connector}, next
                return
            (id, next)->
                id1 = id
                model.set 'propG1', 'valueG12'
                model.set 'propG2', 'valueG22'
                model.set 'propG3', 'valueG32'
                pMgr.initializeOrInsert model, {connector: connector}, next
                return
            (id, next)->
                id2 = id
                pMgr.list 'ClassG', {connector: connector, count: true}, next
                return
            (count, next)->
                assert.strictEqual count, 3
                model.unset pMgr.getIdName model.className
                pMgr.initializeOrInsert model, {connector: connector}, next
                return
            (id, next)->
                assert.strictEqual id, id2
                model.unset pMgr.getIdName model.className
                pMgr.save model, {connector: connector}, next
                return
            (id, msg, next)->
                assert.strictEqual 'function', typeof next
                assert.strictEqual id, id2
                pMgr.list 'ClassG', {connector: connector, count: true}, next
                return
            (count, next)->
                assert.strictEqual count, 3
                model.unset pMgr.getIdName model.className
                model.set 'propG1', 'valueG10'
                model.set 'propG2', 'valueG20'
                pMgr.initialize model, {connector: connector}, next
                return
            (models, next)->
                assert.strictEqual id0, model.get pMgr.getIdName model.className
                model.unset pMgr.getIdName model.className
                model.set 'propG1', 'valueG11'
                model.set 'propG2', 'valueG21'
                model.set 'propG3', 'valueG34'
                pMgr.update model, {connector: connector}, next
                return
            (id, msg, next)->
                assert.strictEqual 'function', typeof next
                assert.strictEqual id1, id
                model.unset pMgr.getIdName model.className
                pMgr.save model, {connector: connector}, next
                return
            (id, msg, next)->
                assert.strictEqual 'function', typeof next
                assert.strictEqual id1, id
                model.unset pMgr.getIdName model.className
                model.set 'propG1', 'valueG12'
                model.set 'propG2', 'valueG22'
                pMgr.delete model, {connector: connector}, next
                return
            (res, next)->
                options =
                    type: 'json'
                    connector: connector
                    order: '{idG}'
                pMgr.list model.className, options, next
                return
            (models, next)->
                assert.strictEqual 2, models.length
                assert.strictEqual id0, models[0].idG
                assert.strictEqual id1, models[1].idG

                model = _model
                model.unset 'propG2'

                # insert with only one unique contraints setted
                model.set 'propG1', 'valueG13'
                model.set 'propG3', 'valueG33'
                pMgr.insert model, {connector: connector}, next
                return
            (id, next)-> pMgr.list 'ClassG', {connector: connector, count: true}, next
            (count, next)->
                assert.strictEqual count, 3

                # save with only one unique contraints setted
                model.set 'propG1', 'valueG14'
                model.set 'propG3', 'valueG34'
                pMgr.save model, {connector: connector}, next
                return
            (id, next)-> pMgr.list 'ClassG', {connector: connector, count: true}, next
            (count, next)->
                assert.strictEqual count, 4

                # update with only one unique contraints setted
                model.set 'propG3', 'valueG34New'
                pMgr.update model, {connector: connector}, next
                return
            (id, msg, next)->
                assert.strictEqual 'function', typeof next
                pMgr.list 'ClassG', {connector: connector, count: true}, next
                return
            (count, next)->
                assert.strictEqual count, 4
                pMgr.delete model, {connector: connector}, next
                return
            (res, next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return
        return

    testCustomColumns = (next)->
        logger.debug 'begin testCustomColumns'
        _next = next
        next = ->
            logger.debug 'finish testCustomColumns'
            _next()

        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassA'

        tasks = [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)->
                model.set 'propA1', 'odd'
                pMgr.insert model, {connector: connector}, next
                return
            (id, next)->
                model.set 'propA1', 'even'
                pMgr.insert model, {connector: connector}, next
                return
            (id, next)->
                model.set 'propA1', 'odd'
                pMgr.insert model, {connector: connector}, next
                return
            (id, next)->
                model.set 'propA1', 'even'
                pMgr.insert model, {connector: connector}, next
                return
            (id, next)->
                options =
                    columns:
                        'even':
                            column: "CASE {propA1} WHEN #{connector.escape 'even'} THEN 1 ELSE 0 END"
                            read: (value)->
                                !!value
                    connector: connector

                pMgr.list 'ClassA', options, next
                return
            (models, next)->
                assert.strictEqual models.length, 4
                assert.strictEqual models[0].get('even'), false
                assert.strictEqual models[1].get('even'), true
                assert.strictEqual models[2].get('even'), false
                assert.strictEqual models[3].get('even'), true
                next()
            (next)-> connector.rollback next, true
        ]

        async.waterfall tasks, (err)->
            assert.ifError err
            next()
            return
        return

    # insert, update, save using write handler that return undefined
    # escape boolean, array, non string
    # update, save using update handler that return undefined
    # hanler write for a propclass
    # where|having as a select query
    # wrong mixin within array
    # construction that is not a function
    # define classes in random order
    # mixins > 2 and in random order

    # join in messy order
    # error handling tests
    # # If parent mixin has been update, child must be considered as being updated
    # issue: update on subclass with no owned properties
    # optimistic lock
    #   update
    #   delete
    # sort,group on mixin|parent|property class prop
    
    series = [
        setUp
        testBasicMapping
        testBasicMapping2
        testInheritance
        testCircularReference
        testThrows
        testGetColumn
        testInsertQuery
        testInsertBasic
        testInsertSubClass
        testInsertMixin
        testInsertMixin2
        testListBasic
        testListSubClass
        testListMixin
        testListMixin2
        testListPropSubClass
        testHandlersAndListField
        testUpdate
        testDelete
        testSave
        testIssue1
        testIssue2
        testStreamBasic
        testStreamSubClass
        testStreamMixin
        testStreamMixin2
        testStreamPropSubClass
        testStarAndInitialize
        testIssue3
        testJoin
        testIssue4
        testSelectBlocks
        testUniqueConstraint
        testCustomColumns
        tearDown
    ]

    timerInit = new Date().getTime()
    async.series series, (err)->
        logger.info 'Finished in ', new Date().getTime() - timerInit
        assert.done err
        return