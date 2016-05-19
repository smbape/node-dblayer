// require('coffee-script').register();

module.exports = {
    AdapterPool: require('./lib/AdapterPool'),
    Connector: require('./lib/Connector'),
    PersistenceManager: require('./lib/PersistenceManager'),
    squel: require('squel'),
    adapters: {
    	common: require('./lib/adapters/common'),
    	mysql: require('./lib/adapters/mysql'),
    	postgres: require('./lib/adapters/postgres')
    }
};