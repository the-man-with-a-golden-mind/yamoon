module GenericsTest exposing (..)

import Compiler.Typecheck as Typecheck
import Dict
import Expect
import Source.Ast as Source
import Test exposing (..)


suite : Test
suite =
    describe "Generics and Polymorphism"
        [ test "Statically checks generic identity function" <|
            \_ ->
                let
                    prog =
                        emptyProgram
                            |> addFunction "id" { type_args = [ "T" ], input = [ ( "x", Source.TypeNamed "T" ) ], output = Source.TypeNamed "T", body = loc (Source.EName "x") }
                            |> addFunction "test" { type_args = [], input = [], output = Source.TypeNumber, body = loc (Source.ECall "id" [ loc (Source.ENumber "42") ]) }
                in
                Typecheck.check prog |> Expect.ok
        , test "Fails on generic type conflict (T matched to number and text)" <|
            \_ ->
                let
                    prog =
                        emptyProgram
                            |> addFunction "pair" { type_args = [ "T" ], input = [ ( "a", Source.TypeNamed "T" ), ( "b", Source.TypeNamed "T" ) ], output = Source.TypeNumber, body = loc (Source.ENumber "0") }
                            |> addFunction "test" { type_args = [], input = [], output = Source.TypeNumber, body = loc (Source.ECall "pair" [ loc (Source.ENumber "1"), loc (Source.EText "oops") ]) }
                in
                Typecheck.check prog |> Expect.equal (Err ["In functions.test.return at line 0, col 0: Generic type parameter 'T' bound to conflicting types: number and text"])
        , test "Propagates instantiated generic types through output" <|
            \_ ->
                let
                    prog =
                        emptyProgram
                            |> addFunction "id" { type_args = [ "T" ], input = [ ( "x", Source.TypeNamed "T" ) ], output = Source.TypeNamed "T", body = loc (Source.EName "x") }
                            -- Calling id("text") should return text, so assigning to number should fail
                            |> addFunction "test" { type_args = [], input = [], output = Source.TypeNumber, body = loc (Source.ECall "id" [ loc (Source.EText "oops") ]) }
                in
                Typecheck.check prog |> Expect.equal (Err ["In functions.test.return at line 0, col 0: Type mismatch: expected number, got text"])
        , test "Supports complex generic container types (list<T>)" <|
            \_ ->
                let
                    prog =
                        emptyProgram
                            |> addFunction "head" { type_args = [ "T" ], input = [ ( "l", Source.TypeList (Source.TypeNamed "T") ) ], output = Source.TypeNamed "T", body = loc (Source.ECall "first" [ loc (Source.EName "l") ]) }
                            |> addFunction "test" { type_args = [], input = [ ( "nums", Source.TypeList Source.TypeNumber ) ], output = Source.TypeNumber, body = loc (Source.ECall "head" [ loc (Source.EName "nums") ]) }
                in
                Typecheck.check prog |> Expect.ok
        , test "Correctly unifies multiple type parameters (K, V)" <|
            \_ ->
                let
                    prog =
                        emptyProgram
                            |> addFunction "lookup" { type_args = [ "K", "V" ], input = [ ( "m", Source.TypeMap (Source.TypeNamed "K") (Source.TypeNamed "V") ), ( "k", Source.TypeNamed "K" ) ], output = Source.TypeUnit (Source.TypeNamed "V"), body = loc (Source.ECall "get" [ loc (Source.EName "m"), loc (Source.EName "k") ]) }
                            |> addFunction "test" { type_args = [], input = [ ( "my_map", Source.TypeMap Source.TypeText Source.TypeNumber ) ], output = Source.TypeUnit Source.TypeNumber, body = loc (Source.ECall "lookup" [ loc (Source.EName "my_map"), loc (Source.EText "key") ]) }
                in
                Typecheck.check prog |> Expect.ok
        , test "Fails when generic parameter cannot be inferred (unbound)" <|
            \_ ->
                let
                    prog =
                        emptyProgram
                            |> addFunction "pure" { type_args = [ "T" ], input = [], output = Source.TypeList (Source.TypeNamed "T"), body = loc (Source.EList []) }
                            |> addFunction "test" { type_args = [], input = [], output = Source.TypeList Source.TypeNumber, body = loc (Source.ECall "pure" []) }
                in
                Typecheck.check prog |> Expect.equal (Err [ "In functions.test.return at line 0, col 0: Cannot infer type for generic parameter 'T'. It is not used in the input arguments." ])
        , test "Correctly parses and checks nested generic types" <|
            \_ ->
                let
                    nestedPair = Source.TypePair (Source.TypePair Source.TypeText Source.TypeNumber) Source.TypeBool
                    prog =
                        emptyProgram
                            |> addFunction "getInner" { type_args = [ "A", "B", "C" ], input = [ ( "p", Source.TypePair (Source.TypePair (Source.TypeNamed "A") (Source.TypeNamed "B")) (Source.TypeNamed "C") ) ], output = Source.TypeNamed "A", body = loc (Source.EField (loc (Source.EField (loc (Source.EName "p")) "p")) "p") }
                            |> addFunction "test" { type_args = [], input = [ ( "my_pair", nestedPair ) ], output = Source.TypeText, body = loc (Source.ECall "getInner" [ loc (Source.EName "my_pair") ]) }
                in
                Typecheck.check prog |> Expect.ok
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


loc : Source.Expr -> Source.LocatedExpr
loc e =
    { pos = { line = 0, col = 0 }, expr = e }
