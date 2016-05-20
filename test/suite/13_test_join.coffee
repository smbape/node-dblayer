logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager, squel} = require '../../'

describe 'join', ->
    it 'should generate select with join query', ->
        query = pMgr.getSelectQuery 'User', {
            join:
                translation:
                    entity: 'Translation'
                    condition: squel.expr().and '{translation, property} = {country:property}'
                    fields: [
                        'value'
                        'property:code'
                    ]
        }
        assert.include query.toString(), 'INNER JOIN'

        query = pMgr.getSelectQuery 'User', {
            join:
                translation:
                    type: 'default'
                    entity: 'Translation'
                    condition: squel.expr().and '{translation, property} = {country:property}'
                    fields: [
                        'value'
                        'property:code'
                    ]
        }
        assert.include query.toString(), 'INNER JOIN'

        query = pMgr.getSelectQuery 'User', {
            join:
                translation:
                    type: 'outer'
                    entity: 'Translation'
                    condition: squel.expr().and '{translation, property} = {country:property}'
                    fields: [
                        'value'
                        'property:code'
                    ]
        }
        assert.include query.toString(), 'OUTER JOIN'

        query = pMgr.getSelectQuery 'User', {
            join:
                translation:
                    type: 'left'
                    entity: 'Translation'
                    condition: squel.expr().and '{translation, property} = {country:property}'
                    fields: [
                        'value'
                        'property:code'
                    ]
        }
        assert.include query.toString(), 'LEFT JOIN'

        query = pMgr.getSelectQuery 'User', {
            join:
                translation:
                    type: 'right'
                    entity: 'Translation'
                    condition: squel.expr().and '{translation, property} = {country:property}'
                    fields: [
                        'value'
                        'property:code'
                    ]
        }
        assert.include query.toString(), 'RIGHT JOIN'

        query = pMgr.getSelectQuery 'User', {
            join:
                translation:
                    type: 'CROSS JOIN'
                    entity: 'Translation'
                    condition: squel.expr().and '{translation, property} = {country:property}'
                    fields: [
                        'value'
                        'property:code'
                    ]
        }
        assert.include query.toString(), 'CROSS JOIN'

        assertThrows ->
            pMgr.getSelectQuery 'User', {
                join:
                    translation:
                        entity: 'Translation'
                        condition: squel.expr().and '{xxxxx, property} = {country:property}'
                        fields: [
                            'value'
                            'property:code'
                        ]
            }
            return
        , 'TABLE_UNDEF'

        assertThrows ->
            pMgr.getSelectQuery 'User', {
                join:
                    translation:
                        type: {}
                        entity: 'Translation'
                        condition: squel.expr().and '{translation, property} = {country:property}'
                        fields: [
                            'value'
                            'property:code'
                        ]
            }
            return
        , 'JOIN_TYPE'

        return

    it 'should join', (done)->
        connector = pools.reader.createConnector()

        countryCode = 'CAMEROUN'

        options =
            connector: connector
            fields: [
                'id'
                'country:property:code'
            ]
            where: [
                '{LNG, key} = ' + connector.escape 'FR'
                '{country:property:code} = ' + connector.escape countryCode
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
                    assert.strictEqual countryCode, model.get('country').get('property').get('code')
                    assert.strictEqual countryCode, model.get('translation').get('property').get('code')

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

        countryCode = 'CAMEROUN'

        options =
            connector: connector
            fields: ['id']
            where: [
                '{author:country:property:code} = ' + connector.escape countryCode
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
                    assert.strictEqual countryCode, model.get('author').get('country').get('property').get('code')
                    assert.strictEqual model.get('id'), pModels[index].get('id')
                next()
                return
        ], done

        return

    it 'should fix issue: no field was considered as *', (done)->
        connector = pools.writer.createConnector()

        countryCode = 'CAMEROUN'

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
                '{country:property:code} = ' + connector.escape countryCode
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
                    assert.strictEqual countryCode, model.country.property.code
                    assert.strictEqual countryCode, model.ctry.property.code
                next()
                return
        ], done
        return

    return
