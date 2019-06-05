var PgClient, PgQueryStream, QueryStream, _, _env, adapter, anyspawn, common, escapeOpts, fs, getTemp, logger, pg, sysPath, umask;

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

PgClient = class PgClient extends pg.Client {
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
  }

};

PgQueryStream = class PgQueryStream extends QueryStream {
  handleRowDescription(message) {
    QueryStream.prototype.handleRowDescription.call(this, message);
    this.emit('fields', message.fields);
  }

  handleError(...args) {
    this.push(null);
    return super.handleError(...args);
  }

};

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
      query = `SET SCHEMA '${options.schema}'`;
      logger.trace('[query] -', query);
      client.query(query, function(err) {
        callback(err, client);
      });
    });
    return client;
  }
});

// http://www.postgresql.org/docs/9.4/static/libpq-envars.html
_env = _.pick(process.env, ['PGHOST', 'PGHOSTADDR', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD', 'PGPASSFILE', 'PGSERVICE', 'PGSERVICEFILE', 'PGREALM', 'PGOPTIONS', 'PGAPPNAME', 'PGSSLMODE', 'PGREQUIRESSL', 'PGSSLCOMPRESSION', 'PGSSLCERT', 'PGSSLKEY', 'PGSSLROOTCERT', 'PGSSLCRL', 'PGREQUIREPEER', 'PGKRBSRVNAME', 'PGGSSLIB', 'PGCONNECT_TIMEOUT', 'PGCLIENTENCODING', 'PGDATESTYLE', 'PGTZ', 'PGGEQO', 'PGSYSCONFDIR', 'PGLOCALEDIR']);

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
  ({
    user,
    password,
    database,
    schema,
    cmd: psql,
    host,
    port,
    stdout,
    stderr,
    tmp,
    keep
  } = options);
  psql || (psql = 'psql');
  stdout || (stdout !== null && (stdout = process.stdout));
  stderr || (stderr !== null && (stderr = process.stderr));
  tmp = getTemp(tmp, options.keep !== true);
  if (schema) {
    script = `SET SCHEMA '${schema}';\n${script}`;
  }
  file = sysPath.join(tmp, 'script.sql');
  fs.writeFileSync(file, script, umask);
  env = _.clone(_env);
  if (user && (password != null ? password.length : void 0) > 0) {
    pgpass = sysPath.join(tmp, 'pgpass.conf');
    fs.writeFileSync(pgpass, `*:*:*:${user}:${password}`, umask);
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
