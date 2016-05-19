logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager, squel} = require '../../'

describe 'user defined columns', ->

    it 'select custom column', (done)->

        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassA'

        twaterfall connector, [
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
                return
        ], done
        return

    return
