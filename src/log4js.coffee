fs = require('fs')
sysPath = require('path')
mkdirp = require('mkdirp')

if !global.log4js
    log4js = global.log4js = require('log4js')

    confile = if process.env.LOG4J_CONF then process.env.LOG4J_CONF else sysPath.join(__dirname, 'log4js.json')
    reloadSecs = if process.env.LOG4J_WATCH then 60 else undefined
    cwd = process.env.LOG4J_LOGS

    loadConfig = ->
        # config = JSON.parse(fs.readFileSync(confile))

        # if config.appenders != null and typeof config.appenders == 'object'
        #     Object.keys(config.appenders).forEach (name) ->
        #         appender = config.appenders[name]
        #         if appender.filename
        #             appender.filename = sysPath.resolve(cwd, appender.filename)
        #         return

        # config
        return {
            "appenders": {
                "console": {
                    "type": "console",
                    "layout": {
                        "type": "colored"
                    }
                }
            },
            "categories": {
                "default": {
                    "appenders": ["console"],
                    "level": "ERROR"
                }
            }
        }

    config = loadConfig()

    mkdirp.sync(cwd) if cwd
    log4js.configure config

module.exports = global.log4js
