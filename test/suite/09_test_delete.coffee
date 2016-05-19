logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager, squel} = require '../../'

describe 'delete', ->

    it 'should delete', (done)->
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

        twaterfall connector, [
            (next)-> pMgr.insert modelD, {connector, reflect: true}, next
            (id, next)-> pMgr.insert modelE, {connector, reflect: true}, next
            (id, next)-> pMgr.insert modelF, {connector}, next
            (id, next)-> assertCount pMgr, [2, 1, 3, 1, 1, 1], connector, next
            (next)->
                modelD.unset pMgr.getIdName 'ClassC'
                modelD.unset pMgr.getIdName 'ClassD'
                modelE.unset pMgr.getIdName 'ClassC'
                modelE.unset pMgr.getIdName 'ClassE'
                pMgr.insert modelD, {connector, reflect: true}, next
                return
            (id, next)-> pMgr.insert modelE, {connector, reflect: true}, next
            (id, next)-> pMgr.insert modelF, {connector, reflect: true}, next
            (id, next)-> assertCount pMgr, [4, 2, 6, 2, 2, 2], connector, next
            (next)-> pMgr.delete modelF, {connector}, next
            (res, next)->
                assert.strictEqual res.affectedRows, 1
                assertCount pMgr, [4, 2, 5, 2, 2, 1], connector, next
                return
            (next)-> pMgr.delete modelE, {connector}, next
            (res, next)->
                assert.strictEqual res.affectedRows, 1
                assertCount pMgr, [3, 1, 4, 2, 1, 1], connector, next
                return
            (next)-> pMgr.delete modelD, {connector}, next
            (res, next)->
                assert.strictEqual res.affectedRows, 1
                assertCount pMgr, [2, 1, 3, 1, 1, 1], connector, next
                return
        ], done

        return

    return