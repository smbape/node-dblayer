var anyspawn = require('anyspawn'),
    sysPath = require('path'),
    argv = process.argv.slice();

argv[1] = sysPath.relative(process.cwd(), argv[1]).replace(/\\/g, '/').replace(/test\/_mocha$/, 'node_modules/mocha/bin/_mocha');
var cmd = argv.map(anyspawn.quoteArg).join(' ');

module.exports = [
    function() {
        process.env.DIALECT = 'mysql';
        prompt();
    },
    function() {
        process.env.DIALECT = 'postgres';
        prompt();
    }
];

function prompt(env) {
    var text = '> DIALECT=' + process.env.DIALECT + ' ' + cmd;
    console.log(text);
}