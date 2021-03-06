var _escape, consumeChunck, eatBlockComment, eatLineComment, eatString, quote, stack, states;

_escape = exports._escape = function(opts, str) {
  var i, iStr, j, len1, ret;
  switch (typeof str) {
    case 'number':
      return str;
    case 'boolean':
      str = str ? '1' : '0';
      return (opts.quoteStart || opts.quote) + str + (opts.quoteEnd || opts.quote);
    case 'string':
      break;
    default:
      // do nothing
      if (Array.isArray(str)) {
        ret = new Array(str.length);
        for (i = j = 0, len1 = str.length; j < len1; i = ++j) {
          iStr = str[i];
          ret[i] = _escape(opts, iStr);
        }
        return '(' + ret.join(', ') + ')';
      }
      str = '' + str;
  }
  str = str.replace(opts.matcher, function(match, _char) {
    return opts.replace[_char];
  });
  return (opts.quoteStart || opts.quote) + str + (opts.quoteEnd || opts.quote);
};

exports.exprNotEqual = function(value, columnId) {
  if (value === null) {
    return columnId + ' IS NOT NULL';
  } else {
    return columnId + ' IS NULL OR ' + columnId + ' <> ' + this.escape(value);
  }
};

exports.exprEqual = function(value, columnId) {
  if (value === null) {
    return columnId + ' IS NULL';
  } else {
    return columnId + ' = ' + this.escape(value);
  }
};

eatLineComment = function(chunck, len, pos, LF) {
  while (pos < len && chunck[pos] !== LF) {
    pos++;
  }
  return [pos, chunck[pos] === LF];
};

eatBlockComment = function(chunck, len, pos) {
  var done;
  while (pos < len && ('*' !== chunck[pos] || '/' !== chunck[pos + 1])) {
    pos++;
  }
  if (done = '*' === chunck[pos] && '/' === chunck[pos + 1]) {
    pos += 2;
  }
  return [pos, done];
};

eatString = function(chunck, len, pos, quote) {
  var done;
  while (pos < len && (chunck[pos] !== quote || chunck[pos + 1] === quote)) {
    pos++;
  }
  if (done = chunck[pos] === quote && chunck[pos + 1] !== quote) {
    pos++;
  }
  return [pos, done];
};

stack = [];

states = [];

quote = null;

consumeChunck = function(chunck, state, callback) {
  var currChar, current, done, error, lastPos, len, level, pos, query, remaining;
  len = chunck.length;
  lastPos = 0;
  ({pos, level, current, states} = state);
  while (!error && pos < len) {
    currChar = chunck[pos];
    switch (current) {
      case 'initial':
        switch (currChar) {
          case '"':
          case "'":
          case '`':
            // console.log 'quote'
            quote = currChar;
            states.push(current);
            current = 'quoting';
            ++pos;
            break;
          case ';':
            // console.log 'semi colon'
            if (level === 0 && lastPos < pos) {
              while (/\s/.test(chunck[lastPos])) {
                lastPos++;
              }
              query = chunck.substring(lastPos, pos);
              if (!/^\s*$/.test(query)) {
                error = callback(query);
              }
              lastPos = pos + 1;
            }
            ++pos;
            break;
          case '(':
            // console.log 'open'
            level++;
            ++pos;
            break;
          case ')':
            // console.log 'close'
            level--;
            ++pos;
            break;
          default:
            ++pos;
        }
        break;
      case 'quoting':
        // console.log 'quoting'
        [pos, done] = eatString(chunck, len, pos, quote);
        if (done) {
          current = 'quoting-end';
        }
        break;
      case 'quoting-end':
        // console.log 'quoting-end'
        if (currChar === quote) {
          current = 'quoting';
          ++pos;
        } else {
          // go back to previous state
          current = states.pop();
          quote = null;
        }
    }
  }
  if (lastPos < pos) {
    remaining = chunck.substring(lastPos, pos);
  }
  state.pos = pos;
  state.level = level;
  state.current = current;
  state.error = error;
  return remaining;
};

exports.split = function(str, callback, done) {
  var lastPos, onData, remainging, remaining, state;
  state = {
    pos: 0,
    level: 0,
    current: 'initial',
    states: []
  };
  switch (typeof str) {
    case 'string':
      remaining = consumeChunck(str, state, callback);
      if (!state.error && remaining && !/^\s*;?\s*$/.test(remaining)) {
        lastPos = 0;
        while (/\s/.test(chunck[lastPos])) {
          lastPos++;
        }
        callback(remaining.substring(lastPos));
      }
      done(state.error);
      return;
    case 'object':
      if (str === null) {
        done();
        return;
      }
      remainging = null;
      onData = function(chunck) {
        var pos;
        if (remaining) {
          chunck = remainging + chunck.toString('utf8');
          pos = remainging.length;
        } else {
          chunck = chunck.toString('utf8');
          pos = 0;
        }
        state.pos = pos;
        remaining = consumeChunck(chunck, state, callback);
        if (state.error) {
          str.removeListener('data', onData);
          str.end();
        }
      };
      str.on('data', onData);
      str.on('end', function(chunck) {
        if (!state.error && remaining && !/^\s*;?\s*$/.test(remaining)) {
          lastPos = 0;
          while (/\s/.test(chunck[lastPos])) {
            lastPos++;
          }
          callback(remaining.substring(lastPos));
        }
        done(state.error);
      });
      break;
    default:
      done();
  }
};
