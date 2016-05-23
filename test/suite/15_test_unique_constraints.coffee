logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager, squel} = require '../../'

describe 'unique constraints', ->

    it 'should unique constraints', (done)->
        # unique constraint used on initialize, update, delete => where must be on properties
        # For convenience, even if a table has a unique constraint on multiple column,
        # add a unique primary key column to get it when insert or update
        # initialize goes with list => where is handled
        # update and delete, for each unique constraint, take the first one that has all it's fields not null

        [pMgr, model, connector, Model] = setUpMapping()
        _model = null

        id0 = id1 = id2 = 0
        twaterfall connector, [
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
            (id, msg, next)->
                id1 = id
                model.set 'propG1', 'valueG12'
                model.set 'propG2', 'valueG22'
                model.set 'propG3', 'valueG32'
                pMgr.insert model, {connector: connector}, next
                return
            (id, next)->
                id2 = id
                pMgr.list 'ClassG', {connector: connector, count: true}, next
                return
            (count, next)->
                assert.strictEqual count, 3
                model.unset pMgr.getIdName model.className
                pMgr.initialize model, {connector: connector}, next
                return
            (rows, next)->
                assert.strictEqual rows[0].get(pMgr.getIdName model.className), id2
                model.unset pMgr.getIdName model.className
                debugger
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
            (id, msg, next)-> pMgr.list 'ClassG', {connector: connector, count: true}, next
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
        ], done
        return

    return
