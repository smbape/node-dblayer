require('coffee-script').register();

var log4js = require('log4js'),
    path = require('path'),
    dirname = path.dirname(__filename),
    path = require('path'),
    workdir = encodeURIComponent(path.join(__dirname, 'databases')),
    async = require('async');

log4js.configure(path.join(dirname, 'log4js.json'))

// DBMS configs
var configs = {
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
    sqlite: {
        read: "sqlite3://buma_test.sqlite?minConnection=0&maxConnection=1&idleTimeout=3600&mode=1&workdir=" + workdir,
        write: "sqlite3://buma_test.sqlite?minConnection=0&maxConnection=1&idleTimeout=3600&mode=2&workdir=" + workdir,
        admin: "sqlite3://buma_test.sqlite?minConnection=0&maxConnection=1&idleTimeout=3600&mode=6&workdir=" + workdir
    }
};

var testSubtasks = ['ConnectorTest', 'PersistenceManagerTest'],
    task;

var library = require('../');
var AdapterPool = library.AdapterPool,
    pools = {};

var dbms, poolAdmin, poolRead, poolWrite, options, taskName, dialects;
var testSuite = module.exports;

function addTask(dbms) {
    if (!configs.hasOwnProperty(dbms)) {
        return;
    }
    options = {};
    options.poolRead = new AdapterPool(configs[dbms].read, {
        name: dbms + 'PoolRead'
    });
    options.poolWrite = new AdapterPool(configs[dbms].write, {
        name: dbms + 'PoolWrite'
    });
    options.poolAdmin = new AdapterPool(configs[dbms].admin, {
        name: dbms + 'PoolAdmin'
    });
    pools[dbms] = options;

    for (var i = 0; i < testSubtasks.length; i++) {
        taskName = testSubtasks[i];
        task = require('./suite/' + taskName);
        testSuite[taskName + ' - ' + dbms] = task(options);
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
                pool.destroyAll(true, function() {
                    if (++count === length) {
                        if ('function' === typeof next) {
                            next();
                        } else if ('undefined' !== typeof next) {
                            next.done();
                        }
                    }
                })
            }(pools[dbms][items[i]]));
        }
    }

    if (!hasPool) {
        next();
    }
}

for (dbms in configs) {
    addTask(dbms);
}

var assert, prop, reporter, tests;

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

function debugTests() {
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
        }(testSuite[prop], prop));
    }

    return function(next) {
        async.series(tests, function() {
            destroyPools(next);
        });
    };
}

if (false) {
    module.exports.run = debugTests();
} else if (isNodeunit) {
    module.exports.end = destroyPools;
} else if (isRequire) {
    module.exports = {
        run: run
    };
} else {
    var program = require('commander');

    program
        .version(require('../package.json').version)
        .option('--dialects <items>', 'A list of comma separated dialects to test', dialects, ['postgres', 'mysql', 'sqlite'])
        .parse(process.argv);

    function dialects(val) {
        var list = val.split(/\s*,\s*/),
            ret = [],
            i;

        for (i = 0; i < list.length; i++) {
            if (/postgres|mysql|sqlite/.test(list[i])) {
                ret.push(list[i]);
            }
        }

        return ret;
    }

    var dialects = program.dialects;

    if (dialects && dialects.length > 0) {

        for (var prop in testSuite) {
            delete testSuite[prop];
        }

        for (var i = dialects.length - 1; i >= 0; i--) {
            addTask(dialects[i]);
        }
    }

    debugTests()();
}