logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager, squel} = require '../../'

describe 'insert', ->
    it 'should should insert plain mapping', (done)->
        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassA'

        twaterfall connector, [
            (next)-> pMgr.insert model, {connector}, next
            (id, next)-> assertPersist pMgr, model, 'A', id, connector, next
        ], done
        return

    it 'should should insert mapping with className', (done)->
        [pMgr, model, connector] = setUpMapping()
        model.className = 'ClassB'

        twaterfall connector, [
            (next)-> pMgr.getInsertQuery(model, {connector}).execute connector, next
            (id, next)-> assertPersist pMgr, model, 'B', id, connector, next
            (row, next)-> assertPersist pMgr, model, 'A', row, connector, next
        ], done

        return

    it 'should insert mapping with mixin 1/2', (done)->
        [pMgr, model, connector] = setUpMapping()
        model.className = 'ClassD'
        rowD = null

        twaterfall connector, [
            (next)-> pMgr.insert model, {connector}, next
            (id, next)-> assertPersist pMgr, model, 'D', id, connector, next
            (row, next)->
                rowD = row
                # Mixin must have the correct id
                assertPersist pMgr, model, 'C', row, connector, next
                return
            # Inherited parent must have the correct id
            (row, next)-> assertPersist pMgr, model, 'A', rowD, connector, next
        ], done

        return

    it 'should insert mapping with mixin 2/2', (done)->
        # insert on class with mixins should also insert in mixins table with the correct id
        # one parent that has inheritance and one final mixin

        [pMgr, model, connector] = setUpMapping()
        model.className = 'ClassE'

        rowE = null
        twaterfall connector, [
            (next)-> pMgr.insert model, {connector}, next
            (id, next)-> assertPersist pMgr, model, 'E', id, connector, next
            (row, next)->
                rowE = row
                # Mixin must have the correct id
                assertPersist pMgr, model, 'C', row, connector, next
                return

            # Inherited parent must have the correct id
            (row, next)-> assertPersist pMgr, model, 'B', rowE, connector, next

            # Inherited parent of inherited parent must have the correct id
            (row, next)-> assertPersist pMgr, model, 'A', row, connector, next
        ], done

        return

    it 'should insert even if mixin properties are not defined', (done)->
        [pMgr, model, connector] = setUpMapping()
        id = null

        twaterfall connector, [
            (next)-> pMgr.insertClassF {propF1: 'propF1', propF2: 'propF2', propF3: 'propF3'}, {connector}, next
            (_id, next)->
                id = _id
                pMgr.listClassF {connector, type: 'json'}, next
                return
            (rows, next)->
                assert.strictEqual rows.length, 1
                assert.deepEqual rows[0], {
                    idC: id
                    propF1: 'propF1'
                    propF2: 'propF2'
                    propF3: 'propF3'
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
