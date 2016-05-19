logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager, squel} = require '../../'

describe 'manager methods', ->
    it 'should get column', ->
        [pMgr, model, connector, Model] = setUpMapping()
        assert.strictEqual pMgr.getTable('ClassA'), 'CLASS_A'
        assert.strictEqual pMgr.getColumn('ClassA', 'idA'), 'A_ID'
        assert.strictEqual pMgr.getColumn('ClassA', 'propA1'), 'PROP_A1'
        assert.strictEqual pMgr.getColumn('ClassA', 'propA2'), 'PROP_A2'
        assert.strictEqual pMgr.getColumn('ClassA', 'propA3'), 'PROP_A3'
        return

    return
