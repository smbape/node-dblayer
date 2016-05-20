module.exports = [
    function() {
        process.env.DIALECT = 'mysql';
        prompt(process.env);
    },
    function() {
        process.env.DIALECT = 'postgres';
        prompt(process.env);
    }
];

function prompt(env) {
    var cmd = 'node node_modules/mocha/bin/_mocha --full-trace --compilers coffee:coffee-script/register test/prepare.coffee test/suite';
    var text = '> DIALECT=' + env.dialect + ' ' + cmd;
    console.log(text);
}