module ExprParserTest exposing (..)

import Dict
import Expect
import Source.Ast exposing (BinaryOp(..), Expr(..), LocatedExpr)
import Source.ExprParser exposing (parse)
import Test exposing (..)


suite : Test
suite =
    describe "Expression Parser"
        [ test "parses simple numbers" <|
            \_ ->
                parse "42"
                    |> mapOk .expr
                    |> Expect.equal (Ok (ENumber "42"))
        , test "parses simple strings" <|
            \_ ->
                parse "\"hello\""
                    |> mapOk .expr
                    |> Expect.equal (Ok (EText "hello"))
        , test "parses simple booleans" <|
            \_ ->
                parse "true"
                    |> mapOk .expr
                    |> Expect.equal (Ok (EBool True))
        , test "parses names" <|
            \_ ->
                parse "variable_name"
                    |> mapOk .expr
                    |> Expect.equal (Ok (EName "variable_name"))
        , test "parses field access" <|
            \_ ->
                parse "user.name"
                    |> mapOk stripExprPositions
                    |> Expect.equal (Ok (EField (loc (EName "user")) "name"))
        , test "parses nested field access" <|
            \_ ->
                parse "a.b.c"
                    |> mapOk stripExprPositions
                    |> Expect.equal (Ok (EField (loc (EField (loc (EName "a")) "b")) "c"))
        , test "parses function call" <|
            \_ ->
                parse "add(1, 2)"
                    |> mapOk stripExprPositions
                    |> Expect.equal (Ok (ECall "add" [ loc (ENumber "1"), loc (ENumber "2") ]))
        , test "parses arithmetic precedence (1 + 2 * 3)" <|
            \_ ->
                parse "1 + 2 * 3"
                    |> mapOk stripExprPositions
                    |> Expect.equal (Ok (EBinary Add (loc (ENumber "1")) (loc (EBinary Mul (loc (ENumber "2")) (loc (ENumber "3"))))))
        , test "parses arithmetic precedence (1 * 2 + 3)" <|
            \_ ->
                parse "1 * 2 + 3"
                    |> mapOk stripExprPositions
                    |> Expect.equal (Ok (EBinary Add (loc (EBinary Mul (loc (ENumber "1")) (loc (ENumber "2")))) (loc (ENumber "3"))))
        , test "parses parentheses" <|
            \_ ->
                parse "(1 + 2) * 3"
                    |> mapOk stripExprPositions
                    |> Expect.equal (Ok (EBinary Mul (loc (EBinary Add (loc (ENumber "1")) (loc (ENumber "2")))) (loc (ENumber "3"))))
        , test "parses comparison precedence" <|
            \_ ->
                parse "x + 1 == y"
                    |> mapOk stripExprPositions
                    |> Expect.equal (Ok (EBinary Eq (loc (EBinary Add (loc (EName "x")) (loc (ENumber "1")))) (loc (EName "y"))))
        , test "parses complex expressions" <|
            \_ ->
                parse "square(x) + 1 > 100"
                    |> mapOk stripExprPositions
                    |> Expect.equal (Ok (EBinary GreaterThan (loc (EBinary Add (loc (ECall "square" [ loc (EName "x") ])) (loc (ENumber "1")))) (loc (ENumber "100"))))
        , test "parses interpolated strings" <|
            \_ ->
                parse "\"Hello, {name}!\""
                    |> mapOk stripExprPositions
                    |> Expect.equal (Ok (EInterpolated [ loc (EText "Hello, "), loc (EName "name"), loc (EText "!") ]))
        ]


mapOk : (a -> b) -> Result e a -> Result e b
mapOk f r =
    Result.map f r


loc : Expr -> LocatedExpr
loc e =
    { pos = { line = 0, col = 0 }, expr = e }


stripExprPositions : LocatedExpr -> Expr
stripExprPositions le =
    case le.expr of
        ENumber s ->
            ENumber s

        EText s ->
            EText s

        EInterpolated fs ->
            EInterpolated (List.map stripLocated fs)

        EBool b ->
            EBool b

        EName s ->
            EName s

        EField e f ->
            EField (stripLocated e) f

        EList l ->
            EList (List.map stripLocated l)

        ECall n a ->
            ECall n (List.map stripLocated a)

        ERecord n f ->
            ERecord n (Dict.map (\_ e -> stripLocated e) f)

        EVariant n v f ->
            EVariant n v (Dict.map (\_ e -> stripLocated e) f)

        EDict f ->
            EDict (Dict.map (\_ e -> stripLocated e) f)

        ERune r a ->
            ERune r (List.map stripLocated a)

        ELoop a b ->
            ELoop (Dict.map (\_ e -> stripLocated e) a) (stripLocated b)

        ELet n v b ->
            ELet n (stripLocated v) (stripLocated b)

        ESet n v b ->
            ESet n (stripLocated v) (stripLocated b)

        EAssert c b ->
            EAssert (stripLocated c) (stripLocated b)

        EUnless c b ->
            EUnless (stripLocated c) (stripLocated b)

        ECast t e ->
            ECast t (stripLocated e)

        EMatch t c d ->
            EMatch (stripLocated t) (Dict.map (\_ e -> stripLocated e) c) (Maybe.map stripLocated d)

        EBinary o l r ->
            EBinary o (stripLocated l) (stripLocated r)

        EIf c t e ->
            EIf (stripLocated c) (stripLocated t) (stripLocated e)

        EIfNot c t e ->
            EIfNot (stripLocated c) (stripLocated t) (stripLocated e)

        ERawHoon s ->
            ERawHoon s


stripLocated : LocatedExpr -> LocatedExpr
stripLocated le =
    { pos = { line = 0, col = 0 }, expr = stripExprPositions le }
