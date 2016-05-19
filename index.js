require('coffee-script').register();

module.exports = {
    AdapterPool: require('./src/AdapterPool'),
    Connector: require('./src/Connector'),
    PersistenceManager: require('./src/PersistenceManager'),
    squel: require('squel'),
    adapters: {
    	common: require('./src/adapters/common'),
    	mysql: require('./src/adapters/mysql'),
    	postgres: require('./src/adapters/postgres')
    }
};