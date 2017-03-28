var PgClient, PgQueryStream, QueryStream, _, _env, adapter, anyspawn, common, escapeOpts, fs, getTemp, logger, pg, sysPath, umask,
  extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
  hasProp = {}.hasOwnProperty;

_ = require('lodash');

common = require('../../schema/adapter');

adapter = _.extend(module.exports, common);

logger = log4js.getLogger(__filename.replace(/^(?:.+[\/\\])?([^.\/\\]+)(?:.[^.]+)?$/, '$1'));

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

pg = require('pg');

QueryStream = require('pg-query-stream');

PgClient = (function(superClass) {
  extend(PgClient, superClass);

  function PgClient() {
    return PgClient.__super__.constructor.apply(this, arguments);
  }

  PgClient.prototype.stream = function(query, params, callback, done) {
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
    query = new PgQueryStream(query);
    stream = this.query(query, params);
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
    stream.on('data', function() {
      ++result.rowCount;
      callback.apply(null, arguments);
    });
    stream.once('end', function() {
      if (!hasError) {
        done(null, result);
      }
    });
    return stream;
  };

  return PgClient;

})(pg.Client);

PgQueryStream = (function(superClass) {
  extend(PgQueryStream, superClass);

  function PgQueryStream() {
    return PgQueryStream.__super__.constructor.apply(this, arguments);
  }

  PgQueryStream.prototype.handleRowDescription = function(message) {
    QueryStream.prototype.handleRowDescription.call(this, message);
    this.emit('fields', message.fields);
  };

  PgQueryStream.prototype.handleError = function() {
    this.push(null);
    return PgQueryStream.__super__.handleError.apply(this, arguments);
  };

  return PgQueryStream;

})(QueryStream);

_.extend(adapter, {
  name: 'postgres',
  squelOptions: {
    nameQuoteCharacter: '"',
    fieldAliasQuoteCharacter: '"',
    tableAliasQuoteCharacter: '"'
  },
  decorateInsert: function(insert, column) {
    insert.returning(this.escapeId(column));
    return insert;
  },
  insertDefaultValue: function(insert, column) {
    insert.set(this.escapeId(column), 'DEFAULT', {
      dontQuote: true
    });
    return insert;
  },
  createConnection: function(options, callback) {
    var client;
    if (typeof callback !== 'function') {
      callback = (function() {});
    }
    client = new PgClient(options);
    client.connect(function(err) {
      var query;
      if (err) {
        return callback(err, null);
      }
      query = "SET SCHEMA '" + options.schema + "'";
      logger.trace('[query] -', query);
      client.query(query, function(err) {
        callback(err, client);
      });
    });
    return client;
  }
});

_env = _.pick(process.env, ['PGHOST', 'PGHOSTADDR', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD', 'PGPASSFILE', 'PGSERVICE', 'PGSERVICEFILE', 'PGREALM', 'PGOPTIONS', 'PGAPPNAME', 'PGSSLMODE', 'PGREQUIRESSL', 'PGSSLCOMPRESSION', 'PGSSLCERT', 'PGSSLKEY', 'PGSSLROOTCERT', 'PGSSLCRL', 'PGREQUIREPEER', 'PGKRBSRVNAME', 'PGGSSLIB', 'PGCONNECT_TIMEOUT', 'PGCLIENTENCODING', 'PGDATESTYLE', 'PGTZ', 'PGGEQO', 'PGSYSCONFDIR', 'PGLOCALEDIR']);

fs = require('fs');

sysPath = require('path');

anyspawn = require('anyspawn');

getTemp = require('../../tools').getTemp;

umask = process.platform === 'win32' ? {
  encoding: 'utf-8',
  mode: 700
} : {
  encoding: 'utf-8',
  mode: 600
};

adapter.exec = adapter.execute = function(script, options, done) {
  var _script, args, database, env, file, host, keep, opts, password, pgpass, port, psql, schema, stderr, stdout, tmp, user;
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
  user = options.user, password = options.password, database = options.database, schema = options.schema, psql = options.cmd, host = options.host, port = options.port, stdout = options.stdout, stderr = options.stderr, tmp = options.tmp, keep = options.keep;
  psql || (psql = 'psql');
  stdout || (stdout !== null && (stdout = process.stdout));
  stderr || (stderr !== null && (stderr = process.stderr));
  tmp = getTemp(tmp, options.keep !== true);
  if (schema) {
    script = "SET SCHEMA '" + schema + "';\n" + script;
  }
  file = sysPath.join(tmp, 'script.sql');
  fs.writeFileSync(file, script, umask);
  env = _.clone(_env);
  if (user && (password != null ? password.length : void 0) > 0) {
    pgpass = sysPath.join(tmp, 'pgpass.conf');
    fs.writeFileSync(pgpass, "*:*:*:" + user + ":" + password, umask);
    env.PGPASSFILE = pgpass;
  }
  args = [];
  if (user) {
    args.push('-U');
    args.push(user);
  }
  if (host) {
    args.push('-h');
    args.push(host);
  }
  if (port) {
    args.push('-p');
    args.push(port);
  }
  if (database) {
    args.push('-d');
    args.push(database);
  }
  args.push('-f');
  args.push(file);
  opts = _.defaults({
    stdio: [process.stdin, stdout, stderr],
    env: env
  }, options);
  anyspawn.exec(psql, args, opts, done);
};
