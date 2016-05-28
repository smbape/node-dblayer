var fs = require('fs'),
    cluster = require('cluster'),
    rimraf = require('rimraf'),
    program = require('commander'),
    _ = require('lodash'),
    dialects = ['mysql', 'postgres'],
    exec = './node_modules/mocha/bin/_mocha',
    reportDir = './test/reports/',
    args = [],
    tasks = [],
    last, dialect, arg;

if (cluster.isMaster) {
    program
        .version(JSON.parse(fs.readFileSync(__dirname + '/../package.json', 'utf8')).version)
        .usage('[options] [files]')
        .option('--dialect <dialect>', 'mysql|postgres', /(?:mysql|postgres)/i)
        .option('--cover', 'add coverage information');

    program.parse(process.argv);

    if (program.dialect) {
        dialects = [program.dialect];
    }

    for (var i = 0, len = dialects.length; i < len; i++) {
        tasks.push(cover.bind(null, dialects[i]));
    }

    if (program.cover) {
        args = [
            'cover',
            '--dir', './test/reports/coverage',
            '--report', 'none',
            // '--print', 'none',
            '--include-pid',
            exec,
            '--'
        ];
        exec = './node_modules/istanbul/lib/cli.js';

        tasks.push(function() {
            require('child_process').spawn('node', [
                exec, 'report',
                '--dir', reportDir + 'coverage'
            ], {
                stdio: 'inherit'
            });
        });
    }

    for (var i = 2, len = process.argv.length; i < len; i++) {
        arg = process.argv[i];
        if (arg === '--dialect') {
            i++;
        } else if (!/^--(?:dialect=|cover$)/.test(arg)) {
            args.push(arg);
        }
    }

    args.push.apply(args, ['-O', '']);
    last = args.length - 1;

    rimraf(reportDir, function() {
        cluster.on('exit', iterate);
        iterate();
    });
}

function iterate(worker, code, signal) {
    var task = tasks.shift();
    if ((code === 0 || code === undefined) && task) {
        task();
    }
}

function cover(dialect) {
    if (dialect) {
        args[last] = 'reportDir=' + reportDir + dialect;

        cluster.setupMaster({
            exec: exec,
            args: args
        });

        cluster.fork(_.defaults({
            DIALECT: dialect
        }, process.env));
    }
}