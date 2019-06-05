var inherits,
  hasProp = {}.hasOwnProperty;

inherits = function(child, parent) {
  var ctor, key;
  for (key in parent) {
    if (!hasProp.call(parent, key)) continue;
    child[key] = parent[key];
  }
  ctor = function() {
    this.constructor = child;
  };
  ctor.prototype = parent.prototype;
  child.prototype = new ctor();
  child.__super__ = parent.prototype;
  return child;
};

module.exports = inherits;
