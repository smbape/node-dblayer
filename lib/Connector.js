var Connector, EventEmitter, MAX_ACQUIRE_TIME, STATES, _, log4js, logger, semLib,
  boundMethodCheck = function(instance, Constructor) { if (!(instance instanceof Constructor)) { throw new Error('Bound instance method accessed before binding'); } };

log4js = require('./log4js');

logger = log4js.getLogger(__filename.replace(/^(?:.+[\/\\])?([^.\/\\]+)(?:.[^.]+)?$/, '$1'));

EventEmitter = require('events').EventEmitter;

semLib = require('sem-lib');

_ = require('lodash');

STATES = {
  INVALID: -1,
  AVAILABLE: 0,
  START_TRANSACTION: 1,
  ROLLBACK: 2,
  COMMIT: 3,
  ACQUIRE: 4,
  RELEASE: 5,
  QUERY: 6,
  FORCE_RELEASE: 6
};

MAX_ACQUIRE_TIME = 1 * 60 * 1000;

module.exports = Connector = (function() {
  class Connector extends EventEmitter {
    constructor(pool, options) {
      var error, i, j, len, len1, method, ref, ref1;
      super();
      this._forceRelease = this._forceRelease.bind(this);
      this._checkSafeEnd = this._checkSafeEnd.bind(this);
      this._giveResource = this._giveResource.bind(this);
      if (!_.isObject(pool)) {
        error = new Error('pool is not defined');
        error.code = 'POOL_UNDEFINED';
        throw error;
      }
      ref = ['escape', 'escapeId', 'escapeSearch', 'escapeBeginWith', 'escapeEndWith'];
      for (i = 0, len = ref.length; i < len; i++) {
        method = ref[i];
        if ('function' === typeof pool.adapter[method]) {
          this[method] = pool.adapter[method].bind(pool.adapter);
        }
      }
      ref1 = ['getDialect', 'exec', 'execute'];
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        method = ref1[j];
        if ('function' === typeof pool[method]) {
          this[method] = pool[method].bind(pool);
        }
      }
      if (_.isPlainObject(options)) {
        this.options = _.clone(options);
      } else {
        this.options = {};
      }
      this.timeout = this.options.timeout || MAX_ACQUIRE_TIME;
      this.resourceSem = semLib.semCreate(1, true);
      this.pool = pool;
      this._savepoints = 0;
      this.state = STATES.AVAILABLE;
      this.acquireTimeout = 0;
      this.resource = 1;
      this.waiting = [];
      this._savepointsStack = [];
    }

    clone() {
      return new Connector(this.pool, this.options);
    }

    getPool() {
      return this.pool;
    }

    getMaxConnection() {
      return this.pool.getMaxConnection();
    }

    _addSavePoint(client) {
      this._savepointsStack.push(new Error("_addSavePoint"));
      if (client) {
        this._client = client;
        this.acquireTimeout = setTimeout(this._forceRelease, this.timeout);
        client.on('end', this._checkSafeEnd);
        logger.debug('acquired client', client.id);
      }
      return this._savepoints++;
    }

    _forceRelease() {
      boundMethodCheck(this, Connector);
      this._takeResource(STATES.FORCE_RELEASE, () => {
        if (this._savepoints === 0) {
          return this._giveResource();
        }
        this.state = STATES.INVALID;
        logger.warn('Force rollback and release cause acquire last longer than acceptable');
        this._rollback(this._giveResource, true);
      }, true);
    }

    _checkSafeEnd() {
      boundMethodCheck(this, Connector);
      if (this._savepoints !== 0) {
        logger.warn('client ends in the middle of a transaction');
        this.state = STATES.INVALID;
        this._release(function() {});
      }
    }

    _removeSavepoint() {
      this._savepointsStack.pop();
      if (--this._savepoints === 0) {
        this._client.removeListener('end', this._checkSafeEnd);
        logger.debug('released client', this._client.id);
        return this._client = null;
      }
    }

    getState() {
      return this.state;
    }

    getSavepointsSize() {
      return this._savepoints;
    }

    _hasError() {
      var error;
      if (this.state === STATES.INVALID) {
        error = new Error('Connector is in invalid state.');
        error.code = 'INVALID_STATE';
        return error;
      }
    }

    _takeResource(state, callback, prior) {
      var err;
      if (err = this._hasError()) {
        return callback(err);
      }
      if (this.resource === 1) {
        this.resource = 0;
        if (state != null) {
          this.state = state;
        }
        callback();
      } else if (prior) {
        this.waiting.unshift([state, callback, prior]);
      } else {
        this.waiting.push([state, callback, prior]);
      }
    }

    _giveResource() {
      var callback, prior, state;
      boundMethodCheck(this, Connector);
      this.resource = 1;
      if (this.state !== STATES.INVALID) {
        this.state = STATES.AVAILABLE;
      }
      if (this.waiting.length) {
        [state, callback, prior] = this.waiting.shift();
        this._takeResource(state, callback, prior);
      }
    }

    acquire(callback) {
      var ret;
      logger.trace(this.pool.options.name, 'acquire');
      ret = (...args) => {
        this._giveResource();
        if (typeof callback === 'function') {
          callback(...args);
        }
      };
      return this._takeResource(STATES.ACQUIRE, (err) => {
        if (err) {
          return ret(err);
        }
        this._acquire(ret);
      });
    }

    _acquire(callback) {
      // check if connection has already been acquired
      if (this._savepoints > 0) {
        logger.trace(this.pool.options.name, 'already acquired');
        callback(null, false);
        return;
      }
      this.pool.acquire((err, client) => {
        if (err) {
          return callback(err);
        }
        logger.trace(this.pool.options.name, 'acquired');
        this._addSavePoint(client);
        return callback(null, true);
      });
    }

    query(query, callback, options) {
      var ret;
      ret = (...args) => {
        this._giveResource();
        if (typeof callback === 'function') {
          callback(...args);
        }
      };
      this._takeResource(STATES.QUERY, (err) => {
        if (err) {
          return ret(err);
        }
        if (this._savepoints === 0) {
          logger.trace(this.pool.options.name, 'automatic acquire for query');
          return this._acquire((err) => {
            if (err) {
              return ret(err);
            }
            return this._query(query, (...args) => {
              logger.trace(this.pool.options.name, 'automatic release for query');
              return this._release((err) => {
                args[0] = err;
                return ret.apply(this, args);
              }, args[0]);
            }, options);
          });
        }
        this._query(query, ret, options);
      });
    }

    _query(query, callback, options = {}) {
      logger.trace(this.pool.options.name, '[query] -', query);
      return this._client.query(query, (err, res) => {
        if (err && options.autoRollback !== false) {
          logger.warn(this.pool.options.name, 'automatic rollback on query error', err);
          return this._rollback(callback, false, err);
        }
        return callback(err, res);
      });
    }

    stream(query, callback, done, options = {}) {
      var ret;
      ret = (...args) => {
        this._giveResource();
        if (typeof done === 'function') {
          done(...args);
        }
      };
      this._takeResource(STATES.STREAM, (err) => {
        if (err) {
          return ret(err);
        }
        if (this._savepoints === 0) {
          logger.trace(this.pool.options.name, 'automatic acquire for stream');
          return this._acquire((err) => {
            if (err) {
              return ret(err);
            }
            logger.trace(this.pool.options.name, 'automatic release for stream');
            return this._stream(query, callback, (...args) => {
              return this._release((err) => {
                args[0] = err;
                return ret.apply(this, args);
              }, args[0]);
            }, options);
          });
        }
        this._stream(query, callback, ret, options);
      });
    }

    _stream(query, callback, done, options = {}) {
      var stream;
      logger.trace(this.pool.options.name, '[stream] -', query);
      stream = this._client.stream(query, function(row) {
        return callback(row, stream);
      }, (err, ...args) => {
        if (err && options.autoRollback !== false) {
          logger.warn(this.pool.options.name, 'automatic rollback on stream error', err);
          return this._rollback(done, false, err);
        }
        return done(err, ...args);
      });
    }

    begin(callback) {
      var err, ret;
      if (this._savepoints === 0) {
        // No automatic acquire because there cannot be an automatic release
        // Programmer may or may not perform a query/stream with the connection.
        // Therefore, there is no way to know when to release connection
        err = new Error('Connector has no active connection. You must acquire a connection before begining a transaction.');
        err.code = 'NO_CONNECTION';
        return callback(err);
      }
      logger.debug(this.pool.options.name, 'begin');
      ret = (...args) => {
        this._giveResource();
        logger.debug(this.pool.options.name, 'begun');
        if (typeof callback === 'function') {
          callback(...args);
        }
      };
      return this._takeResource(STATES.START_TRANSACTION, (err) => {
        if (err) {
          return ret(err);
        }
        if (this._savepoints === 0) {
          // No automatic acquire because there cannot be an automatic release
          // Programmer may or may not perform a query/stream with the connection.
          // Therefore, there is no way to know when to release connection
          err = new Error('Connector has no active connection. You must acquire a connection before begining a transaction.');
          err.code = 'NO_CONNECTION';
          return ret(err);
        }
        return this._begin(ret);
      });
    }

    _begin(callback) {
      var query;
      if (this._savepoints === 1) {
        // we have no transaction
        query = 'BEGIN';
      } else if (this._savepoints > 0) {
        // we are in a transaction, make a savepoint
        query = 'SAVEPOINT sp_' + (this._savepoints - 1);
      }
      logger.trace(this.pool.options.name, '[query] -', query);
      this._client.query(query, (err, res) => {
        if (err) {
          return callback(err);
        }
        this._addSavePoint();
        logger.trace(this.pool.options.name, 'begun');
        callback(null);
      });
    }

    rollback(callback, all = false) {
      var ret;
      logger.debug(this.pool.options.name, 'rollback');
      ret = (...args) => {
        this._giveResource();
        logger.debug(this.pool.options.name, 'rollbacked');
        if (typeof callback === 'function') {
          callback(...args);
        }
      };
      return this._takeResource(STATES.ROLLBACK, (err) => {
        if (err) {
          return ret(err);
        }
        if (this._savepoints === 0) {
          return ret(null);
        }
        return this._rollback(ret, all);
      });
    }

    _rollback(callback, all, errors) {
      var query;
      if (this._savepoints === 1) {
        if (all) {
          return this._release(callback, errors);
        }
        return callback(errors);
      } else if (this._savepoints === 0) {
        return callback(errors);
      } else if (this._savepoints === 2) {
        query = 'ROLLBACK';
      } else {
        query = 'ROLLBACK TO sp_' + (this._savepoints - 2);
      }
      this._removeSavepoint();
      logger.trace(this.pool.options.name, '[query] -', query);
      return this._client.query(query, (err) => {
        if (err) {
          if (typeof errors === 'undefined') {
            errors = err;
          } else if (errors instanceof Array) {
            errors.push(err);
          } else {
            errors = [errors];
            errors.push(err);
          }
        }
        if (all) {
          return this._rollback(callback, all, errors);
        }
        return callback(errors);
      });
    }

    commit(callback, all = false) {
      var _all, _callback, ret;
      if (typeof callback === 'boolean') {
        _all = callback;
      } else if (typeof all === 'boolean') {
        _all = all;
      }
      if (typeof callback === 'function') {
        _callback = callback;
      } else if (typeof all === 'function') {
        _callback = all;
      }
      callback = _callback;
      all = _all;
      logger.debug(this.pool.options.name, 'commit');
      ret = (...args) => {
        this._giveResource();
        logger.debug(this.pool.options.name, 'comitted');
        if (typeof callback === 'function') {
          callback(...args);
        }
      };
      return this._takeResource(STATES.COMMIT, (err) => {
        if (err) {
          return ret(err);
        }
        if (this._savepoints === 0) {
          return ret(null);
        }
        return this._commit(ret, all);
      });
    }

    _commit(callback, all, errors) {
      var query;
      if (this._savepoints === 1) {
        if (all) {
          return this._release(callback, errors);
        }
        return callback(errors);
      } else if (this._savepoints === 0) {
        return callback(errors);
      } else if (this._savepoints === 2) {
        query = 'COMMIT';
      } else {
        query = 'RELEASE SAVEPOINT sp_' + (this._savepoints - 2);
      }
      logger.trace(this.pool.options.name, '[query] -', query);
      return this._client.query(query, (err) => {
        if (err) {
          if (typeof errors === 'undefined') {
            errors = err;
          } else if (errors instanceof Array) {
            errors.push(err);
          } else {
            errors = [errors];
            errors.push(err);
          }
        }
        if (err) {
          return this._rollback(callback, all, errors);
        }
        this._removeSavepoint();
        if (all) {
          return this._commit(callback, all, errors);
        }
        return callback(null);
      });
    }

    release(callback) {
      var ret;
      logger.debug(this.pool.options.name, 'release');
      ret = (...args) => {
        this._giveResource();
        if (typeof callback === 'function') {
          callback(...args);
        }
      };
      return this._takeResource(STATES.RELEASE, (err) => {
        if (err) {
          return ret(err);
        }
        if (this._savepoints === 0) {
          logger.debug(this.pool.options.name, 'already released');
          return ret(null);
        }
        if (this._savepoints !== 1) {
          err = new Error('There is a begining transaction. End it before release');
          err.code = 'NO_RELEASE';
          return ret(err);
        }
        this._release(ret);
      });
    }

    _release(callback, errors) {
      clearTimeout(this.acquireTimeout);
      this.pool.release(this._client);
      logger.debug(this.pool.options.name, 'released');
      this._removeSavepoint();
      callback(errors);
    }

  };

  Connector.prototype.STATES = STATES;

  return Connector;

}).call(this);
