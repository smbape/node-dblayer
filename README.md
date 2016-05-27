# dblayer

ORM, QueryBuilder, QueryTemplating.

## Usage

### Overview

```coffeescript

dblayer = require('dblayer')
mapping = {...}
pMgr = new PersistenceManager mapping, options

pMgr.insertClassName[ options,] callback
pMgr.listClassName[ options,] callback
pMgr.updateClassName[ options,] callback
pMgr.deleteClassName[ options,] callback
pMgr.saveClassName[ options,] callback

```


### Define a mapping

```coffeescript

dblayer = require('dblayer')
_ = require('lodash')
Backbone = require('backbone')

domains = {
    serial:
        type: 'increments'
    short_label:
        type: 'varchar'
        type_args: [31]
    medium_label:
        type: 'varchar'
        type_args: [63]
    long_label:
        type: 'varchar'
        type_args: [255]
    comment:
        type: 'varchar'
        type_args: [1024]
    version:
        type: 'varchar'
        type_args: [10]
        nullable: false
        handlers:
            insert: (value, model, options)->
                '1.0'
            update: (value, model, options)->
                if 'major' is model.get('semver')
                    return (parseInt(value.split('.')[0], 10) + 1) + '.0'
                else
                    value = value.split('.')
                    value[1] = 1 + parseInt(value[1], 10)
                    return value.join('.')
    datetime:
        type: 'timestamp'
        nullable: false
        handlers:
            insert: (model, options, extra)->
                new Date()
            read: (value, model, options)->
                # how to convert database data to property value
                moment.utc(moment(value).format 'YYYY-MM-DD HH:mm:ss.SSS').toDate()
            write: (value, model, options)->
                # how to convert property value to a database valid value
                moment(value).utc().format 'YYYY-MM-DD HH:mm:ss.SSS'
    email:
        type: 'varchar'
        type_args: [63]
    code:
        type: 'varchar'
        type_args: [63]
}

domains.mdate = _.defaults {
    # update only if this value hasn't change compared to the actual one
    lock: true

    # new value to set
    update: (model, options, extra)->
        new Date()
}, domains.datetime

mapping = {}

mapping['User'] =
    table: 'USERS'
    # A valid constructor must have methods ['get', 'set', 'unset', 'toJSON']
    ctor: Backbone.Model.extend {className: 'User'}
    id:
        name: 'id' # property name
        column: 'USR_ID'
        domain: domains.serial
    properties:
        name:
            column: 'USE_NAME'

            # define type using domain property
            domain: domains.medium_label
        firstName:
            column: 'USE_FIRST_NAME'

            # define type using type/type_args properties
            type: 'varchar'
            type_args: [255]
        email:
            column: 'USE_EMAIL'
            domain: domains.email
        login:
            column: 'USE_LOGIN'
            domain: domains.short_label
            nullable: false # login is required. yield a NOT NUL to the column
        password:
            column: 'USE_PASSWORD'
            domain: domains.long_label
        country:
            # this property refers to a Country object class
            className: 'Country'
        occupation:
            column: 'USE_OCCUPATION'
            domain: domains.long_label
        language:
            # this property refers to a Language object class
            className: 'Language'
    constraints: [
        # add some unique constraints
        {type: 'unique', name: 'LOGIN', properties: ['login']}
        {type: 'unique', name: 'EMAIL', properties: ['email']}
    ]

mapping['Property'] =
    table: 'PROPERTIES'
    id:
        name: 'id'
        column: 'LPR_ID'
        domain: domains.serial
    properties:
        code:
            column: 'LPR_CODE'
            domain: domains.code
            nullable: false
    constraints: {type: 'unique', properties: ['code']}

mapping['Language'] =
    table: 'LANGUAGES'
    id:
        name: 'id'
        column: 'LNG_ID'
        domain: domains.serial
    properties:
        code:
            column: 'LNG_CODE'
            domain: domains.short_label
            nullable: false
        key:
            column: 'LNG_KEY'
            domain: domains.short_label
        label:
            column: 'LNG_LABEL'
            domain: domains.medium_label
        property: className: 'Property'
    constraints: {type: 'unique', properties: ['code']}

mapping['Country'] =
    table: 'COUNTRIES'
    id:
        name: 'id'
        column: 'CRY_ID'
        domain: domains.serial
            nullable: false
    properties:
        code:
            column: 'CRY_CODE'
            domain: domains.code
        property: className: 'Property'


# make sure database and schema exist
# make sure users exist and have access to the database and the schema
PersistenceManager = dblayer.PersistenceManager

pMgr = new PersistenceManager mapping, {
    users:
        # will be used to create the model
        admin:
            name: 'admin' # whatever, used for logging
            adapter: 'postgres' # postgres/mysql
            host: '127.0.0.1'
            port: 5432
            database: 'postgres'
            schema: 'DBLAYER'
            user: 'admin'
            password: 'secret'

        # If there is a user that can only read/write into tables
        # using that user ensures that we wont create/alter/delete tables
        # no matter what coding mistakes we make
        writer:
            name: 'writer' # whatever, used for logging
            adapter: 'postgres' # postgres/mysql
            host: '127.0.0.1'
            port: 5432
            database: 'postgres'
            schema: 'DBLAYER'
            user: 'writer'
            password: 'secret'

        # If there is a user that can only read into tables
        # using that user ensures that we wont do anything other than reading
        # no matter what coding mistakes we make
        reader:
            name: 'reader' # whatever, used for logging
            adapter: 'postgres' # postgres/mysql
            host: '127.0.0.1'
            port: 5432
            database: 'postgres'
            schema: 'DBLAYER'
            user: 'reader'
            password: 'secret'
}

```

### Sync model and databse if needed

```coffeescript

# review what will be done on sync
pMgr.sync {exec: false}, (err, queries, oldModel, newModel)->
    if err
        console.error err
        return

    {drop_constraints, drops, creates, alters} = queries
    console.log drop_constraints.concat(drops).concat(creates).concat(alters).join(';\n')

    # destroy pools, otherwise active connections will make us hang
    # to do only when exiting the process
    pMgr.destroyPools()
    return


# perform sync
pMgr.sync {exec: true}, (err, queries, oldModel, newModel)->
    if err
        console.error err
        return

    {drop_constraints, drops, creates, alters} = queries
    console.log drop_constraints.concat(drops).concat(creates).concat(alters).join(';\n')

    # destroy pools, otherwise active connections will make us hang
    # to do only when exiting the process
    pMgr.destroyPools()
    return

# sync and attempt to delete everything that is not in the mapping.
# !!! use with caution
pMgr.sync {purge: true, exec: true}, (err, queries, oldModel, newModel)->
    if err
        console.error err
        return

    {drop_constraints, drops, creates, alters} = queries
    console.log drop_constraints.concat(drops).concat(creates).concat(alters).join(';\n')

    # destroy pools, otherwise active connections will make us hang
    # to do only when exiting the process
    pMgr.destroyPools()
    return

# sync and attempt to cascade delete everything that is not in the mapping.
# !!! use with caution
pMgr.sync {purge: true, cascade: true, exec: true}, (err, queries, oldModel, newModel)->
    if err
        console.error err
        return

    {drop_constraints, drops, creates, alters} = queries
    console.log drop_constraints.concat(drops).concat(creates).concat(alters).join(';\n')

    # destroy pools, otherwise active connections will make us hang
    # to do only when exiting the process
    pMgr.destroyPools()
    return

```

### Insert

```coffeescript

# Insert from plain object
pMgr.insertUser {name: 'root', login: 'root'}, (err, id)->
    console.log 'added user', id

    # destroy pools, otherwise active connections will make us hang
    # to do only when exiting the process
    pMgr.destroyPools()
    return

# Insert from object instance
user = pMgr.newUser {name: 'user1', login: 'user1'}
# or
# user = pMgr.newInstance 'User', {name: 'user2', login: 'user2'}

pMgr.insert user, {}, (err, id)->
    console.log 'added user', id

    # destroy pools, otherwise active connections will make us hang
    # to do only when exiting the process
    pMgr.destroyPools()
    return

# or if you want to use the same model to insert another class object
user = new Backbone.Model {name: 'user3', login: 'user3'}
pMgr.insert user, {className: 'User'}, (err, id)->
    console.log 'added user', id

    # destroy pools, otherwise active connections will make us hang
    # to do only when exiting the process
    pMgr.destroyPools()
    return

```

### List

```coffeescript

# List all users
# pMgr.listClassName[, options], callback
# pMgr.list ClassName , options, callback
pMgr.listUser (err, models)->
    if err
        console.error err
        return

    for model in models
        console.log model.get 'name'

    # destroy pools, otherwise active connections will make us hang
    # to do only when exiting the process
    pMgr.destroyPools()
    return

# List returning json
pMgr.listUser {type: 'json'}, (err, models)->
    if err
        console.error err
        return

    for model in models
        console.log model.name

    # destroy pools, otherwise active connections will make us hang
    # to do only when exiting the process
    pMgr.destroyPools()
    return

# A more complex one
connector = pMgr.connectors.reader
# https://hiddentao.github.io/squel/index.html
squel = dblayer.squel

pMgr.list 'User', {
    type: 'json'
    connector: connector

    # add a custom column
    columns:
        'custom':
            column: "CASE {LNG, key} WHEN #{connector.escape 'custom'} THEN 1 ELSE 0 END"
            read: (value)->
                !!value

    # only select these fields of User
    fields: [
        'id'
        'country:property:code'
    ]

    # join with these
    join:
        ctry:
            entity: 'Translation'
            type: 'left'
            condition: '{ctry, property} = {country:property}'

            # select also this field of Translation
            fields: 'property:code'

        LNG:
            entity: 'Language'
            type: 'left'
            condition: '{LNG, id} = {ctry, language}'

    # order like this
    order: [['{id}', true]]

    # group like this
    group: [
        '{id}'
        '{country}'
        '{country:property:code}'
        '{ctry, property:code}'
        '{LNG, key}'
    ]

    # still following ...
    where: [
        '{LNG, key} = __fr__'
        [
            '{LNG, key} IN ?', ['FR', 'EN']
        ]
        squel.expr().and '{LNG, key} <> __en__'
        [
            '{country:property:code} = ?', 'CAMEROUN'
        ]
    ]
    limit: 10
    offset: 0

    # place named holders values
    values:
        fr: connector.escape 'FR'
        en: connector.escape 'EN'

}, (err, models)->
    if err
        console.error err
        return

    for model in models
        console.log {
            'model.id': model.id
            'model.custom': model.custom
            'model.country.property.code': model.country.property.code
            'model.ctry.property.code': model.ctry.property.code
        }

    # destroy pools, otherwise active connections will make us hang
    # to do only when exiting the process
    pMgr.destroyPools()
    return

```

### Update

```coffeescript

pMgr.listUser {limit: 1}, (err, models)->
    if err
        console.error err
        return

    user = models[0]
    user.set 'name', 'new name'

    # pMgr.updateUser user[, options], callback
    # pMgr.update user, options, callback
    pMgr.update user, {}, (err, id, msg)->
        if err
            console.error err
            return

        # msg will be update or no-update
        console.log 'message', msg

        pMgr.listUser {limit: 1}, (err, models)->
            if err
                console.error err
                return

            console.log 'updated', models[0].get('name') is 'new name'

            # destroy pools, otherwise active connections will make us hang
            # to do only when exiting the process
            pMgr.destroyPools()
            return
        return
    return

```

### Transactions

```coffeescript

async = require 'async'
AdapterPool = dblayer.AdapterPool

pool = new AdapterPool
    name: 'reader' # whatever, used for logging
    adapter: 'postgres' # postgres/mysql
    host: '127.0.0.1'
    port: 5432
    database: 'postgres'
    schema: 'DBLAYER'
    user: 'reader'
    password: 'secret'
    minConnection: 0
    maxConnection: 10
    idleTimeout: 10 * 60 # close connections that have been unused connections for 10 minutes

connector = pool.createConnector()
acquired = false
transaction = false
inserted = null
async.waterfall [
    (next)-> connector.acquire next
    (performed, next)->
        # performed will be true if a new connection was acquired from the pool
        # false if a connection was already acquired
        acquired = performed

        connector.acquire next

    (performed, next)->
        # performed will be false

        # start a transation
        connector.begin next
        return
    (next)->
        transaction = true

        # make a savepoint
        connector.begin next
        return

    (next)->
        # make another savepoint
        connector.begin next
        return

    (next)->
        pMgr.insertUser {name: 'user4', login: 'user4'}, {connector}, next
        return

    (id, next)->
        console.log 'inserted', id
        inserted = id
        pMgr.listUser {connector, type: 'json', where: {id: inserted}}, next
        return

    (models, next)->
        console.log 'visible in transaction', (models[0].id is inserted)

        # rollback to previous save point
        connector.rollback next
        return

    (next)->
        pMgr.listUser {connector, type: 'json', where: {id: inserted}}, next
        return

    (models, next)->
        console.log 'not in transaction', (models.length is 0)

        # make another savepoint
        connector.begin next
        return

    (next)->
        # release previous save point
        connector.commit next

        return

    (next)->
        # release all save points, commit and put back connection in the pool
        connector.commit next, true

        # or rollback all save points and put back connection in the pool
        # connector.rollback next, true
        
        # or controlled commit
        # connection.commit (err)->
        #     # save point released
        #
        #     connection.commit (err)->
        #         # transaction committed
        #         
        #         # put back connection in the pool
        #         connector.release next
        return
], (err)->
    if err
        console.error err

    pool.destroyAll false, (err)->
        console.error err if err
        return

    pMgr.destroyPools false, (err)->
        console.error err if err
        return
    return

```

### Logging

```coffeescript

# log4js package needed
log4js = global.log4js = require 'log4js'

log4js.configure
    "appenders": [
        "type": "console"
        "layout":
            "type": "colored"
    ],
    "levels":
        # DEBUG will log connection creation/destruction, inserted/updated ids
        # TRACE will log every queries done through connector
        "[all]": "DEBUG"

```

## Test

on a unix like terminal

```sh
npm test
```

### Test and coverage
```sh
npm run test-cover
```

### Test a dialect
```sh
DIALECT=postgres node node_modules/mocha/bin/_mocha --full-trace --compilers coffee:coffee-script/register test/prepare.coffee test/suite
```

# More examples

For more examples, look in test/suite

# History
I had a to generate statistic reports of data available in json files (some of them were more than 500MB, writen in a single line) and in a database.  
Data in the json files were related to data in the database.  
The application that generates those data was in java.  
With nodejs and the appropriate librairies, reading those json files was 10 times faster than with tools I found in java.  
There are ORMs that I could have used: [bookshelfjs](http://bookshelfjs.org/), [node-orm2](https://github.com/dresende/node-orm2) or [sequelize](http://docs.sequelizejs.com/en/latest/docs/querying/).

However, no matter what librairy I would have choosen, there were limitations
    - Mapping an existing model was not straight forward (existing tables, columns, constraints), especially for inheritance
    - There was no way to take advantage of SQL query skill without writting raw queries.  
    Example: joinctions, aliased columns, filter/group/order on nested properties.  
    Therefore, there is no need for an ORM
    - I didn't see a way to stream results

My problem was specific and there was no ready to use solutions.  
The specific problem was solved as a part of the application, using java, because it was easier to interact with the existing model like that.  
It was also freaking slow.  
I get pissed off and I decided to create my own ORM in nodejs which has what I wanted:
    - Be close as possible to SQL language
    - Should support multiple inheritance (mixins, properties inherited or only ids)
    - Should support stream
    - Should support transactions.
    - Server returns raw results and client puts data where it should be.

# License

The MIT License (MIT)

Copyright (c) 2014-2016 Stéphane MBAPE (http://smbape.com)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
