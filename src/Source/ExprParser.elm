module Source.ExprParser exposing (parse)

import Parser exposing (..)
import Set
import Source.Ast exposing (BinaryOp(..), Expr(..), LocatedExpr, Pos)


parse : String -> Result (List DeadEnd) LocatedExpr
parse input =
    run (succeed identity |. spaces |= locatedExprParser |. spaces |. end) input


locatedExprParser : Parser LocatedExpr
locatedExprParser =
    lazy (\_ -> located binaryExprParser)


located : Parser Expr -> Parser LocatedExpr
located p =
    succeed (\row col expr -> { pos = { line = row, col = col }, expr = expr })
        |= getRow
        |= getCol
        |= p


binaryExprParser : Parser Expr
binaryExprParser =
    comparisonParser


comparisonParser : Parser Expr
comparisonParser =
    additionParser |> andThen (comparisonHelp [])


comparisonHelp : List ( LocatedExpr, BinaryOp ) -> Expr -> Parser Expr
comparisonHelp revOps left =
    oneOf
        [ backtrackable
            (succeed (\op right -> ( op, right ))
                |. spaces
                |= comparisonOpParser
                |. spaces
                |= (located additionParser)
            )
            |> andThen (\( op, right ) -> comparisonHelp (( { pos = right.pos, expr = left }, op ) :: revOps) right.expr)
        , succeed (buildBinaryExpr revOps { pos = { line = 0, col = 0 }, expr = left })
        ]


comparisonOpParser : Parser BinaryOp
comparisonOpParser =
    oneOf
        [ symbol "==" |> map (\_ -> Eq)
        , symbol "!=" |> map (\_ -> NotEq)
        , symbol ">=" |> map (\_ -> GreaterOrEqual)
        , symbol "<=" |> map (\_ -> LessOrEqual)
        , symbol ">" |> map (\_ -> GreaterThan)
        , symbol "<" |> map (\_ -> LessThan)
        ]


additionParser : Parser Expr
additionParser =
    multiplicationParser |> andThen (additionHelp [])


additionHelp : List ( LocatedExpr, BinaryOp ) -> Expr -> Parser Expr
additionHelp revOps left =
    oneOf
        [ backtrackable
            (succeed (\op right -> ( op, right ))
                |. spaces
                |= additionOpParser
                |. spaces
                |= (located multiplicationParser)
            )
            |> andThen (\( op, right ) -> additionHelp (( { pos = right.pos, expr = left }, op ) :: revOps) right.expr)
        , succeed (buildBinaryExpr revOps { pos = { line = 0, col = 0 }, expr = left })
        ]


additionOpParser : Parser BinaryOp
additionOpParser =
    oneOf
        [ symbol "+" |> map (\_ -> Add)
        , symbol "-" |> map (\_ -> Sub)
        ]


multiplicationParser : Parser Expr
multiplicationParser =
    termParser |> andThen (multiplicationHelp [])


multiplicationHelp : List ( LocatedExpr, BinaryOp ) -> Expr -> Parser Expr
multiplicationHelp revOps left =
    oneOf
        [ backtrackable
            (succeed (\op right -> ( op, right ))
                |. spaces
                |= multiplicationOpParser
                |. spaces
                |= (located termParser)
            )
            |> andThen (\( op, right ) -> multiplicationHelp (( { pos = right.pos, expr = left }, op ) :: revOps) right.expr)
        , succeed (buildBinaryExpr revOps { pos = { line = 0, col = 0 }, expr = left })
        ]


multiplicationOpParser : Parser BinaryOp
multiplicationOpParser =
    oneOf
        [ symbol "*" |> map (\_ -> Mul)
        ]


buildBinaryExpr : List ( LocatedExpr, BinaryOp ) -> LocatedExpr -> Expr
buildBinaryExpr revOps right =
    case revOps of
        [] ->
            right.expr

        ( left, op ) :: rest ->
            buildBinaryExpr rest { pos = left.pos, expr = EBinary op left right }


termParser : Parser Expr
termParser =
    oneOf
        [ literalParser
        , nameOrCallParser
        , parensExprParser
        ]
        |> andThen fieldAccessHelp


fieldAccessHelp : Expr -> Parser Expr
fieldAccessHelp expr =
    oneOf
        [ backtrackable
            (succeed (\_ field -> EField { pos = { line = 0, col = 0 }, expr = expr } field)
                |. spaces
                |= symbol "."
                |. spaces
                |= nameParser
            )
            |> andThen fieldAccessHelp
        , succeed expr
        ]


literalParser : Parser Expr
literalParser =
    oneOf
        [ numberParser
        , stringParser
        , boolParser
        , symbol "~" |> map (\_ -> ECall "unit" [])
        ]


numberParser : Parser Expr
numberParser =
    number
        { int = Just (\i -> ENumber (String.fromInt i))
        , hex = Nothing
        , octal = Nothing
        , binary = Nothing
        , float = Nothing
        }


stringParser : Parser Expr
stringParser =
    oneOf
        [ backtrackable
            (succeed identity
                |. symbol "\""
                |= loop [] stringPartParser
                |. symbol "\""
                |> map
                    (\fragments ->
                        case fragments of
                            [ le ] ->
                                case le.expr of
                                    EText s ->
                                        EText s

                                    _ ->
                                        EInterpolated fragments

                            _ ->
                                EInterpolated fragments
                    )
            )
        , succeed EText
            |. symbol "'"
            |= (getChompedString <|
                    succeed ()
                        |. chompWhile (\c -> c /= '\'')
               )
            |. symbol "'"
        ]


stringPartParser : List LocatedExpr -> Parser (Step (List LocatedExpr) (List LocatedExpr))
stringPartParser acc =
    oneOf
        [ backtrackable
            (succeed (\expr -> Loop (acc ++ [ expr ]))
                |. symbol "{"
                |. spaces
                |= lazy (\_ -> locatedExprParser)
                |. spaces
                |. symbol "}"
            )
        , getChompedString (chompIf (\c -> c /= '"' && c /= '{') |. chompWhile (\c -> c /= '"' && c /= '{'))
            |> andThen
                (\s ->
                    succeed (Loop (acc ++ [ { pos = { line = 0, col = 0 }, expr = EText s } ]))
                )
        , succeed (Done acc)
        ]


boolParser : Parser Expr
boolParser =
    oneOf
        [ keyword "true" |> map (\_ -> EBool True)
        , keyword "false" |> map (\_ -> EBool False)
        ]


nameOrCallParser : Parser Expr
nameOrCallParser =
    nameParser
        |> andThen
            (\name ->
                oneOf
                    [ backtrackable
                        (succeed (ECall name)
                            |. spaces
                            |. symbol "("
                            |. spaces
                            |= sepBy (succeed () |. spaces |. symbol "," |. spaces) (lazy (\_ -> locatedExprParser))
                            |. spaces
                            |. symbol ")"
                        )
                    , succeed (EName name)
                    ]
            )


nameParser : Parser String
nameParser =
    let
        isStart c =
            Char.isLower c || c == '.' || c == '^' || c == '$'

        isInner c =
            Char.isAlphaNum c || c == '_' || c == '-' || c == '^'
    in
    getChompedString <|
        succeed ()
            |. chompIf isStart
            |. chompWhile isInner


parensExprParser : Parser Expr
parensExprParser =
    succeed identity
        |. symbol "("
        |. spaces
        |= (lazy (\_ -> binaryExprParser))
        |. spaces
        |. symbol ")"


sepBy : Parser () -> Parser a -> Parser (List a)
sepBy sep p =
    oneOf
        [ succeed (::)
            |= p
            |= (oneOf
                    [ backtrackable
                        (succeed identity
                            |. sep
                            |= lazy (\_ -> sepBy sep p)
                        )
                    , succeed []
                    ]
               )
        , succeed []
        ]
