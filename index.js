// require('coffee-script').register();
var lib = './lib/';

module.exports = {
    AdapterPool: require(lib + 'AdapterPool'),
    Connector: require(lib + 'Connector'),
    PersistenceManager: require(lib + 'PersistenceManager')
};