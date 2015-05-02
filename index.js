require('coffee-script').register();

module.exports = {
    AdapterPool: require('./src/AdapterPool'),
    Connector: require('./src/Connector'),
    PersistenceManager: require('./src/PersistenceManager')
};