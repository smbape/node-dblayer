var EventEmitter, MSSQLClient, MSSQLConnection, MSSQLRequest, _, _env, adapter, anyspawn, common, escapeOpts, fs, getTemp, logger, slice, sysPath, umask;

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

EventEmitter = require('events').EventEmitter;

({
  Connection: MSSQLConnection,
  Request: MSSQLRequest
} = require('tedious'));

slice = Array.prototype.slice;

MSSQLClient = (function() {
  class MSSQLClient extends EventEmitter {
    constructor(options) {
      super();
      this.options = options = _.clone(options);
      options.server = options.host;
      delete options.host;
      options.userName = options.user;
      delete options.user;
      if (isNaN(options.port)) {
        options.instanceName = options.port;
        delete options.port;
      }
      this.handlers = {};
      this.handlerCount = 0;
      this.queue = [];
      this.available = true;
    }

    connect(callback) {
      var connection, evt, i, len, ref;
      connection = this.connection = new MSSQLConnection(this.options);
      connection.on('connect', callback);
      ref = ['error', 'end'];
      // for evt in ['connect', 'error', 'end', 'debug', 'infoMessage', 'errorMessage', 'databaseChange', 'languageChange', 'charsetCahnge', 'secure']
      for (i = 0, len = ref.length; i < len; i++) {
        evt = ref[i];
        this._delegate(evt);
      }
    }

    end() {
      this.connection.close();
    }

    query(query, params, callback) {
      var result;
      if (!callback && 'function' === typeof params) {
        callback = params;
        params = null;
      }
      if (typeof callback === 'function') {
        result = {
          rowCount: 0,
          fields: null,
          fieldCount: 0,
          rows: []
        };
        this.stream(query, function(row) {
          result.rows.push(row);
        }, function(err, res) {
          if (err) {
            return callback(err);
          }
          result.rowCount = res.rowCount;
          result.fields = res.fields;
          result.fieldCount = res.fieldCount;
          callback(err, result);
        });
      }
    }

    stream(query, params, callback, done) {
      var connection, request, result;
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
      result = {
        rowCount: 0,
        fields: null,
        fieldCount: 0
      };
      request = new MSSQLRequest(query, (err, rowCount) => {
        this._release();
        result.rowCount = rowCount;
        done(err, result);
      });
      connection = this.connection;
      this._acquire(function() {
        request.on('columnMetadata', function(fields) {
          var field, i, len;
          result.fields = fields;
          for (i = 0, len = fields.length; i < len; i++) {
            field = fields[i];
            field.name = field.colName;
            result.fieldCount++;
          }
        });
        request.on('row', function(columns) {
          var colName, i, len, name, row, value;
          row = {};
          if (Array.isArray(columns)) {
            for (i = 0, len = columns.length; i < len; i++) {
              ({
                metadata: {colName},
                value
              } = columns[i]);
              row[colName] = value;
            }
          } else {
            for (name in columns) {
              ({
                metadata: {colName},
                value
              } = columns[name]);
              row[colName] = value;
            }
          }
          callback(row);
        });
        connection.execSql(request);
      });
      return request;
    }

    _delegate(evt) {
      var self;
      self = this;
      self.handlers[evt] = function() {
        var args;
        args = slice.call(arguments);
        args.unshift(evt);
        EventEmitter.prototype.emit.apply(self, args);
      };
      self.handlerCount++;
      self.connection.on(evt, self.handlers[evt]);
      self.connection.on('end', function() {
        self.connection.removeListener(evt, self.handlers[evt]);
        delete self.handlers[evt];
        if (--self.handlerCount === 0) {
          delete self.connection;
        }
      });
    }

    _acquire(callback) {
      if (this.available) {
        this.available = false;
        callback();
        return;
      }
      this.queue.push(callback);
    }

    _release() {
      var callback;
      if (this.available) {
        return;
      }
      if (this.queue.length) {
        callback = this.queue.unshift();
        setImmediate(callback);
        return;
      }
      this.available = true;
    }

  };

  MSSQLClient.prototype.adapter = adapter;

  return MSSQLClient;

}).call(this);

_.extend(adapter, {
  name: 'mssql',
  squelOptions: {
    nameQuoteCharacter: '"',
    fieldAliasQuoteCharacter: '"',
    tableAliasQuoteCharacter: '"'
  },
  decorateInsert: function(insert, column) {
    insert.output(this.escapeId(column));
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
    client = new MSSQLClient(options);
    client.connect(function(err) {
      return callback(err, client);
    });
  }
});

// https://msdn.microsoft.com/fr-fr/library/ms162773.aspx
_env = _.pick(process.env, ['SQLCMDUSER', 'SQLCMDPASSWORD', 'SQLCMDSERVER', 'SQLCMDWORKSTATION', 'SQLCMDDBNAME', 'SQLCMDLOGINTIMEOUT', 'SQLCMDSTATTIMEOUT', 'SQLCMDHEADERS', 'SQLCMDCOLSEP', 'SQLCMDCOLWIDTH', 'SQLCMDPACKETSIZE', 'SQLCMDERRORLEVEL', 'SQLCMDMAXVARTYPEWIDTH', 'SQLCMDMAXFIXEDTYPEWIDTH', 'SQLCMDEDITOR', 'SQLCMDINI']);

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
  var _script, callback, cmd, database, error, host, keep, password, port, schema, stderr, stdout, tmp, user;
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
  ({user, password, database, schema, cmd, host, port, stdout, stderr, tmp, keep} = options);
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
};
