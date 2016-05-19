logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager, squel} = require '../../'

describe 'select blocks', ->
    logger.error 'tests are broken because database has no data'
    return

    it 'should order, group, having, limit, offset', (done)->
        connector = pools.writer.createConnector()

        strCode = 'country.CAMEROUN'

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
                    '{country:property:code} = ?', strCode
                ]
            ]
            limit: 10
            offset: 0
            values:
                fr: connector.escape 'FR'
                en: connector.escape 'EN'

        twaterfall connector, [
            (next)-> pMgr.list 'User', options, next
            (models, next)->
                assert.ok models.length > 0
                for model in models
                    assert.strictEqual strCode, model.country.property.code
                    assert.strictEqual strCode, model.ctry.property.code
                next()
                return
        ]

        return

    return

