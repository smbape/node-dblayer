fs = require 'fs'
sysPath = require 'path'
mkdirp = require 'mkdirp'
{createScript, executeScript, getTemp} = require '../../tools'
_ = require 'lodash'

# http://www.postgresql.org/docs/9.4/static/libpq-envars.html
env = _.pick process.env, [
    'PGHOST'
    'PGHOSTADDR'
    'PGPORT'
    'PGDATABASE'
    'PGUSER'
    'PGPASSWORD'
    'PGPASSFILE'
    'PGSERVICE'
    'PGSERVICEFILE'
    'PGREALM'
    'PGOPTIONS'
    'PGAPPNAME'
    'PGSSLMODE'
    'PGREQUIRESSL'
    'PGSSLCOMPRESSION'
    'PGSSLCERT'
    'PGSSLKEY'
    'PGSSLROOTCERT'
    'PGSSLCRL'
    'PGREQUIREPEER'
    'PGKRBSRVNAME'
    'PGGSSLIB'
    'PGCONNECT_TIMEOUT'
    'PGCLIENTENCODING'
    'PGDATESTYLE'
    'PGTZ'
    'PGGEQO'
    'PGSYSCONFDIR'
    'PGLOCALEDIR'
]

exports.generateScripts = (options = {})->
    {
        owner: root
        password
        database
        schema
        cmd: psql
        users
        host
        port
        create
        tmp
    } = options

    create or (create = {})
    tmp = getTemp(tmp, options.keep isnt true)

    sql = []

    # ================================
    # Create database
    # ================================
    if create.database isnt false
        sql.push """
        CREATE DATABASE "#{database}"
            WITH OWNER = #{root}
            ENCODING = 'UTF8';

        -- #{root} priviledges on database "#{database}"
        REVOKE ALL PRIVILEGES ON DATABASE "#{database}" FROM public;
        GRANT ALL PRIVILEGES ON DATABASE "#{database}" TO "#{root}";
        """

    if create.users isnt false
        for key, user of users
            sql.push """
            CREATE USER "#{user.name}" WITH ENCRYPTED PASSWORD '#{user.password}';
            GRANT CONNECT, TEMPORARY ON DATABASE "#{database}" TO "#{user.name}";
            """

    if sql.length
        databaseSQL = sysPath.join tmp, '01_database.sql'
        fs.writeFileSync databaseSQL, sql.join('\n'), 'utf-8'

    # ================================
    # Create schema and priviledges
    # ================================
    if create.schema isnt false
        sql = """
        -- Create schema
        SET SESSION AUTHORIZATION "#{root}";
        CREATE SCHEMA IF NOT EXISTS "#{schema}" AUTHORIZATION "#{users.admin.name}";
        SET SESSION AUTHORIZATION "#{users.admin.name}";

        -- Allow #{users.writer.name}, #{users.reader.name} to use schema
        GRANT USAGE ON SCHEMA "#{schema}" TO "#{users.reader.name}", "#{users.writer.name}";

        -- #{users.reader.name} priviledges
        GRANT SELECT ON ALL TABLES IN SCHEMA "#{schema}" TO "#{users.reader.name}";
        ALTER DEFAULT PRIVILEGES IN SCHEMA "#{schema}" GRANT SELECT ON TABLES TO "#{users.reader.name}";
        GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA "#{schema}" TO "#{users.reader.name}";
        ALTER DEFAULT PRIVILEGES IN SCHEMA "#{schema}" GRANT EXECUTE ON FUNCTIONS TO "#{users.reader.name}";

        -- #{users.writer.name} priviledges
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA "#{schema}" TO "#{users.writer.name}";
        ALTER DEFAULT PRIVILEGES IN SCHEMA "#{schema}" GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "#{users.writer.name}";
        GRANT USAGE ON ALL SEQUENCES IN SCHEMA "#{schema}" TO "#{users.writer.name}";
        ALTER DEFAULT PRIVILEGES IN SCHEMA "#{schema}" GRANT USAGE ON SEQUENCES TO "#{users.writer.name}";
        GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA "#{schema}" TO "#{users.writer.name}";
        ALTER DEFAULT PRIVILEGES IN SCHEMA "#{schema}" GRANT EXECUTE ON FUNCTIONS TO "#{users.writer.name}";
        """

        schemaSQL = sysPath.join tmp, '02_schema.sql'
        fs.writeFileSync schemaSQL, sql, 'utf-8'

    # ================================
    # Create model
    # ================================
    if create.model isnt false
        script = """
            SET SCHEMA '#{schema}';
            SET SESSION AUTHORIZATION "#{users.admin.name}";

            #{fs.readFileSync sysPath.resolve __dirname, 'model.sql'}
        """

        modelSQL = sysPath.join tmp, '03_model.sql'
        fs.writeFileSync modelSQL, script, 'utf-8'

    {
        databaseSQL
        schemaSQL
        modelSQL
        tmp
    }

exports.install = (options = {}, done)->
    {
        owner: root
        password
        database
        cmd: psql
        host
        port
        stdout
        stderr
    } = options

    stdout or (stdout isnt null and stdout = process.stdout)
    stderr or (stderr isnt null and stderr = process.stderr)

    {
        databaseSQL
        schemaSQL
        modelSQL
        tmp
    } = exports.generateScripts options

    if password
        pgpass = sysPath.join tmp, 'pgpass.conf'
        fs.writeFileSync pgpass, "*:*:*:#{root}:#{password}", 'utf-8'
        env.PGPASSFILE = pgpass

    script = []

    if databaseSQL
        script.push "#{psql} -h #{host} -p #{port} -U \"#{root}\" -f \"#{databaseSQL}\""

    if schemaSQL
        script.push "#{psql} -h #{host} -p #{port} -U \"#{root}\" -d \"#{database}\" -f \"#{schemaSQL}\""

    if modelSQL
        script.push "#{psql} -h #{host} -p #{port} -U \"#{root}\" -d \"#{database}\" -f \"#{modelSQL}\""

    join = if process.platform is 'win32' then ' &\n' else ' &&\n'

    script = createScript sysPath.join(tmp, 'install'), env, script.join(join)
    executeScript script, [], [process.stdin, stdout, stderr], done
    return

exports.uninstall = (options = {}, done)->
    {
        owner: root
        password
        database
        schema
        cmd: psql
        host
        port
        stdout
        stderr
        users
        drop
        tmp
    } = options

    stdout or (stdout isnt null and stdout = process.stdout)
    stderr or (stderr isnt null and stderr = process.stderr)

    drop or (drop = {})
    tmp = getTemp(tmp, options.keep isnt true)

    sql = []
    script = []

    if drop.database is true
        drop.users = true
        drop.schema = true

    if drop.users isnt false
        sql.push """
        -- Revoke #{users.writer.name}, #{users.reader.name} to use schema
        REVOKE USAGE ON SCHEMA "#{schema}" FROM "#{users.reader.name}", "#{users.writer.name}";

        -- #{users.reader.name} priviledges
        REVOKE SELECT ON ALL TABLES IN SCHEMA "#{schema}" FROM "#{users.reader.name}";
        ALTER DEFAULT PRIVILEGES IN SCHEMA "#{schema}" REVOKE SELECT ON TABLES FROM "#{users.reader.name}";
        REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA "#{schema}" FROM "#{users.reader.name}";
        ALTER DEFAULT PRIVILEGES IN SCHEMA "#{schema}" REVOKE EXECUTE ON FUNCTIONS FROM "#{users.reader.name}";

        -- #{users.writer.name} priviledges
        REVOKE SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA "#{schema}" FROM "#{users.writer.name}";
        ALTER DEFAULT PRIVILEGES IN SCHEMA "#{schema}" REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES FROM "#{users.writer.name}";
        REVOKE USAGE ON ALL SEQUENCES IN SCHEMA "#{schema}" FROM "#{users.writer.name}";
        ALTER DEFAULT PRIVILEGES IN SCHEMA "#{schema}" REVOKE USAGE ON SEQUENCES FROM "#{users.writer.name}";
        REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA "#{schema}" FROM "#{users.writer.name}";
        ALTER DEFAULT PRIVILEGES IN SCHEMA "#{schema}" REVOKE EXECUTE ON FUNCTIONS FROM "#{users.writer.name}";
        -- #{users.admin.name}, #{users.writer.name}, #{users.reader.name} priviledges on database "#{database}"

        REVOKE CONNECT, TEMPORARY ON DATABASE "#{database}" FROM "#{users.reader.name}";
        REVOKE CONNECT, TEMPORARY ON DATABASE "#{database}" FROM "#{users.writer.name}";
        REVOKE CONNECT, TEMPORARY ON DATABASE "#{database}" FROM "#{users.admin.name}";
        """

    if drop.schema isnt false
        sql.push """
        SET SESSION AUTHORIZATION "#{users.admin.name}";
        DROP SCHEMA IF EXISTS \"#{schema}\" CASCADE;
        SET SESSION AUTHORIZATION "#{root}";
        """

    if drop.users isnt false
        sql.push """
        DROP ROLE IF EXISTS "#{users.reader.name}";
        DROP ROLE IF EXISTS "#{users.writer.name}";
        DROP ROLE IF EXISTS "#{users.admin.name}";
        """
    if sql.length
        dropschemaSQL = sysPath.join tmp, '99_drop.sql'
        fs.writeFileSync dropschemaSQL, sql.join('\n'), 'utf-8'
        script.push "#{psql} -h #{host} -p #{port} -U \"#{root}\" -d \"#{database}\" -f \"#{dropschemaSQL}\""

    if drop.database isnt false
        script.push "#{psql} -h #{host} -p #{port} -U \"#{root}\" -c \"DROP DATABASE IF EXISTS \\\"#{database}\\\"\""

    if password
        pgpass = sysPath.join tmp, 'pgpass.conf'
        fs.writeFileSync pgpass, "*:*:*:#{root}:#{password}", 'utf-8'
        env.PGPASSFILE = pgpass

    join = if process.platform is 'win32' then ' &\n' else ' &&\n'

    script = createScript sysPath.join(tmp, 'uninstall'), env, script.join(join)
    executeScript script, [], [process.stdin, stdout, stderr], done

    return
