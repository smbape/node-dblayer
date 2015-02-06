'use strict';

require("sm-require")();
var log4js = require('log4js');
var path = require('path');
var dirname = path.dirname(__filename);
log4js.configure(path.join(dirname, 'log4js.json'));

// do test for each dbms
var config = {
    postgres: {
        read: "postgres://user_read:zulu@localhost:5432/buma?schema=test&minConnection=0&maxConnection=10&idleTimeout=3600",
        write: "postgres://user_write:zulu@localhost:5432/buma?schema=test&minConnection=0&maxConnection=10&idleTimeout=3600",
        admin: "postgres://user_admin:zulu@localhost:5432/buma?schema=test&minConnection=0&maxConnection=1&idleTimeout=3600"
    },
    mysql: {
        read: "mysql://user_read:zulu@localhost:3306/buma_test?minConnection=0&maxConnection=10&idleTimeout=3600",
        write: "mysql://user_write:zulu@localhost:3306/buma_test?minConnection=0&maxConnection=10&idleTimeout=3600",
        admin: "mysql://user_admin:zulu@localhost:3306/buma_test?minConnection=0&maxConnection=1&idleTimeout=3600"
    },
    sqlite3: {
        read: "sqlite3://databases/buma_test.sqlite?minConnection=0&maxConnection=1&idleTimeout=3600&mode=1&workdir=#{encodeURIComponent(__dirname)}",
        write: "sqlite3://databases/buma_test.sqlite?minConnection=0&maxConnection=1&idleTimeout=3600&mode=2&workdir=#{encodeURIComponent(__dirname)}",
        admin: "sqlite3://databases/buma_test.sqlite?minConnection=0&maxConnection=1&idleTimeout=3600&mode=6&workdir=#{encodeURIComponent(__dirname)}"
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

function destroyPools(next) {
    var i, dbms, options, items = ['poolRead', 'poolWrite', 'poolAdmin'],
        count = 0,
        length = Object.keys(pools).length,
        hasPool = false;
    for (i = 0; i < items.length; i++) {
        for (dbms in pools) {
            if (!hasPool) {
                hasPool = true;
            }
            (function(pool) {
                pool.drain(function() {
                    pool.destroyAllNow();
                    ++count;
                    if (count === length) {
                        if ('function' === typeof next) {
                            next();
                        } else if ('undefined' !== typeof next) {
                            next.done();
                        }
                    }
                });
            }(pools[dbms][items[i]]));
        }
    }

    if (!hasPool) {
        next();
    }
}

var async = require('async');
var assert, prop, reporter, tests;
var testSuite = module.exports;

var isNodeunit = /\bnodeunit$/.test(process.argv[1]);
var isRequire = __filename !== process.argv[1];

function run(next) {
    var _next;
    if ('function' === typeof next) {
        _next = function() {
            destroyPools(next);
        }
    } else {
        _next = destroyPools;
    }

    // Launch nodeunit if not used
    reporter = require('nodeunit').reporters.default;
    reporter.run({
        'testSuite': testSuite
    }, null, _next);
}

if (false) {
    // For debugging purpose
    assert = require('assert');
    tests = [];
    for (prop in testSuite) {
        (function(fn, prop) {
            tests.push(function(next) {
                console.log('test', prop);
                assert.done = next;
                fn(assert);
            });
        })(testSuite[prop], prop);
    }
    
    module.exports.run = function (next) {
        async.series(tests, function() {
            destroyPools(next);
        });
    };
} else if (isNodeunit) {
    module.exports.end = destroyPools;
} else if (isRequire) {
    module.exports = {run: run};
} else {
    run();
}