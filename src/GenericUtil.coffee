factory = (require)->
    toString = ({}).toString;
    hasOwnProperty = Object::hasOwnProperty
    GenericUtil =
        
        # Based on jQuery 1.11
        isNumeric: (obj) ->
            !Array.isArray( obj ) and (obj - parseFloat( obj ) + 1) >= 0

        isObject: (obj) ->
            typeof obj is 'object' and obj isnt null

        notEmptyString: (str)->
            typeof str is 'string' and str.length > 0

    return GenericUtil

module.exports = factory require