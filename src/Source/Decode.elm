module Source.Decode exposing (decode)

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline exposing (optional, required)
import Parser exposing ((|.), (|=))
import Source.Ast as Ast exposing (..)
import Source.ExprParser as ExprParser


decode : String -> Result String Ast.Program
decode json =
    case Decode.decodeString programDecoder json of
        Ok program ->
            Ok program

        Err err ->
            Err (cleanDecodeError err)

cleanDecodeError : Decode.Error -> String
cleanDecodeError err =
    case findSyntaxError err of
        Just syntaxErr ->
            syntaxErr

        Nothing ->
            formatStructureError "root" err

formatStructureError : String -> Decode.Error -> String
formatStructureError path err =
    case err of
        Decode.Field f e ->
            formatStructureError (if path == "root" then f else path ++ "." ++ f) e

        Decode.Index i e ->
            formatStructureError (path ++ "[" ++ String.fromInt i ++ "]") e

        Decode.OneOf _ ->
            "Invalid YAML structure at '" ++ path ++ "': Does not match any expected format."

        Decode.Failure msg _ ->
            "Invalid YAML structure at '" ++ path ++ "': " ++ msg

findSyntaxError : Decode.Error -> Maybe String
findSyntaxError err =
    case err of
        Decode.Field _ e ->
            findSyntaxError e
            
        Decode.Index _ e ->
            findSyntaxError e
            
        Decode.OneOf errors ->
            errors
                |> List.filterMap findSyntaxError
                |> List.head
                
        Decode.Failure msg _ ->
            if String.startsWith "Invalid expression:" msg || String.startsWith "Syntax error" msg || String.startsWith "Invalid type reference:" msg then
                Just msg
            else
                Nothing

programDecoder : Decoder Ast.Program
programDecoder =
    Decode.succeed
        (\module_ docs options imports types macros native state onLoad pokes watches scries constants functions tests machine ->
            let
                newOptions =
                    { options | prog_context_types = types }
            in
            Ast.Program module_ docs newOptions imports types macros native state onLoad pokes watches scries constants functions tests machine
        )
        |> required "module" Decode.string
        |> optional "docs" (Decode.list Decode.string) []
        |> optional "options" optionsDecoder defaultOptions
        |> optional "imports" (Decode.list Decode.string) []
        |> optional "types" (Decode.dict typeDefDecoder) Dict.empty
        |> optional "macros" (Decode.dict macroDefDecoder) Dict.empty
        |> optional "native" (Decode.dict nativeDefDecoder) Dict.empty
        |> optional "state" (Decode.maybe stateDefDecoder) Nothing
        |> optional "on_load" (Decode.maybe locatedExprDecoder) Nothing
        |> optional "pokes" (Decode.dict pokeDefDecoder) Dict.empty
        |> optional "watches" (Decode.dict locatedExprDecoder) Dict.empty
        |> optional "scries" (Decode.dict scryDefDecoder) Dict.empty
        |> optional "constants" (Decode.dict typedValueOrExprDecoder) Dict.empty
        |> optional "functions" (Decode.dict functionDefDecoder) Dict.empty
        |> optional "tests" (Decode.dict testDefDecoder) Dict.empty
        |> optional "machine" (Decode.map Just machineDefDecoder) Nothing


machineDefDecoder : Decoder MachineDef
machineDefDecoder =
    Decode.succeed MachineDef
        |> required "initial"
            (Decode.succeed (\to data -> { to = to, data = data })
                |> required "to" Decode.string
                |> optional "data" (Decode.dict locatedExprDecoder) Dict.empty
            )
        |> optional "common" (Decode.dict typeRefDecoder) Dict.empty
        |> required "states" (Decode.dict stateConfigDecoder)


stateConfigDecoder : Decoder StateConfig
stateConfigDecoder =
    Decode.succeed StateConfig
        |> optional "data" (Decode.dict typeRefDecoder) Dict.empty
        |> optional "pokes" (Decode.dict pokeDefDecoder) Dict.empty
        |> optional "scries" (Decode.dict scryDefDecoder) Dict.empty
        |> optional "watches" (Decode.dict locatedExprDecoder) Dict.empty


optionsDecoder : Decoder Options
optionsDecoder =
    Decode.succeed (\text num target -> { textRepresentation = text, numberRepresentation = num, target = target, prog_context_types = Dict.empty })
        |> optional "text" textRepresentationDecoder Cord
        |> optional "number" numberRepresentationDecoder UnsignedDecimal
        |> optional "target" targetDecoder Library


stateDefDecoder : Decoder StateDef
stateDefDecoder =
    Decode.succeed StateDef
        |> required "version" Decode.int
        |> required "data" (Decode.dict typeRefDecoder)


nativeDefDecoder : Decoder NativeDef
nativeDefDecoder =
    Decode.succeed NativeDef
        |> optional "type_args" (Decode.list Decode.string) []
        |> optional "input" inputListDecoder []
        |> required "output" typeRefDecoder


pokeDefDecoder : Decoder PokeDef
pokeDefDecoder =
    Decode.succeed PokeDef
        |> optional "mark" (Decode.maybe Decode.string) Nothing
        |> optional "input" inputListDecoder []
        |> required "return" locatedExprDecoder


scryDefDecoder : Decoder ScryDef
scryDefDecoder =
    Decode.succeed ScryDef
        |> required "output" typeRefDecoder
        |> required "return" locatedExprDecoder


testDefDecoder : Decoder TestDef
testDefDecoder =
    Decode.field "kind" Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "unit" ->
                        unitTestDataDecoder |> Decode.map UnitTest

                    "scenario" ->
                        scenarioTestDataDecoder |> Decode.map ScenarioTest

                    "migration" ->
                        migrationTestDataDecoder |> Decode.map MigrationTest

                    _ ->
                        Decode.fail ("Unknown test kind: " ++ kind)
            )


unitTestDataDecoder : Decoder UnitTestData
unitTestDataDecoder =
    Decode.succeed UnitTestData
        |> required "func" Decode.string
        |> required "cases" (Decode.list unitTestCaseDecoder)
        |> optional "fuzz" Decode.bool False


unitTestCaseDecoder : Decoder { input : Dict String LiteralValue, expect : LiteralValue }
unitTestCaseDecoder =
    Decode.succeed (\i e -> { input = i, expect = e })
        |> required "input" (Decode.dict literalValueDecoder)
        |> required "expect" literalValueDecoder


scenarioTestDataDecoder : Decoder ScenarioTestData
scenarioTestDataDecoder =
    Decode.succeed ScenarioTestData
        |> required "setup" Decode.string
        |> required "steps" (Decode.list scenarioStepDecoder)


scenarioStepDecoder : Decoder ScenarioStep
scenarioStepDecoder =
    Decode.succeed ScenarioStep
        |> required "action" scenarioActionDecoder
        |> required "expect" scenarioExpectDecoder


scenarioActionDecoder : Decoder ScenarioAction
scenarioActionDecoder =
    Decode.field "action" Decode.string
        |> Decode.andThen
            (\action ->
                case action of
                    "poke" ->
                        Decode.succeed (\r p -> PokeAction { route = r, payload = p })
                            |> required "route" Decode.string
                            |> optional "payload" (Decode.dict literalValueDecoder) Dict.empty

                    "wait" ->
                        Decode.succeed (\d -> WaitAction { duration = d })
                            |> required "duration" Decode.string

                    _ ->
                        Decode.fail ("Unknown scenario action: " ++ action)
            )


scenarioExpectDecoder : Decoder ScenarioExpect
scenarioExpectDecoder =
    Decode.succeed ScenarioExpect
        |> optional "cards" (Decode.maybe (Decode.list literalValueDecoder)) Nothing
        |> optional "scries" (Decode.dict literalValueDecoder) Dict.empty
        |> optional "state" (Decode.maybe (Decode.dict literalValueDecoder)) Nothing


migrationTestDataDecoder : Decoder MigrationTestData
migrationTestDataDecoder =
    Decode.succeed MigrationTestData
        |> required "from_version" Decode.int
        |> required "old_state" Decode.string
        |> required "expect_state" (Decode.dict literalValueDecoder)


targetDecoder : Decoder Target
targetDecoder =
    Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "library" ->
                        Decode.succeed Library

                    "gall" ->
                        Decode.succeed Gall

                    _ ->
                        Decode.fail ("Unknown target: " ++ s)
            )


textRepresentationDecoder : Decoder TextRepresentation
textRepresentationDecoder =
    Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "cord" ->
                        Decode.succeed Cord

                    "tape" ->
                        Decode.succeed Tape

                    _ ->
                        Decode.fail ("Unknown text representation: " ++ s)
            )


numberRepresentationDecoder : Decoder NumberRepresentation
numberRepresentationDecoder =
    Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "atom" ->
                        Decode.succeed Atom

                    "unsigned" ->
                        Decode.succeed UnsignedDecimal

                    _ ->
                        Decode.fail ("Unknown number representation: " ++ s)
            )


defaultOptions : Options
defaultOptions =
    { textRepresentation = Cord
    , numberRepresentation = UnsignedDecimal
    , target = Library
    , prog_context_types = Dict.empty
    }


macroDefDecoder : Decoder MacroDef
macroDefDecoder =
    Decode.succeed MacroDef
        |> required "args" (Decode.list Decode.string)
        |> required "expand" locatedExprDecoder


typeDefDecoder : Decoder TypeDef
typeDefDecoder =
    Decode.oneOf
        [ Decode.field "kind" Decode.string
            |> Decode.andThen
                (\kind ->
                    case kind of
                        "record" ->
                            Decode.field "fields" (Decode.dict typeRefDecoder) |> Decode.map Record

                        "union" ->
                            Decode.field "variants" (Decode.dict variantDefDecoder) |> Decode.map Union

                        _ ->
                            Decode.fail ("Unknown type kind: " ++ kind)
                )
        , typeRefDecoder |> Decode.map Alias
        ]


variantDefDecoder : Decoder (Maybe (Dict String TypeRef))
variantDefDecoder =
    Decode.oneOf
        [ Decode.dict typeRefDecoder
            |> Decode.andThen
                (\d ->
                    if Dict.isEmpty d then
                        Decode.succeed Nothing

                    else
                        Decode.succeed (Just d)
                )
        , Decode.null Nothing
        ]


typeRefDecoder : Decoder TypeRef
typeRefDecoder =
    Decode.oneOf
        [ Decode.string |> Decode.andThen parseTypeRef
        , Decode.field "list" (Decode.lazy (\_ -> typeRefDecoder)) |> Decode.map TypeList
        , Decode.field "pair" (Decode.list (Decode.lazy (\_ -> typeRefDecoder)))
            |> Decode.andThen
                (\items ->
                    case items of
                        [ a, b ] ->
                            Decode.succeed (TypePair a b)

                        _ ->
                            Decode.fail "pair must have exactly 2 items"
                )
        ]


parseTypeRef : String -> Decoder TypeRef
parseTypeRef s =
    case Parser.run typeParser s of
        Ok t ->
            Decode.succeed t

        Err _ ->
            Decode.fail ("Invalid type reference: " ++ s)


typeParser : Parser.Parser TypeRef
typeParser =
    Parser.lazy (\_ ->
        Parser.oneOf
            [ Parser.backtrackable
                (baseTypeParser
                    |> Parser.andThen (\t ->
                        Parser.succeed (TypeUnit t)
                            |. Parser.spaces
                            |. Parser.symbol "?"
                    )
                )
            , baseTypeParser
            ]
    )


baseTypeParser : Parser.Parser TypeRef
baseTypeParser =
    Parser.lazy (\_ ->
        Parser.oneOf
            [ Parser.keyword "number" |> Parser.map (\_ -> TypeNumber)
            , Parser.keyword "nat" |> Parser.map (\_ -> TypeNat)
            , Parser.keyword "text" |> Parser.map (\_ -> TypeText)
            , Parser.keyword "bool" |> Parser.map (\_ -> TypeBool)
            , Parser.keyword "card" |> Parser.map (\_ -> TypeCard)
            , Parser.succeed TypeList
                |. Parser.keyword "list"
                |. Parser.symbol "<"
                |. Parser.spaces
                |= typeParser
                |. Parser.spaces
                |. Parser.symbol ">"
            , Parser.succeed TypePair
                |. Parser.keyword "pair"
                |. Parser.symbol "<"
                |. Parser.spaces
                |= typeParser
                |. Parser.spaces
                |. Parser.symbol ","
                |. Parser.spaces
                |= typeParser
                |. Parser.spaces
                |. Parser.symbol ">"
            , Parser.succeed TypeQuip
                |. Parser.keyword "quip"
                |. Parser.symbol "<"
                |. Parser.spaces
                |= typeParser
                |. Parser.spaces
                |. Parser.symbol ","
                |. Parser.spaces
                |= typeParser
                |. Parser.spaces
                |. Parser.symbol ">"
            , Parser.succeed TypeMap
                |. Parser.keyword "map"
                |. Parser.symbol "<"
                |. Parser.spaces
                |= typeParser
                |. Parser.spaces
                |. Parser.symbol ","
                |. Parser.spaces
                |= typeParser
                |. Parser.spaces
                |. Parser.symbol ">"
            , Parser.succeed TypeSet
                |. Parser.keyword "set"
                |. Parser.symbol "<"
                |. Parser.spaces
                |= typeParser
                |. Parser.spaces
                |. Parser.symbol ">"
            , Parser.succeed TypeRawHoon
                |. Parser.keyword "raw-hoon"
                |. Parser.symbol "<"
                |. Parser.spaces
                |= (Parser.getChompedString (Parser.chompWhile (\c -> c /= '>')))
                |. Parser.spaces
                |. Parser.symbol ">"
            , ExprParser.nameParser |> Parser.map TypeNamed
            ]
    )


typedValueOrExprDecoder : Decoder TypedValueOrExpr
typedValueOrExprDecoder =
    Decode.oneOf
        [ Decode.succeed TypedValueOrExpr
            |> optional "type" (Decode.map Just typeRefDecoder) Nothing
            |> required "value" valueOrExprDecoder
        , valueOrExprDecoder |> Decode.map (TypedValueOrExpr Nothing)
        ]


valueOrExprDecoder : Decoder ValueOrExpr
valueOrExprDecoder =
    Decode.oneOf
        [ Decode.field "expr" Decode.string
            |> Decode.andThen
                (\s ->
                    case ExprParser.parse s of
                        Ok expr ->
                            Decode.succeed (Computed expr)

                        Err deadEnds ->
                            Decode.fail (deadEndsToString s deadEnds)
                )
        , Decode.field "hoon" Decode.string |> Decode.map RawHoon
        , literalValueDecoder |> Decode.map Literal
        ]


literalValueDecoder : Decoder LiteralValue
literalValueDecoder =
    Decode.oneOf
        [ Decode.int |> Decode.map (String.fromInt >> LitNumber)
        , Decode.float |> Decode.map (String.fromFloat >> LitNumber)
        , Decode.string |> Decode.map LitText
        , Decode.bool |> Decode.map LitBool
        , Decode.null (LitText "~")
        , Decode.list (Decode.lazy (\_ -> literalValueDecoder)) |> Decode.map LitList
        , Decode.dict (Decode.lazy (\_ -> literalValueDecoder))
            |> Decode.andThen
                (\dict ->
                    let
                        keys =
                            Dict.keys dict
                    in
                    case keys of
                        [ typeName ] ->
                            if isUppercase typeName then
                                case Dict.get typeName dict of
                                    Just (LitObject fields) ->
                                        let
                                            innerKeys =
                                                Dict.keys fields
                                        in
                                        case innerKeys of
                                            [ variantName ] ->
                                                if isUppercase variantName then
                                                    case Dict.get variantName fields of
                                                        Just (LitObject variantFields) ->
                                                            Decode.succeed (LitVariant typeName variantName variantFields)

                                                        Just (LitText "~") ->
                                                            Decode.succeed (LitVariant typeName variantName Dict.empty)

                                                        _ ->
                                                            Decode.succeed (LitRecord typeName fields)

                                                else
                                                    Decode.succeed (LitRecord typeName fields)

                                            _ ->
                                                Decode.succeed (LitRecord typeName fields)

                                    _ ->
                                        Decode.succeed (LitObject dict)

                            else
                                Decode.succeed (LitObject dict)

                        _ ->
                            Decode.succeed (LitObject dict)
                )
        ]


functionDefDecoder : Decoder FunctionDef
functionDefDecoder =
    Decode.succeed FunctionDef
        |> optional "type_args" (Decode.list Decode.string) []
        |> optional "input" inputListDecoder []
        |> required "output" typeRefDecoder
        |> required "return" locatedExprDecoder
        |> optional "jet" (Decode.maybe Decode.string) Nothing


inputListDecoder : Decoder (List ( String, TypeRef ))
inputListDecoder =
    Decode.oneOf
        [ Decode.dict typeRefDecoder |> Decode.map Dict.toList
        , Decode.list (Decode.dict typeRefDecoder)
            |> Decode.andThen
                (\list ->
                    list
                        |> List.map Dict.toList
                        |> List.concat
                        |> Decode.succeed
                )
        ]


locatedExprDecoder : Decoder LocatedExpr
locatedExprDecoder =
    Decode.oneOf
        [ Decode.string
            |> Decode.andThen
                (\s ->
                    case ExprParser.parse s of
                        Ok expr ->
                            Decode.succeed expr

                        Err deadEnds ->
                            Decode.fail (deadEndsToString s deadEnds)
                )
        , exprDecoder |> Decode.map (\e -> { pos = { line = 0, col = 0 }, expr = e })
        ]


exprDecoder : Decoder Expr
exprDecoder =
    Decode.oneOf
        [ Decode.bool |> Decode.map EBool
        , Decode.int |> Decode.map (String.fromInt >> ENumber)
        , Decode.float |> Decode.map (String.fromFloat >> ENumber)
        , Decode.null (ECall "unit" [])
        , Decode.list (Decode.lazy (\_ -> locatedExprDecoder)) |> Decode.map EList
        , Decode.field "if" (Decode.lazy (\_ -> locatedExprDecoder))
            |> Decode.andThen
                (\cond ->
                    Decode.oneOf
                        [ Decode.succeed (EIf cond)
                            |> required "then" (Decode.lazy (\_ -> locatedExprDecoder))
                            |> required "else" (Decode.lazy (\_ -> locatedExprDecoder))
                        , Decode.succeed (EIfNot cond)
                            |> required "not_then" (Decode.lazy (\_ -> locatedExprDecoder))
                            |> required "not_else" (Decode.lazy (\_ -> locatedExprDecoder))
                        ]
                )
        , Decode.field "match" (Decode.lazy (\_ -> locatedExprDecoder))
            |> Decode.andThen
                (\target ->
                    Decode.succeed (EMatch target)
                        |> required "cases" (Decode.dict (Decode.lazy (\_ -> locatedExprDecoder)))
                        |> optional "default" (Decode.map Just (Decode.lazy (\_ -> locatedExprDecoder))) Nothing
                )
        , Decode.field "cast" (Decode.lazy (\_ -> typeRefDecoder))
            |> Decode.andThen
                (\targetType ->
                    Decode.field "value" (Decode.lazy (\_ -> locatedExprDecoder))
                        |> Decode.map (ECast targetType)
                )
        , Decode.field "transition"
            (Decode.succeed (\to data common -> ETransition { to = to, data = data, common = common })
                |> required "to" Decode.string
                |> optional "data" (Decode.dict (Decode.lazy (\_ -> locatedExprDecoder))) Dict.empty
                |> optional "common" (Decode.map Just (Decode.dict (Decode.lazy (\_ -> locatedExprDecoder)))) Nothing
            )
        , Decode.dict (Decode.lazy (\_ -> locatedExprDecoder))
            |> Decode.andThen
                (\dict ->
                    let
                        keys =
                            Dict.keys dict
                    in
                    if List.member "loop" keys then
                        case Dict.get "loop" dict of
                            Just body ->
                                case body.expr of
                                    EDict innerDict ->
                                        case ( Dict.get "args" innerDict, Dict.get "return" innerDict ) of
                                            ( Just argsLe, Just ret ) ->
                                                case argsLe.expr of
                                                    EDict args ->
                                                        Decode.succeed (ELoop args ret)

                                                    _ ->
                                                        Decode.succeed (ELoop Dict.empty body)

                                            _ ->
                                                Decode.succeed (ELoop Dict.empty body)

                                    _ ->
                                        Decode.succeed (ELoop Dict.empty body)

                            Nothing ->
                                Decode.fail "logic error"

                    else if List.member "let" keys && List.member "in" keys then
                        case ( Dict.get "let" dict, Dict.get "in" dict ) of
                            ( Just bindingsLe, Just body ) ->
                                case bindingsLe.expr of
                                    EDict bindings ->
                                        let
                                            nestLet : List ( String, LocatedExpr ) -> LocatedExpr -> Decoder Expr
                                            nestLet b rest =
                                                case b of
                                                    [] ->
                                                        Decode.succeed rest.expr

                                                    ( n, v ) :: bs ->
                                                        nestLet bs rest |> Decode.map (ELet n v << (\e -> { pos = rest.pos, expr = e }))
                                        in
                                        nestLet (Dict.toList bindings) body

                                    _ ->
                                        Decode.fail "invalid let bindings"

                            _ ->
                                Decode.fail "invalid let/in"

                    else if List.member "set" keys && List.member "in" keys then
                        case ( Dict.get "set" dict, Dict.get "in" dict ) of
                            ( Just bindingsLe, Just body ) ->
                                case bindingsLe.expr of
                                    EDict bindings ->
                                        let
                                            nestSet : List ( String, LocatedExpr ) -> LocatedExpr -> Decoder Expr
                                            nestSet b rest =
                                                case b of
                                                    [] ->
                                                        Decode.succeed rest.expr

                                                    ( n, v ) :: bs ->
                                                        nestSet bs rest |> Decode.map (ESet n v << (\e -> { pos = rest.pos, expr = e }))
                                        in
                                        nestSet (Dict.toList bindings) body

                                    _ ->
                                        Decode.fail "invalid set bindings"

                            _ ->
                                Decode.fail "invalid set/in"

                    else if List.member "assert" keys && List.member "in" keys then
                        case ( Dict.get "assert" dict, Dict.get "in" dict ) of
                            ( Just cond, Just body ) ->
                                Decode.succeed (EAssert cond body)

                            _ ->
                                Decode.fail "invalid assert/in"

                    else if List.member "unless" keys && List.member "in" keys then
                        case ( Dict.get "unless" dict, Dict.get "in" dict ) of
                            ( Just cond, Just body ) ->
                                Decode.succeed (EUnless cond body)

                            _ ->
                                Decode.fail "invalid unless/in"

                    else
                        case keys of
                            [ typeName ] ->
                                if isUppercase typeName then
                                    case Dict.get typeName dict of
                                        Just bodyLe ->
                                            case bodyLe.expr of
                                                EDict fields ->
                                                    let
                                                        innerKeys =
                                                            Dict.keys fields
                                                    in
                                                    case innerKeys of
                                                        [ variantName ] ->
                                                            if isUppercase variantName then
                                                                case Dict.get variantName fields of
                                                                    Just variantLe ->
                                                                        case variantLe.expr of
                                                                            EDict variantFields ->
                                                                                Decode.succeed (EVariant typeName variantName variantFields)

                                                                            ECall "unit" [] ->
                                                                                Decode.succeed (EVariant typeName variantName Dict.empty)

                                                                            _ ->
                                                                                Decode.succeed (ERecord typeName fields)

                                                                    Nothing ->
                                                                        Decode.succeed (ERecord typeName fields)

                                                            else
                                                                Decode.succeed (ERecord typeName fields)

                                                        _ ->
                                                            Decode.succeed (ERecord typeName fields)

                                                ERecord variantName variantFields ->
                                                    if isUppercase variantName then
                                                        let
                                                            normalizedFields =
                                                                case Dict.get variantName variantFields of
                                                                    Just fieldLe ->
                                                                        if Dict.size variantFields == 1 && fieldLe.expr == ECall "unit" [] then
                                                                            Dict.empty

                                                                        else
                                                                            variantFields

                                                                    Nothing ->
                                                                        variantFields
                                                        in
                                                        Decode.succeed (EVariant typeName variantName normalizedFields)

                                                    else
                                                        Decode.succeed (ERecord typeName (Dict.singleton variantName bodyLe))

                                                _ ->
                                                    Decode.succeed (ERecord typeName (Dict.singleton typeName bodyLe))

                                        Nothing ->
                                            Decode.fail "logic error"

                                else
                                    Decode.succeed (EDict (Dict.fromList (List.map (\k -> ( k, Maybe.withDefault { expr = ENumber "0", pos = { col = 0, line = 0 } } (Dict.get k dict) )) keys)))

                            _ ->
                                Decode.succeed (EDict (Dict.fromList (List.map (\k -> ( k, Maybe.withDefault { expr = ENumber "0", pos = { col = 0, line = 0 } } (Dict.get k dict) )) keys)))
                )
        , Decode.field "rune" Decode.string
            |> Decode.andThen
                (\r ->
                    Decode.succeed (ERune r)
                        |> optional "args" (Decode.list (Decode.lazy (\_ -> locatedExprDecoder))) []
                )
        , Decode.field "if_not" (Decode.lazy (\_ -> locatedExprDecoder))
            |> Decode.andThen
                (\cond ->
                    Decode.succeed (EIfNot cond)
                        |> required "then" (Decode.lazy (\_ -> locatedExprDecoder))
                        |> required "else" (Decode.lazy (\_ -> locatedExprDecoder))
                )
        , Decode.field "hoon" Decode.string |> Decode.map ERawHoon
        ]


deadEndsToString : String -> List Parser.DeadEnd -> String
deadEndsToString input deadEnds =
    let
        problemToString p =
            case p of
                Parser.Expecting s ->
                    "expected '" ++ s ++ "'"

                Parser.ExpectingInt ->
                    "expected an integer"

                Parser.ExpectingHex ->
                    "expected a hexadecimal number"

                Parser.ExpectingOctal ->
                    "expected an octal number"

                Parser.ExpectingBinary ->
                    "expected a binary number"

                Parser.ExpectingFloat ->
                    "expected a float"

                Parser.ExpectingNumber ->
                    "expected a number"

                Parser.ExpectingVariable ->
                    "expected a variable name"

                Parser.ExpectingSymbol s ->
                    "expected symbol '" ++ s ++ "'"

                Parser.ExpectingKeyword s ->
                    "expected keyword '" ++ s ++ "'"

                Parser.ExpectingEnd ->
                    "expected end of expression"

                Parser.UnexpectedChar ->
                    "unexpected character"

                Parser.Problem s ->
                    s

                Parser.BadRepeat ->
                    "bad repeat"

        deadEndToString de =
            "Syntax error at line " ++ String.fromInt de.row ++ ", col " ++ String.fromInt de.col ++ ": " ++ problemToString de.problem
    in
    "Invalid expression: '" ++ input ++ "'\n" ++ String.join "\n" (List.map deadEndToString deadEnds)


isUppercase : String -> Bool
isUppercase s =
    let
        first =
            String.left 1 s
    in
    first == String.toUpper first && first /= String.toLower first
