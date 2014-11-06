'use strict';

require("sm-require")();
var log4js = require('log4js');
var path = require('path');
var dirname = path.dirname(__filename);
log4js.configure(path.join(dirname, 'log4js.json'));

// do test for each dbms
var config = {
    postgres: {
        read: "postgres://user_read:zulu@localhost:5432/exbam?schema=testschema&minConnection=0&maxConnection=10&idleTimeout=3600",
        write: "postgres://user_write:zulu@localhost:5432/exbam?schema=testschema&minConnection=0&maxConnection=10&idleTimeout=3600",
        admin: "postgres://user_admin:zulu@localhost:5432/exbam?schema=testschema&minConnection=0&maxConnection=1&idleTimeout=3600"
    },
    mysql: {
        read: "mysql://user_read:zulu@localhost:3306/testschema?minConnection=0&maxConnection=10&idleTimeout=3600",
        write: "mysql://user_write:zulu@localhost:3306/testschema?minConnection=0&maxConnection=10&idleTimeout=3600",
        admin: "mysql://user_admin:zulu@localhost:3306/testschema?minConnection=0&maxConnection=1&idleTimeout=3600"
    }
};

var testSubtasks = ['ConnectorTest', 'PersistenceManagerTest'],
    task;

var library = require('../');
var AdapterPool = library.AdapterPool,
    pools = {};

var dbms, poolAdmin, poolRead, poolWrite, options, taskName;

for (dbms in config) {

    options = {};
    options.poolRead = new AdapterPool(config[dbms].read, {
        name: dbms + 'PoolRead'
    });
    options.poolWrite = new AdapterPool(config[dbms].write, {
        name: dbms + 'PoolWrite'
    });
    options.poolAdmin = new AdapterPool(config[dbms].admin, {
        name: dbms + 'PoolAdmin'
    });
    pools[dbms] = options;

    for (var i = 0; i < testSubtasks.length; i++) {
        taskName = testSubtasks[i];
        task = require('./suite/' + taskName);
        module.exports[taskName + ' - ' + dbms] = task(options);
    }
}

function destroyPools() {
    var i, dbms, options, items = ['poolRead', 'poolWrite', 'poolAdmin'];
    for (i = 0; i < items.length; i++) {
        for (dbms in pools) {
            (function(pool) {
                pool.drain(function() {
                    pool.destroyAllNow();
                });
            }(pools[dbms][items[i]]));
        }
    }
}

var async = require('async');
var assert, prop, reporter, tests;
var testSuite = module.exports;

var isNodeunit = /\bnodeunit$/.test(process.argv[1]);

if (false) {
    // For debugging purpose
    assert = require('assert');
    tests = [];
    for (prop in testSuite) {
        (function(fn) {
            tests.push(function(next) {
                assert.done = next;
                fn(assert);
            });
        })(testSuite[prop]);
    }
    async.series(tests, destroyPools);
} else if (!isNodeunit) {
    // Launch nodeunit if not used
    reporter = require('nodeunit').reporters.default;
    reporter.run({
        'testSuite': testSuite
    }, null, destroyPools);
}