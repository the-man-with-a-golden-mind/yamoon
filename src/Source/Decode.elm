module Source.Decode exposing (decode)

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline exposing (optional, required)
import Parser
import Source.Ast as Ast exposing (..)
import Source.ExprParser as ExprParser


decode : String -> Result String Ast.Program
decode json =
    case Decode.decodeString programDecoder json of
        Ok program ->
            Ok program

        Err err ->
            Err (Decode.errorToString err)


programDecoder : Decoder Ast.Program
programDecoder =
    Decode.succeed
        (\module_ docs options imports types macros native state onLoad pokes watches scries constants functions tests ->
            let
                newOptions =
                    { options | prog_context_types = types }
            in
            Ast.Program module_ docs newOptions imports types macros native state onLoad pokes watches scries constants functions tests
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
    if String.endsWith "?" s then
        parseTypeRef (String.dropRight 1 s) |> Decode.map TypeUnit

    else if s == "number" then
        Decode.succeed TypeNumber

    else if s == "nat" then
        Decode.succeed TypeNat

    else if s == "text" then
        Decode.succeed TypeText

    else if s == "bool" then
        Decode.succeed TypeBool

    else if s == "card" then
        Decode.succeed TypeCard

    else if String.startsWith "list<" s && String.endsWith ">" s then
        let
            inner =
                String.slice 5 (String.length s - 1) s
        in
        parseTypeRef inner |> Decode.map TypeList

    else if String.startsWith "pair<" s && String.endsWith ">" s then
        let
            inner =
                String.slice (String.length "pair<") (String.length s - 1) s

            parts =
                String.split "," inner
                    |> List.map String.trim
        in
        case parts of
            [ aStr, bStr ] ->
                Decode.map2 TypePair (parseTypeRef aStr) (parseTypeRef bStr)

            _ ->
                Decode.fail "pair<A, B> must have exactly 2 types"

    else if String.startsWith "quip<" s && String.endsWith ">" s then
        let
            inner =
                String.slice (String.length "quip<") (String.length s - 1) s

            parts =
                String.split "," inner
                    |> List.map String.trim
        in
        case parts of
            [ aStr, bStr ] ->
                Decode.map2 TypeQuip (parseTypeRef aStr) (parseTypeRef bStr)

            _ ->
                Decode.fail "quip<A, B> must have exactly 2 types"

    else if String.startsWith "map<" s && String.endsWith ">" s then
        let
            inner =
                String.slice (String.length "map<") (String.length s - 1) s

            parts =
                String.split "," inner
                    |> List.map String.trim
        in
        case parts of
            [ aStr, bStr ] ->
                Decode.map2 TypeMap (parseTypeRef aStr) (parseTypeRef bStr)

            _ ->
                Decode.fail "map<K, V> must have exactly 2 types"

    else if String.startsWith "set<" s && String.endsWith ">" s then
        let
            inner =
                String.slice (String.length "set<") (String.length s - 1) s
        in
        parseTypeRef inner |> Decode.map TypeSet

    else
        Decode.succeed (TypeNamed s)


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
                                        case Dict.toList bindings of
                                            [ ( name, val ) ] ->
                                                Decode.succeed (ELet name val body)

                                            _ ->
                                                Decode.fail "let currently supports exactly 1 binding"

                                    _ ->
                                        Decode.fail "invalid let bindings"

                            _ ->
                                Decode.fail "invalid let/in"

                    else if List.member "set" keys && List.member "in" keys then
                        case ( Dict.get "set" dict, Dict.get "in" dict ) of
                            ( Just bindingsLe, Just body ) ->
                                case bindingsLe.expr of
                                    EDict bindings ->
                                        case Dict.toList bindings of
                                            [ ( name, val ) ] ->
                                                Decode.succeed (ESet name val body)

                                            _ ->
                                                Decode.fail "set currently supports exactly 1 binding"

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

                    else if List.member "match" keys && List.member "cases" keys then
                        case ( Dict.get "match" dict, Dict.get "cases" dict ) of
                            ( Just target, Just casesLe ) ->
                                case casesLe.expr of
                                    EDict cases ->
                                        Decode.succeed (EMatch target cases (Dict.get "default" dict))

                                    _ ->
                                        Decode.fail "invalid match cases"

                            _ ->
                                Decode.fail "invalid match"

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
        deadEndToString de =
            "Syntax error at line " ++ String.fromInt de.row ++ ", col " ++ String.fromInt de.col
    in
    "Invalid expression: '" ++ input ++ "'\n" ++ String.join "\n" (List.map deadEndToString deadEnds)


isUppercase : String -> Bool
isUppercase s =
    let
        first =
            String.left 1 s
    in
    first == String.toUpper first && first /= String.toLower first
