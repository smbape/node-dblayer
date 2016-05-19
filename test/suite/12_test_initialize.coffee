logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager, squel} = require '../../'

describe 'initialize', ->

    it 'should initiliaze', (done)->
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
        twaterfall connector, [
            (next)-> pMgr.insert modelD, {connector}, next
            (id, next)->
                modelD.set pMgr.getIdName('ClassD'), id
                pMgr.insert modelE, {connector}, next
                return
            (id, next)->
                modelE.set pMgr.getIdName('ClassE'), id
                pMgr.insert modelF, {connector}, next
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
                pMgr.insert modelE, {connector}, next
                return
            (id, next)->
                modelE.set pMgr.getIdName('ClassE'), id
                pMgr.insert modelF, {connector}, next
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
        ], done

        return
    return
