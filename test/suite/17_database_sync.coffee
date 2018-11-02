logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager, squel} = require '../../'

describe 'sync', ->
    @timeout 15 * 1000

    concatQueries = ({drop_constraints, drops, creates, alters})->
        drop_constraints.concat(drops).concat(creates).concat(alters).join(';\n')

    tableNameLowerCase = (name, lower_case_table_names)->
        return if lower_case_table_names is 1 then name.toLowerCase() else name

    it 'should update existing model', (done)->
        [pMgr, model, connector, Model] = setUpMapping()
        connector = globals.connectors.new_writer
        syncConnector = globals.connectors.new_admin

        opts = _.defaults {
            cascade: false
            if_exists: false
            prompt: false
            connector: syncConnector
        }, _.pick(globals.config, ['tmp', 'keep', 'stdout', 'stderr'])

        id = undefined
        step = 0

        twaterfall connector, [
            (next)->
                # logger.fatal 'step', ++step
                pMgr.sync _.defaults({purge: false, exec: true}, opts), next
                return
            (queries, oldModel, newModel, next)->
                # logger.fatal 'step', ++step
                assert.ok concatQueries(queries).length
                { options: { lower_case_table_names } } = queries

                assert.property oldModel, tableNameLowerCase('ACTIONS', lower_case_table_names)
                assert.property oldModel, tableNameLowerCase('DEFAULT_PRIVILEDGES', lower_case_table_names)
                assert.property oldModel, tableNameLowerCase('DELEGATES', lower_case_table_names)
                assert.property oldModel, tableNameLowerCase('FOLDER', lower_case_table_names)
                assert.property oldModel, tableNameLowerCase('PRIVILEDGES', lower_case_table_names)
                assert.property oldModel, tableNameLowerCase('RESOURCE', lower_case_table_names)
                assert.property oldModel, tableNameLowerCase('WORKSPACE', lower_case_table_names)
                assert.property oldModel, tableNameLowerCase('CLASS_D', lower_case_table_names)
                assert.property oldModel[tableNameLowerCase('CLASS_D', lower_case_table_names)], 'indexes'
                assert.property oldModel[tableNameLowerCase('CLASS_D', lower_case_table_names)].indexes, 'RELATIONSHIP_1_FK'
                assert.property oldModel, tableNameLowerCase('CLASS_E', lower_case_table_names)
                assert.property oldModel[tableNameLowerCase('CLASS_E', lower_case_table_names)], 'indexes'
                assert.property oldModel[tableNameLowerCase('CLASS_E', lower_case_table_names)].indexes, 'RELATIONSHIP_2_FK'
                assert.property oldModel, tableNameLowerCase('CLASS_F', lower_case_table_names)
                assert.property oldModel[tableNameLowerCase('CLASS_F', lower_case_table_names)], 'indexes'
                assert.property oldModel[tableNameLowerCase('CLASS_F', lower_case_table_names)].indexes, 'RELATIONSHIP_3_FK'
                assert.property oldModel[tableNameLowerCase('CLASS_F', lower_case_table_names)].indexes, 'RELATIONSHIP_4_FK'
                assert.property oldModel, tableNameLowerCase('CLASS_H', lower_case_table_names)
                assert.property oldModel[tableNameLowerCase('CLASS_H', lower_case_table_names)], 'indexes'
                assert.property oldModel[tableNameLowerCase('CLASS_H', lower_case_table_names)].indexes, 'RELATIONSHIP_5_FK'
                assert.property oldModel[tableNameLowerCase('CLASS_H', lower_case_table_names)].indexes, 'RELATIONSHIP_6_FK'

                pMgr.sync _.defaults({purge: true, exec: false}, opts), next
                return
            (queries, oldModel, newModel, next)->
                # logger.fatal 'step', ++step
                # not purge should keep not mapped tables but rename indexes
                assert.ok concatQueries(queries).length
                { options: { lower_case_table_names } } = queries

                assert.property oldModel, tableNameLowerCase('ACTIONS', lower_case_table_names)
                assert.property oldModel, tableNameLowerCase('DEFAULT_PRIVILEDGES', lower_case_table_names)
                assert.property oldModel, tableNameLowerCase('DELEGATES', lower_case_table_names)
                assert.property oldModel, tableNameLowerCase('FOLDER', lower_case_table_names)
                assert.property oldModel, tableNameLowerCase('PRIVILEDGES', lower_case_table_names)
                assert.property oldModel, tableNameLowerCase('RESOURCE', lower_case_table_names)
                assert.property oldModel, tableNameLowerCase('WORKSPACE', lower_case_table_names)
                assert.property oldModel, tableNameLowerCase('CLASS_D', lower_case_table_names)
                assert.property oldModel[tableNameLowerCase('CLASS_D', lower_case_table_names)], 'indexes'
                assert.property oldModel[tableNameLowerCase('CLASS_D', lower_case_table_names)].indexes, 'RELATIONSHIP_1_FK'
                assert.property oldModel, tableNameLowerCase('CLASS_E', lower_case_table_names)
                assert.property oldModel[tableNameLowerCase('CLASS_E', lower_case_table_names)], 'indexes'
                assert.property oldModel[tableNameLowerCase('CLASS_E', lower_case_table_names)].indexes, 'RELATIONSHIP_2_FK'
                assert.property oldModel, tableNameLowerCase('CLASS_F', lower_case_table_names)
                assert.property oldModel[tableNameLowerCase('CLASS_F', lower_case_table_names)], 'indexes'
                assert.property oldModel[tableNameLowerCase('CLASS_F', lower_case_table_names)].indexes, 'CUSTOM_FK'
                assert.property oldModel[tableNameLowerCase('CLASS_F', lower_case_table_names)].indexes, 'CLASS_F_CLA_A_ID_HAS_CLASS_E_A_ID_FK'
                assert.property oldModel, tableNameLowerCase('CLASS_H', lower_case_table_names)
                assert.property oldModel[tableNameLowerCase('CLASS_H', lower_case_table_names)], 'indexes'
                assert.property oldModel[tableNameLowerCase('CLASS_H', lower_case_table_names)].indexes, 'RELATIONSHIP_5_FK'
                assert.property oldModel[tableNameLowerCase('CLASS_H', lower_case_table_names)].indexes, 'RELATIONSHIP_6_FK'

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
                pMgr.sync _.defaults({purge: true, exec: true}, opts), next
                return
            (queries, oldModel, newModel, next)->
                # logger.fatal 'step', ++step
                pMgr.sync _.defaults({purge: true, exec: false}, opts), next
                return
            (queries, oldModel, newModel, next)->
                # logger.fatal 'step', ++step
                # purge should remove tables and indexes
                assert.lengthOf concatQueries(queries), 0
                { options: { lower_case_table_names } } = queries

                # console.log require('util').inspect oldModel[tableNameLowerCase('CLASS_D', lower_case_table_names)], {colors: true, depth: null}

                assert.notProperty oldModel, tableNameLowerCase('ACTIONS', lower_case_table_names)
                assert.notProperty oldModel, tableNameLowerCase('DEFAULT_PRIVILEDGES', lower_case_table_names)
                assert.notProperty oldModel, tableNameLowerCase('DELEGATES', lower_case_table_names)
                assert.notProperty oldModel, tableNameLowerCase('FOLDER', lower_case_table_names)
                assert.notProperty oldModel, tableNameLowerCase('PRIVILEDGES', lower_case_table_names)
                assert.notProperty oldModel, tableNameLowerCase('RESOURCE', lower_case_table_names)
                assert.notProperty oldModel, tableNameLowerCase('WORKSPACE', lower_case_table_names)
                assert.notProperty oldModel[tableNameLowerCase('CLASS_D', lower_case_table_names)], 'indexes'
                assert.notProperty oldModel[tableNameLowerCase('CLASS_E', lower_case_table_names)], 'indexes'
                assert.notProperty oldModel[tableNameLowerCase('CLASS_H', lower_case_table_names)], 'indexes'

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
