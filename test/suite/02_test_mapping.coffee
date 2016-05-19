logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager} = require '../../'

describe 'mapping', ->

    it 'should map', ->
        mapping = {}

        # Check consistency
        assertPartial mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'
        ,
            className: 'ClassA'
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'

        # String id is for name and column
        assertPartial mapping, 'ClassA',
            table: 'TableA'
            id: 'idA'
        ,
            table: 'TableA'
            id:
                name: 'idA'
                column: 'idA'

        # Empty id column is replaced by id name
        assertPartial mapping, 'ClassA',
            table: 'TableA'
            id: name: 'idA'
        ,
            table: 'TableA'
            id:
                name: 'idA'
                column: 'idA'

        # default table name is className
        assertPartial mapping, 'ClassA',
            id:
                name: 'id'
                column: 'colIdA'
        ,
            table: 'ClassA'
            id:
                name: 'id'
                column: 'colIdA'

        # Check consistency
        assertPartial mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'
            properties:
                propA1:
                    column: 'colPropA1'
        ,
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'
            properties:
                propA1:
                    column: 'colPropA1'

        # Property as string => column name
        assertPartial mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'
            properties:
                propA1: 'colPropA1'
        ,
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'
            properties:
                propA1:
                    column: 'colPropA1'

        # constraint
        assertPartial mapping, 'ClassA',
            table: 'TableA'
            id: 'idA'
            properties:
                propA1: 'colPropA1'
                propA2: 'colPropA2'
            constraints: [
                {type: 'unique', properties: 'propA1'}
            ]
        ,
            table: 'TableA'
            id:
                name: 'idA'
                column: 'idA'

        # constraint
        assertPartial mapping, 'ClassA',
            table: 'TableA'
            id: 'idA'
            properties:
                propA1: 'colPropA1'
                propA2: 'colPropA2'
            constraints: [
                {type: 'unique', properties: ['propA1']}
                {type: 'unique', properties: ['propA2']}
            ]
        ,
            table: 'TableA'
            id:
                name: 'idA'
                column: 'idA'

        # constraint
        assertPartial mapping, 'ClassA',
            table: 'TableA'
            id: 'idA'
            properties:
                propA1: 'colPropA1'
                propA2: 'colPropA2'
            constraints: [
                {type: 'unique', properties: ['propA1', 'propA2']}
            ]
        ,
            table: 'TableA'
            id:
                name: 'idA'
                column: 'idA'

        return

    it 'should throws', ->
        mapping = {}

        # Column cannot be setted as undefined
        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'idA'
                clumn: undefined
        , 'ID_COLUMN'

        # Column cannot be setted as null
        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'idA'
                column: null
        , 'ID_COLUMN'

        # Column cannot be setted as not string
        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'idA'
                column: {}
        , 'ID_COLUMN'

        # Column cannot be setted as empty string
        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'idA'
                column: ''
        , 'ID_COLUMN'

        # Column key is mandatory for setted properties
        assertPartialThrows mapping, 'ClassA',
            id:
                name: 'id'
            properties:
                propA1:
                    toto: 'colPropA'
                propA2:
                    column: 'colPropA'
        , 'COLUMN'

        # Property cannot be null
        assertPartialThrows mapping, 'ClassA',
            id:
                name: 'id'
            properties:
                propA1: null
                propA2:
                    column: 'colPropA'
        , 'PROP'

        # Property cannot be undefined
        assertPartialThrows mapping, 'ClassA',
            id:
                name: 'id'
            properties:
                propA1: undefined
                propA2:
                    column: 'colPropA'
        , 'PROP'

        # Duplicate columns in id and properties
        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'
            properties:
                propA1:
                    column: 'colIdA'
        , 'DUP_COLUMN'

        # Duplicate columns, in properties
        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'
            properties:
                propA1:
                    column: 'colPropA'
                propA2:
                    column: 'colPropA'
        , 'DUP_COLUMN'

        # Undefined class in properties
        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'
            properties: 
                propA2:
                    className: 'colPropA2'
                propA3:
                    className: 'colPropA3'
                propA1: 'colPropA1'
        , 'UNDEF_CLASS'

        mapping['ClassA'] =
            id: 'idA'

        # Mixin column cannot be undefined
        assertPartialThrows mapping, 'ClassB',
            id: 'idB'
            mixins: [
                className: 'ClassA'
                column: undefined
            ]
        , 'MIXIN_COLUMN'

        # Mixin column cannot be null
        assertPartialThrows mapping, 'ClassB',
            id: 'idB'
            mixins: [
                className: 'ClassA'
                column: null
            ]
        , 'MIXIN_COLUMN'

        # Mixin column cannot be not a string
        assertPartialThrows mapping, 'ClassB',
            id: 'idB'
            mixins: [
                className: 'ClassA'
                column: {}
            ]
        , 'MIXIN_COLUMN'

        # Mixin column cannot be an empty string
        assertPartialThrows mapping, 'ClassB',
            id: 'idB'
            mixins: [
                className: 'ClassA'
                column: ''
            ]
        , 'MIXIN_COLUMN'

        # Table cannot be undefined
        assertPartialThrows mapping, 'ClassB',
            table: undefined
            id:
                name: 'id'
        , 'TABLE'

        # Table cannot be null
        assertPartialThrows mapping, 'ClassB',
            table: null
            id:
                name: 'id'
        , 'TABLE'

        # Table cannot be not a string
        assertPartialThrows mapping, 'ClassB',
            table: {}
            id:
                name: 'id'
        , 'TABLE'

        # Table cannot be an empty string
        assertPartialThrows mapping, 'ClassB',
            table: ''
            id:
                name: 'id'
        , 'TABLE'

        # Id Cannot be undefined
        assertPartialThrows mapping, 'ClassB',
            id: undefined
        , 'ID'

        # Id Cannot be null
        assertPartialThrows mapping, 'ClassB',
            id: null
        , 'ID'

        # Id Cannot be an empty string
        assertPartialThrows mapping, 'ClassB',
            id: ''
        , 'ID'

        # Mixins cannot be undefined
        assertPartialThrows mapping, 'ClassB',
            id:
                name: 'id'
            mixins: undefined
        , 'MIXINS'

        # Mixins cannot be null
        assertPartialThrows mapping, 'ClassB',
            id:
                name: 'id'
            mixins: null
        , 'MIXINS'

        # Mixins cannot be not a string and not an Array
        assertPartialThrows mapping, 'ClassB',
            id:
                name: 'id'
            mixins: {}
        , 'MIXINS'

        # Mixin must have a className prop if as Array
        assertPartialThrows mapping, 'ClassB',
            id:
                name: 'id'
            mixins: [
                id: 'toto'
            ]
        , 'MIXIN'

        # Mixin must have a className prop if as Array
        assertPartialThrows mapping, 'ClassB',
            id:
                name: 'id'
            mixins: [
                undefined
            ]
        , 'MIXIN'

        # name and className cannot be both setted
        assertPartialThrows mapping, 'ClassB',
            id:
                name: 'id'
                className: 'toto'
        , 'INCOMP_ID'

        # constraint
        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            properties:
                propA1: 'colPropA1'
                propA2: 'colPropA2'
            constraints: null
        , 'CONSTRAINT'

        # constraint
        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            properties:
                propA1: 'colPropA1'
                propA2: 'colPropA2'
            constraints: [
                {type: 'unique', properties: ['propA1']}
                {type: 'unknown', properties: ['propA2']}
            ]
        , 'CONSTRAINT'

        # constraint
        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            properties:
                propA1: 'colPropA1'
                propA2: 'colPropA2'
            constraints: [
                {type: 'unique', properties: undefined}
            ]
        , 'CONSTRAINT'

        # constraint
        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            properties:
                propA1: 'colPropA1'
                propA2: 'colPropA2'
            constraints: [
                {type: 'unique', properties: ['propA1']}
                {type: 'unknown', properties: ['propB2']}
            ]
        , 'CONSTRAINT'

        # constraint
        assertPartialThrows mapping, 'ClassA',
            ctor: 'toto'
            table: 'TableA'
            properties:
                propA1: 'colPropA1'
                propA2: 'colPropA2'
        , 'CTOR'
        return

    return
