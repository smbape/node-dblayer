inherits = (child, parent) ->
    for own key of parent
        child[key] = parent[key]

    ctor = ->
        this.constructor = child
        return

    ctor.prototype = parent.prototype
    child.prototype = new ctor()
    child.__super__ = parent.prototype

    return child

module.exports = inherits
