module Compiler.Lower exposing (lower, lowerTests)

import Dict exposing (Dict)
import Hoon.Ast as Hoon
import Source.Ast as Source


lower : Source.Program -> Hoon.HoonProgram
lower prog =
    let
        docs =
            List.map Hoon.HoonComment prog.docs

        baseArms =
            List.concat
                [ lowerTypes prog
                , lowerConstants prog
                , lowerFunctions prog
                ]

        gallArms =
            if prog.options.target == Source.Gall then
                lowerGall prog

            else
                []

        finalArms =
            baseArms ++ gallArms
        in
    Hoon.HoonModule prog.imports docs finalArms


lowerStateMold : Source.Options -> Source.StateDef -> Hoon.HoonMold
lowerStateMold opts s =
    let
        fields =
            s.fields
                |> Dict.toList
                |> List.map (\( k, v ) -> k ++ "=" ++ moldToString (lowerTypeRef opts v))
                |> String.join " "
    in
    Hoon.MRaw ("[% " ++ String.fromInt s.version ++ " " ++ fields ++ "]")


lowerTests : Source.Program -> Hoon.HoonProgram
lowerTests prog =
    let
        testArms =
            prog.tests
                |> Dict.toList
                |> List.map (\( name, def ) -> lowerTest prog name def)
                |> List.concat

        imports =
            [ "/+  test" ] ++ prog.imports
    in
    Hoon.HoonTestFile imports testArms


lowerTest : Source.Program -> String -> Source.TestDef -> List Hoon.HoonArm
lowerTest prog name def =
    case def of
        Source.UnitTest data ->
            [ lowerUnitTest name data ]

        Source.ScenarioTest data ->
            [ lowerScenarioTest prog name data ]

        Source.MigrationTest data ->
            [ lowerMigrationTest name data ]


lowerUnitTest : String -> Source.UnitTestData -> Hoon.HoonArm
lowerUnitTest name data =
    let
        assertions =
            data.cases
                |> List.map
                    (\c ->
                        let
                            args =
                                c.input
                                    |> Dict.values
                                    |> List.map (lowerLiteralValue >> loc)

                            call =
                                Hoon.HCall data.func args

                            expect =
                                lowerLiteralValue c.expect
                        in
                        Hoon.HCall "expect-eq" [ loc call, loc expect ]
                    )

        body =
            case assertions of
                [] ->
                    Hoon.HRaw "%.y"

                [ x ] ->
                    x

                _ ->
                    Hoon.HCall "all" (List.map loc assertions)
    in
    Hoon.HoonArm ("test-" ++ camelToKebab name) (Hoon.HGate [] body)


lowerScenarioTest : Source.Program -> String -> Source.ScenarioTestData -> Hoon.HoonArm
lowerScenarioTest prog name data =
    let
        init =
            Hoon.HLet "state" (Hoon.HName data.setup) <|
                Hoon.HLet "bowl" (Hoon.HRaw "mock-bowl") <|
                    lowerSteps data.steps

        lowerSteps steps =
            case steps of
                [] ->
                    Hoon.HBool True

                step :: rest ->
                    let
                        stepLogic =
                            case step.action of
                                Source.PokeAction { route, payload } ->
                                    let
                                        mark =
                                            prog.pokes
                                                |> Dict.get route
                                                |> Maybe.andThen .mark
                                                |> Maybe.withDefault "tas"

                                        payloadHoon =
                                            lowerLiteralValue (Source.LitObject payload)
                                    in
                                    Hoon.HLet "[cards state]" (Hoon.HRaw ("(on-poke:" ++ camelToKebab route ++ " bowl %" ++ mark ++ " !>(" ++ renderHoonExprForRaw payloadHoon ++ "))")) <|
                                        lowerExpectations step.expect (lowerSteps rest)

                                Source.WaitAction { duration } ->
                                    Hoon.HLet "bowl" (Hoon.HRaw ("bowl(now (add now.bowl " ++ duration ++ "))")) <|
                                        lowerSteps rest
                    in
                    stepLogic

        lowerExpectations expect next =
            let
                assertions =
                    List.concat
                        [ case expect.state of
                            Just s ->
                                [ Hoon.HCall "expect-eq" [ loc (Hoon.HName "state"), loc (lowerLiteralValue (Source.LitObject s)) ] ]

                            Nothing ->
                                []
                        , expect.scries
                            |> Dict.toList
                            |> List.map
                                (\( path, val ) ->
                                    Hoon.HCall "expect-eq"
                                        [ loc (Hoon.HRaw ("(on-peek:" ++ camelToKebab name ++ " " ++ pathToHoon path ++ ")"))
                                        , loc (lowerLiteralValue val)
                                        ]
                                )
                        ]

                body =
                    case assertions of
                        [] ->
                            next

                        _ ->
                            Hoon.HCall "all" (List.map loc (assertions ++ [ next ]))
            in
            body
    in
    Hoon.HoonArm ("test-" ++ camelToKebab name) (Hoon.HGate [] init)


lowerMigrationTest : String -> Source.MigrationTestData -> Hoon.HoonArm
lowerMigrationTest name data =
    let
        body =
            Hoon.HLet "old" (Hoon.HRaw ("!>(" ++ data.oldState ++ ")")) <|
                Hoon.HLet "new-state" (Hoon.HRaw "(on-load old)") <|
                    Hoon.HCall "expect-eq" [ loc (Hoon.HName "new-state"), loc (lowerLiteralValue (Source.LitObject data.expectState)) ]
    in
    Hoon.HoonArm ("test-" ++ camelToKebab name) (Hoon.HGate [] body)


pathToHoon : String -> String
pathToHoon path =
    path
        |> String.split "/"
        |> List.filter (not << String.isEmpty)
        |> List.map (\s -> "%" ++ s)
        |> (\parts -> "[" ++ String.join " " parts ++ " ~]")


lowerLiteralValue : Source.LiteralValue -> Hoon.HoonExpr
lowerLiteralValue val =
    case val of
        Source.LitNumber s ->
            Hoon.HAtom s

        Source.LitText s ->
            case s of
                "" ->
                    Hoon.HRaw "~"

                _ ->
                    Hoon.HCord s

        Source.LitBool b ->
            Hoon.HBool b

        Source.LitList l ->
            Hoon.HList (List.map lowerLiteralValue l)

        Source.LitObject obj ->
            lowerCellList (obj |> Dict.toList |> List.map (\( k, v ) -> loc (Hoon.HRaw (k ++ "=" ++ renderHoonExprForRaw (lowerLiteralValue v)))))

        Source.LitRecord t f ->
            lowerCellList (f |> Dict.toList |> List.map (\( k, v ) -> loc (Hoon.HRaw (k ++ "=" ++ renderHoonExprForRaw (lowerLiteralValue v)))))

        Source.LitVariant typeName variantName fields ->
            let
                tagName =
                    Hoon.HRaw ("%" ++ camelToKebab variantName)
            in
            if Dict.isEmpty fields then
                tagName
            else
                Hoon.HCell tagName (lowerCellList (fields |> Dict.toList |> List.map (\( k, v ) -> loc (Hoon.HRaw (k ++ "=" ++ renderHoonExprForRaw (lowerLiteralValue v))))))


lowerGall : Source.Program -> List Hoon.HoonArm
lowerGall prog =
    let
        stateArms =
            case ( prog.machine, prog.state ) of
                ( Just machine, _ ) ->
                    [ Hoon.HoonArm "state-v0" (Hoon.HRaw (lowerMachineMold prog.options machine))
                    , Hoon.HoonArm "state" (Hoon.HRaw "state-v0")
                    ]

                ( Nothing, Just s ) ->
                    [ Hoon.HoonArm ("state-v" ++ String.fromInt s.version) (Hoon.HRaw (moldToString (lowerStateMold prog.options s)))
                    , Hoon.HoonArm "state" (Hoon.HRaw ("state-v" ++ String.fromInt s.version))
                    ]

                _ ->
                    []

        initialStateArm =
            case prog.machine of
                Just machine ->
                    [ Hoon.HoonArm "initial-state" (lowerMachineInitial prog.options machine) ]

                Nothing ->
                    []

        onInit =
            case ( prog.machine, prog.state ) of
                ( Just _, _ ) ->
                    [ Hoon.HoonArm "on-init" (Hoon.HGate [] (Hoon.HCall "pure" [ loc (Hoon.HName "initial-state") ])) ]

                ( Nothing, Just _ ) ->
                    case Dict.get "on-init" prog.functions of
                        Just _ ->
                            []

                        Nothing ->
                            [ Hoon.HoonArm "on-init" (Hoon.HGate [] (Hoon.HCall "pure" [ loc (Hoon.HName "initialState") ])) ]

                _ ->
                    []

        onLoad =
            case prog.onLoad of
                Just migration ->
                    [ Hoon.HoonArm "on-load" (Hoon.HGate [ ( "old=vase", Hoon.MRaw "vase" ) ] (Hoon.HLet "old" (Hoon.HRaw "q.old") (lowerExpr prog.options migration))) ]

                Nothing ->
                    []

        onPoke =
            case prog.machine of
                Just machine ->
                    [ lowerMachineOnPoke prog machine ]

                Nothing ->
                    if not (Dict.isEmpty prog.pokes) then
                        [ lowerOnPoke prog ]

                    else
                        []

        onWatch =
            case prog.machine of
                Just machine ->
                    [ lowerMachineOnWatch prog machine ]

                Nothing ->
                    if not (Dict.isEmpty prog.watches) then
                        [ lowerOnWatch prog ]

                    else
                        []

        onPeek =
            case prog.machine of
                Just machine ->
                    [ lowerMachineOnPeek prog machine ]

                Nothing ->
                    if not (Dict.isEmpty prog.scries) then
                        [ lowerOnPeek prog ]

                    else
                        []

        pokeHandlers =
            prog.pokes
                |> Dict.toList
                |> List.map (\( name, def ) -> lowerPokeHandler prog name def)

        machineHandlers =
            case prog.machine of
                Just machine ->
                    machine.states
                        |> Dict.toList
                        |> List.map (\( stateName, config ) -> lowerMachineStateHandlers prog machine stateName config)
                        |> List.concat

                Nothing ->
                    []
    in
    stateArms ++ initialStateArm ++ onInit ++ onLoad ++ onPoke ++ onWatch ++ onPeek ++ pokeHandlers ++ machineHandlers


lowerPokeHandler : Source.Program -> String -> Source.PokeDef -> Hoon.HoonArm
lowerPokeHandler prog name def =
    let
        inputs =
            def.input
                |> List.map (\( k, v ) -> ( k, lowerTypeRef prog.options v ))

        body =
            lowerExpr prog.options def.body
    in
    Hoon.HoonArm name (Hoon.HGate inputs body)


lowerMachineStateHandlers : Source.Program -> Source.MachineDef -> String -> Source.StateConfig -> List Hoon.HoonArm
lowerMachineStateHandlers prog machine stateName config =
    let
        pokeHandlers =
            config.pokes
                |> Dict.toList
                |> List.map
                    (\( pokeName, def ) ->
                        lowerPokeHandler prog (lowerCase stateName ++ "-" ++ pokeName) def
                    )

        scryHandlers =
            config.scries
                |> Dict.toList
                |> List.map
                    (\( scryPath, def ) ->
                        let
                            name =
                                lowerCase stateName ++ "-scry-" ++ (scryPath |> String.split "/" |> String.join "-")
                        in
                        Hoon.HoonArm name (Hoon.HGate [] (lowerExpr prog.options def.body))
                    )
    in
    pokeHandlers ++ scryHandlers


lowerCase : String -> String
lowerCase s =
    String.toLower (String.left 1 s) ++ String.dropLeft 1 s


lowerMachineMold : Source.Options -> Source.MachineDef -> String

lowerMachineMold opts machine =
    let
        commonFields =
            machine.common
                |> Dict.toList
                |> List.map (\( k, v ) -> k ++ "=" ++ moldToString (lowerTypeRef opts v))
                |> String.join " "

        variants =
            machine.states
                |> Dict.toList
                |> List.map
                    (\( name, config ) ->
                        let
                            variantName =
                                "%" ++ camelToKebab name

                            fields =
                                config.data
                                    |> Dict.toList
                                    |> List.map (\( k, v ) -> k ++ "=" ++ moldToString (lowerTypeRef opts v))
                                    |> String.join " "
                        in
                        if String.isEmpty fields then
                            variantName

                        else
                            "[" ++ variantName ++ " " ++ fields ++ "]"
                    )
                |> String.join " "
    in
    "[%0 " ++ commonFields ++ " mode=$%(" ++ variants ++ ")]"


lowerMachineInitial : Source.Options -> Source.MachineDef -> Hoon.HoonExpr
lowerMachineInitial opts machine =
    let
        commonFields =
            machine.common
                |> Dict.keys
                |> List.map (\k -> loc (Hoon.HRaw (k ++ "=* " ++ moldToString (lowerTypeRef opts (Maybe.withDefault Source.TypeNumber (Dict.get k machine.common))))))

        mode =
            let
                tagName =
                    Hoon.HRaw ("%" ++ camelToKebab machine.initial.to)

                data =
                    machine.initial.data
                        |> Dict.toList
                        |> List.map (\( k, v ) -> loc (Hoon.HRaw (k ++ "=" ++ renderHoonExprForRaw (lowerExpr opts v))))
            in
            if List.isEmpty data then
                tagName

            else
                Hoon.HCell tagName (lowerCellList data)
    in
    Hoon.HCell (Hoon.HAtom "0") (lowerCellList (commonFields ++ [ loc (Hoon.HRaw ("mode=" ++ renderHoonExprForRaw mode)) ]))


lowerMachineOnPoke : Source.Program -> Source.MachineDef -> Hoon.HoonArm
lowerMachineOnPoke prog machine =
    let
        stateMatches =
            machine.states
                |> Dict.toList
                |> List.map
                    (\( stateName, config ) ->
                        let
                            pattern =
                                "[* * %" ++ camelToKebab stateName ++ " *]"

                            markMatch =
                                config.pokes
                                    |> Dict.toList
                                    |> List.map
                                        (\( pokeName, def ) ->
                                            let
                                                mark =
                                                    Maybe.withDefault "tas" def.mark

                                                handlerName =
                                                    lowerCase stateName ++ "-" ++ pokeName

                                                call =
                                                    Hoon.HCall handlerName [ loc (Hoon.HRaw "q.vase") ]
                                            in
                                            ( "%" ++ mark, call )
                                        )

                            stateBody =
                                if List.isEmpty markMatch then
                                    Hoon.HRaw "on-poke:def"

                                else
                                    Hoon.HMatch (loc (Hoon.HRaw "mark")) markMatch (Just (Hoon.HRaw "on-poke:def"))

                            -- Bind state fields into the subject
                            -- mode is the last field in our state record
                            finalBody =
                                if Dict.isEmpty config.data then
                                    stateBody

                                else
                                    Hoon.HLet "+*" (Hoon.HRaw "mode.state") stateBody
                        in
                        ( pattern, finalBody )
                    )

        body =
            Hoon.HMatch (loc (Hoon.HRaw "state")) stateMatches (Just (Hoon.HRaw "on-poke:def"))
    in
    Hoon.HoonArm "on-poke" (Hoon.HGate [ ( "mark=@tas", Hoon.MAtom ), ( "vase=vase", Hoon.MRaw "vase" ) ] body)


lowerMachineOnWatch : Source.Program -> Source.MachineDef -> Hoon.HoonArm
lowerMachineOnWatch prog machine =
    let
        stateMatches =
            machine.states
                |> Dict.toList
                |> List.map
                    (\( stateName, config ) ->
                        let
                            pattern =
                                "[* * %" ++ camelToKebab stateName ++ " *]"

                            watchMatch =
                                config.watches
                                    |> Dict.toList
                                    |> List.map
                                        (\( path, watchBody ) ->
                                            let
                                                pathPattern =
                                                    path
                                                        |> String.split "/"
                                                        |> List.filter (not << String.isEmpty)
                                                        |> List.map (\s -> "%" ++ s)
                                                        |> (\parts -> "[" ++ String.join " " parts ++ " ~]")
                                            in
                                            ( pathPattern, lowerExpr prog.options watchBody )
                                        )

                            stateBody =
                                if List.isEmpty watchMatch then
                                    Hoon.HRaw "on-watch:def"

                                else
                                    Hoon.HMatch (loc (Hoon.HRaw "path")) watchMatch (Just (Hoon.HRaw "on-watch:def"))

                            finalBody =
                                if Dict.isEmpty config.data then
                                    stateBody

                                else
                                    Hoon.HLet "+*" (Hoon.HRaw "mode.state") stateBody
                        in
                        ( pattern, finalBody )
                    )

        body =
            Hoon.HMatch (loc (Hoon.HRaw "state")) stateMatches (Just (Hoon.HRaw "on-watch:def"))
    in
    Hoon.HoonArm "on-watch" (Hoon.HGate [ ( "path=path", Hoon.MRaw "path" ) ] body)


lowerMachineOnPeek : Source.Program -> Source.MachineDef -> Hoon.HoonArm
lowerMachineOnPeek prog machine =
    let
        stateMatches =
            machine.states
                |> Dict.toList
                |> List.map
                    (\( stateName, config ) ->
                        let
                            pattern =
                                "[* * %" ++ camelToKebab stateName ++ " *]"

                            scryMatch =
                                config.scries
                                    |> Dict.toList
                                    |> List.map
                                        (\( path, def ) ->
                                            let
                                                pathPattern =
                                                    path
                                                        |> String.split "/"
                                                        |> List.filter (not << String.isEmpty)
                                                        |> List.map (\s -> "%" ++ s)
                                                        |> (\parts -> "[" ++ String.join " " parts ++ " ~]")

                                                handlerName =
                                                    lowerCase stateName ++ "-scry-" ++ (path |> String.split "/" |> String.join "-")

                                                scryBody =
                                                    Hoon.HRaw ("[~ ~ %tas !>(" ++ handlerName ++ ")]")
                                            in
                                            ( pathPattern, scryBody )
                                        )

                            stateBody =
                                if List.isEmpty scryMatch then
                                    Hoon.HRaw "on-peek:def"

                                else
                                    Hoon.HMatch (loc (Hoon.HRaw "path")) scryMatch (Just (Hoon.HRaw "on-peek:def"))

                            finalBody =
                                if Dict.isEmpty config.data then
                                    stateBody

                                else
                                    Hoon.HLet "+*" (Hoon.HRaw "mode.state") stateBody
                        in
                        ( pattern, finalBody )
                    )

        body =
            Hoon.HMatch (loc (Hoon.HRaw "state")) stateMatches (Just (Hoon.HRaw "on-peek:def"))
    in
    Hoon.HoonArm "on-peek" (Hoon.HGate [ ( "path=path", Hoon.MRaw "path" ) ] body)


lowerOnPoke : Source.Program -> Hoon.HoonArm
lowerOnPoke prog =
    let
        markMatch =
            prog.pokes
                |> Dict.toList
                |> List.map
                    (\( name, def ) ->
                        let
                            mark =
                                case def.mark of
                                    Just m ->
                                        "%" ++ m

                                    Nothing ->
                                        "%tas"

                            call =
                                Hoon.HCall name [ loc (Hoon.HRaw "q.vase") ]
                        in
                        ( mark, call )
                    )

        body =
            Hoon.HMatch (loc (Hoon.HRaw "mark")) markMatch (Just (Hoon.HRaw "on-poke:def"))
    in
    Hoon.HoonArm "on-poke" (Hoon.HGate [ ( "mark=@tas", Hoon.MAtom ), ( "vase=vase", Hoon.MRaw "vase" ) ] body)


lowerOnWatch : Source.Program -> Hoon.HoonArm
lowerOnWatch prog =
    let
        watchMatch =
            prog.watches
                |> Dict.toList
                |> List.map
                    (\( path, watchBody ) ->
                        let
                            pattern =
                                path
                                    |> String.split "/"
                                    |> List.filter (not << String.isEmpty)
                                    |> List.map (\s -> "%" ++ s)
                                    |> (\parts -> "[" ++ String.join " " parts ++ " ~]")
                        in
                        ( pattern, lowerExpr prog.options watchBody )
                    )

        body =
            Hoon.HMatch (loc (Hoon.HRaw "path")) watchMatch (Just (Hoon.HRaw "on-watch:def"))
    in
    Hoon.HoonArm "on-watch" (Hoon.HGate [ ( "path=path", Hoon.MRaw "path" ) ] body)


lowerOnPeek : Source.Program -> Hoon.HoonArm
lowerOnPeek prog =
    let
        scryMatch =
            prog.scries
                |> Dict.toList
                |> List.map
                    (\( path, def ) ->
                        let
                            pattern =
                                path
                                    |> String.split "/"
                                    |> List.filter (not << String.isEmpty)
                                    |> List.map (\s -> "%" ++ s)
                                    |> (\parts -> "[" ++ String.join " " parts ++ " ~]")

                            scryBody =
                                Hoon.HRaw ("[~ ~ %tas !>(" ++ renderHoonExprForRaw (lowerExpr prog.options def.body) ++ ")]")
                        in
                        ( pattern, scryBody )
                    )

        body =
            Hoon.HMatch (loc (Hoon.HRaw "path")) scryMatch (Just (Hoon.HRaw "on-peek:def"))
    in
    Hoon.HoonArm "on-peek" (Hoon.HGate [ ( "path=path", Hoon.MRaw "path" ) ] body)


lowerTypes : Source.Program -> List Hoon.HoonArm
lowerTypes prog =
    prog.types
        |> Dict.toList
        |> List.map
            (\( name, def ) ->
                Hoon.HoonArm name (lowerTypeDef prog.options def)
            )


lowerTypeDef : Source.Options -> Source.TypeDef -> Hoon.HoonExpr
lowerTypeDef opts def =
    case def of
        Source.Alias tr ->
            Hoon.HRaw (moldToString (lowerTypeRef opts tr))

        Source.Record fields ->
            let
                renderedFields =
                    fields
                        |> Dict.toList
                        |> List.map (\( k, v ) -> k ++ "=" ++ moldToString (lowerTypeRef opts v))
                        |> String.join " "
            in
            Hoon.HRaw (",[" ++ renderedFields ++ "]")

        Source.Union variants ->
            let
                renderedVariants =
                    variants
                        |> Dict.toList
                        |> List.map
                            (\( name, mFields ) ->
                                let
                                    tagName =
                                        "%" ++ camelToKebab name
                                 in
                                case mFields of
                                    Just fields ->
                                        let
                                            renderedFields =
                                                fields
                                                    |> Dict.toList
                                                    |> List.map (\( k, v ) -> k ++ "=" ++ moldToString (lowerTypeRef opts v))
                                                    |> String.join " "
                                        in
                                        "[" ++ tagName ++ " " ++ renderedFields ++ "]"

                                    Nothing ->
                                        tagName
                            )
                        |> String.join " "
            in
            Hoon.HRaw ("$%( " ++ renderedVariants ++ " )")


camelToKebab : String -> String
camelToKebab s =
    let
        chars =
            String.toList s

        helper cs =
            case cs of
                [] ->
                    []

                x :: xs ->
                    if Char.isUpper x then
                        '-' :: Char.toLower x :: helper xs

                    else
                        x :: helper xs
    in
    case chars of
        [] ->
            ""

        x :: xs ->
            let
                res =
                    String.fromList (Char.toLower x :: helper xs)
            in
            if String.startsWith "-" res then
                String.dropLeft 1 res

            else
                res


moldToString : Hoon.HoonMold -> String
moldToString mold =
    case mold of
        Hoon.MAtom ->
            "@"

        Hoon.MUnsigned ->
            "@ud"

        Hoon.MBool ->
            "?"

        Hoon.MCord ->
            "cord"

        Hoon.MTape ->
            "tape"

        Hoon.MList inner ->
            "(list " ++ moldToString inner ++ ")"

        Hoon.MPair a b ->
            "[" ++ moldToString a ++ " " ++ moldToString b ++ "]"

        Hoon.MRaw s ->
            s

        Hoon.MNamed s ->
            s


lowerConstants : Source.Program -> List Hoon.HoonArm
lowerConstants prog =
    prog.constants
        |> Dict.toList
        |> List.map
            (\( name, typedVe ) ->
                Hoon.HoonArm name (lowerTypedValueOrExpr prog.options typedVe)
            )


lowerTypedValueOrExpr : Source.Options -> Source.TypedValueOrExpr -> Hoon.HoonExpr
lowerTypedValueOrExpr opts tve =
    case tve.value of
        Source.Literal val ->
            lowerLiteral opts tve.type_ val

        Source.Computed le ->
            lowerExpr opts le

        Source.RawHoon s ->
            Hoon.HRaw s


lowerLiteral : Source.Options -> Maybe Source.TypeRef -> Source.LiteralValue -> Hoon.HoonExpr
lowerLiteral opts mType val =
    case val of
        Source.LitNumber s ->
            Hoon.HAtom s

        Source.LitText s ->
            case s of
                "" ->
                    Hoon.HRaw "~"

                _ ->
                    case opts.textRepresentation of
                        Source.Cord ->
                            Hoon.HCord s

                        Source.Tape ->
                            Hoon.HRaw ("\"" ++ s ++ "\"")

        Source.LitBool b ->
            Hoon.HBool b

        Source.LitList list ->
            case mType of
                Just tr ->
                    case resolveSourceType opts tr of
                        Source.TypePair a b ->
                            case list of
                                [ la, lb ] ->
                                    Hoon.HCell (lowerLiteral opts (Just a) la) (lowerLiteral opts (Just b) lb)

                                _ ->
                                    Hoon.HRaw ":: pair must have exactly 2 items"

                        _ ->
                            Hoon.HList (List.map (lowerLiteral opts Nothing) list)

                _ ->
                    Hoon.HList (List.map (lowerLiteral opts Nothing) list)

        Source.LitRecord typeName fields ->
            case Dict.get typeName opts.prog_context_types of
                Just (Source.Record fieldDefs) ->
                    let
                        orderedValues =
                            fieldDefs
                                |> Dict.keys
                                |> List.map
                                    (\fieldName ->
                                        case Dict.get fieldName fields of
                                            Just fieldVal ->
                                                lowerLiteral opts Nothing fieldVal

                                            Nothing ->
                                                Hoon.HRaw ":: missing field"
                                    )
                    in
                    lowerCellList (List.map loc orderedValues)

                _ ->
                    Hoon.HRaw (":: unknown record type " ++ typeName)

        Source.LitVariant typeName variantName fields ->
            let
                tagName =
                    Hoon.HRaw ("%" ++ camelToKebab variantName)
            in
            if Dict.isEmpty fields then
                tagName

            else
                case Dict.get typeName opts.prog_context_types of
                    Just (Source.Union variants) ->
                        case Dict.get variantName variants of
                            Just (Just fieldDefs) ->
                                let
                                    orderedValues =
                                        fieldDefs
                                            |> Dict.keys
                                            |> List.map
                                                (\fieldName ->
                                                    case Dict.get fieldName fields of
                                                        Just fieldVal ->
                                                            lowerLiteral opts Nothing fieldVal

                                                        Nothing ->
                                                            Hoon.HRaw ":: missing field"
                                                )
                                in
                                Hoon.HCell tagName (lowerCellList (List.map loc orderedValues))

                            _ ->
                                Hoon.HRaw (":: unknown variant " ++ variantName)

                    _ ->
                        Hoon.HRaw (":: unknown union type " ++ typeName)

        Source.LitObject obj ->
            lowerCellList (obj |> Dict.toList |> List.map (\( k, v ) -> loc (Hoon.HRaw (k ++ "=" ++ renderHoonExprForRaw (lowerLiteral opts Nothing v)))))


lowerCellList : List Hoon.LocatedHoonExpr -> Hoon.HoonExpr
lowerCellList exprs =
    case exprs of
        [] ->
            Hoon.HRaw "~"

        [ x ] ->
            x.expr

        x :: xs ->
            Hoon.HCell x.expr (lowerCellList xs)


lowerFunctions : Source.Program -> List Hoon.HoonArm
lowerFunctions prog =
    prog.functions
        |> Dict.toList
        |> List.map
            (\( name, def ) ->
                let
                    inputs =
                        def.input
                            |> List.map (\( k, v ) -> ( k, lowerTypeRef prog.options v ))

                    body =
                        lowerExpr prog.options def.body

                    gate =
                        if List.isEmpty def.type_args then
                            Hoon.HGate inputs body

                        else
                            Hoon.HRaw ("|*  " ++ renderWetGateInputs inputs ++ "\n" ++ indent (renderHoonExprForRaw body))

                    finalExpr =
                        case def.jet of
                            Just tag ->
                                Hoon.HRaw ("~%  %" ++ tag ++ "  ..  " ++ renderHoonExprForRaw gate)

                            Nothing ->
                                gate
                in
                Hoon.HoonArm name finalExpr
            )

renderWetGateInputs : List (String, Hoon.HoonMold) -> String
renderWetGateInputs inputs =
    case inputs of
        [] -> "*"
        [(name, _)] -> name ++ "=*"
        _ -> "[" ++ (List.map (\(n, _) -> n ++ "=*") inputs |> String.join " ") ++ "]"


lowerExpr : Source.Options -> Source.LocatedExpr -> Hoon.HoonExpr
lowerExpr opts le =
    case le.expr of
        Source.ENumber s ->
            Hoon.HAtom s

        Source.EText s ->
            case s of
                "" ->
                    Hoon.HRaw "~"

                _ ->
                    case opts.textRepresentation of
                        Source.Cord ->
                            Hoon.HCord s

                        Source.Tape ->
                            Hoon.HRaw ("\"" ++ s ++ "\"")

        Source.EInterpolated fragments ->
            lowerInterpolated opts fragments

        Source.EBool b ->
            Hoon.HBool b

        Source.EName s ->
            Hoon.HName s

        Source.EField e f ->
            Hoon.HField (lowerExpr opts e |> loc) f

        Source.EList list ->
            Hoon.HList (List.map (lowerExpr opts) list)

        Source.ECall name args ->
            lowerCall opts name args

        Source.ERecord typeName fields ->
            case Dict.get typeName opts.prog_context_types of
                Just (Source.Record fieldDefs) ->
                    let
                        orderedValues =
                            fieldDefs
                                |> Dict.keys
                                |> List.map
                                    (\fieldName ->
                                        case Dict.get fieldName fields of
                                            Just fieldExpr ->
                                                lowerExpr opts fieldExpr

                                            Nothing ->
                                                Hoon.HRaw ":: missing field"
                                    )
                    in
                    lowerCellList (List.map loc orderedValues)

                _ ->
                    Hoon.HRaw (":: unknown record type " ++ typeName)

        Source.EVariant typeName variantName fields ->
            let
                tagName =
                    Hoon.HRaw ("%" ++ camelToKebab variantName)
            in
            if Dict.isEmpty fields then
                tagName

            else
                case Dict.get typeName opts.prog_context_types of
                    Just (Source.Union variants) ->
                        case Dict.get variantName variants of
                            Just (Just fieldDefs) ->
                                let
                                    orderedValues =
                                        fieldDefs
                                            |> Dict.keys
                                            |> List.map
                                                (\fieldName ->
                                                    case Dict.get fieldName fields of
                                                        Just fieldExpr ->
                                                            lowerExpr opts fieldExpr

                                                        Nothing ->
                                                            Hoon.HRaw ":: missing field"
                                                )
                                in
                                Hoon.HCell tagName (lowerCellList (List.map loc orderedValues))

                            _ ->
                                Hoon.HRaw (":: unknown variant " ++ variantName)

                    _ ->
                        Hoon.HRaw (":: unknown union type " ++ typeName)

        Source.EDict fields ->
            lowerCellList (fields |> Dict.toList |> List.map (\( k, v ) -> loc (Hoon.HRaw (k ++ "=" ++ renderHoonExprForRaw (lowerExpr opts v)))))

        Source.ERune r args ->
            Hoon.HRune r (List.map (lowerExpr opts) args)

        Source.ELoop args body ->
            let
                bodyHoon =
                    lowerExpr opts body

                initialArgs =
                    if Dict.isEmpty args then
                        Nothing

                    else
                        Just (lowerExpr opts { pos = body.pos, expr = Source.EDict args })
            in
            Hoon.HLoop (Maybe.map loc initialArgs) bodyHoon

        Source.ELet name val body ->
            Hoon.HLet name (lowerExpr opts val) (lowerExpr opts body)

        Source.ESet name val body ->
            Hoon.HSet name (lowerExpr opts val) (lowerExpr opts body)

        Source.EAssert cond body ->
            Hoon.HAssert (lowerExpr opts cond) (lowerExpr opts body)

        Source.EUnless cond body ->
            Hoon.HUnless (lowerExpr opts cond) (lowerExpr opts body)

        Source.ECast t e ->
            Hoon.HCast (lowerTypeRef opts t) (lowerExpr opts e)

        Source.EMatch target cases mDefault ->
            let
                renderedCases =
                    cases
                        |> Dict.toList
                        |> List.map
                            (\( k, v ) ->
                                let
                                    pattern =
                                        if isUppercase k then
                                            let
                                                kebab =
                                                    camelToKebab k

                                                hasFields =
                                                    opts.prog_context_types
                                                        |> Dict.values
                                                        |> List.filterMap
                                                            (\def ->
                                                                case def of
                                                                    Source.Union variants ->
                                                                        Dict.get k variants

                                                                    _ ->
                                                                        Nothing
                                                            )
                                                        |> List.head
                                                        |> Maybe.andThen identity
                                                        |> Maybe.map (\_ -> True)
                                                        |> Maybe.withDefault False
                                            in
                                            if hasFields then
                                                "[%" ++ kebab ++ " *]"

                                            else
                                                "%" ++ kebab

                                        else
                                            k
                                in
                                ( pattern, lowerExpr opts v )
                            )

                defaultExpr =
                    case mDefault of
                        Just d ->
                            Just (lowerExpr opts d)

                        Nothing ->
                            Nothing
            in
            Hoon.HMatch (loc (lowerExpr opts target)) renderedCases defaultExpr

        Source.EBinary op left right ->
            lowerBinary opts op left right

        Source.EIf cond then_ else_ ->
            Hoon.HIf (lowerExpr opts cond) (lowerExpr opts then_) (lowerExpr opts else_)

        Source.EIfNot cond then_ else_ ->
            Hoon.HIfNot (lowerExpr opts cond) (lowerExpr opts then_) (lowerExpr opts else_)

        Source.ETransition t ->
            let
                tagName =
                    "%" ++ camelToKebab t.to

                dataFields =
                    t.data
                        |> Dict.toList
                        |> List.map (\( k, v ) -> k ++ "=" ++ renderHoonExprForRaw (lowerExpr opts v))
                        |> String.join " "

                modeExpr =
                    if String.isEmpty dataFields then
                        tagName

                    else
                        "[" ++ tagName ++ " " ++ dataFields ++ "]"

                commonUpdates =
                    case t.common of
                        Just updates ->
                            updates
                                |> Dict.toList
                                |> List.map (\( k, v ) -> k ++ "=" ++ renderHoonExprForRaw (lowerExpr opts v))
                                |> String.join ", "

                        Nothing ->
                            ""

                stateUpdate =
                    if String.isEmpty commonUpdates then
                        "state(mode " ++ modeExpr ++ ")"

                    else
                        "state(mode " ++ modeExpr ++ ", " ++ commonUpdates ++ ")"
            in
            Hoon.HCell (Hoon.HList []) (Hoon.HRaw stateUpdate)

        Source.ERawHoon s ->
            Hoon.HRaw s


lowerInterpolated : Source.Options -> List Source.LocatedExpr -> Hoon.HoonExpr
lowerInterpolated opts fragments =
    case fragments of
        [] ->
            Hoon.HCord ""

        [ f ] ->
            lowerStringFragment opts f

        fs ->
            case fs of
                f :: rest ->
                    Hoon.HCall "cat" [ loc (Hoon.HAtom "3"), loc (lowerStringFragment opts f), loc (lowerInterpolated opts rest) ]

                [] ->
                    Hoon.HCord ""


lowerStringFragment : Source.Options -> Source.LocatedExpr -> Hoon.HoonExpr
lowerStringFragment opts le =
    case le.expr of
        Source.EText s ->
            Hoon.HCord s

        Source.ENumber s ->
            Hoon.HCall "scot" [ loc (Hoon.HRaw "%ud"), loc (Hoon.HAtom s) ]

        _ ->
            Hoon.HCall "scot" [ loc (Hoon.HRaw "%t"), loc (lowerExpr opts le) ]


renderHoonExprForRaw : Hoon.HoonExpr -> String
renderHoonExprForRaw he =
    case he of
        Hoon.HAtom s ->
            s

        Hoon.HCord s ->
            "'" ++ s ++ "'"

        Hoon.HBool b ->
            if b then
                "%.y"

            else
                "%.n"

        Hoon.HName s ->
            s

        Hoon.HCell a b ->
            "[" ++ renderHoonExprForRaw a ++ " " ++ renderHoonExprForRaw b ++ "]"

        Hoon.HList list ->
            if List.isEmpty list then
                "~"

            else
                "~[" ++ (List.map renderHoonExprForRaw list |> String.join " ") ++ "]"

        Hoon.HCall name args ->
            if name == "=" then
                "=(" ++ (List.map (\ale -> renderHoonExprForRaw ale.expr) args |> String.join " ") ++ ")"

            else if name == "$" then
                "$(" ++ (List.map (\ale -> renderHoonExprForRaw ale.expr) args |> String.join " ") ++ ")"

            else
                "(" ++ name ++ " " ++ (List.map (\ale -> renderHoonExprForRaw ale.expr) args |> String.join " ") ++ ")"

        Hoon.HField e f ->
            f ++ "." ++ renderHoonExprForRaw e.expr

        Hoon.HCast m e ->
            "^-(" ++ moldToString m ++ " " ++ renderHoonExprForRaw e ++ ")"

        Hoon.HRune r args ->
            if List.isEmpty args then
                r

            else
                let
                    argsStr =
                        List.map renderHoonExprForRaw args
                in
                r ++ "(" ++ String.join " " argsStr ++ ")"

        Hoon.HIf cond then_ else_ ->
            "?:(" ++ renderHoonExprForRaw cond ++ " " ++ renderHoonExprForRaw then_ ++ " " ++ renderHoonExprForRaw else_ ++ ")"

        Hoon.HIfNot cond then_ else_ ->
            "?.(" ++ renderHoonExprForRaw cond ++ " " ++ renderHoonExprForRaw then_ ++ " " ++ renderHoonExprForRaw else_ ++ ")"

        Hoon.HGate inputs body ->
            "|=(" ++ (List.map (\( n, m ) -> n ++ "=" ++ moldToString m) inputs |> String.join " ") ++ " " ++ renderHoonExprForRaw body ++ ")"

        Hoon.HLet name val body ->
            "=+(" ++ name ++ "=" ++ renderHoonExprForRaw val ++ " " ++ renderHoonExprForRaw body ++ ")"

        Hoon.HSet name val body ->
            "=.(" ++ name ++ " " ++ renderHoonExprForRaw val ++ " " ++ renderHoonExprForRaw body ++ ")"

        Hoon.HAssert cond body ->
            "?>(" ++ renderHoonExprForRaw cond ++ " " ++ renderHoonExprForRaw body ++ ")"

        Hoon.HUnless cond body ->
            "?<(" ++ renderHoonExprForRaw cond ++ " " ++ renderHoonExprForRaw body ++ ")"

        Hoon.HLoop mArgs body ->
            case mArgs of
                Just args ->
                    "=+(" ++ renderHoonExprForRaw args.expr ++ " |-(" ++ renderHoonExprForRaw body ++ "))"

                Nothing ->
                    "|-(" ++ renderHoonExprForRaw body ++ ")"

        Hoon.HMatch target cases mDefault ->
            let
                d =
                    case mDefault of
                        Just def ->
                            renderHoonExprForRaw def

                        Nothing ->
                            "!!"

                c =
                    cases
                        |> List.map (\( k, v ) -> k ++ " " ++ renderHoonExprForRaw v)
                        |> String.join " "
            in
            "?+(" ++ renderHoonExprForRaw target.expr ++ " " ++ d ++ " " ++ c ++ ")"

        Hoon.HRaw s ->
            s


isUppercase : String -> Bool
isUppercase s =
    let
        first =
            String.left 1 s
    in
    first == String.toUpper first && first /= String.toLower first


resolveSourceType : Source.Options -> Source.TypeRef -> Source.TypeRef
resolveSourceType opts tr =
    case tr of
        Source.TypeNamed "any" ->
            Source.TypeRawHoon "any"

        Source.TypeNamed name ->
            case Dict.get name opts.prog_context_types of
                Just (Source.Alias inner) ->
                    resolveSourceType opts inner

                _ ->
                    tr

        _ ->
            tr


inferSourceExprType : Source.Options -> Source.LocatedExpr -> Result String Source.TypeRef
inferSourceExprType opts le =
    case le.expr of
        Source.EName name ->
            case Dict.get name opts.prog_context_types of
                Just (Source.Alias tr) ->
                    Ok (resolveSourceType opts tr)

                _ ->
                    Ok Source.TypeNumber

        _ ->
            Ok Source.TypeNumber


lowerCall : Source.Options -> String -> List Source.LocatedExpr -> Hoon.HoonExpr
lowerCall opts name args =
    if name == "first" then
        case args of
            [ arg ] ->
                Hoon.HField (lowerExpr opts arg |> loc) "i"

            _ ->
                Hoon.HCall name (List.map (lowerExpr opts >> loc) args)

    else if name == "rest" then
        case args of
            [ arg ] ->
                Hoon.HField (lowerExpr opts arg |> loc) "t"

            _ ->
                Hoon.HCall name (List.map (lowerExpr opts >> loc) args)

    else if name == "prepend" then
        case args of
            [ item, list ] ->
                Hoon.HCell (lowerExpr opts item) (lowerExpr opts list)

            _ ->
                Hoon.HCall name (List.map (lowerExpr opts >> loc) args)

    else if name == "pure" then
        case args of
            [ arg ] ->
                Hoon.HCell (Hoon.HList []) (lowerExpr opts arg)

            _ ->
                Hoon.HCall name (List.map (lowerExpr opts >> loc) args)

    else if name == "cell" then
        case args of
            [ a, b ] ->
                Hoon.HCell (lowerExpr opts a) (lowerExpr opts b)

            _ ->
                Hoon.HCall name (List.map (lowerExpr opts >> loc) args)

    else if name == "unit" then
        case args of
            [ arg ] ->
                Hoon.HCell (Hoon.HList []) (lowerExpr opts arg)

            [] ->
                Hoon.HList []

            _ ->
                Hoon.HCall name (List.map (lowerExpr opts >> loc) args)

    else if name == "length" then
        Hoon.HCall "lent" (List.map (lowerExpr opts >> loc) args)

    else if name == "append" then
        Hoon.HCall "snoc" (List.map (lowerExpr opts >> loc) args)

    else if name == "map" then
        Hoon.HCall "turn" (List.map (lowerExpr opts >> loc) args)

    else if name == "filter" then
        Hoon.HCall "skim" (List.map (lowerExpr opts >> loc) args)

    else if name == "fold" then
        Hoon.HCall "roll" (List.map (lowerExpr opts >> loc) args)

    else if name == "give" then
        case args of
            [ path, gift ] ->
                Hoon.HRaw ("[%give " ++ renderHoonExprForRaw (lowerExpr opts path) ++ " " ++ renderHoonExprForRaw (lowerExpr opts gift) ++ "]")

            _ ->
                Hoon.HCall name (List.map (lowerExpr opts >> loc) args)

    else if name == "init" then
        case args of
            [ door, sample ] ->
                Hoon.HRune "~." [ lowerExpr opts door, lowerExpr opts sample ]

            _ ->
                Hoon.HCall name (List.map (lowerExpr opts >> loc) args)

    else if name == "my" then
        case args of
            [ list ] ->
                Hoon.HCall "my" [ lowerExpr opts list |> loc ]

            _ ->
                Hoon.HCall name (List.map (lowerExpr opts >> loc) args)

    else if name == "recurse" then
        Hoon.HCall "$" (List.map (lowerExpr opts >> loc) args)

    else if name == "scry" then
        case args of
            [ m, p ] ->
                Hoon.HRune ".^" [ lowerExpr opts m, lowerExpr opts p ]

            _ ->
                Hoon.HCall name (List.map (lowerExpr opts >> loc) args)

    else if name == "get" then
        case args of
            [ coll, key ] ->
                Hoon.HRaw ("(~(get by " ++ renderHoonExprForRaw (lowerExpr opts coll) ++ ") " ++ renderHoonExprForRaw (lowerExpr opts key) ++ ")")

            _ ->
                Hoon.HCall name (List.map (lowerExpr opts >> loc) args)

    else if name == "put" then
        case args of
            [ coll, key, val ] ->
                Hoon.HRaw ("(~(put by " ++ renderHoonExprForRaw (lowerExpr opts coll) ++ ") " ++ renderHoonExprForRaw (lowerExpr opts key) ++ " " ++ renderHoonExprForRaw (lowerExpr opts val) ++ ")")

            _ ->
                Hoon.HCall name (List.map (lowerExpr opts >> loc) args)

    else if name == "has" then
        case args of
            [ coll, key ] ->
                let
                    isSet =
                        case inferSourceExprType opts coll of
                            Ok (Source.TypeSet _) ->
                                True

                            _ ->
                                False

                    engine =
                        if isSet then
                            "in"

                        else
                            "by"
                 in
                Hoon.HRaw ("(~(has " ++ engine ++ " " ++ renderHoonExprForRaw (lowerExpr opts coll) ++ ") " ++ renderHoonExprForRaw (lowerExpr opts key) ++ ")")

            _ ->
                Hoon.HCall name (List.map (lowerExpr opts >> loc) args)

    else if name == "nock" then
        case args of
            [ formula ] ->
                Hoon.HRune ".~" [ lowerExpr opts formula ]

            _ ->
                Hoon.HCall name (List.map (lowerExpr opts >> loc) args)

    else
        Hoon.HCall name (List.map (lowerExpr opts >> loc) args)


lowerBinary : Source.Options -> Source.BinaryOp -> Source.LocatedExpr -> Source.LocatedExpr -> Hoon.HoonExpr
lowerBinary opts op left right =
    let
        l =
            lowerExpr opts left

        r =
            lowerExpr opts right
    in
    case op of
        Source.Add ->
            Hoon.HCall "add" [ loc l, loc r ]

        Source.Sub ->
            Hoon.HCall "sub" [ loc l, loc r ]

        Source.Mul ->
            Hoon.HCall "mul" [ loc l, loc r ]

        Source.Eq ->
            Hoon.HCall "=" [ loc l, loc r ]

        Source.NotEq ->
            Hoon.HCall "not" [ loc (Hoon.HCall "=" [ loc l, loc r ]) ]

        Source.GreaterThan ->
            Hoon.HCall "gth" [ loc l, loc r ]

        Source.LessThan ->
            Hoon.HCall "lth" [ loc l, loc r ]

        Source.GreaterOrEqual ->
            Hoon.HCall "gte" [ loc l, loc r ]

        Source.LessOrEqual ->
            Hoon.HCall "lte" [ loc l, loc r ]


lowerTypeRef : Source.Options -> Source.TypeRef -> Hoon.HoonMold
lowerTypeRef opts tr =
    case tr of
        Source.TypeNumber ->
            case opts.numberRepresentation of
                Source.Atom ->
                    Hoon.MAtom

                Source.UnsignedDecimal ->
                    Hoon.MUnsigned

        Source.TypeNat ->
            Hoon.MUnsigned

        Source.TypeText ->
            case opts.textRepresentation of
                Source.Cord ->
                    Hoon.MCord

                Source.Tape ->
                    Hoon.MTape

        Source.TypeBool ->
            Hoon.MBool

        Source.TypeList t ->
            Hoon.MList (lowerTypeRef opts t)

        Source.TypePair a b ->
            Hoon.MPair (lowerTypeRef opts a) (lowerTypeRef opts b)

        Source.TypeQuip a b ->
            Hoon.MRaw ("(quip " ++ moldToString (lowerTypeRef opts a) ++ " " ++ moldToString (lowerTypeRef opts b) ++ ")")

        Source.TypeCard ->
            Hoon.MRaw "card"

        Source.TypeUnit t ->
            Hoon.MRaw ("(unit " ++ moldToString (lowerTypeRef opts t) ++ ")")

        Source.TypeMap k v ->
            Hoon.MRaw ("(map " ++ moldToString (lowerTypeRef opts k) ++ " " ++ moldToString (lowerTypeRef opts v) ++ ")")

        Source.TypeSet t ->
            Hoon.MRaw ("(set " ++ moldToString (lowerTypeRef opts t) ++ ")")

        Source.TypeNamed s ->
            Hoon.MNamed s

        Source.TypeRawHoon s ->
            Hoon.MRaw s


loc : Hoon.HoonExpr -> Hoon.LocatedHoonExpr
loc e =
    { pos = { line = 0, col = 0 }, expr = e }


indent : String -> String
indent s =
    s
        |> String.split "\n"
        |> List.map (\line -> "  " ++ line)
        |> String.join "\n"
