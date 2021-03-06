var AdapterPool, Connector, Semaphore, SemaphorePool, _delegateAdapterExec, client_seq_id, clone, defaultOptions, defaults, extend, inherits, internal, isNumeric, isObject, isPlainObject, levelMap, log4js, logger, sysPath, url;

log4js = require('./log4js');

logger = log4js.getLogger(__filename.replace(/^(?:.+[\/\\])?([^.\/\\]+)(?:.[^.]+)?$/, '$1'));

url = require('url');

sysPath = require('path');

({Semaphore} = require('sem-lib'));

clone = require('lodash/clone');

defaults = require('lodash/defaults');

extend = require('lodash/extend');

isObject = require('lodash/isObject');

isPlainObject = require('lodash/isPlainObject');

inherits = require('./inherits');

Connector = require('./Connector');

// Based on jQuery 1.11
isNumeric = function(obj) {
  return !Array.isArray(obj) && (obj - parseFloat(obj) + 1) >= 0;
};

internal = {};

internal.adapters = {};

internal.getAdapter = function(options) {
  var adapter, err;
  if (typeof options.adapter === 'string') {
    adapter = internal.adapters[options.adapter];
    if (typeof adapter === 'undefined') {
      adapter = require('./dialects/' + options.adapter + '/adapter');
      internal.adapters[options.adapter] = adapter;
    }
  } else if (isObject(options.adapter)) {
    adapter = options.adapter;
  }
  if (typeof adapter.createConnection !== 'function') {
    err = new Error('adapter object has no method createConnection');
    err.code = 'BAD_ADAPTER';
    throw err;
  }
  return adapter;
};

defaultOptions = {
  minConnection: 0,
  maxConnection: 1,
  idleTimeout: 10 * 60 //idle for 10 minutes
};

levelMap = {
  error: 'error',
  warn: 'warn',
  info: 'debug',
  verbose: 'trace'
};

client_seq_id = 0;

SemaphorePool = function(options = {}) {
  var i, j, len, len1, opt, ref, ref1;
  this._factory = {};
  ref = ['name', 'create', 'destroy', 'priority'];
  for (i = 0, len = ref.length; i < len; i++) {
    opt = ref[i];
    if (options.hasOwnProperty(opt)) {
      this._factory[opt] = options[opt];
    }
  }
  ref1 = ['min', 'max', 'idle'];
  for (j = 0, len1 = ref1.length; j < len1; j++) {
    opt = ref1[j];
    if (options.hasOwnProperty(opt)) {
      this._factory[opt] = parseInt(options[opt], 10);
    } else {
      this._factory[opt] = 0;
    }
  }
  SemaphorePool.__super__.constructor.call(this, this._max, true, this._priority);
  this._created = {
    length: 0
  };
  this._acquired = {};
  this._avalaible = [];
  this._timers = {};
  this._listeners = {};
  this._ensureMinimum();
};

inherits(SemaphorePool, Semaphore);

Object.assign(SemaphorePool.prototype, {
  getName: function() {
    return this._factory.name;
  },
  acquire: function(callback, opts = {}) {
    var self;
    if (this.destroyed) {
      callback(new Error('pool is destroyed'));
      return;
    }
    self = this;
    return self.semTake({
      priority: opts.priority,
      num: 1,
      timeOut: opts.timeOut,
      onTimeOut: opts.onTimeOut,
      onTake: function() {
        var client, clientId;
        if (self._avalaible.length === 0) {
          self._factory.create(function(err, client) {
            if (err) {
              return callback(err);
            }
            err = self._onClientCreate(client);
            callback(err, client);
          });
          return;
        }
        logger.debug('[', self._factory.name, '] [', self.id, '] reused from availables', self._avalaible.length);
        clientId = self._avalaible.shift();
        client = self._created[clientId];
        self._acquired[clientId] = client;
        self._removeIdle(client);
        callback(null, client);
      }
    });
  },
  _onClientCreate: function(client) {
    var listener;
    if (this._destroying || this.destroyed) {
      this._factory.destroy(client);
      return new Error('pool is destroyed');
    }
    logger.debug('[', this._factory.name, '] [', this.id, '] acquire', this._avalaible.length);
    this._created.length++;
    this._created[client.id] = client;
    this._acquired[client.id] = client;
    listener = this._listeners[client.id] = this._removeClient.bind(this, client);
    client.on('end', listener);
  },
  release: function(client) {
    if (this._acquired.hasOwnProperty(client.id)) {
      logger.debug("[", this._factory.name, "] [", this.id, "] release '", client.id, "'. Avalaible", this._avalaible.length);
      this._avalaible.push(client.id);
      delete this._acquired[client.id];
      this._idle(client);
      return this.semGive();
    }
    return false;
  },
  _idle: function(client) {
    if (this._factory.idle > 0) {
      this._removeIdle(client);
      this._timers[client.id] = setTimeout(this.destroy.bind(this, client), this._factory.idle);
      logger.debug("[", this._factory.name, "] [", this.id, "] idle [", client.id, "]");
    }
  },
  _removeIdle: function(client) {
    if (this._timers.hasOwnProperty(client.id)) {
      logger.debug("[", this._factory.name, "] [", this.id, "] remove idle [", client.id, "]");
      clearTimeout(this._timers[client.id]);
      delete this._timers[client.id];
    }
  },
  destroy: function(client, force) {
    if (this._created.hasOwnProperty(client.id)) {
      if (force || this._factory.min < this._created.length) {
        this._removeClient(client);
        this._factory.destroy(client);
        return true;
      } else {
        this._idle(client);
      }
    }
    return false;
  },
  _superDestroy: function(safe, _onDestroy) {
    return SemaphorePool.__super__.destroy.call(this, safe, _onDestroy);
  },
  destroyAll: function(safe, _onDestroy) {
    var self;
    self = this;
    self._superDestroy(safe, function() {
      self._onDestroy();
      if ('function' === typeof _onDestroy) {
        _onDestroy();
      }
    });
  },
  _removeClient: function(client) {
    var index, listener;
    if (this._created.hasOwnProperty(client.id)) {
      this._created.length--;
      listener = this._listeners[client.id];
      client.removeListener('end', listener);
      this._removeIdle(client);
      this.release(client);
      index = this._avalaible.indexOf(client.id);
      if (~index) {
        this._avalaible.splice(index, 1);
      }
      delete this._listeners[client.id];
      delete this._created[client.id];
      delete this._acquired[client.id];
      logger.debug("[", this._factory.name, "] [", this.id, "] removed '", client.id, "'. ", this._avalaible.length, "/", this._created.length);
      if (!this._destroying) {
        this._ensureMinimum();
      }
    }
  },
  _onDestroy: function(safe) {
    var client, clientId, ref, ref1, timer;
    this._avalaible.splice(0, this._avalaible.length);
    ref = this._created;
    for (clientId in ref) {
      client = ref[clientId];
      if (clientId !== 'length') {
        this._removeClient(client);
        this._factory.destroy(client);
      }
    }
    ref1 = this._timers;
    for (clientId in ref1) {
      timer = ref1[clientId];
      if (timer) {
        clearTimeout(timer);
      }
    }
  },
  _ensureMinimum: function() {
    var self;
    self = this;
    if (self._factory.min > self._created.length) {
      logger.debug("[", self._factory.name, "] [", self.id, "] _ensureMinimum.", self._created.length, "/", self._factory.min);
      self.acquire(function(err, client) {
        if (err) {
          return self.emit('error', err);
        }
        self.release(client);
        self._ensureMinimum();
      });
    }
  }
});

_delegateAdapterExec = function(defaultOptions, script, options, done) {
  var _script;
  if (isPlainObject(script)) {
    _script = options;
    options = script;
    script = _script;
  }
  if ('function' === typeof options) {
    done = options;
    options = {};
  }
  if (!isPlainObject(options)) {
    options = {};
  }
  return this.exec(script, defaults({}, options, defaultOptions), done);
};

AdapterPool = function(connectionUrl, options, next) {
  var adapter, err, except, i, index, j, k, key, len, len1, len2, method, parsed, prop, ref, ref1, ref2, self;
  if (arguments.length === 1) {
    if (connectionUrl !== null && 'object' === typeof connectionUrl) {
      options = connectionUrl;
      connectionUrl = null;
    }
  } else if (arguments.length === 2) {
    if ('function' === typeof options) {
      next = options;
      options = null;
    }
    if (connectionUrl !== null && 'object' === typeof connectionUrl) {
      options = connectionUrl;
      connectionUrl = null;
    }
  }
  if (connectionUrl && typeof connectionUrl !== 'string') {
    err = new Error("'connectionUrl' must be a String");
    err.code = 'BAD_CONNECTION_URL';
    throw err;
  }
  if (options && 'object' !== typeof options) {
    err = new Error("'options' must be an object");
    err.code = 'BAD_OPTION';
    throw err;
  }
  if (connectionUrl) {
    this.connectionUrl = connectionUrl;
    parsed = url.parse(connectionUrl, true, true);
    this.options = {};
    this.options.adapter = parsed.protocol && parsed.protocol.substring(0, parsed.protocol.length - 1);
    this.options.database = parsed.pathname && parsed.pathname.substring(1);
    this.options.host = parsed.hostname;
    if (isNumeric(parsed.port)) {
      this.options.port = parseInt(parsed.port, 10);
    }
    if (parsed.auth) {
      // treat the first : as separator since password may contain : as well
      index = parsed.auth.indexOf(':');
      this.options.user = parsed.auth.substring(0, index);
      this.options.password = parsed.auth.substring(index + 1);
    }
    for (key in parsed.query) {
      this.options[key] = parsed.query[key];
    }
    extend(this.options, options);
    options || (options = {});
  } else if (options) {
    this.options = clone(options);
    parsed = {
      query: {}
    };
    parsed.protocol = this.options.adapter + '/';
    parsed.pathname = '/' + this.options.database;
    parsed.hostname = this.options.host;
    if (isNumeric(this.options.port)) {
      parsed.port = this.options.port;
    }
    if ('string' === typeof this.options.user && this.options.user.length > 0) {
      if ('string' === typeof this.options.password && this.options.password.length > 0) {
        parsed.auth = this.options.user + ':' + this.options.password;
      } else {
        parsed.auth = this.options.user;
      }
    }
    except = ['adapter', 'database', 'port', 'user', 'password'];
    for (key in this.options) {
      if (-1 === except.indexOf(key)) {
        parsed.query[key] = this.options[key];
      }
    }
    this.connectionUrl = url.format(parsed);
  } else {
    err = new Error("Invalid arguments. Usage: options[, fn]; url[, fn]: url, options[, fn]");
    err.code = 'INVALID_ARGUMENTS';
    throw err;
  }
  if (typeof this.options.adapter !== 'string' || this.options.adapter.length === 0) {
    err = new Error('adapter must be a not empty string');
    err.code = 'BAD_ADAPTER';
    throw err;
  }
  ref = ['name'];
  for (i = 0, len = ref.length; i < len; i++) {
    prop = ref[i];
    if (typeof options.hasOwnProperty(prop)) {
      this.options[prop] = options[prop];
    }
  }
  ref1 = ['minConnection', 'maxConnection', 'idleTimeout'];
  for (j = 0, len1 = ref1.length; j < len1; j++) {
    prop = ref1[j];
    if (isNumeric(this.options[prop])) {
      this.options[prop] = parseInt(this.options[prop], 10);
    } else {
      this.options[prop] = defaultOptions[prop];
    }
  }
  adapter = this.adapter = internal.getAdapter(this.options);
  ref2 = ['escape', 'escapeId', 'escapeSearch', 'escapeBeginWith', 'escapeEndWith'];
  for (k = 0, len2 = ref2.length; k < len2; k++) {
    method = ref2[k];
    if ('function' === typeof adapter[method]) {
      this[method] = adapter[method].bind(adapter);
    }
  }
  this.exec = this.execute = _delegateAdapterExec.bind(adapter, this.options);
  self = this;
  AdapterPool.__super__.constructor.call(this, {
    name: self.options.name,
    create: function(callback) {
      self.adapter.createConnection(self.options, function(err, client) {
        if (err) {
          return callback(err, null);
        }
        client.id = ++client_seq_id;
        logger.info("[", self._factory.name, "] [", self.id, "] create [", client_seq_id, "]");
        callback(null, client);
      });
    },
    destroy: function(client) {
      if (client._destroying) {
        return;
      }
      client._destroying = true;
      client.end();
      logger.info("[", self._factory.name, "] [", self.id, "] destroy [", client.id, "]");
    },
    max: self.options.maxConnection,
    min: self.options.minConnection,
    idle: self.options.idleTimeout * 1000
  });
  if (typeof next === 'function') {
    self.check(next);
  }
};

inherits(AdapterPool, SemaphorePool);

Object.assign(AdapterPool.prototype, {
  check: function(next) {
    if ('function' !== typeof next) {
      next = function() {};
    }
    this.acquire((err, connection) => {
      if (err) {
        return next(err);
      }
      this.release(connection);
      next();
    });
  },
  getDialect: function() {
    return this.options.adapter;
  },
  createConnector: function(options) {
    return new Connector(this, defaults({}, options, this.options));
  },
  getMaxConnection: function() {
    return this.options.maxConnection;
  }
});

module.exports = AdapterPool;
