var ArrayStream, EventEmitter, MODES, SQLite3Connection, SQLite3Query, SQLite3Stream, _, adapter, anyspawn, common, escapeOpts, fs, getTemp, log4js, logger, path, sqlite3, sysPath, umask;

path = require('path');

_ = require('lodash');

sqlite3 = require('sqlite3');

EventEmitter = require('events').EventEmitter;

log4js = global.log4js || (global.log4js = require('log4js'));

logger = log4js.getLogger(__filename.replace(/^(?:.+[\/\\])?([^.\/\\]+)(?:.[^.]+)?$/, '$1'));

MODES = {
  READ: [Math.pow(2, 0), sqlite3.OPEN_READONLY],
  WRITE: [Math.pow(2, 1), sqlite3.OPEN_READWRITE],
  CREATE: [Math.pow(2, 2), sqlite3.OPEN_CREATE]
};

adapter = exports;

common = require('../../schema/adapter');

_.extend(adapter, common, {
  name: 'sqlite3',
  createConnection: function(options, callback) {
    var database, filename, mode, name, opt_mode, value;
    database = options.database || '';
    if (options.host) {
      filename = path.join(options.host, database);
    } else {
      filename = database;
    }
    if (options.workdir) {
      filename = path.join(options.workdir, filename);
    }
    if (!filename || filename === '/:memory') {
      filename = ':memory:';
    }
    if (!isNaN(options.mode)) {
      mode = 0;
      opt_mode = parseInt(options.mode, 10);
      for (name in MODES) {
        value = MODES[name];
        if (value[0] === (value[0] & opt_mode)) {
          mode |= value[1];
        }
      }
    }
    if (!mode) {
      mode = sqlite3.OPEN_READWRITE | sqlite3.OPEN_CREATE;
    }
    return new SQLite3Connection(filename, mode, function(err, client) {
      if (err) {
        return callback(err);
      }
      // https://www.sqlite.org/faq.html#q22
      // Does SQLite support foreign keys?
      // As of version 3.6.19, SQLite supports foreign key constraints.
      // But enforcement of foreign key constraints is turned off by default (for backwards compatibility).
      // To enable foreign key constraint enforcement, run PRAGMA foreign_keys=ON or compile with -DSQLITE_DEFAULT_FOREIGN_KEYS=1.
      client.query('PRAGMA foreign_keys = ON', function(err) {
        if (err) {
          return callback(err);
        }
        callback(err, client);
      });
    });
  },
  squelOptions: {
    replaceSingleQuotes: true,
    nameQuoteCharacter: '"',
    fieldAliasQuoteCharacter: '"',
    tableAliasQuoteCharacter: '"'
  }
});

escapeOpts = {
  id: {
    quote: '"',
    matcher: /(["\\\0\n\r\b])/g,
    replace: {
      '"': '""',
      '\0': '\\0',
      '\n': '\\n',
      '\r': '\\r',
      '\b': '\\b'
    }
  },
  literal: {
    quote: "'",
    matcher: /(['\\\0\n\r\b])/g,
    replace: {
      "'": "''",
      '\0': '\\0',
      '\n': '\\n',
      '\r': '\\r',
      '\b': '\\b'
    }
  },
  search: {
    quoteStart: "'%",
    quoteEnd: "%'",
    matcher: /(['\\\0\n\r\b])/g,
    replace: {
      "'": "''",
      '\0': '\\0',
      '\n': '\\n',
      '\r': '\\r',
      '\b': '\\b',
      '%': '!%',
      '_': '!_',
      '!': '!!'
    }
  }
};

escapeOpts.begin = _.clone(escapeOpts.search);

escapeOpts.begin.quoteStart = "'";

escapeOpts.end = _.clone(escapeOpts.search);

escapeOpts.end.quoteEnd = "'";

adapter.escape = common._escape.bind(common, escapeOpts.literal);

adapter.escapeId = common._escape.bind(common, escapeOpts.id);

adapter.escapeSearch = common._escape.bind(common, escapeOpts.search);

adapter.escapeBeginWith = common._escape.bind(common, escapeOpts.begin);

adapter.escapeEndWith = common._escape.bind(common, escapeOpts.end);

SQLite3Connection = (function() {
  class SQLite3Connection extends EventEmitter {
    constructor(filename, mode, callback) {
      super();
      // mkdirp do not throw on invalid path
      // mkdirp = require 'mkdirp'
      // mkdirp.sync path.dirname filename
      logger.debug('SQLite3Connection', filename);
      this.db = new sqlite3.Database(filename, mode);
      // always perform series write
      // parallel read write may lead to errors if not well controlled
      this.db.serialize();
      this.db.on('error', (err) => {
        this.emit('error', err);
      });
      this.db.once('error', callback);
      this.db.once('open', () => {
        this.db.removeListener('error', callback);
        callback(null, this);
      });
      this.db.on('close', () => {
        this.emit('end');
      });
      return;
    }

    query() {
      var query;
      query = new SQLite3Query(arguments);
      query.execute(this.db);
      return query;
    }

    stream() {
      var stream;
      stream = new SQLite3Stream(arguments);
      stream.execute(this.db);
      return stream;
    }

    end() {
      logger.debug('close connection');
      this.db.close();
    }

  };

  SQLite3Connection.prototype.adapter = adapter;

  return SQLite3Connection;

}).call(this);

SQLite3Query = class SQLite3Query extends EventEmitter {
  constructor(...args) {
    super();
    this.init(...args);
  }

  init(text, values, callback) {
    this.text = text;
    if (Array.isArray(values)) {
      this.values = values;
    } else {
      this.values = [];
      if (arguments.length === 2 && 'function' === typeof values) {
        callback = values;
      }
    }
    this.callback = 'function' === typeof callback ? callback : function() {};
  }

  execute(db) {
    var callback, hasError, query, result, values;
    query = this.text;
    values = this.values;
    callback = this.callback;
    // Quick falsy test to determine if insert|update|delete or else
    // falsy because (insert toto ...) will not be recognise as insert because of bracket
    // Real parser needed, but may be heavy for marginal cases
    // https://github.com/mapbox/node-sqlite3/wiki/API#databaserunsql-param--callback
    if (query.match(/^\s*insert\s+/i)) {
      db.run(query, values, function(err) {
        if (err) {
          return callback(err);
        }
        callback(err, {
          lastInsertId: this.lastID
        });
      });
      return;
    }
    if (query.match(/^\s*(?:update|delete)\s+/i)) {
      db.run(query, values, function(err) {
        if (err) {
          return callback(err);
        }
        callback(err, {
          changedRows: this.changes,
          affectedRows: this.changes
        });
      });
      return;
    }
    result = {
      rows: []
    };
    hasError = false;
    db.each(query, values, function(err, row) {
      if (err) {
        if (!hasError) {
          hasError = true;
          callback(err);
        }
        return;
      }
      result.rows.push(row);
    }, function(err, rowCount) {
      if (hasError) {
        return;
      }
      if (err) {
        return callback(err);
      }
      result.rowCount = rowCount;
      if (rowCount > 0) {
        result.fields = Object.keys(result.rows[0]).map(function(name) {
          return {
            name: name
          };
        });
      } else {
        result.fields = [];
      }
      callback(err, result);
    });
  }

};

ArrayStream = require('duplex-arraystream');

SQLite3Stream = class SQLite3Stream extends ArrayStream {
  constructor(args) {
    super([], {
      duplex: true
    });
    this.init.apply(this, args);
  }

  init(text, values, callback, done) {
    this.text = text;
    if (Array.isArray(values)) {
      this.values = values;
    } else {
      this.values = [];
      if (arguments.length === 2) {
        if ('function' === typeof values) {
          done = values;
        }
      } else if (arguments.length === 3) {
        if ('function' === typeof callback) {
          done = callback;
        }
        if ('function' === typeof values) {
          callback = values;
        }
      }
    }
    this.callback = 'function' === typeof callback ? callback : function() {};
    this.done = 'function' === typeof done ? done : function() {};
  }

  execute(db) {
    var done, hasError, query, result, values;
    query = this.text;
    values = this.values;
    done = this.done;
    result = {};
    hasError = false;
    this.on('data', this.callback);
    this.once('error', function(err) {
      hasError = true;
      done(err);
    });
    this.once('end', () => {
      this.removeListener('data', this.callback);
      if (hasError) {
        return;
      }
      // return done(err) if err
      if (!result.fields) {
        result.fields = [];
      }
      done(null, result);
    });
    db.each(query, values, (err, row) => {
      if (err) {
        this.emit('error', err);
        return;
      }
      if (!result.fields) {
        result.fields = Object.keys(row).map(function(name) {
          return {
            name: name
          };
        });
        this.emit('fields', result.fields);
      }
      this.write(row, 'item');
    }, (err) => {
      this.end();
      if (err) {
        this.emit('error', err);
      }
    });
  }

};

// Stream: error, fields, data, end
fs = require('fs');

sysPath = require('path');

anyspawn = require('anyspawn');

({getTemp} = require('../../tools'));

umask = process.platform === 'win32' ? {
  encoding: 'utf-8',
  mode: 700
} : {
  encoding: 'utf-8',
  mode: 600
};

adapter.exec = adapter.execute = function(script, options, done) {
  var _script, args, callback, child, cmd, database, error, file, keep, opts, readable, stderr, stdout, tmp;
  if (_.isPlainObject(script)) {
    _script = options;
    options = script;
    script = _script;
  }
  if ('function' === typeof options) {
    done = options;
    options = {};
  }
  if (!_.isPlainObject(options)) {
    options = {};
  }
  ({database, cmd, stdout, stderr, tmp, keep} = options);
  cmd || (cmd = 'sqlite3');
  if (cmd && 'object' === typeof cmd) {
    error = null;
    callback = function(err, res) {
      error = err;
    };
    this.split(script, function(query) {
      if (!error) {
        cmd.query(query, callback);
      }
    }, function(err) {
      done(err || error);
    });
    return;
  }
  stdout || (stdout !== null && (stdout = process.stdout));
  stderr || (stderr !== null && (stderr = process.stderr));
  tmp = getTemp(tmp, options.keep !== true);
  file = sysPath.join(tmp, 'script.sql');
  fs.writeFileSync(file, script, umask);
  args = [database];
  args.push('-f');
  args.push(file);
  opts = _.defaults({
    stdio: ['pipe', stdout, stderr]
  }, options);
  child = anyspawn.exec(cmd, args, opts, done);
  readable = fs.createReadStream(file);
  readable.pipe(child.stdin);
};
