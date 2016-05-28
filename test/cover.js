var cluster = require('cluster'),
    _ = require('lodash'),
    dialects = ['mysql', 'postgres'],
    argv = process.argv.slice(2).concat(['-O', '']),
    last = argv.length - 1,
    dialect;

if (cluster.isMaster) {
    // setup cluster if running with istanbul coverage
    if (process.env.running_under_istanbul) {
        // use coverage for forked process
        // disabled reporting and output for child process
        // enable pid in child process coverage filename

        cluster.on('exit', function(worker, code, signal) {
            cover(dialects.shift());
        });

        cover(dialects.shift());
    }
}

function cover(dialect) {
    if (dialect) {
        argv[last] = 'reportDir=test/reports/' + dialect;

        cluster.setupMaster({
            exec: './node_modules/istanbul/lib/cli.js',
            args: [
                'cover',
                '--dir', './test/reports/coverage',
                '--report', 'none',
                '--print', 'none',
                '--include-pid',
                './node_modules/mocha/bin/_mocha', '--'
            ].concat(argv)
        });

        cluster.fork(_.defaults({
            DIALECT: dialect
        }, process.env));
    }
}