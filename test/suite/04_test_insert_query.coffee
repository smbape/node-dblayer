logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager, squel} = require '../../'

describe 'insert query', ->

    mapping = {}
    Model = undefined
    model = undefined

    it 'should generate insert query for native type properties', ->
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

        assertInsertQuery(mapping, model, 'ClassA', squel.insert(squelOptions)
            .into adapter.escapeId mapping['ClassA'].table
            .setFields squelFields {colIdA: 'idAValue', colPropA1: 'propA1Value'}
            .toString())

        return

    it 'should generate insert query for className properties', ->
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

        assertInsertQuery(mapping, model, 'ClassB', squel.insert(squelOptions)
            .into adapter.escapeId mapping['ClassB'].table
            .setFields squelFields {colIdB: 'idBValue', colIdA: 'idAValue', colPropB2: 'propB2Value'}
            .toString())

        # id + properties class
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

        assertInsertQuery(mapping, model, 'ClassB', squel.insert(squelOptions)
            .into adapter.escapeId mapping['ClassB'].table
            .setFields squelFields {colIdB: 'idBValue', colPropB1: 'idAValue', colPropB2: 'propB2Value'}
            .toString())

        return

    it 'should generate insert query for nested className properties', ->
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

        assertInsertQuery(mapping, model, 'ClassC', squel.insert(squelOptions)
            .into adapter.escapeId mapping['ClassC'].table
            .setFields squelFields {idC: 'idCValue', colIdA: 'idAValue'}
            .toString())

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

        assertInsertQuery(mapping, model, 'ClassC', squel.insert(squelOptions)
            .into adapter.escapeId mapping['ClassC'].table
            .setFields squelFields {idC: 'idCValue', colIdB: 'idAValue'}
            .toString())

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

        assertInsertQuery(mapping, model, 'ClassD', squel.insert(squelOptions)
            .into adapter.escapeId mapping['ClassD'].table
            .setFields squelFields {idD: 'idDValue', colIdA: 'idAValue'}
            .toString())

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

        assertInsertQuery(mapping, model, 'ClassD', squel.insert(squelOptions)
            .into adapter.escapeId mapping['ClassD'].table
            .setFields squelFields {idD: 'idDValue', colIdB: 'idAValue'}
            .toString())

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

        assertInsertQuery(mapping, model, 'ClassD', squel.insert(squelOptions)
            .into adapter.escapeId mapping['ClassD'].table
            .setFields squelFields {idD: 'idDValue', colIdC: 'idAValue'}
            .toString())

        return

    it 'should throw error if no id is setted for sub-element', ->
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
        return

    it 'should only insert setted properties', ->
        # only insert setted properties
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

        assertInsertQuery(mapping, model, 'ClassD', squel.insert(squelOptions)
            .into adapter.escapeId mapping['ClassD'].table
            .setFields squelFields
                idD: 'idDValue'
                colIdC: 'idAValue'
                colPropD1: 'propD1Value'
                colPropD3: 'propD3Value'
            .toString())

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

        assert.strictEqual(query.text, squel.insert(squelOptions)
            .into adapter.escapeId mapping['ClassB'].table
            .setFields(squelFields({
                colIdA: '?'
                colPropB0: '?'
                colPropB1: '?'
                colPropB3: '?'
            }) , {dontQuote: true})
            .toString())

        assert.strictEqual query.values[1], 'idAB0Value'
        assert.strictEqual query.values[2], 'propB1Value'
        assert.strictEqual query.values[3], 'propB3Value'

        query = query.values[0]
        assert.strictEqual(query.toString(), squel.insert(squelOptions)
            .into adapter.escapeId mapping['ClassA'].table
            .setFields squelFields
                colIdA: 'idAValue'
                colPropA1: 'propA1Value'
                colPropA3: 'propA3Value'
            .toString())

        return

    it 'should insert query for mixins', ->
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
        assert.strictEqual(query.text, squel.insert(squelOptions)
            .into adapter.escapeId mapping['ClassC'].table
            .setFields(squelFields({
                colIdA: '?'
                colIdB: '?'
                colIdC: '?'
                colPropC0: '?'
                colPropC1: '?'
                colPropC3: '?'
            }) , {dontQuote: true})
            .toString())
        assert.strictEqual query.values[2], 'idCValue'
        assert.strictEqual query.values[3], 'idAC0Value'
        assert.strictEqual query.values[4], 'propC1Value'
        assert.strictEqual query.values[5], 'propC3Value'

        query2 = query.values[0]
        assert.strictEqual(query2.toString(), squel.insert(squelOptions)
            .into adapter.escapeId mapping['ClassA'].table
            .setFields squelFields
                colIdA: 'idAValue'
                colPropA1: 'propA1Value'
                colPropA3: 'propA3Value'
            .toString())

        query2 = query.values[1]
        assert.strictEqual(query2.toString(), squel.insert(squelOptions)
            .into adapter.escapeId mapping['ClassB'].table
            .setFields squelFields
                colIdB: 'idBValue'
                colPropB0: 'idAB0Value'
                colPropB1: 'propB1Value'
                colPropB3: 'propB3Value'
            .toString())

        return
    return
