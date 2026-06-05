module TypecheckTest exposing (..)

import Dict
import Expect
import Source.Ast as Source
import Compiler.Typecheck as Typecheck
import Test exposing (..)


suite : Test
suite =
    describe "Type Checker"
        [ test "fails on unknown name" <|
            \_ ->
                let
                    prog =
                        emptyProgram
                            |> addFunction "f" { input = [], output = Source.TypeNumber, body = loc (Source.EName "unknown") }
                in
                Typecheck.check prog
                    |> Expect.err
        , test "fails on type mismatch" <|
            \_ ->
                let
                    prog =
                        emptyProgram
                            |> addFunction "f" { input = [], output = Source.TypeNumber, body = loc (Source.EText "oops") }
                in
                Typecheck.check prog
                    |> Expect.err
        , test "fails on arity mismatch" <|
            \_ ->
                let
                    prog =
                        emptyProgram
                            |> addFunction "f" { input = [ ( "x", Source.TypeNumber ) ], output = Source.TypeNumber, body = loc (Source.EName "x") }
                            |> addFunction "g" { input = [], output = Source.TypeNumber, body = loc (Source.ECall "f" [ loc (Source.ENumber "1"), loc (Source.ENumber "2") ]) }
                in
                Typecheck.check prog
                    |> Expect.err
        ]


emptyProgram : Source.Program
emptyProgram =
    { moduleName = "test"
    , docs = []
    , options = { textRepresentation = Source.Cord, numberRepresentation = Source.UnsignedDecimal, target = Source.Library, prog_context_types = Dict.empty }
    , imports = []
    , types = Dict.empty
    , macros = Dict.empty
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


loc : Source.Expr -> Source.LocatedExpr
loc e =
    { pos = { line = 0, col = 0 }, expr = e }
