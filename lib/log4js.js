var config, confile, cwd, fs, loadConfig, log4js, mkdirp, reloadSecs, sysPath;

fs = require('fs');

sysPath = require('path');

mkdirp = require('mkdirp');

if (!global.log4js) {
  log4js = global.log4js = require('log4js');
  confile = process.env.LOG4J_CONF ? process.env.LOG4J_CONF : sysPath.join(__dirname, 'log4js.json');
  reloadSecs = process.env.LOG4J_WATCH ? 60 : void 0;
  cwd = process.env.LOG4J_LOGS;
  loadConfig = function() {
    return {
      // config = JSON.parse(fs.readFileSync(confile))

      // if config.appenders != null and typeof config.appenders == 'object'
      //     Object.keys(config.appenders).forEach (name) ->
      //         appender = config.appenders[name]
      //         if appender.filename
      //             appender.filename = sysPath.resolve(cwd, appender.filename)
      //         return

      // config
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
    };
  };
  config = loadConfig();
  if (cwd) {
    mkdirp.sync(cwd);
  }
  log4js.configure(config);
}

module.exports = global.log4js;
