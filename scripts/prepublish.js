const sysPath = require("path");
const rimraf = require("rimraf");
rimraf(sysPath.join(__dirname, "../lib"), err => {
    if (err) {
        throw err;
    }

    require("coffeescript/bin/coffee");
});
