var PlaceHolderParser;

module.exports = PlaceHolderParser = class PlaceHolderParser {
  constructor(beginStr = '__', endStr) {
    var endWithWordChar, reg, special;
    if ('string' !== typeof beginStr || beginStr.length === 0) {
      throw new Error('Invalid begin string');
    }
    if (arguments.length < 2) {
      endStr = beginStr;
    } else if (arguments.length > 2) {
      throw new Error('More than 2 arguments has been given');
    } else if ('string' !== typeof endStr || endStr.length === 0) {
      throw new Error('Invalid end string');
    }
    special = /([\\^$.|?*+()\[\]{}])/g;
    beginStr = beginStr.replace(special, '\\$1');
    endStr = endStr.replace(special, '\\$1');
    reg = ['(?:(["\'`])|'];
    if (/^\\?\w/.test(beginStr.substring(0, 2))) {
      reg.push('\\b');
    }
    reg.push(beginStr);
    reg.push('((?:(?!', endStr);
    if (endWithWordChar = /\w/.test(endStr[endStr.length - 1])) {
      reg.push('\\b');
    }
    reg.push(').)+)(', endStr, ')?');
    if (endWithWordChar) {
      reg.push('\\b');
    }
    reg.push(')');
    this.reg = new RegExp(reg.join(''), 'g');
  }

  parse(str) {
    var cursor, indexes, list, quoting;
    list = [];
    indexes = {};
    cursor = 0;
    quoting = false;
    str.replace(this.reg, function(match, quote, key, end, start, str) {
      if (quoting) {
        // placeholder match is ignored within a string
        if (quote === quoting) {
          // end of a quoted string
          quoting = false;
        }
      } else {
        if (quote) {
          // begining of a quoted string
          quoting = quote;
        } else if (end) {
          // placeholder found

          // get string up to start of placeholder
          if (cursor < start) {
            list[list.length] = str.substring(cursor, start);
          }
          // move cursor after match
          cursor = start + match.length;
          // remeber placeholder position for replacement
          indexes[key] || (indexes[key] = []);
          indexes[key].push(list.length);
          list[list.length] = match;
        }
      }
      return match;
    });
    if (cursor < str.length) {
      list[list.length] = str.substring(cursor, str.length);
    }
    return [list, indexes];
  }

  replace(str, callback) {
    var quoting;
    quoting = false;
    return str.replace(this.reg, function(match, quote, key, end) {
      if (quoting) {
        // placeholder match is ignored within a string
        if (quote === quoting) {
          // end of a quoted string
          quoting = false;
        }
      } else {
        if (quote) {
          // begining of a quoted string
          quoting = quote;
        } else if (end) {
          // placeholder found
          match = callback(key);
        }
      }
      return match;
    });
  }

  precompile(str) {
    var except, i, index, indexes, j, key, len, len1, list, ref;
    [list, indexes] = this.parse(str);
    except = [];
    for (key in indexes) {
      ref = indexes[key];
      for (i = 0, len = ref.length; i < len; i++) {
        index = ref[i];
        except.push(index);
        list[index] = `' + (context['${key}'] || '') + '`;
      }
    }
    for (index = j = 0, len1 = list.length; j < len1; index = ++j) {
      str = list[index];
      if (-1 === except.indexOf(index)) {
        list[index] = str.replace(/'/g, "\\'");
      }
    }
    return `function template(context) {\n    if (context === null || 'object' !== typeof context) {\n        context = {};\n    }\n    return '${list.join('')}';\n}`;
  }

  unsafeCompile(str) {
    return (new Function(this.precompile(str) + "return template;"))();
  }

  safeCompile(str) {
    var indexes, list;
    [list, indexes] = this.parse(str);
    return function(context) {
      var _list, i, index, key, len, ref;
      if (context === null || 'object' !== typeof context) {
        return list.join('');
      }
      _list = list.slice();
      for (key in indexes) {
        if (context.hasOwnProperty(key)) {
          ref = indexes[key];
          for (i = 0, len = ref.length; i < len; i++) {
            index = ref[i];
            _list[index] = context[key];
          }
        }
      }
      return _list.join('');
    };
  }

};
