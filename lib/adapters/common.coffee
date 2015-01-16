
module.exports = 
    exprNotEqual: (value, escapeColumn)->
        if value is null
            escapeColumn + ' IS NOT NULL'
        else
            escapeColumn + ' IS NULL OR ' + escapeColumn + ' <> ' + @escape value

    exprEqual: (value, escapeColumn)->
        if value is null
            escapeColumn + ' IS NULL'
        else
            escapeColumn + ' = ' + @escape value
