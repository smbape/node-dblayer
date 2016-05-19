logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager, squel} = require '../../'

describe 'update', ->
    it 'should update', (done)->
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

        twaterfall connector, [
            (next)-> pMgr.insert modelD, {connector, reflect: true}, next
            (id, next)-> pMgr.insert modelE, {connector, reflect: true}, next
            (id, next)-> pMgr.insert modelF, {connector, reflect: true}, next
            (id, next)->
                modelD.unset pMgr.getIdName 'ClassC'
                modelD.unset pMgr.getIdName 'ClassD'
                modelE.unset pMgr.getIdName 'ClassC'
                modelE.unset pMgr.getIdName 'ClassE'
                modelF.unset pMgr.getIdName 'ClassF'
                pMgr.insert modelD, {connector, reflect: true}, next
                return
            (id, next)-> pMgr.insert modelE, {connector, reflect: true}, next
            (id, next)-> pMgr.insert modelF, {connector, reflect: true}, next
            (id, next)->
                modelD.set 'propA1', newD1Value
                modelE.set 'propA1', newE1Value
                modelF.set 'propC1', newF1Value
                pMgr.update modelD, {connector}, next
                return
            (id, msg, next)->
                assert.strictEqual msg, 'update'
                pMgr.update modelE, {connector}, next
                return
            (id, msg, next)->
                assert.strictEqual msg, 'update'
                modelF.set 'propClassD', modelD.get pMgr.getIdName 'ClassD'
                pMgr.update modelF, {connector}, next
                return
            (id, msg, next)->
                assert.strictEqual msg, 'update'
                # update should reflect className properties
                actualAttributes = modelF.get('propClassD').toJSON()
                expectedAttributes = _.pick modelD.toJSON(), Object.keys(actualAttributes)
                assert.deepEqual actualAttributes, expectedAttributes
                modelF.set 'propClassD', modelD.get pMgr.getIdName 'ClassD'
                pMgr.update modelF, {connector}, next
                return
            (id, msg, next)->
                assert.strictEqual msg, 'no-update'
                # update should reflect className properties even on no-update
                actualAttributes = modelF.get('propClassD').toJSON()
                expectedAttributes = _.pick modelD.toJSON(), Object.keys(actualAttributes)
                assert.deepEqual actualAttributes, expectedAttributes
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
    return
