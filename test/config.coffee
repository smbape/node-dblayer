
module.exports =
    postgres:
        owner: 'postgres'       # a user who can create/use database and create schema
        password: 'dev.psql'
        database: 'postgres'
        schema: 'DBLAYER_TEST'
        host: '127.0.0.1'
        port: 5432
        cmd: 'psql'
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
        create:
            database: false
            schema: true
            users: true
        drop:
            database: false
            schema: true
            users: true
        recreate:
            database: false
            schema: true
            users: true
        stdout: null
        stderr: null
        keep: false
