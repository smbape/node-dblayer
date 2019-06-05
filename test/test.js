const fs = require("fs");
const cluster = require("cluster");
const rimraf = require("rimraf");
const program = require("commander");
const defaults = require("lodash/defaults");
const {fork, spawn} = require("child_process");
let dialects = ["mysql", "postgres"];
let exec = "./node_modules/mocha/bin/_mocha";
const reportDir = "./test/reports/";

let args = [];
const tasks = [];
let last;

const iterate = code => {
    const task = tasks.shift();
    if (!code && task) {
        task();
    }
};

const testSuite = dialect => {
    args[last] = `reportDir=${ reportDir }${ dialect }`;

    const child = fork(exec, args, {
        env: defaults({
            DIALECT: dialect
        }, process.env)
    });

    child.on("error", iterate);
    child.on("exit", iterate);
};

if (cluster.isMaster) {
    program
        .version(JSON.parse(fs.readFileSync(`${ __dirname }/../package.json`, "utf8")).version)
        .usage("[options] [files]")
        .option("--dialect <dialect>", "mysql|postgres", /(?:mysql|postgres)/i)
        .option("--cover", "add coverage information");

    program.parse(process.argv);

    if (program.dialect) {
        dialects = [program.dialect];
    }

    for (let i = 0, len = dialects.length; i < len; i++) {
        tasks.push(testSuite.bind(null, dialects[i]));
    }

    if (program.cover) {
        args = [
            "cover",
            "--dir", `${ reportDir }coverage`,
            "--report", "none",
            // '--print', 'none',
            "--include-pid",
            exec,
            "--"
        ];
        exec = "./node_modules/nyc/bin/nyc.js";

        tasks.push(() => {
            spawn("node", [
                exec, "report",
                "--dir", `${ reportDir }coverage`
            ], {
                stdio: "inherit"
            });
        });
    }

    for (let i = 2, len = process.argv.length, arg; i < len; i++) {
        arg = process.argv[i];
        if (arg === "--dialect") {
            i++;
        } else if (!/^--(?:dialect=|cover$)/.test(arg)) {
            args.push(arg);
        }
    }

    args.push("-O", "");
    last = args.length - 1;

    rimraf(reportDir, () => {
        iterate();
    });
}
