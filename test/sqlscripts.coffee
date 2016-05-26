async = require 'async'
_ = require 'lodash'
{squel} = require('../')

module.exports = (config, connectors, done)->
    pMgr = globals.pMgr

    scripts = []

    languages = []
    languages.push
        data:
            code: 'fr-FR'
            key: 'FR'
            label: 'Français'
        translation:
            'fr-FR': 'Français'
            'en-GB': 'French'

    languages.push
        data:
            code: 'en-GB'
            key: 'EN'
            label: 'English'
        translation:
            'fr-FR': 'Anglais'
            'en-GB': 'English'

    countries = []
    countries.push
        data:
            code: 'ARGENTINA'
        translation:
            'fr-FR': 'Argentine'
            'en-GB': 'Argentina'
    countries.push
        data:
            code: 'CAMEROUN'
        translation:
            'fr-FR': 'Cameroun'
            'en-GB': 'Cameroon'
    countries.push
        data:
            code: 'FRANCE'
        translation:
            'fr-FR': 'France'
            'en-GB': 'France'
    countries.push
        data:
            code: 'UNITED KINGDOM'
        translation:
            'fr-FR': 'Royaumes Unis'
            'en-GB': 'United Kingdom'

    data = languages.concat(countries)
    properties = data.map (data)-> data.data
    translations = data.map (data)-> data.translation
    insertPropertiesQuery = pMgr.getInsertQueryString 'Property', properties, {dialect: config.dialect}

    PROPERTIES = {}
    LANGUAGES = {}
    COUNTRIES = {}

    users = []
    names = ['Abbot', 'Brandt', 'Compton', 'Dykes', 'Ernst', 'Fultz', 'Gutierrez', 'Yamamoto']
    firstNames = ['Brice', 'Felton', 'Lee', 'Trent', 'Hank', 'Ismael'].concat ['Clara', 'Kyoko', 'Pearl', 'Sofia', 'Julie', 'Melba']
    occupations = ['Drafter', 'Housebreaker', 'Miner', 'Physician']

    async.waterfall [
        (next)-> connectors.writer.query insertPropertiesQuery, next
        (res, next)-> pMgr.listProperty {type: 'json'}, next
        (rows, next)->
            for row in rows
                PROPERTIES[row.code] = pMgr.newProperty row

            for language in languages
                language.data.property = PROPERTIES[language.data.code]

            insertLanguagesQuery = pMgr.getInsertQueryString 'Language', languages.map((data)-> data.data), {dialect: config.dialect}
            connectors.writer.query insertLanguagesQuery, next
            return
        (res, next)->
            pMgr.listLanguage {
                type: 'json'
                fields: ['*', 'property:*']
            }, next
            return
        (rows, next)->
            for row in rows
                LANGUAGES[row.code] = pMgr.newLanguage row

            for country in countries
                country.data.property = PROPERTIES[country.data.code]

            insertCountriesQuery = pMgr.getInsertQueryString 'Country', countries.map((data)-> data.data), {dialect: config.dialect}
            connectors.writer.query insertCountriesQuery, next
            return
        (res, next)->
            pMgr.listCountry {
                type: 'json'
                fields: ['*', 'property:*']
            }, next
            return
        (rows, next)->
            for row in rows
                COUNTRIES[row.code] = pMgr.newLanguage row

            entries = []
            i = 0
            _.forEach PROPERTIES, (property)->
                for lng, value of translations[i]
                    entries.push
                        language: LANGUAGES[lng]
                        property: property
                        value: value
                i++
                return

            insertTranslationsQuery = pMgr.getInsertQueryString 'Translation', entries, {dialect: config.dialect}
            connectors.writer.query insertTranslationsQuery, next
            return
        (res, next)->
            name = 'admin'
            firstName = 'admin'
            pMgr.insertUser {
                name: name.toUpperCase()
                firstName: firstName
                email: firstName.toLowerCase() + '.' + name.toLowerCase() + '@xxxxx.com'
                login: firstName.charAt(0).toLowerCase() + name.toLowerCase()
                occupation: occupations[0]
                country: COUNTRIES.CAMEROUN
                language: LANGUAGES['fr-FR']
            }, next
            return
        (admin, next)->
            countries = Object.keys(COUNTRIES)
            languages = Object.keys(LANGUAGES)

            author = null
            for name, iname in names
                for firstName, i in firstNames
                    users.push
                        name: name.toUpperCase()
                        firstName: firstName
                        email: firstName.toLowerCase() + '.' + name.toLowerCase() + '@xxxxx.com'
                        login: firstName.charAt(0).toLowerCase() + name.toLowerCase()
                        occupation: occupations[(iname + i) % occupations.length]
                        country: COUNTRIES[countries[(iname + i + 1) % countries.length]]
                        language: LANGUAGES[languages[(iname + i + 1) % languages.length]]
                        author: admin

            insertUsersDataQuery = pMgr.getInsertQueryString 'Data', users, {dialect: config.dialect}
            connectors.writer.query insertUsersDataQuery, next
            return
        (id, next)->
            pMgr.listData {
                type: 'json'
                fields: ['id']
                offset: 1
            }, next
            return
        (rows, next)->
            for row, i in rows
                users[i].id = row.id

            insertUsersQuery = pMgr.getInsertQueryString 'User', users, {dialect: config.dialect}
            connectors.writer.query insertUsersQuery, next
            return
    ], done
    return
