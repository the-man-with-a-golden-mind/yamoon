module MacroTest exposing (..)

import Dict
import Expect
import Set
import Source.Ast as Source
import Compiler.Macro as Macro
import Test exposing (..)


suite : Test
suite =
    describe "Macro Expansion"
        [ test "expands simple macro" <|
            \_ ->
                let
                    macros =
                        Dict.fromList
                            [ ( "square", { args = [ "x" ], expand = loc (Source.EBinary Source.Mul (loc (Source.EName "x")) (loc (Source.EName "x"))) } ) ]

                    inputExpr =
                        Source.ECall "square" [ loc (Source.ENumber "5") ]

                    expectedExpr =
                        Source.EBinary Source.Mul (loc (Source.ENumber "5")) (loc (Source.ENumber "5"))
                in
                Macro.expandExpr macros Set.empty Dict.empty inputExpr
                    |> Expect.equal expectedExpr
        , test "expands nested macros" <|
            \_ ->
                let
                    macros =
                        Dict.fromList
                            [ ( "square", { args = [ "x" ], expand = loc (Source.EBinary Source.Mul (loc (Source.EName "x")) (loc (Source.EName "x"))) } )
                            , ( "quad", { args = [ "y" ], expand = loc (Source.ECall "square" [ loc (Source.ECall "square" [ loc (Source.EName "y") ]) ]) } )
                            ]

                    inputExpr =
                        Source.ECall "quad" [ loc (Source.ENumber "2") ]

                    expectedExpr =
                        Source.EBinary Source.Mul
                            (loc (Source.EBinary Source.Mul (loc (Source.ENumber "2")) (loc (Source.ENumber "2"))))
                            (loc (Source.EBinary Source.Mul (loc (Source.ENumber "2")) (loc (Source.ENumber "2"))))
                in
                Macro.expandExpr macros Set.empty Dict.empty inputExpr
                    |> Expect.equal expectedExpr
        , test "expands macro with multiple arguments" <|
            \_ ->
                let
                    macros =
                        Dict.fromList
                            [ ( "add3", { args = [ "a", "b", "c" ], expand = loc (Source.EBinary Source.Add (loc (Source.EName "a")) (loc (Source.EBinary Source.Add (loc (Source.EName "b")) (loc (Source.EName "c"))))) } ) ]

                    inputExpr =
                        Source.ECall "add3" [ loc (Source.ENumber "1"), loc (Source.ENumber "2"), loc (Source.ENumber "3") ]

                    expectedExpr =
                        Source.EBinary Source.Add (loc (Source.ENumber "1")) (loc (Source.EBinary Source.Add (loc (Source.ENumber "2")) (loc (Source.ENumber "3"))))
                in
                Macro.expandExpr macros Set.empty Dict.empty inputExpr
                    |> Expect.equal expectedExpr
        , test "detects circular macros" <|
            \_ ->
                let
                    macros =
                        Dict.fromList
                            [ ( "f", { args = [ "x" ], expand = loc (Source.ECall "f" [ loc (Source.EName "x") ]) } ) ]

                    inputExpr =
                        Source.ECall "f" [ loc (Source.ENumber "1") ]

                    expectedExpr =
                        Source.ERawHoon ":: circular macro detected: f"
                in
                Macro.expandExpr macros Set.empty Dict.empty inputExpr
                    |> Expect.equal expectedExpr
        ]


loc : Source.Expr -> Source.LocatedExpr
loc e =
    { pos = { line = 0, col = 0 }, expr = e }
