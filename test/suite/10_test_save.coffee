logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager, squel} = require '../../'

describe 'save', ->
    it 'should save', (done)->
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

        step = 0
        twaterfall connector, [
            (next)-> pMgr.save modelD, {connector}, next
            (id, msg, next)->
                assert.strictEqual msg, 'insert'
                assert.strictEqual id, modelD.get pMgr.getIdName modelD.className
                pMgr.save modelE, {connector}, next
                return
            (id, msg, next)->
                assert.strictEqual msg, 'insert'
                assert.strictEqual id, modelE.get pMgr.getIdName modelE.className
                pMgr.save modelF, {connector}, next
                return
            (id, msg, next)->
                assert.strictEqual msg, 'insert'
                assert.strictEqual id, modelF.get pMgr.getIdName modelF.className
                modelD.unset pMgr.getIdName 'ClassC'
                modelD.unset pMgr.getIdName 'ClassD'
                modelE.unset pMgr.getIdName 'ClassC'
                modelE.unset pMgr.getIdName 'ClassE'
                modelF.unset pMgr.getIdName 'ClassF'
                pMgr.save modelD, {connector}, next
                return
            (id, msg, next)->
                # missing id attibutes should make save insert, even if only one in the table
                assert.strictEqual msg, 'insert'
                assert.strictEqual id, modelD.get pMgr.getIdName modelD.className
                modelD.prevId = modelD.get pMgr.getIdName modelD.className
                pMgr.save modelE, {connector}, next
                return
            (id, msg, next)->
                # missing id attibutes should make save insert, even if only one in the table
                assert.strictEqual msg, 'insert'
                assert.strictEqual id, modelE.get pMgr.getIdName modelE.className
                modelE.prevId = modelE.get pMgr.getIdName modelE.className
                pMgr.save modelF, {connector}, next
                return
            (id, msg, next)->
                # missing id attibutes should make save insert, even if only one in the table
                assert.strictEqual msg, 'insert'
                modelF.prevId = modelF.get pMgr.getIdName modelF.className
                modelD.set 'propA1', newD1Value
                modelE.set 'propA1', newE1Value
                modelF.set 'propC1', newF1Value
                pMgr.save modelD, {connector}, next
                return
            (id, msg, next)->
                # save should update if a single match is found
                assert.strictEqual msg, 'update'
                assert.strictEqual newD1Value, modelD.get 'propA1'
                assert.strictEqual id, modelD.get pMgr.getIdName modelD.className
                assert.strictEqual id, modelD.prevId
                pMgr.save modelE, {connector}, next
                return
            (id, msg, next)->
                # save should update if a single match is found
                assert.strictEqual msg, 'update'
                assert.strictEqual newE1Value, modelE.get 'propA1'
                assert.strictEqual id, modelE.get pMgr.getIdName modelE.className
                assert.strictEqual id, modelE.prevId
                pMgr.save modelF, {connector}, next
                return
            (id, msg, next)->
                # save should update if a single match is found
                assert.strictEqual msg, 'update'
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
        ], done

        return

    it 'should fix issue: Saving model with an unset propClass throws exception', (done)->
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
        twaterfall connector, [
            (next)-> pMgr.save modelD, {connector}, next
            (id, msg, next)->
                assert.strictEqual msg, 'insert'
                pMgr.insert modelF, {connector}, next
                return
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
            (model, next)-> pMgr.delete model, {connector}, next
            (res, next)->
                modelF.set 'propClassE', ''
                pMgr.insert modelF, {connector}, next
                return
            (id, next)-> assertListUnique pMgr, options, next
            (model, next)->
                assertPropSubClass model, modelD
                assert.strictEqual model.get('propClassE'), null
                pMgr.delete model, {connector}, next
                return
            (res, next)->
                modelF.set 'propClassD', modelD.get pMgr.getIdName 'ClassD'
                modelF.unset 'propClassE'
                pMgr.insert modelF, {connector}, next
                return
            (id, next)-> assertListUnique pMgr, options, next
            (model, next)->
                assertPropSubClass model, modelD
                assert.strictEqual model.get('propClassE'), null
                pMgr.delete model, {connector}, next
                return
            (res, next)-> 
                modelF.set 'propClassD', parseInt modelD.get(pMgr.getIdName 'ClassD'), 10
                modelF.unset 'propClassE'
                pMgr.insert modelF, {connector}, next
                return
            (id, next)-> assertListUnique pMgr, options, next
            (model, next)->
                assertPropSubClass model, modelD
                assert.strictEqual model.get('propClassE'), null
                pMgr.save modelF, {connector}, next
                return
            (id, msg, next)->
                assert.strictEqual msg, 'insert'
                assert.strictEqual id, modelF.get pMgr.getIdName modelF.className
                options.listOptions.where = [
                    '{idC} = ' + id
                ]
                pMgr.list 'ClassF', {connector, count: true}, next
                return
            (count, next)->
                assert.strictEqual count, 2
                assertListUnique pMgr, options, next
                return
            (model, next)->
                assertPropSubClass model, modelD
                next()
                return
        ], done

        return

    return