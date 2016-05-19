logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager, squel} = require '../../'

describe 'insert', ->
    it 'should should insert plain mapping', (done)->
        [pMgr, model, connector, Model] = setUpMapping()
        model.className = 'ClassA'

        async.waterfall [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.insert model, {connector}, next
            (id, next)-> assertPersist pMgr, model, 'A', id, connector, next
            (row, next)-> connector.rollback next, true
        ], done
        return

    it 'should should insert mapping with className', (done)->
        [pMgr, model, connector] = setUpMapping()
        model.className = 'ClassB'

        async.waterfall [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.getInsertQuery(model, {connector}).execute connector, next
            (id, next)-> assertPersist pMgr, model, 'B', id, connector, next
            (row, next)-> assertPersist pMgr, model, 'A', row, connector, next
            (row, next)-> connector.rollback next, true
        ], done

        return

    it 'should insert mapping with mixin 1/2', (done)->
        [pMgr, model, connector] = setUpMapping()
        model.className = 'ClassD'
        rowD = null

        async.waterfall [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.insert model, {connector}, next
            (id, next)-> assertPersist pMgr, model, 'D', id, connector, next
            (row, next)->
                rowD = row
                # Mixin must have the correct id
                assertPersist pMgr, model, 'C', row, connector, next
                return
            # Inherited parent must have the correct id
            (row, next)-> assertPersist pMgr, model, 'A', rowD, connector, next
            (row, next)-> connector.rollback next, true
        ], done

        return

    it 'should insert mapping with mixin 2/2', (done)->
        # insert on class with mixins should also insert in mixins table with the correct id
        # one parent that has inheritance and one final mixin

        [pMgr, model, connector] = setUpMapping()
        model.className = 'ClassE'

        rowE = null
        async.waterfall [
            (next)-> connector.acquire next
            (performed, next)-> connector.begin next
            (next)-> pMgr.insert model, {connector: connector}, next
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
            (row, next)-> connector.rollback next, true
        ], done

        return
    return
