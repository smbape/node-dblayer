logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager, squel} = require '../../'

describe 'join', ->
    logger.error 'tests are broken because database has no data'
    return

    it 'should join', (done)->
        strCode = 'country.CAMEROUN'

        options =
            connector: connector
            fields: [
                'id'
                'country:property:code'
            ]
            where: [
                '{LNG, key} = ' + connector.escape 'FR'
                '{country:property:code} = ' + connector.escape strCode
            ]
            join:
                translation:
                    entity: 'Translation'
                    condition: squel.expr().and '{translation, property} = {country:property}'
                    fields: [
                        'value'
                        'property:code'
                    ]
                LNG:
                    entity: 'Language'
                    type: 'left'
                    condition: '{LNG, id} = {translation, language}'
                    fields: [
                        'code'
                        'key'
                    ]
            limit: 5

        twaterfall connector, [
            (next)-> pMgr.list 'User', options, next
            (models, next)->
                assert.ok models.length > 0
                assert.ok models.length <= options.limit
                for model in models
                    assert.strictEqual strCode, model.get('country').get('property').get('code')
                    assert.strictEqual strCode, model.get('translation').get('property').get('code')

                # test count with fields and join
                # Using LIMIT you will not limit the count or sum but only the returned rows
                # http://stackoverflow.com/questions/17020842/mysql-count-with-limit#answers-header
                options.count = true
                pMgr.list 'User', options, next
                return
            (count, next)->
                # There are supposed to be 25 users matching the where field
                assert.strictEqual count, 25
                next()
                return
        ], done
        return

    it 'should fix list isues', (done)->
        # Nested condition on non selected field cause crash
        # Mixin parent causes inner join instead of left join for left join on child
        # Select a was select a:*

        connector = pools.writer.createConnector()

        options =
            connector: connector
            fields: 'id'
            where: [
                '{author:country:property:code} = ' + connector.escape 'country.CAMEROUN'
            ]
            order: '{id}' # Important. For an unknown reason, second query is ordered

        pModels = null
        twaterfall connector, [
            (next)-> pMgr.list 'User', options, next
            (models, next)-> 
                assert.ok models.length > 0
                pModels = models
                options.fields = [
                    'id'
                    'author:country:property:*'
                    'author:language:property:*'
                ]

                pMgr.list 'User', options, next
                return
            (models, next)->
                for model, index in models
                    assert.strictEqual 'country.CAMEROUN', model.get('author').get('country').get('property').get('code')
                    assert.strictEqual model.get('id'), pModels[index].get('id')
                next()
                return
        ], done

        return

    it 'should fix issue: no field was considered as *', (done)->
        connector = pools.writer.createConnector()

        strCode = 'country.CAMEROUN'

        options =
            type: 'json'
            connector: connector
            fields: [
                'name'
                'firstName'
                'occupation'
                'email'
                'country:property:code'
            ]
            where: [
                '{LNG, key} = ' + connector.escape 'FR'
                '{country:property:code} = ' + connector.escape strCode
            ]
            join:
                ctry:
                    entity: 'Translation'
                    condition: '{ctry, property} = {country:property}'
                    fields: [
                        'property:code'
                    ]
                LNG:
                    entity: 'Language'
                    type: 'left'
                    condition: '{LNG, id} = {ctry, language}'

        twaterfall connector, [
            (next)-> pMgr.list 'User', options, next
            (models, next)->
                assert.ok models.length > 0
                for model in models
                    assert.strictEqual strCode, model.country.property.code
                    assert.strictEqual strCode, model.ctry.property.code
                next()
                return
        ], done
        return

    return
