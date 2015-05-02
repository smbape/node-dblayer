squel = require 'squel'
_ = require 'lodash'

cls = squel.cls

# HAVING
class cls.HavingBlock extends cls.Block
    constructor: (options) ->
        super options
        @havings = []

    # Add a HAVING condition.
    #
    # When the final query is constructed all the HAVING conditions are combined using the intersection (AND) operator.
    having: (condition, values...) ->
        condition = @_sanitizeCondition(condition)

        finalCondition = ""
        finalValues = []

        # if it's an Expression instance then convert to text and values
        if condition instanceof cls.Expression
            t = condition.toParam()
            finalCondition = t.text
            finalValues = t.values
        else
            for idx in [0...condition.length] by 1
                c = condition.charAt(idx)
                if '?' is c and 0 < values.length
                    nextValue = values.shift()
                    if Array.isArray(nextValue) # having b in (?, ? ?)
                        inValues = []
                        for item in nextValue
                            inValues.push @_sanitizeValue(item)
                        finalValues = finalValues.concat(inValues)
                        finalCondition += "(#{('?' for item in inValues).join ', '})"
                    else
                        finalCondition += '?'
                        finalValues.push @_sanitizeValue(nextValue)
                else
                    finalCondition += c

        if "" isnt finalCondition
            @havings.push
                text: finalCondition
                values: finalValues


    buildStr: (queryBuilder) ->
        if 0 >= @havings.length then return ""

        havingStr = ""

        for having in @havings
            if "" isnt havingStr then havingStr += ") AND ("
            if 0 < having.values.length
                # replace placeholders with actual parameter values
                pIndex = 0
                for idx in [0...having.text.length] by 1
                    c = having.text.charAt(idx)
                    if '?' is c
                        havingStr += @_formatValue( having.values[pIndex++] )
                    else
                        havingStr += c
            else
                havingStr += having.text

        "HAVING (#{havingStr})"


    buildParam: (queryBuilder) ->
        ret = 
            text: ""
            values: []

        if 0 >= @havings.length then return ret

        havingStr = ""

        for having in @havings
            if "" isnt havingStr then havingStr += ") AND ("
            havingStr += having.text
            for v in having.values
                ret.values.push( @_formatValueAsParam v )
                value = @_formatValueAsParam(value)
        ret.text = "HAVING (#{havingStr})"
        ret

# SELECT query builder.
class cls.Select extends cls.QueryBuilder
    constructor: (options, blocks = null) ->
        blocks or= [
            new cls.StringBlock(options, 'SELECT'),
            new cls.DistinctBlock(options),
            new cls.GetFieldBlock(options),
            new cls.FromTableBlock(_.extend({}, options, { allowNested: true })),
            new cls.JoinBlock(_.extend({}, options, { allowNested: true })),
            new cls.WhereBlock(options),
            new cls.GroupByBlock(options),
            new cls.HavingBlock(options),
            new cls.OrderByBlock(options),
            new cls.LimitBlock(options),
            new cls.OffsetBlock(options)
        ]

        super options, blocks

    isNestable: ->
        true

module.exports = squel