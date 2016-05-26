logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager, squel} = require '../../'

describe 'stream', ->

    it 'should stream plain mapping', (done)->
        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassA'

        options =
            classNameLetter: 'A'
            model: model
            listOptions:
                connector: connector

        id1 = id2 = null
        twaterfall connector, [
            (next)-> pMgr.insert model, {connector}, next
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
                pMgr.insert model, {connector}, next
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
                pMgr.insert model, {connector}, next
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
        ], done

        return

    it 'should stream inherited properties', (done)->
        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassB'

        twaterfall connector, [
            (next)-> pMgr.insert model, {connector}, next
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
        ], done
        return

    it 'should stream mixin 1/2', (done)->
        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassD'

        twaterfall connector, [
            (next)-> pMgr.insert model, {connector}, next
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
        ], done
        return

    it 'should stream mixin 2/2', (done)->
        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassE'

        twaterfall connector, [
            (next)-> pMgr.insert model, {connector}, next
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
        ], done
        return

    it 'should stream nested properties', (done)->
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
        listConnector = globals.pools.reader.createConnector()

        options = listOptions = null
        async.waterfall [
            (next)-> connector.acquire next
            (performed, next)-> pMgr.insert modelD, {connector, reflect: true}, next
            (id, next)->
                pMgr.insert modelE, {connector}, next
                return
            (id, next)->
                # modelE will be used for multiple insert.
                # Using reflect will cause every related class to have an id, therefore preventing new insertion of the same object
                modelE.set pMgr.getIdName('ClassE'), id
                pMgr.insert modelF, {connector}, next
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
                pMgr.insert modelE, {connector}, next
                return
            (id, next)->
                modelE.set pMgr.getIdName('ClassE'), id
                pMgr.insert modelF, {connector}, next
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
                pMgr.insert modelF, {connector}, next
                return
            (id, next)-> pMgr.insert modelF, {connector, listConnector: listConnector}, next
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
        ], done

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
