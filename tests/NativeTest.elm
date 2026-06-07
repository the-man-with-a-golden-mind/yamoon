module NativeTest exposing (..)

import Compiler.Typecheck as Typecheck
import Dict
import Expect
import Source.Ast as Source
import Source.StandardLibrary as StdLib
import Test exposing (..)


suite : Test
suite =
    describe "Native Library Integration"
        [ test "Statically checks standard 'ja' library" <|
            \_ ->
                let
                    funcDef = { type_args = [], input = [], output = Source.TypeRawHoon "any", body = loc (Source.ECall "ja" [ loc (Source.EDict Dict.empty) ]), jet = Nothing }
                    prog =
                        { emptyProgram
                            | functions = Dict.singleton "f" funcDef
                        }

                in
                Typecheck.check prog |> Expect.ok
        , test "Fails on arity mismatch for standard 'ja' library" <|
            \_ ->
                let
                    prog =
                        { emptyProgram
                            | functions = Dict.singleton "f" { type_args = [], input = [], output = Source.TypeRawHoon "any", body = loc (Source.ECall "ja" [ loc (Source.ENumber "1"), loc (Source.ENumber "2") ]), jet = Nothing }
                        }
                in
                Typecheck.check prog |> Expect.equal (Err ["In functions.f.return at line 0, col 0: Arity mismatch for ja: expected 1, got 2"])
        , test "Statically checks user-defined native library" <|
            \_ ->
                let
                    prog =
                        { emptyProgram
                            | native = Dict.singleton "my-lib" { type_args = [], input = [ ( "x", Source.TypeNumber ) ], output = Source.TypeText }
                            , functions = Dict.singleton "f" { type_args = [], input = [], output = Source.TypeText, body = loc (Source.ECall "my-lib" [ loc (Source.ENumber "42") ]), jet = Nothing }
                        }
                in
                Typecheck.check prog |> Expect.ok
        , test "Fails on type mismatch for user-defined native library" <|
            \_ ->
                let
                    prog =
                        { emptyProgram
                            | native = Dict.singleton "my-lib" { type_args = [], input = [ ( "x", Source.TypeNumber ) ], output = Source.TypeText }
                            , functions = Dict.singleton "f" { type_args = [], input = [], output = Source.TypeText, body = loc (Source.ECall "my-lib" [ loc (Source.EText "oops") ]), jet = Nothing }
                        }
                in
                Typecheck.check prog |> Expect.equal (Err ["In functions.f.return at line 0, col 0: Type mismatch: expected number, got text"])
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


loc : Source.Expr -> Source.LocatedExpr
loc e =
    { pos = { line = 0, col = 0 }, expr = e }
