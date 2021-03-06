_ = require 'lodash'

_.extend exports,
    postgres:
        root: 'postgres'       # a user who can create/use database and create schema
        password: 'dev.psql'
        database: 'postgres'
        schema: 'DBLAYER_TEST'
        host: '127.0.0.1'
        port: 5432
        cmd: 'psql'
        create:
            database: false
            schema: true
            users: true
            model: false
        drop:
            database: false
            schema: true
            users: true

    mysql:
        root: 'root'
        password: 'dev.mysql'
        host: '127.0.0.1'
        port: 3306
        cmd: 'mysql'
        database: 'DBLAYER_TEST'
        create:
            database: true
            users: true
            model: false
        drop:
            database: true
            users: true

    mssql:
        root: 'sa'
        password: 'dev.mssql'
        host: '127.0.0.1'
        port: 1433
        database: 'DBLAYER_TEST'
        create:
            database: true
            users: true
            model: false
        drop:
            database: true
            users: true

for dialect, config of exports
    _.extend config,
        users:
            admin:
                adapter: dialect
                name: 'bcms_admin'
                password: 'bcms_admin'
            writer:
                adapter: dialect
                name: 'bcms_writer'
                password: 'bcms_writer'
            reader:
                adapter: dialect
                name: 'bcms_reader'
                password: 'bcms_reader'
        stdout: null # 1, process.stdout
        stderr: null # 2, process.stderr
        keep: false

for key in Object.keys(exports)
    newConfig = exports['new_' + key] = _.cloneDeep exports[key]
    newConfig.create.model = true

    for name, user of newConfig.users
        user.name = 'new_' + user.name
        user.password = 'new_' + user.password

    if newConfig.schema
        newConfig.schema = 'NEW_' + newConfig.schema
    else
        newConfig.database = 'NEW_' + newConfig.database

for dialect, config of exports
    for name, user of config.users
        _.defaults user, {user: user.name}, _.pick config, ['host', 'port', 'database', 'schema']

# console.log require('util').inspect exports, {colors: true, depth: null}
