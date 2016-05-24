logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager, squel} = require '../../'

describe 'sync', ->
    @timeout 3600 * 1000

    it 'should create when model does not exist', (done)->
        [pMgr, model, connector, Model] = setUpMapping()
        opts = _.defaults {
            purge: true
            cascade: false
            if_exists: false
            prompt: false
        }, _.pick(config, ['tmp', 'keep', 'stdout', 'stderr'])
        id = undefined

        twaterfall connector, [
            (next)->
                pMgr.sync connectors.admin, _.defaults({exec: true}, opts), next
                return
            (queries, oldModel, newModel, next)->
                # console.log require('util').inspect(oldModel.TRANSLATIONS, {colors: true, depth: null})
                # console.log require('util').inspect(newModel.TRANSLATIONS, {colors: true, depth: null})
                # console.log queries
                assert.ok queries.length
                pMgr.sync connectors.admin, _.defaults({exec: false}, opts), next
                return
            (queries, oldModel, newModel, next)->
                # console.log require('util').inspect(oldModel.TRANSLATIONS, {colors: true, depth: null})
                # console.log require('util').inspect(newModel.TRANSLATIONS, {colors: true, depth: null})
                # console.log queries
                assert.strictEqual queries, ''
                pMgr.insertClassJ {propJ1: 'propJ1', propJ2: 'propJ2', propJ3: 'propJ3'}, {connector}, next
                return
            (_id, next)->
                id = _id
                pMgr.listClassJ {connector, type: 'json'}, next
                return
            (rows, next)->
                assert.strictEqual rows.length, 1
                assert.deepEqual rows[0], {
                    idC: id
                    propJ1: 'propJ1'
                    propJ2: 'propJ2'
                    propJ3: 'propJ3'
                    propClassD: null
                    propClassE: null
                    propC1: null
                    propC2: null
                    propC3: null
                }
                next()
                return
        ], done
        return

    return
