logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager, squel} = require '../../'

describe 'select blocks', ->
    it 'should order, group, having, limit, offset', (done)->
        connector = globals.pools.writer.createConnector()

        countryCode = 'CAMEROUN'

        options =
            type: 'json'
            connector: connector
            fields: [
                'id'
                'country:property:code'
            ]
            join:
                ctry:
                    entity: 'Translation'
                    type: 'left'
                    condition: '{ctry, property} = {country:property}'
                    fields: 'property:code'
                LNG:
                    entity: 'Language'
                    type: 'left'
                    condition: '{LNG, id} = {ctry, language}'
            order: [['{id}', true]]
            group: [
                '{id}'
                '{country}'
                '{country:property}'
                '{country:property:code}'
                '{ctry, property}'
                '{ctry, property:code}'
                '{LNG, key}'
            ]
            having: [
                '{LNG, key} = __fr__'
                [
                    '{LNG, key} IN ?', ['FR']
                ]
                squel.expr().and '{LNG, key} <> __en__'
                [
                    '{country:property:code} = ?', countryCode
                ]
            ]
            limit: 10
            offset: 0
            values:
                fr: connector.escape 'FR'
                en: connector.escape 'EN'

        twaterfall connector, [
            (next)-> globals.pMgr.list 'User', options, next
            (models, next)->
                assert.ok models.length > 0
                for model in models
                    assert.strictEqual countryCode, model.country.property.code
                    assert.strictEqual countryCode, model.ctry.property.code
                next()
                return
        ], done

        return

    return

