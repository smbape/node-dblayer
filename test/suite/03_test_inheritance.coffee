logger = log4js.getLogger __filename.replace /^(?:.+[\\\/])?([^.\\\/]+)(?:.[^.]+)?$/, '$1'

async = require 'async'
_ = require 'lodash'
{PersistenceManager} = require '../../'

describe 'inheritance', ->

    it 'should inherit', ->
        mapping = {}

        # Parent is undefined
        assertPartialThrows mapping, 'ClassB',
            id:
                className: 'ClassA'
            properties:
                propB1: 'colPropB1'
                propB2: 'colPropB2'
        , 'UNDEF_CLASS'

        mapping['ClassA'] =
            id:
                name: 'idA'
                column: 'colIdA'

        # omitted id column becomes parent id column
        assertPartial mapping, 'ClassB',
            id:
                className: 'ClassA'
        ,
            className: 'ClassB'
            id:
                name: 'idA'
                className: 'ClassA'
                column: 'colIdA'
                pk: 'ClassB'
                type_args: [undefined, true]

        # Check consitency
        assertPartial mapping, 'ClassB',
            id:
                className: 'ClassA'
                column: 'colIdB'
        ,
            id:
                name: 'idA'
                className: 'ClassA'
                column: 'colIdB'
                pk: 'ClassB'
                type_args: [undefined, true]

        # Deep child, inherits it ancestor first setted properties
        mapping['ClassB'] =
            id:
                className: 'ClassA'
        assertPartial mapping, 'ClassC',
            id:
                className: 'ClassB'
        ,
            id:
                name: 'idA'
                className: 'ClassB'
                column: 'colIdA'
                pk: 'ClassC'
                type_args: [undefined, true]

        # Deep child, inherits it ancestor first setted properties
        mapping['ClassB'] =
            id:
                column: 'colIdB'
                className: 'ClassA'
        assertPartial mapping, 'ClassC',
            id:
                className: 'ClassB'
        ,
            id:
                name: 'idA'
                className: 'ClassB'
                column: 'colIdB'
                pk: 'ClassC'
                type_args: [undefined, true]
        delete mapping['ClassC']

        # Parent is considered as a mixin. Cannot appear as a mixin
        assertPartialThrows mapping, 'ClassB',
            id:
                className: 'ClassA'
            mixins: 'ClassA'
        , 'DUP_MIXIN'

        # mixin as string
        assertPartial mapping, 'ClassB',
            id:
                name: 'ClassB'
            mixins: 'ClassA'
        ,
            mixins: [
                className: 'ClassA'
                column: 'colIdA'
                fk: "ClassB_colIdA_EXT_ClassA_colIdA"
                type_args: [undefined, true]
            ]

        # mixin as Array
        assertPartial mapping, 'ClassB',
            id:
                name: 'ClassB'
            mixins: ['ClassA']
        ,
            mixins: [
                className: 'ClassA'
                column: 'colIdA'
                fk: "ClassB_colIdA_EXT_ClassA_colIdA"
                type_args: [undefined, true]
            ]

        # mixin as Array of object
        assertPartial mapping, 'ClassB',
            id:
                name: 'ClassB'
            mixins: [
                className: 'ClassA'
            ]
        ,
            mixins: [
                className: 'ClassA'
                column: 'colIdA'
                fk: "ClassB_colIdA_EXT_ClassA_colIdA"
                type_args: [undefined, true]
            ]

        # fk can only be a string
        assertPartialThrows mapping, 'ClassB',
            id:
                name: 'ClassB'
            mixins: [
                className: 'ClassA'
                fk: true
            ]
        , 'INDEX'

        #  should keep mixin fk
        assertPartial mapping, 'ClassB',
            id:
                name: 'ClassB'
            mixins: [
                className: 'ClassA'
                fk: 'custom'
            ]
        ,
            mixins: [
                className: 'ClassA'
                column: 'colIdA'
                fk: "custom"
                type_args: [undefined, true]
            ]

        # Duplicate table
        assertPartialThrows mapping, 'ClassC',
            table: 'ClassA'
            id:
                name: 'idC'
            mixins: ['ClassB']
            properties:
                propC1: 'colPropC1'
        , 'DUP_TABLE'

        # mixin column takes class id column
        mapping['ClassB'] =
            id:
                className: 'ClassA'
        assertPartial mapping, 'ClassC',
            id:
                name: 'idC'
            mixins: ['ClassB']
        ,
            mixins: [
                className: 'ClassB'
                column: 'colIdA'
                fk: "ClassC_colIdA_EXT_ClassB_colIdA"
                type_args: [undefined, true]
            ]

        # Check consistency
        assertPartial mapping, 'ClassC',
            id:
                name: 'idC'
            mixins: [
                className: 'ClassB'
                column: 'colMixB'
            ]
        ,
            mixins: [
                className: 'ClassB'
                column: 'colMixB'
                fk: "ClassC_colMixB_EXT_ClassB_colIdA"
                type_args: [undefined, true]
            ]

        # prop className, if no column, use id column
        assertPartial mapping, 'ClassC',
            id:
                name: 'idC'
            properties:
                propB1:
                    className: 'ClassB'
        ,
            properties:
                propB1:
                    column: 'colIdA'
                    className: 'ClassB'
                    fk: 'ClassC_colIdA_HAS_ClassB_colIdA'
                    type_args: [undefined, true]

        # should keep prop class fk
        assertPartial mapping, 'ClassC',
            id:
                name: 'idC'
            properties:
                propB1:
                    className: 'ClassB'
                    fk: 'custom'
                propB2:
                    column: 'propB2'
                    className: 'ClassA'
        ,
            properties:
                propB1:
                    column: 'colIdA'
                    className: 'ClassB'
                    fk: 'custom'
                    type_args: [undefined, true]
                propB2:
                    column: 'propB2'
                    className: 'ClassA'
                    fk: 'ClassC_propB2_HAS_ClassA_colIdA'
                    type_args: [undefined, true]

        # should allow only distinct fk names
        assertPartialThrows mapping, 'ClassC',
            id:
                name: 'idC'
            properties:
                propB1:
                    className: 'ClassB'
                    fk: 'custom'
                propB2:
                    column: 'propB2'
                    className: 'ClassA'
                    fk: 'custom'
        , 'INDEX'

        assertPartialThrows mapping, 'ClassC',
            id:
                name: 'idC'
            mixins: [
                className: 'ClassB'
                column: 'colMixB'
                fk: 'custom'
            ]
            properties:
                propB1:
                    className: 'ClassB'
                    fk: 'custom'
        , 'INDEX'

        mapping['ClassB'] =
            id: 'idB'
            mixins: [
                className: 'ClassA'
                column: 'colMixA'
                fk: 'custom'
            ]
        assertPartialThrows mapping, 'ClassC',
            id:
                name: 'idC'
            mixins: [
                className: 'ClassB'
                column: 'colMixB'
            ]
            properties:
                propB1:
                    className: 'ClassB'
                    fk: 'custom'
        , 'INDEX'

        # fk prop class can only be a string
        assertPartialThrows mapping, 'ClassC',
            id:
                name: 'idC'
            properties:
                propB1:
                    className: 'ClassB'
                    fk: true
        , 'INDEX'

        # if prop column name is given, it is preserved
        delete mapping['ClassC']
        assertPartial mapping, 'ClassB',
            id:
                name: 'idB'
            properties:
                propB1:
                    column: 'colPropB1'
                    className: 'ClassA'
        ,
            properties:
                propB1:
                    column: 'colPropB1'
                    className: 'ClassA'
                    fk: 'ClassB_colPropB1_HAS_ClassA_colIdA'
                    type_args: [undefined, true]

        # test that, if not only normalize class are given in the mixins, 
        # throws an error, telling what class depends on which one
        mapping['ClassB'] = 
            id:
                className: 'ClassA'
        assertPartialThrows mapping, 'ClassC',
            id:
                className: 'ClassA'
            mixins: ['ClassB']
        , 'RELATED_MIXIN'

        assertPartialThrows mapping, 'ClassC',
            table: 'TableC'
            id:
                name: 'idC'
            mixins: [{
                className: 'ClassA'
                column: 'colIdA'
            },{ 
                className: 'ClassB'
                column: 'colIdB'
            }]
        , 'RELATED_MIXIN'

    it 'should throw circular ref', ->
        mapping = {}

        # A <- B <- C <- C
        mapping['ClassA'] =
            table: 'TableA'
            id:
                name: 'id'
                column: 'colIdA'

        mapping['ClassB'] =
            table: 'TableB'
            id:
                className: 'ClassA'

        assertPartialThrows mapping, 'ClassC',
            table: 'TableC'
            id:
                name: 'ClassC'
            mixins: ['ClassC']
        , 'CIRCULAR_REF'

        # A <- B + D <- C <- D
        mapping['ClassC'] =
            table: 'TableC'
            id:
                className: 'ClassD'
            mixins: ['ClassB']

        assertPartialThrows mapping, 'ClassD',
            table: 'TableD'
            id:
                className: 'ClassC'
        , 'CIRCULAR_REF'

        # D <- C <- D
        mapping['ClassC'] =
            table: 'TableC'
            id:
                name: 'ClassC'
            mixins: 'ClassD'

        assertPartialThrows mapping, 'ClassD',
            table: 'TableD'
            id:
                name: 'ClassD'
            mixins: 'ClassC'
        , 'CIRCULAR_REF'

        # A <- B <- C <- A
        mapping['ClassC'] =
            table: 'TableC'
            id:
                name: 'ClassC'
            mixins: 'ClassB'

        assertPartialThrows mapping, 'ClassA',
            table: 'TableA'
            id:
                name: 'ClassA'
            mixins: 'ClassC'
        , 'CIRCULAR_REF'

        return

    return
