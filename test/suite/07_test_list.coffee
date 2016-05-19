logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager, squel} = require '../../'

moment = require 'moment'

describe 'list', ->
    it 'should list on plain mapping', (done)->

        # Test list of inserted items in a with no relations
        # Test where condition

        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassA'

        options =
            classNameLetter: 'A'
            model: model
            listOptions: {connector}

        id1 = id2 = null
        twaterfall connector, [
            (next)-> pMgr.insert model, {connector}, next
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
                pMgr.insert model, {connector}, next
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
                pMgr.insert model, {connector}, next
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
                pMgr.insert model, {connector}, next
                return
            (id, next)->
                # H has no id
                assert.ok !id
                options.classNameLetter = 'H'
                assertListUnique pMgr, options, next
                return
            (_model, next)-> connector.rollback next, true
        ], done

        return

    it 'should list on mapping with className', (done)->
        # Test list on a class that has an inherited parent
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

                # Listing  classB should returned properties of ClassA and ClassB
                assertListUnique pMgr, options, next
                return
            (models, next)-> connector.rollback next, true
        ], done

        return

    it 'should list on mapping with mixins 1/2', (done)->
        # Test list on a class with parent and mixins
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

                # Listing  classD should returned properties of ClassA, ClassC and ClassD
                assertListUnique pMgr, options, next
                return
            (models, next)-> connector.rollback next, true
        ], done

        return

    it 'should list on mapping with mixins 2/2', (done)->

        # Test list of class with nested parent inheritance
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

                # Listing classD should returned properties of all related classes
                assertListUnique pMgr, options, next
                return
            (models, next)-> connector.rollback next, true
        ], done

        return

    it 'should list properties of className', (done)->
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
        twaterfall connector, [
            (next)-> pMgr.insert modelD, {connector, reflect: true}, next
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
                assertListUnique pMgr, options, next
                return
            (model, next)->
                # List must returned property class properties
                assertPropSubClass model, modelD, modelE
                modelE.set 'propA1', newE1Value
                modelF.set 'propC1', newFC1Value
                modelE.unset pMgr.getIdName 'ClassE'
                pMgr.insert modelE, {connector}, next
                return
            (id, next)->
                modelE.set pMgr.getIdName('ClassE'), id
                pMgr.insert modelF, {connector}, next
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
                pMgr.insert modelF, {connector}, next
                return
            (id, next)-> pMgr.insert modelF, {connector}, next
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
        ], done

        return

    it 'should list using handlers and only selected fields', (done)->
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
        twaterfall connector, [
            (next)-> pMgr.insert modelD, {connector, reflect: true}, next
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
                pMgr.insert modelE, {connector, reflect: true}, next
                return
            (id, next)->
                assert.strictEqual id, modelE.get pMgr.getIdName 'ClassE'
                modificationDate = moment modelE.get 'modificationDate'
                creationDate = moment modelE.get 'creationDate'
                assert.ok Math.abs(modificationDate.diff(creationDate)) < 2
                now = moment()
                assert.ok Math.abs(now.diff(creationDate)) < 1500
                assert.ok Math.abs(now.diff(modificationDate)) < 1500
                pMgr.insert modelF, {connector, reflect: true}, next
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
                pMgr.insert modelD, {connector, reflect: true}, next
                return
            (id, next)-> pMgr.insert modelE, {connector, reflect: true}, next
            (id, next)-> pMgr.insert modelF, {connector, reflect: true}, next
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
        ], done

        return

    it 'should fix issue: Combination of where and fields throws on certain circumstances', (done)->
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
        twaterfall connector, [
            (next)-> pMgr.save modelD, {connector: connector}, next
            (id, msg, next)->
                assert.strictEqual msg, 'insert'
                idD = id
                pMgr.save modelF, {connector: connector}, next
                return
            (id, msg, next)->
                assert.strictEqual msg, 'insert'
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
                return
            (models, next)->
                assert.strictEqual models.length, 1
                model = models[0]
                assert.strictEqual model.propClassD.propA1, modelD.get 'propA1'
                assert.strictEqual model.propC1, modelF.get 'propC1'
                next()
                return
        ], done

        return

    return
