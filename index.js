require('coffee-script').register();
var log4js = require('log4js');
// var dirname = path.dirname(__filename);
// log4js.configure(path.join(dirname, 'log4js.json'));

module.exports = {
	log4js: log4js,
    AdapterPool: require('./lib/AdapterPool'),
    Connector: require('./lib/Connector'),
    PersistenceManager: require('./lib/PersistenceManager')
};