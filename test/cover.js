const cluster = require("cluster");
const _ = require("lodash");
const dialects = ["mysql", "postgres"];
const argv = process.argv.slice(2).concat(["-O", ""]);
const last = argv.length - 1;

const cover = dialect => {
    if (!dialect) {
        return;
    }

    argv[last] = `reportDir=test/reports/${ dialect }`;

    cluster.setupMaster({
        exec: "./node_modules/istanbul/lib/cli.js",
        args: [
            "cover",
            "--dir", "./test/reports/coverage",
            "--report", "none",
            "--print", "none",
            "--include-pid",
            "./node_modules/mocha/bin/_mocha", "--"
        ].concat(argv)
    });

    cluster.fork(_.defaults({
        DIALECT: dialect
    }, process.env));
};

if (cluster.isMaster) {
    // setup cluster if running with istanbul coverage
    if (process.env.NYC_PARENT_PID) {
        // use coverage for forked process
        // disabled reporting and output for child process
        // enable pid in child process coverage filename

        cluster.on("exit", (worker, code, signal) => {
            cover(dialects.shift());
        });

        cover(dialects.shift());
    }
}
