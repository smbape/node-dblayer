_ = require 'lodash'

module.exports =
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
        drop:
            database: false
            schema: true
            users: true
    mysql:
        # If you are on Windows
        # add in "C:\ProgramData\MySQL\MySQL Server 5.7\my.ini"
        # lower_case_table_names=2
        # and restart the server
        root: 'root'
        password: 'dev.mysql'
        host: '127.0.0.1'
        port: 3306
        cmd: 'mysql'
        database: 'DBLAYER_TEST'
        create:
            database: true
            users: true
        drop:
            database: true
            users: true

for dialect, config of module.exports
    _.extend config,
        users:
            admin:
                name: 'bcms_admin'
                password: 'bcms_admin'
            writer:
                name: 'bcms_writer'
                password: 'bcms_writer'
            reader:
                name: 'bcms_reader'
                password: 'bcms_reader'
        stdout: null # 1, process.stdout
        stderr: null # 2, process.stderr
        keep: false

