logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager, squel} = require '../../'

describe 'sync', ->
    @timeout 15 * 1000

    concatQueries = ({drop_constraints, drops, creates, alters})->
        drop_constraints.concat(drops).concat(creates).concat(alters).join(';\n')

    it 'should update existing model', (done)->
        [pMgr, model, connector, Model] = setUpMapping()
        connector = globals.connectors.new_writer
        opts = _.defaults {
            cascade: false
            if_exists: false
            prompt: false
        }, _.pick(globals.config, ['tmp', 'keep', 'stdout', 'stderr'])
        id = undefined
        step = 0

        twaterfall connector, [
            (next)->
                # logger.fatal 'step', ++step
                pMgr.sync globals.connectors.new_admin, _.defaults({purge: false, exec: true}, opts), next
                return
            (queries, oldModel, newModel, next)->
                # logger.fatal 'step', ++step
                assert.ok concatQueries(queries).length

                assert.property oldModel, 'ACTIONS'
                assert.property oldModel, 'DEFAULT_PRIVILEDGES'
                assert.property oldModel, 'DELEGATES'
                assert.property oldModel, 'FOLDER'
                assert.property oldModel, 'PRIVILEDGES'
                assert.property oldModel, 'RESOURCE'
                assert.property oldModel, 'WORKSPACE'
                assert.property oldModel, 'CLASS_D'
                assert.property oldModel.CLASS_D, 'indexes'
                assert.property oldModel.CLASS_D.indexes, 'RELATIONSHIP_1_FK'
                assert.property oldModel, 'CLASS_E'
                assert.property oldModel.CLASS_E, 'indexes'
                assert.property oldModel.CLASS_E.indexes, 'RELATIONSHIP_2_FK'
                assert.property oldModel, 'CLASS_F'
                assert.property oldModel.CLASS_F, 'indexes'
                assert.property oldModel.CLASS_F.indexes, 'RELATIONSHIP_3_FK'
                assert.property oldModel.CLASS_F.indexes, 'RELATIONSHIP_4_FK'
                assert.property oldModel, 'CLASS_H'
                assert.property oldModel.CLASS_H, 'indexes'
                assert.property oldModel.CLASS_H.indexes, 'RELATIONSHIP_5_FK'
                assert.property oldModel.CLASS_H.indexes, 'RELATIONSHIP_6_FK'

                pMgr.sync globals.connectors.new_admin, _.defaults({purge: true, exec: false}, opts), next
                return
            (queries, oldModel, newModel, next)->
                # logger.fatal 'step', ++step
                # not purge should keep not mapped tables but rename indexes
                assert.ok concatQueries(queries).length

                assert.property oldModel, 'ACTIONS'
                assert.property oldModel, 'DEFAULT_PRIVILEDGES'
                assert.property oldModel, 'DELEGATES'
                assert.property oldModel, 'FOLDER'
                assert.property oldModel, 'PRIVILEDGES'
                assert.property oldModel, 'RESOURCE'
                assert.property oldModel, 'WORKSPACE'
                assert.property oldModel, 'CLASS_D'
                assert.property oldModel.CLASS_D, 'indexes'
                assert.property oldModel.CLASS_D.indexes, 'RELATIONSHIP_1_FK'
                assert.property oldModel, 'CLASS_E'
                assert.property oldModel.CLASS_E, 'indexes'
                assert.property oldModel.CLASS_E.indexes, 'RELATIONSHIP_2_FK'
                assert.property oldModel, 'CLASS_F'
                assert.property oldModel.CLASS_F, 'indexes'
                assert.property oldModel.CLASS_F.indexes, 'CUSTOM_FK'
                assert.property oldModel.CLASS_F.indexes, 'CLASS_F_CLA_A_ID_HAS_CLASS_E_A_ID_FK'
                assert.property oldModel, 'CLASS_H'
                assert.property oldModel.CLASS_H, 'indexes'
                assert.property oldModel.CLASS_H.indexes, 'RELATIONSHIP_5_FK'
                assert.property oldModel.CLASS_H.indexes, 'RELATIONSHIP_6_FK'

                pMgr.insertClassJ {propJ1: 'propJ1', propJ2: 'propJ2', propJ3: 'propJ3'}, {connector}, next
                return
            (_id, next)->
                # logger.fatal 'step', ++step
                id = _id
                pMgr.listClassJ {connector, type: 'json'}, next
                return
            (rows, next)->
                # logger.fatal 'step', ++step
                assert.lengthOf rows, 1
                assert.deepEqual rows[0], {
                    idC: id
                    propJ1: 'propJ1'
                    propJ2: 'propJ2'
                    propJ3: 'propJ3'
                    propJ4: 'default value'
                    propClassD: null
                    propClassE: null
                    propC1: null
                    propC2: null
                    propC3: null
                }
                pMgr.sync globals.connectors.new_admin, _.defaults({purge: true, exec: true}, opts), next
                return
            (queries, oldModel, newModel, next)->
                # logger.fatal 'step', ++step
                pMgr.sync globals.connectors.new_admin, _.defaults({purge: true, exec: false}, opts), next
                return
            (queries, oldModel, newModel, next)->
                # logger.fatal 'step', ++step
                # purge should remove tables and indexes
                assert.lengthOf concatQueries(queries), 0

                # console.log require('util').inspect oldModel.CLASS_D, {colors: true, depth: null}

                assert.notProperty oldModel, 'ACTIONS'
                assert.notProperty oldModel, 'DEFAULT_PRIVILEDGES'
                assert.notProperty oldModel, 'DELEGATES'
                assert.notProperty oldModel, 'FOLDER'
                assert.notProperty oldModel, 'PRIVILEDGES'
                assert.notProperty oldModel, 'RESOURCE'
                assert.notProperty oldModel, 'WORKSPACE'
                assert.notProperty oldModel.CLASS_D, 'indexes'
                assert.notProperty oldModel.CLASS_E, 'indexes'
                assert.notProperty oldModel.CLASS_H, 'indexes'

                pMgr.listClassJ {connector, type: 'json'}, next
                return
            (rows, next)->
                # logger.fatal 'step', ++step
                assert.lengthOf rows, 1
                assert.deepEqual rows[0], {
                    idC: id
                    propJ1: 'propJ1'
                    propJ2: 'propJ2'
                    propJ3: 'propJ3'
                    propJ4: 'default value'
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
