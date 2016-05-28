// require('coffee-script').register();
module.exports = {
    AdapterPool: require('./lib/AdapterPool'),
    Connector: require('./lib/Connector'),
    PersistenceManager: require('./lib/PersistenceManager'),
    tools: require('./lib/tools'),
    log4js: require('./lib/log4js'),
    squel: require('squel')
};