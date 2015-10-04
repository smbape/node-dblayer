store
=======

Experimental ORM, QueryBuilder, QueryTemplating.

Paused.

The idea is using a mapping
```coffee-script

mapping['Data'] =
    table: 'BASIC_DATA'
    ctor: Backbone.Model
    id:
        name: 'id'
        column: 'DAT_ID'
    properties:
        author:
            column: 'AOR_ID'
            className: 'User'

mapping['User'] =
    table: 'USERS'
    ctor: Backbone.Model
    id: className: 'Data'
    properties:
        name: 'USE_NAME'
        firstName: 'USE_FIRST_NAME'
        email: 'USE_EMAIL'
        login: 'USE_LOGIN'
        password: 'USE_PASSWORD'
        country: className: 'Country'
        occupation: 'USE_OCCUPATION'
        language: className: 'Language'
        ip: 'USE_IP'
    constraints: [
        {type: 'unique', properties: ['login']}
        {type: 'unique', properties: ['email']}
    ]
```

and options
```coffee-script
options =
    dialect: 'postgres'
    fields: [
        'id'
        'name'
        'firstName'
        'name'
        'occupation'
        'email'
        'country:id'
    ]
    join:
        ctry:
            entity: 'Translation'
            type: 'left'
            condition: '{ctry, property} = {country:property}'
            fields: 'value'
        LNG:
            entity: 'Language'
            type: 'left'
            condition: '{LNG, id} = {ctry, language}'
    where: '{LNG, key} IS NULL OR {LNG, key} = __lng__'
    order: '{id}'
```

will generate
```coffee-script
manager = new Manager(mapping)
compiled = manager.compile 'User', options
template = compiled.template
consume = compiled.consume

# Server side
query = template {lng: 'FR'}
dbConnector.stream query, (row)->
    response.stream row
    return
, (err)->
    response.done(err)
    return

# Client side
request = new Request(url);
request.on 'row', (row)->
    obj = consume row
    return
request.on 'end', done
```

Server returns raw results and client puts data where it should be.
Should support multiple inheritence (mixins, properties inherited or only ids), stream, transactions.

License
-------
The MIT License (MIT)

Copyright (c) 2014-2015 Stéphane MBAPE (http://smbape.com)

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
