
module.exports = 
    exprNotEqual: (value, escapeColumn)->
        connector = @
        if value is null
            escapeColumn + ' IS NOT NULL'
        else
            escapeColumn + ' IS NULL OR ' + escapeColumn + ' <> ' + connector.escape value

    exprEqual: (value, escapeColumn)->
        connector = @
        if value is null
            escapeColumn + ' IS NULL'
        else
            escapeColumn + ' = ' + connector.escape value
