var _, adapter, common, escapeOpts, logger;

_ = require('lodash');

common = require('../../schema/adapter');

adapter = module.exports;

_.extend(adapter, common);

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

throw new Error('not implemented');

_.extend(adapter, {
  name: 'oracle',
  createConnection: function(options, callback) {
    throw new Error('not implemented');
  },
  squelOptions: {
    replaceSingleQuotes: true,
    nameQuoteCharacter: '"',
    fieldAliasQuoteCharacter: '"',
    tableAliasQuoteCharacter: '"'
  },
  decorateInsert: function(query, column) {
    throw new Error('not implemented');
  }
});
