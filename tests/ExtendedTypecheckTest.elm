module ExtendedTypecheckTest exposing (..)

import Compiler.Typecheck as Typecheck
import Dict exposing (Dict)
import Expect
import Source.Ast as Source
import Test exposing (..)


suite : Test
suite =
    describe "Extended Typechecker Coverage"
        [ describe "Bindings (Let, Set, Loop)"
            [ test "Succeeds with simple let" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addFunction "f" { type_args = [], input = [], output = Source.TypeNumber, body = loc (Source.ELet "x" (loc (Source.ENumber "1")) (loc (Source.EName "x"))) }
                    in
                    Typecheck.check prog |> Expect.ok
            , test "Fails on unbound let variable" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addFunction "f" { type_args = [], input = [], output = Source.TypeNumber, body = loc (Source.ELet "x" (loc (Source.ENumber "1")) (loc (Source.EName "y"))) }
                    in
                    Typecheck.check prog |> Expect.equal (Err ["In functions.f.return at line 0, col 0: Unknown name: y"])
            , test "Succeeds with set update" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addFunction "f" { type_args = [], input = [ ( "x", Source.TypeNumber ) ], output = Source.TypeNumber, body = loc (Source.ESet "x" (loc (Source.ENumber "2")) (loc (Source.EName "x"))) }
                    in
                    Typecheck.check prog |> Expect.ok
            , test "Fails on set update with type mismatch" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addFunction "f" { type_args = [], input = [ ( "x", Source.TypeNumber ) ], output = Source.TypeNumber, body = loc (Source.ESet "x" (loc (Source.EText "bad")) (loc (Source.EName "x"))) }
                    in
                    Typecheck.check prog |> Expect.equal (Err ["In functions.f.return at line 0, col 0: Type mismatch: expected number, got text"])
            , test "Succeeds with simple loop" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addFunction "f" { type_args = [], input = [], output = Source.TypeNumber, body = loc (Source.ELoop Dict.empty (loc (Source.ENumber "42"))) }
                    in
                    Typecheck.check prog |> Expect.ok
            ]
        , describe "Assertions and Unless"
            [ test "Succeeds with assert" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addFunction "f" { type_args = [], input = [], output = Source.TypeNumber, body = loc (Source.EAssert (loc (Source.EBool True)) (loc (Source.ENumber "42"))) }
                    in
                    Typecheck.check prog |> Expect.ok
            , test "Fails on assert with non-bool condition" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addFunction "f" { type_args = [], input = [], output = Source.TypeNumber, body = loc (Source.EAssert (loc (Source.ENumber "1")) (loc (Source.ENumber "42"))) }
                    in
                    Typecheck.check prog |> Expect.equal (Err ["In functions.f.return at line 0, col 0: Type mismatch: expected bool, got number"])
            , test "Succeeds with unless" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addFunction "f" { type_args = [], input = [], output = Source.TypeNumber, body = loc (Source.EUnless (loc (Source.EBool False)) (loc (Source.ENumber "42"))) }
                    in
                    Typecheck.check prog |> Expect.ok
            ]
        , describe "Standard Library"
            [ test "Succeeds with math(number)" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addFunction "f" { type_args = [], input = [], output = Source.TypeNumber, body = loc (Source.ECall "math" [ loc (Source.ENumber "10") ]) }
                    in
                    Typecheck.check prog |> Expect.ok
            , test "Succeeds with snag(number, list<T>)" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addFunction "f" { type_args = [], input = [ ( "l", Source.TypeList Source.TypeNumber ) ], output = Source.TypeUnit Source.TypeNumber, body = loc (Source.ECall "snag" [ loc (Source.ENumber "0"), loc (Source.EName "l") ]) }
                    in
                    Typecheck.check prog |> Expect.ok
            ]
        , describe "Complex Expressions"
            [ test "Succeeds with variants and match" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addType "Mood" (Source.Union (Dict.fromList [ ( "Happy", Nothing ), ( "Sad", Nothing ) ]))
                                |> addFunction "f" { type_args = [], input = [ ( "m", Source.TypeNamed "Mood" ) ], output = Source.TypeNumber, body = loc (Source.EMatch (loc (Source.EName "m")) (Dict.fromList [ ( "Happy", loc (Source.ENumber "1") ), ( "Sad", loc (Source.ENumber "0") ) ]) Nothing) }
                    in
                    Typecheck.check prog |> Expect.ok
            , test "Fails on match with missing variant" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addType "Mood" (Source.Union (Dict.fromList [ ( "Happy", Nothing ), ( "Sad", Nothing ) ]))
                                |> addFunction "f" { type_args = [], input = [ ( "m", Source.TypeNamed "Mood" ) ], output = Source.TypeNumber, body = loc (Source.EMatch (loc (Source.EName "m")) (Dict.fromList [ ( "Happy", loc (Source.ENumber "1") ) ]) Nothing) }
                    in
                    Typecheck.check prog |> Expect.equal (Err ["In functions.f.return at line 0, col 0: Non-exhaustive patterns for variant match: Sad"])
            , test "Succeeds with simple list" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addFunction "f" { type_args = [], input = [], output = Source.TypeList Source.TypeNumber, body = loc (Source.EList [ loc (Source.ENumber "1"), loc (Source.ENumber "2") ]) }
                    in
                    Typecheck.check prog |> Expect.ok
            , test "Fails on list with inconsistent types" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addFunction "f" { type_args = [], input = [], output = Source.TypeList Source.TypeNumber, body = loc (Source.EList [ loc (Source.ENumber "1"), loc (Source.EText "bad") ]) }
                    in
                    Typecheck.check prog |> Expect.equal (Err ["In functions.f.return at line 0, col 0: Type mismatch: expected number, got text"])
            , test "Succeeds with interpolated string" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addFunction "f" { type_args = [], input = [ ( "name", Source.TypeText ) ], output = Source.TypeText, body = loc (Source.EInterpolated [ loc (Source.EText "Hello "), loc (Source.EName "name") ]) }
                    in
                    Typecheck.check prog |> Expect.ok
            , test "Succeeds with ERune" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addFunction "f" { type_args = [], input = [], output = Source.TypeRawHoon "any", body = loc (Source.ERune "++" [ loc (Source.ENumber "1"), loc (Source.ENumber "2") ]) }
                    in
                    Typecheck.check prog |> Expect.ok
            ]
        ]


emptyProgram : Source.Program
emptyProgram =
    { moduleName = "test"
    , docs = []
    , options = { textRepresentation = Source.Cord, numberRepresentation = Source.UnsignedDecimal, target = Source.Library, prog_context_types = Dict.empty }
    , imports = []
    , types = Dict.empty
    , macros = Dict.empty
    , native = Dict.empty
    , state = Nothing
    , onLoad = Nothing
    , pokes = Dict.empty
    , watches = Dict.empty
    , scries = Dict.empty
    , constants = Dict.empty
    , functions = Dict.empty
    , tests = Dict.empty
    , machine = Nothing
    }


addFunction : String -> { type_args : List String, input : List ( String, Source.TypeRef ), output : Source.TypeRef, body : Source.LocatedExpr } -> Source.Program -> Source.Program
addFunction name def prog =
    { prog | functions = Dict.insert name { type_args = def.type_args, input = def.input, output = def.output, body = def.body, jet = Nothing } prog.functions }


addType : String -> Source.TypeDef -> Source.Program -> Source.Program
addType name def prog =
    let
        newTypes =
            Dict.insert name def prog.types

        newOptions =
            prog.options
    in
    { prog | types = newTypes, options = { newOptions | prog_context_types = newTypes } }


loc : Source.Expr -> Source.LocatedExpr
loc e =
    { pos = { line = 0, col = 0 }, expr = e }
