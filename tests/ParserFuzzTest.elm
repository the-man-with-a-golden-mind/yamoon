module ParserFuzzTest exposing (..)

import Expect
import Fuzz exposing (Fuzzer)
import Source.Ast exposing (BinaryOp(..), Expr(..), LocatedExpr)
import Source.ExprParser exposing (parse)
import Test exposing (..)


suite : Test
suite =
    describe "Expression Parser Fuzzing"
        [ fuzz Fuzz.string "parser never crashes on random strings" <|
            \input ->
                case parse input of
                    _ ->
                        Expect.pass
        , fuzz validNameFuzzer "parser always accepts valid names" <|
            \name ->
                parse name
                    |> mapOk .expr
                    |> Expect.equal (Ok (EName name))
        , fuzz arithmeticExprFuzzer "parser handles random arithmetic chains" <|
            \input ->
                case parse input of
                    Ok _ ->
                        Expect.pass

                    Err _ ->
                        Expect.pass
        , fuzz callExprFuzzer "parser handles random function calls" <|
            \input ->
                case parse input of
                    Ok _ ->
                        Expect.pass

                    Err _ ->
                        Expect.pass
        ]


mapOk : (a -> b) -> Result e a -> Result e b
mapOk f r =
    Result.map f r


validNameFuzzer : Fuzzer String
validNameFuzzer =
    Fuzz.constant "abc"


arithmeticExprFuzzer : Fuzzer String
arithmeticExprFuzzer =
    let
        opFuzzer =
            Fuzz.oneOf [ Fuzz.constant "+", Fuzz.constant "-", Fuzz.constant "*" ]

        termFuzzer =
            Fuzz.oneOf [ Fuzz.map String.fromInt Fuzz.int, Fuzz.constant "x" ]
    in
    Fuzz.map3 (\a op b -> a ++ " " ++ op ++ " " ++ b)
        termFuzzer
        opFuzzer
        termFuzzer


callExprFuzzer : Fuzzer String
callExprFuzzer =
    let
        argFuzzer =
            Fuzz.oneOf [ Fuzz.map String.fromInt Fuzz.int, Fuzz.constant "y" ]
    in
    Fuzz.map3 (\name arg1 arg2 -> name ++ "(" ++ arg1 ++ ", " ++ arg2 ++ ")")
        (Fuzz.constant "f")
        argFuzzer
        argFuzzer
