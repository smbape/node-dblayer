var ConnectionConfig, HWM, MySQLConnection, MySQLLibConnection, _, adapter, anyspawn, common, escapeOpts, fs, getTemp, logger, mysql, once, path, prependListener, sysPath, umask;

_ = require('lodash');

common = require('../../schema/adapter');

adapter = _.extend(module.exports, common);

logger = log4js.getLogger(__filename.replace(/^(?:.+[\/\\])?([^.\/\\]+)(?:.[^.]+)?$/, '$1'));

escapeOpts = {
  id: {
    quote: '`',
    matcher: /([`\\\0\n\r\b])/g,
    replace: {
      '`': '\\`',
      '\\': '\\\\',
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
      "'": "\\'",
      '\\': '\\\\',
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

mysql = require('mysql');

MySQLLibConnection = require('mysql/lib/Connection');

ConnectionConfig = require('mysql/lib/ConnectionConfig');

prependListener = require('prepend-listener');

once = require('once');

path = require('path');

HWM = Math.pow(2, 7);

MySQLConnection = (function() {
  class MySQLConnection extends MySQLLibConnection {
    constructor(options) {
      super({
        config: new ConnectionConfig(options)
      });
      this.options = _.clone(options);
    }

    query(query, params, callback) {
      var stream;
      stream = this._createQuery(query, params, callback);
      super.query(stream.query);
      return stream;
    }

    stream(query, params, callback, done) {
      var hasError, result, stream;
      if (arguments.length === 3) {
        done = callback;
        callback = params;
        params = [];
      }
      if (!(params instanceof Array)) {
        params = [];
      }
      if (typeof done !== 'function') {
        done = (function() {});
      }
      stream = MySQLLibConnection.prototype.query.call(this, query, params).stream({
        highWaterMark: HWM
      });
      hasError = false;
      result = {
        rowCount: 0
      };
      stream.once('error', function(err) {
        hasError = err;
        done(err);
      });
      stream.on('fields', function(fields) {
        result.fields = fields;
      });
      stream.on('data', function(row) {
        if (row.constructor.name === 'OkPacket') {
          result.fieldCount = row.fieldCount;
          result.affectedRows = row.affectedRows;
          result.changedRows = row.changedRows;
          result.lastInsertId = row.insertId;
        } else {
          ++result.rowCount;
          callback(row);
        }
      });
      stream.once('end', function() {
        if (!hasError) {
          done(void 0, result);
        }
      });
      return stream;
    }

    _createQuery(text, values, callback) {
      var emitClose, hasError, query, result, stream;
      if (typeof callback === 'undefined' && typeof values === 'function') {
        callback = values;
        values = void 0;
      }
      values = values || [];
      query = mysql.createQuery(text, values);
      stream = query.stream({
        highWaterMark: HWM
      });
      emitClose = once(stream.emit.bind(stream, 'close'));
      prependListener(query, 'end', emitClose);
      stream.query = query;
      stream.text = text;
      stream.values = values;
      stream.callback = callback;
      if (typeof callback === 'function') {
        result = {
          rows: [],
          rowCount: 0,
          lastInsertId: 0,
          fields: null,
          fieldCount: 0
        };
        hasError = false;
        stream.on('error', function(err) {
          emitClose();
          hasError = true;
          this.callback(err);
        });
        stream.on('fields', function(fields) {
          result.fields = fields;
        });
        stream.on('data', function(row) {
          if (row.constructor.name === 'OkPacket') {
            result.fieldCount = row.fieldCount;
            result.affectedRows = row.affectedRows;
            result.changedRows = row.changedRows;
            result.lastInsertId = row.insertId;
          } else {
            ++result.rowCount;
            result.rows.push(row);
          }
        });
        stream.on('end', function() {
          if (!hasError) {
            this.callback(null, result);
          }
        });
      }
      stream.once('end', function() {
        delete this.query;
      });
      return stream;
    }

  };

  MySQLConnection.prototype.adapter = adapter;

  return MySQLConnection;

}).call(this);

_.extend(adapter, {
  name: 'mysql',
  squelOptions: {
    nameQuoteCharacter: '`',
    fieldAliasQuoteCharacter: '`',
    tableAliasQuoteCharacter: '`'
  },
  insertDefaultValue: function(insert, column) {
    var _toString;
    _toString = insert.toString;
    insert.toString = function() {
      return _toString.call(insert) + ' VALUES()';
    };
    // insert.set this.escapeId(column), '', {dontQuote: true}
    return insert;
  },
  createConnection: function(options, callback) {
    var client;
    if (typeof callback !== 'function') {
      callback = (function() {});
    }
    client = new MySQLConnection(options);
    return client.connect(function(err) {
      if (err) {
        return callback(err);
      }
      return callback(err, client);
    });
  }
});

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
  var _script, args, child, cmd, database, file, force, host, keep, my, opts, password, pipe, port, readable, stderr, stdout, tmp, user;
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
  ({user, password, database, cmd, host, port, stdout, stderr, tmp, keep, force} = options);
  cmd || (cmd = 'mysql');
  stdout || (stdout !== null && (stdout = process.stdout));
  stderr || (stderr !== null && (stderr = process.stderr));
  tmp = getTemp(tmp, options.keep !== true);
  if (database) {
    script = `USE \`${database}\`;\n${script}`;
  }
  file = sysPath.join(tmp, 'script.sql');
  fs.writeFileSync(file, `${script}`, umask);
  if (user && (password != null ? password.length : void 0) > 0) {
    my = sysPath.join(tmp, 'my.conf');
    fs.writeFileSync(my, `[client]\npassword=${password}\n`, umask);
    args = [`--defaults-extra-file=${my}`];
  } else {
    pipe = true;
    args = ['-p'];
  }
  if (user) {
    args.push('-u');
    args.push(user);
  }
  if (host) {
    args.push('-h');
    args.push(host);
  }
  if (port) {
    args.push('-P');
    args.push(port);
  }
  if (force) {
    args.push('-f');
  }
  // args.push '-e'
  // args.push "source #{anyspawn.quoteArg(file)}"

  // console.log args.join(' ')
  opts = _.defaults({
    stdio: ['pipe', stdout, stderr],
    env: process.env
  }, options);
  child = anyspawn.exec(cmd, args, opts, done);
  readable = fs.createReadStream(file);
  readable.pipe(child.stdin);
  if (pipe) {
    process.stdin.pipe(child.stdin);
  }
};
