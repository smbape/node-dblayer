// Generated by CoffeeScript 1.12.2
var _, i, len, method, mkdirp, ref, rimraf, sysPath, temp, tracked;

sysPath = require('path');

_ = require('lodash');

mkdirp = require('mkdirp');

temp = require('temp');

rimraf = require('rimraf');

exports.getExports = function(name, dialect) {
  return require('./dialects/' + dialect + '/' + name);
};

ref = ['adapter', 'sync', 'schema'];
for (i = 0, len = ref.length; i < len; i++) {
  method = ref[i];
  exports[method] = exports.getExports.bind(exports, method);
}

exports.guessEscapeOpts = function() {
  var adapter, args, connector, dialect, err, j, len1, opt, options, ref1;
  args = Array.prototype.slice.call(arguments);
  args.unshift({});
  options = _.defaults.apply(_, args);
  connector = options.connector, dialect = options.dialect;
  if ('string' !== options.dialect && connector && 'function' === typeof connector.getDialect) {
    dialect = options.dialect = connector.getDialect();
  }
  try {
    adapter = exports.adapter(dialect);
  } catch (error) {
    err = error;
  }
  if (connector || adapter) {
    ref1 = ['escape', 'escapeId', 'escapeSearch', 'escapeBeginWith', 'escapeEndWith', 'exprNotEqual', 'exprEqual'];
    for (j = 0, len1 = ref1.length; j < len1; j++) {
      opt = ref1[j];
      if (connector && 'function' !== typeof options[opt] && 'function' === typeof connector[opt]) {
        options[opt] = connector[opt].bind(connector);
      } else if (adapter && 'function' === typeof adapter[opt]) {
        options[opt] = adapter[opt];
      } else if ('function' === typeof exports[opt]) {
        options[opt] = exports[opt];
      }
    }
  }
  return options;
};

exports.toUpperWords = function(lowerwords) {
  var key, value, words;
  words = {};
  for (key in lowerwords) {
    value = lowerwords[key];
    words[key] = value.toUpperCase();
  }
  return words;
};

tracked = {};

exports.getTemp = function(tmp, track) {
  if (track == null) {
    track = true;
  }
  if (!tmp) {
    tmp = temp.mkdirSync('dblayer');
  }
  tmp = sysPath.resolve(tmp);
  mkdirp.sync(tmp);
  if (track && !tracked.hasOwnProperty(tmp)) {
    tracked[tmp] = true;
    process.on('exit', function() {
      rimraf.sync(tmp);
    });
  }
  return tmp;
};