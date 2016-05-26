if not global.log4js
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
            "[all]": "INFO"

module.exports = global.log4js
