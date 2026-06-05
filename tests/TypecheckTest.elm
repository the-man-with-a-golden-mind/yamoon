module TypecheckTest exposing (..)

import Compiler.Typecheck as Typecheck
import Dict exposing (Dict)
import Expect
import Source.Ast as Source
import Test exposing (..)


suite : Test
suite =
    describe "Typechecker"
        [ describe "Basic Validation"
            [ test "Fails on unknown variable name" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addFunction "f" { type_args = [], input = [], output = Source.TypeNumber, body = loc (Source.EName "unknown") }
                    in
                    Typecheck.check prog |> Expect.equal (Err ["In functions.f.return at line 0, col 0: Unknown name: unknown"])
            , test "Succeeds on correct return type" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addFunction "f" { type_args = [], input = [], output = Source.TypeNumber, body = loc (Source.ENumber "42") }
                    in
                    Typecheck.check prog |> Expect.ok
            , test "Fails on type mismatch in function return" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addFunction "f" { type_args = [], input = [], output = Source.TypeNumber, body = loc (Source.EText "oops") }
                    in
                    Typecheck.check prog |> Expect.equal (Err ["In functions.f.return at line 0, col 0: Type mismatch: expected number, got text"])
            , test "Succeeds with function calls" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addFunction "square" { type_args = [], input = [ ( "x", Source.TypeNumber ) ], output = Source.TypeNumber, body = loc (Source.ENumber "0") }
                                |> addFunction "main" { type_args = [], input = [], output = Source.TypeNumber, body = loc (Source.ECall "square" [ loc (Source.ENumber "4") ]) }
                    in
                    Typecheck.check prog |> Expect.ok
            ]
        , describe "Record Validation"
            [ test "Checks record field access" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addType "User" (Source.Record (Dict.singleton "id" Source.TypeNumber))
                                |> addFunction "f" { type_args = [], input = [ ( "u", Source.TypeNamed "User" ) ], output = Source.TypeNumber, body = loc (Source.EField (loc (Source.EName "u")) "id") }
                    in
                    Typecheck.check prog |> Expect.ok
            , test "Fails on missing record field" <|
                \_ ->
                    let
                        prog =
                            emptyProgram
                                |> addType "User" (Source.Record (Dict.singleton "id" Source.TypeNumber))
                                |> addFunction "f" { type_args = [], input = [ ( "u", Source.TypeNamed "User" ) ], output = Source.TypeNumber, body = loc (Source.EField (loc (Source.EName "u")) "oops") }
                    in
                    Typecheck.check prog |> Expect.equal (Err ["In functions.f.return at line 0, col 0: Type User does not have field: oops"])
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
    }


addFunction : String -> Source.FunctionDef -> Source.Program -> Source.Program
addFunction name def prog =
    { prog | functions = Dict.insert name def prog.functions }


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
