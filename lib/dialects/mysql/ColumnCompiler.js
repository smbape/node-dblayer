var ColumnCompiler, LOWERWORDS, MySQLColumnCompiler, _, map, tools,
  extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
  hasProp = {}.hasOwnProperty;

_ = require('lodash');

ColumnCompiler = require('../../schema/ColumnCompiler');

tools = require('../../tools');

map = Array.prototype.map;

LOWERWORDS = {
  auto_increment: 'auto_increment',
  tinyint: 'tinyint',
  mediumint: 'mediumint',
  unsigned: 'unsigned',
  zerofill: 'zerofill',
  drop_primary_key: 'drop primary key',
  drop_foreign_key: 'drop foreign key',
  rename_index: 'rename index',
  change_column: 'change column'
};

module.exports = MySQLColumnCompiler = (function(superClass) {
  extend(MySQLColumnCompiler, superClass);

  function MySQLColumnCompiler() {
    return MySQLColumnCompiler.__super__.constructor.apply(this, arguments);
  }

  return MySQLColumnCompiler;

})(ColumnCompiler);

MySQLColumnCompiler.prototype.adapter = require('./adapter');

MySQLColumnCompiler.prototype.smallincrements = function() {
  return [this.words.smallint, this.words.unsigned, this.words.not_null, this.words.auto_increment, this.words.unique].join(' ');
};

MySQLColumnCompiler.prototype.mediumincrements = function() {
  return [this.words.mediumint, this.words.unsigned, this.words.not_null, this.words.auto_increment, this.words.unique].join(' ');
};

MySQLColumnCompiler.prototype.increments = function() {
  return [this.words.integer, this.words.unsigned, this.words.not_null, this.words.auto_increment, this.words.unique].join(' ');
};

MySQLColumnCompiler.prototype.bigincrements = function() {
  return [this.words.bigint, this.words.unsigned, this.words.not_null, this.words.auto_increment, this.words.unique].join(' ');
};

MySQLColumnCompiler.prototype.bit = function(length) {
  length = this._num(length, null);
  if (length && length !== 1) {
    return this.words.bit + '(' + length + ')';
  } else {
    return this.words.bit;
  }
};

MySQLColumnCompiler.prototype.tinyint = function(m, unsigned, zerofill) {
  var mdefault, type;
  if (unsigned) {
    mdefault = 3;
  } else {
    mdefault = 4;
  }
  m = this._num(m, mdefault);
  type = [m !== mdefault ? this.words.tinyint + '(' + m + ')' : this.words.tinyint];
  if (unsigned) {
    type.push(this.words.unsigned);
  }
  if (zerofill) {
    type.push(this.words.zerofill);
  }
  return type.join(' ');
};

MySQLColumnCompiler.prototype.bool = function() {
  return this.words.tinyint + '(1)';
};

MySQLColumnCompiler.prototype.smallint = function(m, unsigned, zerofill) {
  var mdefault, type;
  if (unsigned) {
    mdefault = 5;
  } else {
    mdefault = 6;
  }
  m = this._num(m, mdefault);
  type = [m !== mdefault ? this.words.smallint + '(' + m + ')' : this.words.smallint];
  if (unsigned) {
    type.push(this.words.unsigned);
  }
  if (zerofill) {
    type.push(this.words.zerofill);
  }
  return type.join(' ');
};

MySQLColumnCompiler.prototype.mediumint = function(m, unsigned, zerofill) {
  var mdefault, type;
  if (unsigned) {
    mdefault = 8;
  } else {
    mdefault = 9;
  }
  m = this._num(m, mdefault);
  type = [m !== mdefault ? this.words.mediumint + '(' + m + ')' : this.words.mediumint];
  if (unsigned) {
    type.push(this.words.unsigned);
  }
  if (zerofill) {
    type.push(this.words.zerofill);
  }
  return type.join(' ');
};

MySQLColumnCompiler.prototype.integer = function(m, unsigned, zerofill) {
  var mdefault, type;
  if (unsigned) {
    mdefault = 10;
  } else {
    mdefault = 11;
  }
  m = this._num(m, mdefault);
  type = [m !== mdefault ? this.words.integer + '(' + m + ')' : this.words.integer];
  if (unsigned) {
    type.push(this.words.unsigned);
  }
  if (zerofill) {
    type.push(this.words.zerofill);
  }
  return type.join(' ');
};

MySQLColumnCompiler.prototype.bigint = function(m, unsigned, zerofill) {
  var type;
  m = this._num(m, 20);
  type = [m !== 20 ? this.words.bigint + '(' + m + ')' : this.words.bigint];
  if (unsigned) {
    type.push(this.words.unsigned);
  }
  if (zerofill) {
    type.push(this.words.zerofill);
  }
  return type.join(' ');
};

MySQLColumnCompiler.prototype.numeric = MySQLColumnCompiler.prototype.dec = MySQLColumnCompiler.prototype.fixed = MySQLColumnCompiler.prototype.decimal = function(m, d, unsigned, zerofill) {
  var type;
  type = [this.words.decimal + '(' + this._num(m, 10) + ', ' + this._num(d, 0) + ')'];
  if (unsigned) {
    type.push(this.words.unsigned);
  }
  if (zerofill) {
    type.push(this.words.zerofill);
  }
  return type.join(' ');
};

MySQLColumnCompiler.prototype.float = function(m, d, unsigned, zerofill) {
  var type;
  m = this._num(m, null);
  if (m && d) {
    type = [this.words.float + '(' + m + ', ' + this._num(d, 2) + ')'];
  } else if (m && m !== 12) {
    type = [this.words.float + '(' + m + ')'];
  } else {
    type = [this.words.float];
  }
  type = [this.words.float];
  if (unsigned) {
    type.push(this.words.unsigned);
  }
  if (zerofill) {
    type.push(this.words.zerofill);
  }
  return type.join(' ');
};

MySQLColumnCompiler.prototype.double = function(m, d, unsigned, zerofill) {
  var type;
  m = this._num(m, null);
  if (m && d) {
    type = [this.words.double + '(' + m + ', ' + this._num(d, 2) + ')'];
  } else if (m && m !== 22) {
    type = [this.words.double + '(' + m + ')'];
  } else {
    type = [this.words.double];
  }
  if (unsigned) {
    type.push(this.words.unsigned);
  }
  if (zerofill) {
    type.push(this.words.zerofill);
  }
  return type.join(' ');
};

MySQLColumnCompiler.prototype.date = function() {
  return this.words.date;
};

MySQLColumnCompiler.prototype.datetime = function(fsp) {
  var type;
  type = this.words.datetime;
  fsp = this._num(fsp, null);
  if (fsp) {
    return type + "(" + fsp + ")";
  } else {
    return type;
  }
};

MySQLColumnCompiler.prototype.timestamp = function(fsp) {
  var type;
  type = this.words.timestamp;
  fsp = this._num(fsp, null);
  if (fsp) {
    return type + "(" + fsp + ")";
  } else {
    return type;
  }
};

MySQLColumnCompiler.prototype.time = function(fsp) {
  var type;
  type = this.words.time;
  fsp = this._num(fsp, null);
  if (fsp) {
    return type + "(" + fsp + ")";
  } else {
    return type;
  }
};

LOWERWORDS.year = 'year';

MySQLColumnCompiler.prototype.year = function() {
  return this.words.year;
};

MySQLColumnCompiler.prototype.char = function(m) {
  return this.words.char + '(' + this._num(m, 255) + ')';
};

MySQLColumnCompiler.prototype.varchar = function(m) {
  return this.words.varchar + '(' + this._num(m, 255) + ')';
};

MySQLColumnCompiler.prototype.binary = function(m) {
  return this.words.binary + '(' + this._num(m, 255) + ')';
};

MySQLColumnCompiler.prototype.varbinary = function(m) {
  return this.words.varbinary + '(' + this._num(m, 255) + ')';
};

LOWERWORDS.tinyblob = 'tinyblob';

MySQLColumnCompiler.prototype.tinyblob = function() {
  return this.words.tinyblob;
};

LOWERWORDS.tinytext = 'tinytext';

MySQLColumnCompiler.prototype.tinytext = function() {
  return this.words.tinytext;
};

LOWERWORDS.blob = 'blob';

MySQLColumnCompiler.prototype.blob = function(m) {
  var type;
  type = this.words.blob;
  m = this._num(m, null);
  if (m && m !== 65535) {
    return type + "(" + m + ")";
  } else {
    return type;
  }
};

MySQLColumnCompiler.prototype.text = function(m) {
  var type;
  type = this.words.text;
  m = this._num(m, null);
  if (m && m !== 65535) {
    return type + "(" + m + ")";
  } else {
    return type;
  }
};

LOWERWORDS.mediumblob = 'mediumblob';

MySQLColumnCompiler.prototype.mediumblob = function() {
  return this.words.mediumblob;
};

LOWERWORDS.mediumtext = 'mediumtext';

MySQLColumnCompiler.prototype.mediumtext = function() {
  return this.words.mediumtext;
};

LOWERWORDS.longblob = 'longblob';

MySQLColumnCompiler.prototype.longblob = function() {
  return this.words.longblob;
};

LOWERWORDS.longtext = 'longtext';

MySQLColumnCompiler.prototype.longtext = function() {
  return this.words.longtext;
};

MySQLColumnCompiler.prototype["enum"] = function() {
  return this.words["enum"] + '(' + map.call(arguments, this.adapter.escape).join(',') + ')';
};

MySQLColumnCompiler.prototype.set = function() {
  return this.words.set + '(' + map.call(arguments, this.adapter.escape).join(',') + ')';
};

MySQLColumnCompiler.prototype.json = function() {
  return this.words.json;
};

MySQLColumnCompiler.prototype.LOWERWORDS = _.defaults(LOWERWORDS, ColumnCompiler.prototype.LOWERWORDS);

MySQLColumnCompiler.prototype.UPPERWORDS = _.defaults(tools.toUpperWords(LOWERWORDS), ColumnCompiler.prototype.UPPERWORDS);

MySQLColumnCompiler.prototype.getColumnModifier = function(spec) {
  if (/^(?:(small|big)?(?:increments|serial)|serial([248]))$/.test(spec.type)) {
    return '';
  }
  return MySQLColumnCompiler.__super__.getColumnModifier.call(this, spec);
};
