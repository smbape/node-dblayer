fs = require 'fs'
sysPath = require 'path'
mkdirp = require 'mkdirp'
{createScript, executeScript, getTemp} = require '../../tools'
_ = require 'lodash'

env = process.env
umask = if process.platform is 'win32' then {encoding: 'utf-8', mode: 700} else {encoding: 'utf-8', mode: 600}

exports.generateScripts = (options = {})->
    {
        root
        password
        database
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

    users = _.cloneDeep users
    for key, user of users
        user.name = "'#{user.name}'@'#{host}'"
    # console.log require('util').inspect(users, {colors: true, depth: true})

    # ================================
    # Create users
    # ================================
    if create.users isnt false
        for key, user of users
            sql.push """
            CREATE USER #{user.name} IDENTIFIED BY '#{user.password}';
            """

    # ================================
    # Create database
    # ================================
    if create.database isnt false
        sql.push """
        CREATE DATABASE IF NOT EXISTS `#{database}` DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;
        -- REVOKE ALL ON `#{database}`.* FROM #{users.admin.name}, #{users.writer.name}, #{users.reader.name};
        GRANT ALL ON `#{database}`.* TO #{users.admin.name};
        GRANT CREATE TEMPORARY TABLES, EXECUTE, SELECT ON `#{database}`.* TO #{users.reader.name};
        GRANT CREATE TEMPORARY TABLES, EXECUTE, SELECT, INSERT, UPDATE, DELETE ON `#{database}`.* TO #{users.writer.name};
        FLUSH PRIVILEGES;
        """

    if sql.length
        databaseSQL = sysPath.join tmp, '01_database.sql'
        fs.writeFileSync databaseSQL, sql.join('\n'), 'utf-8'

    # ================================
    # Create model
    # ================================
    if create.model isnt false
        script = """
            USE `#{database}`;
            #{fs.readFileSync sysPath.resolve __dirname, 'model.sql'}
        """

        modelSQL = sysPath.join tmp, '02_model.sql'
        fs.writeFileSync modelSQL, script, 'utf-8'

    {
        databaseSQL
        modelSQL
        tmp
    }

exports.install = (options = {}, done)->
    {
        root
        password
        database
        cmd: mysql
        host
        port
        stdout
        stderr
    } = options

    stdout or (stdout isnt null and stdout = process.stdout)
    stderr or (stderr isnt null and stderr = process.stderr)

    {
        databaseSQL
        modelSQL
        tmp
    } = exports.generateScripts options

    if password.length > 0
        my = sysPath.join tmp, 'my.conf'
        fs.writeFileSync my, "[client]\npassword=#{password}\n", umask
        mysql = "#{mysql} --defaults-extra-file=#{my} -h #{host} -P #{port} --user=#{root}"
    else
        mysql = "#{mysql} -h #{host} -P #{port} --user=#{root}"

    script = []

    if databaseSQL
        script.push "#{mysql} < \"#{databaseSQL}\""

    if modelSQL
        script.push "#{mysql} < \"#{modelSQL}\""

    join = if process.platform is 'win32' then ' &\n' else ' &&\n'
    script = createScript sysPath.join(tmp, 'install'), env, script.join(join)
    executeScript script, [], [process.stdin, stdout, stderr], done
    return

exports.uninstall = (options = {}, done)->
    {
        root
        password
        database
        schema
        cmd: mysql
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

    users = _.cloneDeep users
    for key, user of users
        user.name = "'#{user.name}'@'#{host}'"
    # console.log require('util').inspect(users, {colors: true, depth: true})

    sql = []

    if drop.database is true
        drop.users = true

    if drop.users isnt false
        for key, user of users
            sql.push """
            REVOKE ALL ON `#{database}`.* FROM #{user.name};
            DROP USER IF EXISTS #{user.name};
            """
        sql.push "FLUSH PRIVILEGES;"

    if drop.database isnt false
        sql.push "DROP DATABASE IF EXISTS `#{database}`;"

    if password.length > 0
        my = sysPath.join tmp, 'my.conf'
        fs.writeFileSync my, "[client]\npassword=#{password}\n", umask
        mysql = "#{mysql} --defaults-extra-file=#{my} -h #{host} -P #{port} --user=#{root}"
    else
        mysql = "#{mysql} -h #{host} -P #{port} --user=#{root}"

    script = []
    if sql.length
        dropDatabaseSQL = sysPath.join tmp, '99_drop.sql'
        fs.writeFileSync dropDatabaseSQL, sql.join('\n'), 'utf-8'
        script.push "#{mysql} -f < \"#{dropDatabaseSQL}\""

    join = if process.platform is 'win32' then ' &\n' else ' &&\n'
    script = createScript sysPath.join(tmp, 'uninstall'), env, script.join(join)
    executeScript script, [], [process.stdin, stdout, stderr], done

    return