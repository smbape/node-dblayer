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
        next()

    tearDown = (next)->
        next()

    assertPartialThrows = (mapping, className, given, expected)->
        mapping[className] = given
        assert.throws ->
            pMgr = new PersistenceManager mapping
        , (err)->
            err.code is expected
        , 'unexpected error'

    assertPartial = (mapping, className, given, expected)->
        mapping[className] = given
        pMgr = new PersistenceManager mapping
        given = pMgr.getDefinition className
        for prop, value of expected
            assert.ok _.isEqual given[prop], value
        return

    testBasicMapping = (next)->
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

        # Must define id
        # update: no longer the case
        # assertPartialThrows mapping, 'ClassA',
        #     table: 'TableA'
        # , 'NO_ID'

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

        # No table given => table = className
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

    testBasicMapping2 = (next)->
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

    testInheritance = (next)->
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

    testCircularReference = (next)->
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

    testThrows = (next)->
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

    assertInsertQuery = (mapping, model, className, expected)->
        model.className = className
        pMgr = new PersistenceManager mapping
        query = pMgr.getInsertQuery model, {force: true}
        assert.strictEqual query.toString(), expected

    assertInsertQueryThrows = (mapping, model, className, expected, options)->
        model.className = className
        pMgr = new PersistenceManager mapping
        assert.throws ->
            pMgr.getInsertQuery model, options
        , (err)->
            err.code is expected
        , 'unexpected error'

    testInsert = (next)->
        mapping = {}

        class Model
            get: (prop)->
                return prop + 'Value'

        model = new Model()

        # id + properties
        mapping['ClassA'] =
            table: 'TableA'
            id:
                name: 'idA'
                column: 'colIdA'
            properties:
                propA1: 'colPropA1'
        assertInsertQueryThrows mapping, model, 'ClassA', 'ID_EXISTS'
        assertInsertQuery mapping, model, 'ClassA', 'INSERT INTO TableA (colPropA1) VALUES (\'propA1Value\')'

        # id + properties class
        class Model
            get: (prop)->
                if prop.substring(0, 9) is 'propClass'
                    return new Model()
                return prop + 'Value'

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
        
        assertInsertQuery mapping, model, 'ClassB', 'INSERT INTO TableB (colIdA, colPropB2) VALUES (\'idAValue\', \'propB2Value\')'

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
        
        assertInsertQuery mapping, model, 'ClassB', 'INSERT INTO TableB (colPropB1, colPropB2) VALUES (\'idAValue\', \'propB2Value\')'

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
        assertInsertQuery mapping, model, 'ClassC', 'INSERT INTO TableC (colIdA) VALUES (\'idAValue\')'
        
        # prop.className -> id.className -> id.className
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
        assertInsertQuery mapping, model, 'ClassC', 'INSERT INTO TableC (colIdB) VALUES (\'idAValue\')'
        
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
        assertInsertQuery mapping, model, 'ClassD', 'INSERT INTO TableD (colIdA) VALUES (\'idAValue\')'
        
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
        assertInsertQuery mapping, model, 'ClassD', 'INSERT INTO TableD (colIdB) VALUES (\'idAValue\')'
        
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
        assertInsertQuery mapping, model, 'ClassD', 'INSERT INTO TableD (colIdC) VALUES (\'idAValue\')'
        
        # throw error if no id is setted for sub-element
        class Model
            get: (prop)->
                if prop is 'idA'
                    return
                if prop.substring(0, 9) is 'propClass'
                    return new Model()
                return prop + 'Value'
        model = new Model()
        assertInsertQueryThrows mapping, model, 'ClassD', 'NO_ID', {force: true}
        
        # only save setted properties
        class Model
            get: (prop)->
                if prop.charAt(prop.length - 1) is '2'
                    return
                if prop.substring(0, 9) is 'propClass'
                    return new Model()
                return prop + 'Value'
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
        assertInsertQuery mapping, model, 'ClassD', 'INSERT INTO TableD (colIdC, colPropD1, colPropD3) VALUES (\'idAValue\', \'propD1Value\', \'propD3Value\')'
        
        # id className
        class Model
            constructor: (@preffix = '')->
            get: (prop)->
                if prop.charAt(prop.length - 1) is '2'
                    return
                if prop.substring(0, 9) is 'propClass'
                    return new Model prop.substring 9
                return prop + @preffix + 'Value'
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
        query = pMgr.getInsertQuery model, {force: true}
        query = query.toParam()
        assert.strictEqual query.text, 'INSERT INTO TableB (colIdA, colPropB0, colPropB1, colPropB3) VALUES (?, ?, ?, ?)'
        assert.strictEqual query.values[1], 'idAB0Value'
        assert.strictEqual query.values[2], 'propB1Value'
        assert.strictEqual query.values[3], 'propB3Value'
        query = query.values[0]
        assert.strictEqual query.toString(), 'INSERT INTO TableA (colPropA1, colPropA3) VALUES (\'propA1Value\', \'propA3Value\')'
        
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
        query = pMgr.getInsertQuery model, {force: true}
        query = query.toParam()
        assert.strictEqual query.text, 'INSERT INTO TableB (colIdA, colPropB0, colPropB1, colPropB3) VALUES (?, ?, ?, ?)'
        assert.strictEqual query.values[1], 'idAB0Value'
        assert.strictEqual query.values[2], 'propB1Value'
        assert.strictEqual query.values[3], 'propB3Value'
        query2 = query.values[0]
        assert.strictEqual query2.toString(), 'INSERT INTO TableA (colPropA1, colPropA3) VALUES (\'propA1Value\', \'propA3Value\')'
        
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
        query = pMgr.getInsertQuery model, {force: true}
        query = query.toParam()
        assert.strictEqual query.text, 'INSERT INTO TableC (colIdA, colIdB, colPropC0, colPropC1, colPropC3) VALUES (?, ?, ?, ?, ?)'
        assert.strictEqual query.values[2], 'idAC0Value'
        assert.strictEqual query.values[3], 'propC1Value'
        assert.strictEqual query.values[4], 'propC3Value'
        query2 = query.values[0]
        assert.strictEqual query2.toString(), 'INSERT INTO TableA (colPropA1, colPropA3) VALUES (\'propA1Value\', \'propA3Value\')'
        query2 = query.values[1]
        assert.strictEqual query2.toString(), 'INSERT INTO TableB (colPropB0, colPropB1, colPropB3) VALUES (\'idAB0Value\', \'propB1Value\', \'propB3Value\')'

        next()

    assertPersist = (pMgr, model, classNameLetter, id, connector, next)->
        className = 'Class' + classNameLetter
        definition = pMgr.getDefinition className
        if _.isObject id
            id = id[definition.id.column]
        query = squel
            .select(pMgr.getSquelOptions(connector.getDialect()))
            .from connector.escapeId definition.table
            .where connector.escapeId(definition.id.column) + ' = ?', id
            .toString()
        connector.query query, (err, res)->
            assert.ifError err
            assert.strictEqual res.rows.length, 1
            row = res.rows[0]
            assert.strictEqual row['PROP_' + classNameLetter + '1'], model.get 'prop' + classNameLetter + '1'
            assert.strictEqual row['PROP_' + classNameLetter + '2'], model.get 'prop' + classNameLetter + '2'
            assert.strictEqual row['PROP_' + classNameLetter + '3'], model.get 'prop' + classNameLetter + '3'
            next row

    setUpMapping = ->
        mapping = {}
        modelId = 0
        class Model
            constructor: ()->
                @id = modelId++
                @attributes = {}
            clone: ->
                _clone = new Model()
                _clone.attributes = _.clone @attributes
                _clone
            set: (prop, value)->
                @attributes[prop] = value
                return @
            get: (prop)->
                @attributes[prop]
            remove: (prop)->
                delete @attributes[prop]
            toJSON: ->
                @attributes

        class ModelA extends Model
            className: 'ClassA'

        handlersCreation =
            insert: (options)->
                new Date()
            read: (value, options)->
                moment.utc(moment(value).format 'YYYY-MM-DD HH:mm:ss').toDate()
            write: (value, options)->
                moment(value).utc().format 'YYYY-MM-DD HH:mm:ss'

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

        pMgr = new PersistenceManager mapping

        model = new Model()

        model.set 'propA1', 'propA1Value'
        model.set 'propA2', 'propA2Value'
        model.set 'propA3', 'propA3Value'

        model.set 'propB1', 'propB1Value'
        model.set 'propB2', 'propB2Value'
        model.set 'propB3', 'propB3Value'

        model.set 'propC1', 'propC1Value'
        model.set 'propC2', 'propC2Value'
        model.set 'propC3', 'propC3Value'

        model.set 'propD1', 'propD1Value'
        model.set 'propD2', 'propD2Value'
        model.set 'propD3', 'propD3Value'

        model.set 'propE1', 'propE1Value'
        model.set 'propE2', 'propE2Value'
        model.set 'propE3', 'propE3Value'

        model.set 'propF1', 'propF1Value'
        model.set 'propF2', 'propF2Value'
        model.set 'propF3', 'propF3Value'

        connector = poolWrite.createConnector()

        return [pMgr, model, connector, Model, mapping]

    testGet = (next)->
        [pMgr, model, connector, Model] = setUpMapping()
        assert.strictEqual pMgr.getColumn('ClassA', 'idA'), 'A_ID'
        assert.strictEqual pMgr.getColumn('ClassA', 'propA1'), 'PROP_A1'
        assert.strictEqual pMgr.getColumn('ClassA', 'propA2'), 'PROP_A2'
        assert.strictEqual pMgr.getColumn('ClassA', 'propA3'), 'PROP_A3'
        next()

    testInsertBasic = (next)->
        [pMgr, model, connector] = setUpMapping()
        model.className = 'ClassA'

        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                pMgr.insert model, {connector: connector}, (err, id)->
                    assert.ifError err
                    assertPersist pMgr, model, 'A', id, connector, ->
                        connector.rollback (err)->
                            assert.ifError err
                            next()
                        , true

    testInsertSubClass = (next)->
        [pMgr, model, connector] = setUpMapping()
        model.className = 'ClassB'
        query = pMgr.getInsertQuery model, {connector: connector, dialect: connector.getDialect()}

        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                query.execute connector, (err, id)->
                    assert.ifError err
                    assertPersist pMgr, model, 'B', id, connector, (row)->
                        assertPersist pMgr, model, 'A', row, connector, (row)->
                            connector.rollback (err)->
                                assert.ifError err
                                next()
                            , true

    testInsertMixin = (next)->
        [pMgr, model, connector] = setUpMapping()
        model.className = 'ClassD'

        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                pMgr.insert model, {connector: connector}, (err, id)->
                    assert.ifError err
                    assertPersist pMgr, model, 'D', id, connector, (rowD)->
                        assertPersist pMgr, model, 'C', rowD, connector, (rowC)->
                            assertPersist pMgr, model, 'A', rowD, connector, (rowA)->
                                connector.rollback (err)->
                                    assert.ifError err
                                    next()
                                , true

    testInsertMixin2 = (next)->
        [pMgr, model, connector] = setUpMapping()
        model.className = 'ClassE'

        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                pMgr.insert model, {connector: connector}, (err, id)->
                    assert.ifError err
                    assertPersist pMgr, model, 'E', id, connector, (rowE)->
                        assertPersist pMgr, model, 'C', rowE, connector, (rowC)->
                            assertPersist pMgr, model, 'B', rowE, connector, (rowB)->
                                assertPersist pMgr, model, 'A', rowB, connector, (rowA)->
                                    connector.rollback (err)->
                                        assert.ifError err
                                        next()
                                    , true

    assertList = (pMgr, options, next)->
        classNameLetter = options.classNameLetter
        listOptions = options.listOptions

        className = 'Class' + classNameLetter
        query = pMgr.list className, listOptions, (err, models)->
            assert.ifError err
            assert.ok models.length > 0
            next models

    assertListUnique = (pMgr, options, next)->
        classNameLetter = options.classNameLetter
        model = options.model
        letters = options.letters or [classNameLetter]

        assertList pMgr, options, (models)->
            assert.strictEqual models.length, 1
            pModel = models[0]
            for letter in letters
                for index in [1..3]
                    prop = 'prop' + letter + index
                    assert.strictEqual model.get(prop), pModel.get prop
            next models[0]

    testListBasic = (next)->
        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassA'

        options =
            classNameLetter: 'A'
            model: model
            listOptions:
                connector: connector

        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                pMgr.insert model, {connector: connector}, (err, id)->
                    assert.ifError err
                    assertListUnique pMgr, options, ->
                        id1 = id
                        options.listOptions.where = '{idA} = ' + id
                        assertListUnique pMgr, options, ->
                            options.listOptions.where = '{propA1} = ' + connector.escape model.get 'propA1'
                            assertListUnique pMgr, options, ->
                                model.set 'propA1', 'value'
                                pMgr.insert model, {connector: connector}, (err, id)->
                                    assert.ifError err
                                    id2 = id
                                    options.listOptions.where = [
                                        '{idA} = ' + id
                                        '{propA1} = ' + connector.escape model.get 'propA1'
                                    ]
                                    assertListUnique pMgr, options, ->
                                            column = '{propA1}'
                                            condition1 = column + ' = ' + connector.escape 'propA1Value' 
                                            condition2 = column +  ' = ' + connector.escape 'value' 
                                            options.listOptions.where = [
                                                squel.expr().and( condition1 ).or condition2 
                                            ]
                                            assertList pMgr, options, (models)->
                                                assert.strictEqual models.length, 2
                                                assert.strictEqual 'propA1Value', models[0].get 'propA1'
                                                assert.strictEqual 'value', models[1].get 'propA1'
                                                assert.strictEqual id1, models[0].get 'idA'
                                                assert.strictEqual id2, models[1].get 'idA'
                                                options.listOptions.where = '{propA1} = ' + connector.escape model.get 'propA1'
                                                assertListUnique pMgr, options, ->
                                                    model.set 'propA2', 'value'
                                                    pMgr.insert model, {connector: connector}, (err, id)->
                                                        assert.ifError err
                                                        assertList pMgr, options, (models)->
                                                            assert.strictEqual models.length, 2
                                                            assert.strictEqual 'propA2Value', models[0].get 'propA2'
                                                            assert.strictEqual 'value', models[1].get 'propA2'
                                                            connector.rollback (err)->
                                                                assert.ifError err
                                                                next()
                                                            , true

    testListSubClass = (next)->
        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassB'
        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                pMgr.insert model, {connector: connector}, (err, id)->
                    assert.ifError err
                    options =
                        classNameLetter: 'B'
                        model: model
                        letters: ['A', 'B']
                        listOptions:
                            where: '{idA} = ' + id
                            connector: connector
                    assertListUnique pMgr, options, ->
                        connector.rollback (err)->
                            assert.ifError err
                            next()
                        , true

    testListMixin = (next)->
        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassD'

        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                pMgr.insert model, {connector: connector}, (err, id)->
                    assert.ifError err
                    options =
                        classNameLetter: 'D'
                        model: model
                        letters: ['A', 'C', 'D']
                        listOptions:
                            where: '{idA} = ' + id
                            connector: connector
                    assertListUnique pMgr, options, ->
                        connector.rollback (err)->
                            assert.ifError err
                            next()
                        , true

    testListMixin2 = (next)->
        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassE'
        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                pMgr.insert model, {connector: connector}, (err, id)->
                    assert.ifError err
                    options =
                        classNameLetter: 'E'
                        model: model
                        letters: ['A', 'B', 'C', 'E']
                        listOptions:
                            where: '{idA} = ' + id
                            connector: connector
                    assertListUnique pMgr, options, ->
                        connector.rollback (err)->
                            assert.ifError err
                            next()
                        , true

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

        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                pMgr.insert modelD, {connector: connector}, (err, id)->
                    assert.ifError err
                    modelD.set pMgr.getId('ClassD'), id
                    pMgr.insert modelE, {connector: connector}, (err, id)->
                        assert.ifError err
                        modelE.set pMgr.getId('ClassE'), id
                        pMgr.insert modelF, {connector: connector}, (err, id)->
                            assert.ifError err
                            options =
                                classNameLetter: 'F'
                                model: modelF
                                letters: ['C', 'F']
                                listOptions:
                                    where: '{' + pMgr.getId('ClassF') + '} = ' + id
                                    connector: connector
                            assertListUnique pMgr, options, (model)->
                                assertPropSubClass model, modelD, modelE
                                modelE.set 'propA1', newE1Value
                                modelF.set 'propC1', newF1Value
                                modelE.remove pMgr.getId 'ClassE'
                                modelF.remove pMgr.getId 'ClassF'
                                pMgr.insert modelE, {connector: connector}, (err, id)->
                                    assert.ifError err
                                    modelE.set pMgr.getId('ClassE'), id
                                    pMgr.insert modelF, {connector: connector}, (err, id)->
                                        assert.ifError err
                                        options.listOptions.where = '{propC1} = ' + connector.escape newF1Value
                                        assertListUnique pMgr, options, (model)->
                                            assertPropSubClass model, modelD, modelE
                                            options.listOptions.where = '{propClassE:propA1} = ' + connector.escape newE1Value
                                            assertListUnique pMgr, options, (model)->
                                                assertPropSubClass model, modelD, modelE
                                                options.listOptions.where = [
                                                    '{propClassE:propA1} = ' + connector.escape newE1Value
                                                    '{propC1} = ' + connector.escape newF1Value
                                                ]
                                                assertListUnique pMgr, options, (model)->
                                                    assertPropSubClass model, modelD, modelE
                                                    options.listOptions.where = [
                                                        '{propClassE:propA1} = ' + connector.escape 'propA1Value'
                                                        '{propC1} = ' + connector.escape newF1Value
                                                    ]
                                                    pMgr.list 'ClassF', options.listOptions, (err, models)->
                                                        assert.ifError err
                                                        assert.strictEqual models.length, 0
                                                        connector.rollback (err)->
                                                            assert.ifError err
                                                            next()
                                                        , true

    testListField = (next)->
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

        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                pMgr.insert modelD, {connector: connector, reflect: true}, (err, id)->
                    assert.ifError err
                    assert.strictEqual id, modelD.get pMgr.getId 'ClassD'
                    creationDate = modelD.get 'creationDate'
                    modificationDate = modelD.get 'modificationDate'
                    assert.ok creationDate instanceof Date
                    assert.ok modificationDate instanceof Date
                    creationDate = moment creationDate
                    modificationDate = moment modificationDate
                    assert.strictEqual modificationDate.diff(creationDate), 0
                    now = moment()
                    assert.ok Math.abs(now.diff(creationDate)) < 1500
                    assert.ok Math.abs(now.diff(modificationDate)) < 1500
                    pMgr.insert modelE, {connector: connector, reflect: true}, (err, id)->
                        assert.ifError err
                        assert.strictEqual id, modelE.get pMgr.getId 'ClassE'
                        modificationDate = moment modelE.get 'modificationDate'
                        creationDate = moment modelE.get 'creationDate'
                        assert.strictEqual modificationDate.diff(creationDate), 0
                        now = moment()
                        assert.ok Math.abs(now.diff(creationDate)) < 1500
                        assert.ok Math.abs(now.diff(modificationDate)) < 1500
                        pMgr.insert modelF, {connector: connector, reflect: true}, (err, id)->
                            assert.ifError err
                            assert.strictEqual id, modelF.get pMgr.getId 'ClassF'
                            modelD.remove pMgr.getId 'ClassC'
                            modelD.remove pMgr.getId 'ClassD'
                            modelE.remove pMgr.getId 'ClassC'
                            modelE.remove pMgr.getId 'ClassE'
                            modelF.remove pMgr.getId 'ClassF'
                            modelD.set 'propA1', newD1Value
                            modelE.set 'propA1', newE1Value
                            modelF.set 'propC1', newF1Value
                            pMgr.insert modelD, {connector: connector, reflect: true}, (err, id)->
                                assert.ifError err
                                pMgr.insert modelE, {connector: connector, reflect: true}, (err, id)->
                                    assert.ifError err
                                    pMgr.insert modelF, {connector: connector, reflect: true}, (err, id)->
                                        assert.ifError err
                                        options =
                                            classNameLetter: 'F'
                                            model: modelF
                                            letters: ['C', 'F']
                                            listOptions:
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
                                                type: 'json'

                                        assertList pMgr, options, (models)->
                                            assert.strictEqual models.length, 1
                                            model = models[0]
                                            assert.ok _.isPlainObject model
                                            assert.strictEqual model.propClassD.propA1, modelD.get 'propA1'
                                            assert.strictEqual model.propClassE.propA1, modelE.get 'propA1'
                                            assert.strictEqual model.propC1, modelF.get 'propC1'
                                            connector.rollback (err)->
                                                assert.ifError err
                                                next()
                                            , true

    testUpdate = (next)->
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

        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                pMgr.insert modelD, {connector: connector, reflect: true}, (err, id)->
                    assert.ifError err
                    pMgr.insert modelE, {connector: connector, reflect: true}, (err, id)->
                        assert.ifError err
                        pMgr.insert modelF, {connector: connector, reflect: true}, (err, id)->
                            assert.ifError err
                            modelD.remove pMgr.getId 'ClassC'
                            modelD.remove pMgr.getId 'ClassD'
                            modelE.remove pMgr.getId 'ClassC'
                            modelE.remove pMgr.getId 'ClassE'
                            modelF.remove pMgr.getId 'ClassF'
                            pMgr.insert modelD, {connector: connector, reflect: true}, (err, id)->
                                assert.ifError err
                                pMgr.insert modelE, {connector: connector, reflect: true}, (err, id)->
                                    assert.ifError err
                                    pMgr.insert modelF, {connector: connector, reflect: true}, (err, id)->
                                        assert.ifError err
                                        modelD.set 'propA1', newD1Value
                                        modelE.set 'propA1', newE1Value
                                        modelF.set 'propC1', newF1Value
                                        pMgr.update modelD, {connector: connector}, (err, id)->
                                            assert.ifError err
                                            pMgr.update modelE, {connector: connector}, (err, id)->
                                                assert.ifError err
                                                pMgr.update modelF, {connector: connector}, (err, id)->
                                                    assert.ifError err
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
                                                    assertListUnique pMgr, options, (model)->
                                                        assertPropSubClass model, modelD, modelE
                                                        connector.rollback (err)->
                                                            assert.ifError err
                                                            next()
                                                        , true

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
            assert.ifError err
            assert.strictEqual expected[0], parseInt res.rows[0].count, 10
            assert.strictEqual expected[1], parseInt res.rows[1].count, 10
            assert.strictEqual expected[2], parseInt res.rows[2].count, 10
            assert.strictEqual expected[3], parseInt res.rows[3].count, 10
            assert.strictEqual expected[4], parseInt res.rows[4].count, 10
            assert.strictEqual expected[5], parseInt res.rows[5].count, 10
            next()

    testDelete = (next)->
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

        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                pMgr.insert modelD, {connector: connector, reflect: true}, (err, id)->
                    assert.ifError err
                    pMgr.insert modelE, {connector: connector, reflect: true}, (err, id)->
                        assert.ifError err
                        pMgr.insert modelF, {connector: connector}, (err, id)->
                            assert.ifError err
                            assertCount pMgr, [2, 1, 3, 1, 1, 1], connector, ->
                                modelD.remove pMgr.getId 'ClassC'
                                modelD.remove pMgr.getId 'ClassD'
                                modelE.remove pMgr.getId 'ClassC'
                                modelE.remove pMgr.getId 'ClassE'
                                pMgr.insert modelD, {connector: connector, reflect: true}, (err, id)->
                                    assert.ifError err
                                    pMgr.insert modelE, {connector: connector, reflect: true}, (err, id)->
                                        assert.ifError err
                                        pMgr.insert modelF, {connector: connector, reflect: true}, (err, id)->
                                            assert.ifError err
                                            assertCount pMgr, [4, 2, 6, 2, 2, 2], connector, ->
                                                pMgr.delete modelF, {connector: connector}, (err)->
                                                    assert.ifError err
                                                    assertCount pMgr, [4, 2, 5, 2, 2, 1], connector, ->
                                                        pMgr.delete modelE, {connector: connector}, (err)->
                                                            assert.ifError err
                                                            assertCount pMgr, [3, 1, 4, 2, 1, 1], connector, ->
                                                                pMgr.delete modelD, {connector: connector}, (err)->
                                                                    assert.ifError err
                                                                    assertCount pMgr, [2, 1, 3, 1, 1, 1], connector, ->
                                                                        connector.rollback (err)->
                                                                            assert.ifError err
                                                                            next()
                                                                        , true

    testSave = (next)->
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

        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                pMgr.save modelD, {connector: connector}, (err, id)->
                    assert.ifError err
                    assert.strictEqual id, modelD.get pMgr.getId modelD.className
                    pMgr.save modelE, {connector: connector}, (err, id)->
                        assert.ifError err
                        assert.strictEqual id, modelE.get pMgr.getId modelE.className
                        pMgr.save modelF, {connector: connector}, (err, id)->
                            assert.ifError err
                            assert.strictEqual id, modelF.get pMgr.getId modelF.className
                            modelD.remove pMgr.getId 'ClassC'
                            modelD.remove pMgr.getId 'ClassD'
                            modelE.remove pMgr.getId 'ClassC'
                            modelE.remove pMgr.getId 'ClassE'
                            modelF.remove pMgr.getId 'ClassF'
                            pMgr.save modelD, {connector: connector}, (err, id)->
                                assert.ifError err
                                assert.strictEqual id, modelD.get pMgr.getId modelD.className
                                pMgr.save modelE, {connector: connector}, (err, id)->
                                    assert.ifError err
                                    assert.strictEqual id, modelE.get pMgr.getId modelE.className
                                    pMgr.save modelF, {connector: connector}, (err, id)->
                                        modelD.set 'propA1', newD1Value
                                        modelE.set 'propA1', newE1Value
                                        modelF.set 'propC1', newF1Value
                                        pMgr.save modelD, {connector: connector}, (err, id)->
                                            assert.ifError err
                                            assert.strictEqual newD1Value, modelD.get 'propA1'
                                            pMgr.save modelE, {connector: connector}, (err, id)->
                                                assert.ifError err
                                                assert.strictEqual newE1Value, modelE.get 'propA1'
                                                pMgr.save modelF, {connector: connector}, (err, id)->
                                                    assert.ifError err
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
                                                    assertListUnique pMgr, options, (model)->
                                                        assertPropSubClass model, modelD, modelE
                                                        connector.rollback (err)->
                                                            assert.ifError err
                                                            next()
                                                        , true

    testIssue1 = (next)->
        # Saving model with an unset propClass throws exception
        
        [pMgr, model, connector, Model] = setUpMapping()
        modelF = model.clone()
        modelF.className = 'ClassF'
        modelD = model.clone()
        modelD.className = 'ClassD'
        modelF.set 'propClassD', modelD

        # F -> C
        # E -> (B -> A), C
        # D -> A, C

        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                pMgr.save modelD, {connector: connector}, (err, id)->
                    assert.ifError err
                    pMgr.save modelF, {connector: connector}, (err, id)->
                        assert.ifError err
                        assert.strictEqual id, modelF.get pMgr.getId modelF.className
                        options =
                            classNameLetter: 'F'
                            model: modelF
                            letters: ['C', 'F']
                            listOptions:
                                where: [
                                    '{idC} = ' + id
                                ]
                                connector: connector
                        assertListUnique pMgr, options, (model)->
                            assertPropSubClass model, modelD
                            connector.rollback (err)->
                                assert.ifError err
                                next()
                            , true

    testIssue2 = (next)->
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

        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                pMgr.save modelD, {connector: connector}, (err, idD)->
                    assert.ifError err
                    pMgr.save modelF, {connector: connector}, (err, id)->
                        assert.ifError err
                        assert.strictEqual id, modelF.get pMgr.getId modelF.className
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
                        assertList pMgr, options, (models)->
                            assert.strictEqual models.length, 1
                            model = models[0]
                            assert.strictEqual model.propClassD.propA1, modelD.get 'propA1'
                            assert.strictEqual model.propC1, modelF.get 'propC1'
                            connector.rollback (err)->
                                assert.ifError err
                                next()
                            , true

    assertStream = (pMgr, options, callback, next)->
        classNameLetter = options.classNameLetter
        listOptions = options.listOptions

        className = 'Class' + classNameLetter
        pMgr.stream className, listOptions, callback, (err, fields)->
            assert.ifError err
            next err, fields

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
        , (err, fields)->
            assert.ifError err
            assert.strictEqual count, 1
            for letter in letters
                for index in [1..3]
                    assert.strictEqual model.get('prop' + letter + index), pModel.get 'prop' + letter + index
            next pModel

    testStreamBasic = (next)->
        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassA'

        options =
            classNameLetter: 'A'
            model: model
            listOptions:
                connector: connector

        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                pMgr.insert model, {connector: connector}, (err, id)->
                    assert.ifError err
                    assertStreamUnique pMgr, options, ->
                        id1 = id
                        options.listOptions.where = '{idA} = ' + id
                        assertStreamUnique pMgr, options, ->
                            options.listOptions.where = '{propA1} = ' + connector.escape model.get 'propA1'
                            assertStreamUnique pMgr, options, ->
                                model.set 'propA1', 'value'
                                pMgr.insert model, {connector: connector}, (err, id)->
                                    assert.ifError err
                                    id2 = id
                                    options.listOptions.where = [
                                        '{idA} = ' + id
                                        '{propA1} = ' + connector.escape model.get 'propA1'
                                    ]
                                    assertStreamUnique pMgr, options, ->
                                            column = '{propA1}'
                                            condition1 = column + ' = ' + connector.escape 'propA1Value' 
                                            condition2 = column +  ' = ' + connector.escape 'value' 
                                            options.listOptions.where = [
                                                squel.expr().and( condition1 ).or condition2 
                                            ]
                                            count = 0
                                            assertStream pMgr, options, (pModel)->
                                                if count is 0
                                                    assert.strictEqual 'propA1Value', pModel.get 'propA1'
                                                    assert.strictEqual id1, pModel.get 'idA'
                                                else if count is 1
                                                    assert.strictEqual 'value', pModel.get 'propA1'
                                                    assert.strictEqual id2, pModel.get 'idA'
                                                else
                                                    assert.strictEqual count, 1
                                                count++
                                            , (err, fields)->
                                                assert.ifError err
                                                options.listOptions.where = '{propA1} = ' + connector.escape model.get 'propA1'
                                                assertStreamUnique pMgr, options, ->
                                                    model.set 'propA2', 'value'
                                                    pMgr.insert model, {connector: connector}, (err, id)->
                                                        assert.ifError err
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
                                                        , (err, fields)->
                                                            assert.ifError err
                                                            connector.rollback (err)->
                                                                assert.ifError err
                                                                next()
                                                            , true

    testStreamSubClass = (next)->
        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassB'
        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                pMgr.insert model, {connector: connector}, (err, id)->
                    assert.ifError err
                    options =
                        classNameLetter: 'B'
                        model: model
                        letters: ['A', 'B']
                        listOptions:
                            where: '{idA} = ' + id
                            connector: connector
                    assertStreamUnique pMgr, options, ->
                        connector.rollback (err)->
                            assert.ifError err
                            next()
                        , true

    testStreamMixin = (next)->
        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassD'

        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                pMgr.insert model, {connector: connector}, (err, id)->
                    assert.ifError err
                    options =
                        classNameLetter: 'D'
                        model: model
                        letters: ['A', 'C', 'D']
                        listOptions:
                            where: '{idA} = ' + id
                            connector: connector
                    assertStreamUnique pMgr, options, ->
                        connector.rollback (err)->
                            assert.ifError err
                            next()
                        , true

    testStreamMixin2 = (next)->
        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassE'
        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                pMgr.insert model, {connector: connector}, (err, id)->
                    assert.ifError err
                    options =
                        classNameLetter: 'E'
                        model: model
                        letters: ['A', 'B', 'C', 'E']
                        listOptions:
                            where: '{idA} = ' + id
                            connector: connector
                    assertStreamUnique pMgr, options, ->
                        connector.rollback (err)->
                            assert.ifError err
                            next()
                        , true

    testStar = (next)->
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

        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err
                pMgr.insert modelD, {connector: connector}, (err, id)->
                    assert.ifError err
                    modelD.set pMgr.getId('ClassD'), id
                    pMgr.insert modelE, {connector: connector}, (err, id)->
                        assert.ifError err
                        modelE.set pMgr.getId('ClassE'), id
                        pMgr.insert modelF, {connector: connector}, (err, id)->
                            assert.ifError err
                            options =
                                classNameLetter: 'F'
                                model: modelF
                                letters: ['C', 'F']
                                listOptions:
                                    fields: ['propClassD:*', '*', 'propClassE:*']
                                    where: '{' + pMgr.getId('ClassF') + '} = ' + id
                                    connector: connector
                            # TODO: make sure only one query is sent
                            assertListUnique pMgr, options, (model)->
                                assertPropSubClass model, modelD, modelE
                                modelE.set 'propA1', newE1Value
                                modelF.set 'propC1', newF1Value
                                modelE.remove pMgr.getId 'ClassE'
                                modelF.remove pMgr.getId 'ClassF'
                                pMgr.insert modelE, {connector: connector}, (err, id)->
                                    assert.ifError err
                                    modelE.set pMgr.getId('ClassE'), id
                                    pMgr.insert modelF, {connector: connector}, (err, id)->
                                        assert.ifError err
                                        options.listOptions.where = '{propC1} = ' + connector.escape newF1Value
                                        assertListUnique pMgr, options, (model)->
                                            assertPropSubClass model, modelD, modelE
                                            options.listOptions.where = '{propClassE:propA1} = ' + connector.escape newE1Value
                                            assertListUnique pMgr, options, (model)->
                                                assertPropSubClass model, modelD, modelE
                                                options.listOptions.where = [
                                                    '{propClassE:propA1} = ' + connector.escape newE1Value
                                                    '{propC1} = ' + connector.escape newF1Value
                                                ]
                                                assertListUnique pMgr, options, (model)->
                                                    assertPropSubClass model, modelD, modelE
                                                    options.listOptions.where = [
                                                        '{propClassE:propA1} = ' + connector.escape 'propA1Value'
                                                        '{propC1} = ' + connector.escape newF1Value
                                                    ]
                                                    pMgr.list 'ClassF', options.listOptions, (err, models)->
                                                        assert.ifError err
                                                        assert.strictEqual models.length, 0
                                                        connector.rollback (err)->
                                                            assert.ifError err
                                                            next()
                                                        , true

    testIssue3 = (next)->
        # Nested condition on non selected field crash
        # Mixin cause inner join instead of left join for left join parent
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
        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err

                pMgr.list 'User', options, (err, models)->
                    assert.ifError err
                    assert.ok models.length > 0
                    pModels = models
                    options.fields = [
                        'id'
                        'author:country:property:*'
                        'author:language:property:*'
                    ]

                    pMgr.list 'User', options, (err, models)->
                        for model, index in models
                            assert.strictEqual 'country.CAMEROUN', model.get('author').get('country').get('property').get('code')
                            assert.strictEqual model.get('id'), pModels[index].get('id')
                        connector.rollback (err)->
                            assert.ifError err
                            next()
                        , true

    testJoin = (next)->
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
                    condition: '{translation, property} = {country:property}'
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

        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err

                pMgr.list 'User', options, (err, models)->
                    assert.ifError err
                    assert.ok models.length > 0
                    for model in models
                        assert.strictEqual strCode, model.get('country').get('property').get('code')
                        assert.strictEqual strCode, model.get('translation').get('property').get('code')
                    connector.rollback (err)->
                        assert.ifError err
                        next()
                    , true

    testIssue4 = (next)->
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

        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err

                pMgr.list 'User', options, (err, models)->
                    assert.ifError err
                    assert.ok models.length > 0
                    for model in models
                        assert.strictEqual strCode, model.country.property.code
                        assert.strictEqual strCode, model.ctry.property.code
                    connector.rollback (err)->
                        assert.ifError err
                        next()
                    , true

    testSelectParts = (next)->
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
            order: '{id}'
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
                '{LNG, key} = ' + connector.escape 'FR'
                '{country:property:code} = ' + connector.escape strCode
            ]
            limit: 10
            offset: 0
        connector.acquire (err)->
            assert.ifError err
            connector.begin (err)->
                assert.ifError err

                pMgr.list 'User', options, (err, models)->
                    assert.ifError err
                    assert.ok models.length > 0
                    for model in models
                        assert.strictEqual strCode, model.country.property.code
                        assert.strictEqual strCode, model.ctry.property.code
                    connector.rollback (err)->
                        assert.ifError err
                        next()
                    , true

    # issue: test update on subclass with no properties
    # testOtherStream with committed transactions
    # test optimistic lock
    #   update
    #   delete
    # sort,group on mixin|parent class prop
    # sort,group on property class prop
    # sort, group, limit offset
    # initialize model i.e. use database value to fill model values. must have an id
    # stream list
    # check bad filter
    # check:
    #     database and mapping are compatible
    # collection
    # stream with inherited =>
    #   2 connections?
    # stream with collections?
    #   two connections?
    # decision: manually set joins, stream only do one request, charge to you to recompute records
    
    series = [
        setUp
        testBasicMapping
        testBasicMapping2
        testInheritance
        testCircularReference
        testThrows
        testGet
        testInsert
        testInsertBasic
        testInsertSubClass
        testInsertMixin
        testInsertMixin2
        testListBasic
        testListSubClass
        testListMixin
        testListMixin2
        testListPropSubClass
        testListField
        testUpdate
        testDelete
        testSave
        testIssue1
        testIssue2
        testStreamBasic
        testStreamSubClass
        testStreamMixin
        testStreamMixin2
        testStar
        testIssue3
        testJoin
        testIssue4
        testSelectParts
        tearDown
    ]

    async.series series, assert.done