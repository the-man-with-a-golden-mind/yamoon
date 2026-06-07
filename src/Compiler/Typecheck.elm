module Compiler.Typecheck exposing (check)

import Dict exposing (Dict)
import Source.Ast as Source
import Source.StandardLibrary as StdLib


type Error
    = UnknownName Context String
    | UnknownType Context String
    | UnknownFunction Context String
    | ArityMismatch Context String Int Int
    | TypeMismatch Context Source.TypeRef Source.TypeRef
    | NotARecord Context Source.TypeRef
    | NotAUnion Context Source.TypeRef
    | MissingField Context String String
    | UnknownVariant Context String String
    | UnknownPokeRoute Context String
    | MissingTestSubject Context String
    | GenericConflict Context String Source.TypeRef Source.TypeRef
    | UnboundGeneric Context String
    | TransitionToUnknownState Context String
    | MissingStateData Context String String
    | NonExhaustiveMatch Context String


check : Source.Program -> Result (List String) ()
check prog =
    let
        baseLocalVars =
            case prog.state of
                Just _ ->
                    Dict.singleton "state" (Source.TypeNamed "state")

                Nothing ->
                    Dict.empty

        ctxTypes =
            case prog.state of
                Just s ->
                    Dict.insert "state" (Source.Record s.fields) prog.types

                Nothing ->
                    prog.types

        allNatives =
            Dict.union prog.native StdLib.standardNatives

        ctx =
            { types = ctxTypes
            , constants = prog.constants
            , functions = prog.functions
            , native = allNatives
            , localVars = baseLocalVars
            , typeArgs = []
            , typeBindings = Dict.empty
            , machine = prog.machine
            , path = []
            , currentPos = { line = 0, col = 0 }
            }

        errors =
            List.concat
                [ checkConstants ctx
                , checkFunctions ctx
                , checkOnLoad ctx prog.onLoad
                , checkWatches ctx prog.watches
                , checkPokes ctx prog.pokes
                , checkTests ctx prog.tests
                , checkMachine ctx
                ]
    in
    if List.isEmpty errors then
        Ok ()

    else
        Err (List.map errorToString errors)


type alias Context =
    { types : Dict String Source.TypeDef
    , constants : Dict String Source.TypedValueOrExpr
    , functions : Dict String Source.FunctionDef
    , native : Dict String Source.NativeDef
    , localVars : Dict String Source.TypeRef
    , typeArgs : List String
    , typeBindings : Dict String Source.TypeRef
    , machine : Maybe Source.MachineDef
    , path : List String
    , currentPos : Source.Pos
    }


checkConstants : Context -> List Error
checkConstants ctx =
    ctx.constants
        |> Dict.toList
        |> List.map (\( name, tve ) -> checkTypedValueOrExpr { ctx | path = [ "constants", name ], localVars = Dict.empty } tve)
        |> List.concat


checkFunctions : Context -> List Error
checkFunctions ctx =
    ctx.functions
        |> Dict.toList
        |> List.map (\( name, def ) -> checkFunction { ctx | path = [ "functions", name ] } name def)
        |> List.concat


checkOnLoad : Context -> Maybe Source.LocatedExpr -> List Error
checkOnLoad ctx mLe =
    case mLe of
        Just le ->
            case inferExprType { ctx | path = [ "on_load" ], localVars = Dict.empty } le of
                Ok _ ->
                    []

                Err err ->
                    [ err ]

        Nothing ->
            []


checkWatches : Context -> Dict String Source.LocatedExpr -> List Error
checkWatches ctx watches =
    watches
        |> Dict.toList
        |> List.map (\( path, le ) -> checkExpr { ctx | path = [ "watches", path ] } le)
        |> List.concat


checkPokes : Context -> Dict String Source.PokeDef -> List Error
checkPokes ctx pokes =
    pokes
        |> Dict.toList
        |> List.map (\( name, def ) -> checkPoke { ctx | path = [ "pokes", name ] } def)
        |> List.concat


checkMachine : Context -> List Error
checkMachine ctx =
    case ctx.machine of
        Just machine ->
            let
                initialErrors =
                    case Dict.get machine.initial.to machine.states of
                        Just stateDef ->
                            checkTransitionData { ctx | path = [ "machine", "initial" ] } machine.initial.to stateDef.data machine.initial.data

                        Nothing ->
                            [ TransitionToUnknownState { ctx | path = [ "machine", "initial" ] } machine.initial.to ]

                statesErrors =
                    machine.states
                        |> Dict.toList
                        |> List.map (\( name, config ) -> checkStateConfig { ctx | path = [ "machine", "states", name ] } machine name config)
                        |> List.concat
            in
            initialErrors ++ statesErrors

        Nothing ->
            []


checkTransitionData : Context -> String -> Dict String Source.TypeRef -> Dict String Source.LocatedExpr -> List Error
checkTransitionData ctx stateName expectedFields providedFields =
    let
        missingFields =
            Dict.keys expectedFields
                |> List.filter (\k -> not (Dict.member k providedFields))
                |> List.map (MissingStateData ctx stateName)

        typeErrors =
            providedFields
                |> Dict.toList
                |> List.map
                    (\( k, v ) ->
                        case Dict.get k expectedFields of
                            Just expectedType ->
                                case inferExprType ctx v of
                                    Ok actualType ->
                                        if typesEqual ctx actualType expectedType then
                                            []

                                        else
                                            [ TypeMismatch { ctx | currentPos = v.pos } expectedType actualType ]

                                    Err err ->
                                        [ err ]

                            Nothing ->
                                []
                    )
                |> List.concat
    in
    missingFields ++ typeErrors


checkStateConfig : Context -> Source.MachineDef -> String -> Source.StateConfig -> List Error
checkStateConfig ctx machine name config =
    let
        stateLocalVars =
            Dict.union machine.common config.data

        newCtx =
            { ctx | localVars = Dict.union stateLocalVars ctx.localVars }

        pokesErrors =
            config.pokes
                |> Dict.toList
                |> List.map (\( pokeName, def ) -> checkPoke { newCtx | path = ctx.path ++ [ "pokes", pokeName ] } def)
                |> List.concat

        scriesErrors =
            config.scries
                |> Dict.toList
                |> List.map (\( scryPath, def ) -> checkScry { newCtx | path = ctx.path ++ [ "scries", scryPath ] } def)
                |> List.concat

        watchesErrors =
            config.watches
                |> Dict.toList
                |> List.map (\( watchPath, le ) -> checkExpr { newCtx | path = ctx.path ++ [ "watches", watchPath ] } le)
                |> List.concat
    in
    pokesErrors ++ scriesErrors ++ watchesErrors


checkScry : Context -> Source.ScryDef -> List Error
checkScry ctx def =
    let
        newCtx =
            { ctx | path = ctx.path ++ [ "return" ] }
    in
    case inferExprType newCtx def.body of
        Ok t ->
            if typesEqual ctx t def.output then
                []

            else
                [ TypeMismatch { newCtx | currentPos = def.body.pos } def.output t ]

        Err err ->
            [ err ]


checkPoke : Context -> Source.PokeDef -> List Error
checkPoke ctx def =
    let
        newLocalVars =
            List.foldl (\( k, v ) acc -> Dict.insert k v acc) ctx.localVars def.input

        newCtx =
            { ctx | localVars = newLocalVars, path = ctx.path ++ [ "return" ] }
    in
    case inferExprType newCtx def.body of
        Ok _ ->
            []

        Err err ->
            [ err ]


checkTests : Context -> Dict String Source.TestDef -> List Error
checkTests ctx tests =
    tests
        |> Dict.toList
        |> List.map (\( name, def ) -> checkTest { ctx | path = [ "tests", name ] } def)
        |> List.concat


checkTest : Context -> Source.TestDef -> List Error
checkTest ctx testDef =
    case testDef of
        Source.UnitTest data ->
            case Dict.get data.func ctx.functions of
                Just _ ->
                    []

                Nothing ->
                    [ UnknownFunction ctx data.func ]

        Source.ScenarioTest data ->
            List.concatMap (checkScenarioStep ctx) data.steps

        Source.MigrationTest _ ->
            []


checkScenarioStep : Context -> Source.ScenarioStep -> List Error
checkScenarioStep _ _ =
    []


checkExpr : Context -> Source.LocatedExpr -> List Error
checkExpr ctx le =
    case inferExprType ctx le of
        Ok _ ->
            []

        Err err ->
            [ err ]


checkFunction : Context -> String -> Source.FunctionDef -> List Error
checkFunction ctx _ def =
    let
        newLocalVars =
            List.foldl (\( k, v ) acc -> Dict.insert k v acc) Dict.empty def.input

        newCtx =
            { ctx | localVars = newLocalVars, path = ctx.path ++ [ "return" ], typeArgs = def.type_args }

        returnTypeResult =
            inferExprType newCtx def.body
    in
    case returnTypeResult of
        Ok returnType ->
            if typesEqual ctx returnType def.output then
                []

            else
                [ TypeMismatch { newCtx | currentPos = def.body.pos } def.output returnType ]

        Err err ->
            [ err ]


checkTypedValueOrExpr : Context -> Source.TypedValueOrExpr -> List Error
checkTypedValueOrExpr ctx tve =
    let
        valCtx =
            { ctx | path = ctx.path ++ [ "value" ] }
    in
    case tve.value of
        Source.Literal val ->
            case tve.type_ of
                Just t ->
                    let
                        inferred =
                            inferLiteralType ctx (Just t) val
                    in
                    if typesEqual ctx inferred t then
                        []

                    else
                        [ TypeMismatch { valCtx | currentPos = { line = 0, col = 0 } } t inferred ]

                Nothing ->
                    []

        Source.Computed le ->
            case inferExprType valCtx le of
                Ok actual ->
                    case tve.type_ of
                        Just t ->
                            if typesEqual ctx actual t then
                                []

                            else
                                [ TypeMismatch { valCtx | currentPos = le.pos } t actual ]

                        Nothing ->
                            []

                Err err ->
                    [ err ]

        Source.RawHoon _ ->
            []


inferExprType : Context -> Source.LocatedExpr -> Result Error Source.TypeRef
inferExprType ctx le =
    let
        newCtx =
            { ctx | currentPos = le.pos }
    in
    case le.expr of
        Source.ENumber _ ->
            Ok Source.TypeNumber

        Source.EText _ ->
            Ok Source.TypeText

        Source.EInterpolated _ ->
            Ok Source.TypeText

        Source.EBool _ ->
            Ok Source.TypeBool

        Source.EName name ->
            let
                realName =
                    dropCarets name
            in
            if List.member realName ctx.typeArgs then
                Ok (Source.TypeNamed realName)

            else
                case Dict.get realName ctx.localVars of
                    Just t ->
                        Ok t

                    Nothing ->
                        case Dict.get realName ctx.constants of
                            Just tve ->
                                case tve.type_ of
                                    Just t ->
                                        Ok t

                                    Nothing ->
                                        Ok (inferLiteralType ctx Nothing (extractLiteral tve.value))

                            _ ->
                                Err (UnknownName newCtx name)

        Source.EField e field ->
            case inferExprType ctx e of
                Ok tr ->
                    case resolveType ctx tr of
                        Source.TypeNamed typeName ->
                            case Dict.get typeName ctx.types of
                                Just (Source.Record fields) ->
                                    case Dict.get field fields of
                                        Just t ->
                                            Ok t

                                        Nothing ->
                                            Err (MissingField newCtx typeName field)

                                Just (Source.Union _) ->
                                    Ok (Source.TypeRawHoon "any")

                                _ ->
                                    Err (NotARecord newCtx (Source.TypeNamed typeName))

                        _ ->
                            Ok (Source.TypeRawHoon "any")

                Err err ->
                    Err err

        Source.EList list ->
            case list of
                [] ->
                    Ok (Source.TypeList (Source.TypeRawHoon "any"))

                x :: xs ->
                    case inferExprType ctx x of
                        Ok tx ->
                            let
                                checkElement : Source.LocatedExpr -> Result Error ()
                                checkElement el =
                                    case inferExprType ctx el of
                                        Ok tel ->
                                            if typesEqual ctx tel tx then
                                                Ok ()

                                            else
                                                Err (TypeMismatch { ctx | currentPos = el.pos } tx tel)

                                        Err err ->
                                            Err err
                            in
                            case List.foldl (\el res -> Result.andThen (\_ -> checkElement el) res) (Ok ()) xs of
                                Ok () ->
                                    Ok (Source.TypeList tx)

                                Err err ->
                                    Err err

                        Err err ->
                            Err err

        Source.ECall name args ->
            case Dict.get name ctx.functions of
                Just def ->
                    let
                        expectedArity =
                            List.length def.input

                        actualArity =
                            List.length args
                    in
                    if expectedArity /= actualArity then
                        Err (ArityMismatch newCtx name expectedArity actualArity)

                    else if not (List.isEmpty def.type_args) then
                        case instantiate ctx def.type_args (List.map Tuple.second def.input) args of
                            Ok bindings ->
                                case findUnbound def.type_args bindings of
                                    Just unbound ->
                                        Err (UnboundGeneric newCtx unbound)
                                    Nothing ->
                                        Ok (substitute bindings def.output)

                            Err err ->
                                Err err

                    else
                        case checkArgs ctx (List.map Tuple.second def.input) args of
                            Ok () ->
                                Ok def.output

                            Err err ->
                                Err err

                Nothing ->
                    case Dict.get name ctx.native of
                        Just nativeDef ->
                            let
                                expectedArity =
                                    List.length nativeDef.input

                                actualArity =
                                    List.length args
                            in
                            if expectedArity /= actualArity then
                                Err (ArityMismatch newCtx name expectedArity actualArity)

                            else if not (List.isEmpty nativeDef.type_args) then
                                case instantiate ctx nativeDef.type_args (List.map Tuple.second nativeDef.input) args of
                                    Ok bindings ->
                                        case findUnbound nativeDef.type_args bindings of
                                            Just unbound ->
                                                Err (UnboundGeneric newCtx unbound)
                                            Nothing ->
                                                Ok (substitute bindings nativeDef.output)

                                    Err err ->
                                        Err err

                            else
                                case checkArgs ctx (List.map Tuple.second nativeDef.input) args of
                                    Ok () ->
                                        Ok nativeDef.output

                                    Err err ->
                                        Err err

                        Nothing ->
                            checkBuiltin newCtx name args

        Source.ERecord typeName _ ->
            Ok (Source.TypeNamed typeName)

        Source.EVariant typeName variantName _ ->
            case Dict.get typeName ctx.types of
                Just (Source.Union variants) ->
                    case Dict.get variantName variants of
                        Just _ ->
                            Ok (Source.TypeNamed typeName)

                        Nothing ->
                            Err (UnknownVariant newCtx typeName variantName)

                _ ->
                    Err (NotAUnion newCtx (Source.TypeNamed typeName))

        Source.EDict fields ->
            case Dict.values fields of
                [] ->
                    Ok (Source.TypeMap Source.TypeText (Source.TypeRawHoon "any"))

                x :: _ ->
                    case inferExprType ctx x of
                        Ok tx ->
                            Ok (Source.TypeMap Source.TypeText tx)
                        
                        Err err ->
                            Err err

        Source.ERune _ args ->
            let
                _ =
                    List.map (inferExprType ctx) args
            in
            Ok (Source.TypeRawHoon "any")

        Source.ELoop args body ->
            let
                inferredArgs =
                    Dict.map (\_ expr -> Result.withDefault (Source.TypeRawHoon "any") (inferExprType ctx expr)) args
                    
                loopCtx =
                    { ctx | localVars = Dict.union inferredArgs ctx.localVars }
            in
            inferExprType loopCtx body

        Source.ELet name val body ->
            case inferExprType ctx val of
                Ok t ->
                    let
                        letCtx =
                            { ctx | localVars = Dict.insert name t ctx.localVars }
                    in
                    inferExprType letCtx body

                Err err ->
                    Err err

        Source.ESet name val body ->
            case ( Dict.get name ctx.localVars, inferExprType ctx val ) of
                ( Just t, Ok actual ) ->
                    if typesEqual ctx actual t then
                        inferExprType ctx body

                    else
                        Err (TypeMismatch newCtx t actual)

                _ ->
                    inferExprType ctx body

        Source.EAssert cond body ->
            case inferExprType ctx cond of
                Ok Source.TypeBool ->
                    inferExprType ctx body

                Ok t ->
                    Err (TypeMismatch { ctx | currentPos = cond.pos } Source.TypeBool t)

                Err err ->
                    Err err

        Source.EUnless cond body ->
            case inferExprType ctx cond of
                Ok Source.TypeBool ->
                    inferExprType ctx body

                Ok t ->
                    Err (TypeMismatch { ctx | currentPos = cond.pos } Source.TypeBool t)

                Err err ->
                    Err err

        Source.ECast t e ->
            case inferExprType ctx e of
                Ok actual ->
                    if typesEqual ctx actual t then
                        Ok t

                    else
                        Err (TypeMismatch newCtx t actual)

                Err err ->
                    Err err

        Source.EMatch target cases mDefault ->
            case inferExprType ctx target of
                Ok (Source.TypeNamed typeName) ->
                    case Dict.get typeName ctx.types of
                        Just (Source.Union variants) ->
                            let
                                providedVariants =
                                    Dict.keys cases

                                missingVariants =
                                    Dict.keys variants
                                        |> List.filter (\v -> not (List.member v providedVariants))

                                isExhaustive =
                                    List.isEmpty missingVariants || mDefault /= Nothing
                            in
                            if not isExhaustive then
                                Err (NonExhaustiveMatch newCtx (List.head missingVariants |> Maybe.withDefault ""))

                            else
                                let
                                    checkBranch : String -> Source.LocatedExpr -> Result Error Source.TypeRef
                                    checkBranch variantName body =
                                        let
                                            variantFields =
                                                Dict.get variantName variants
                                                    |> Maybe.andThen identity
                                                    |> Maybe.withDefault Dict.empty

                                            branchCtx =
                                                { ctx | localVars = Dict.union variantFields ctx.localVars }
                                        in
                                        inferExprType branchCtx body

                                    branches =
                                        Dict.toList cases
                                in
                                case branches of
                                    [] ->
                                        case mDefault of
                                            Just def ->
                                                inferExprType ctx def

                                            Nothing ->
                                                Ok (Source.TypeRawHoon "any")

                                    ( firstVar, firstBody ) :: rest ->
                                        case checkBranch firstVar firstBody of
                                            Ok tFirst ->
                                                let
                                                    checkOtherBranch : ( String, Source.LocatedExpr ) -> Result Error ()
                                                    checkOtherBranch ( var, bod ) =
                                                        case checkBranch var bod of
                                                            Ok tVar ->
                                                                if typesEqual ctx tVar tFirst then
                                                                    Ok ()

                                                                else
                                                                    Err (TypeMismatch { ctx | currentPos = bod.pos } tFirst tVar)

                                                            Err err ->
                                                                Err err
                                                in
                                                case List.foldl (\b res -> Result.andThen (\_ -> checkOtherBranch b) res) (Ok ()) rest of
                                                    Ok () ->
                                                        case mDefault of
                                                            Just def ->
                                                                case inferExprType ctx def of
                                                                    Ok tDef ->
                                                                        if typesEqual ctx tDef tFirst then
                                                                            Ok tFirst

                                                                        else
                                                                            Err (TypeMismatch { ctx | currentPos = def.pos } tFirst tDef)

                                                                    Err err ->
                                                                        Err err

                                                            Nothing ->
                                                                Ok tFirst

                                                    Err err ->
                                                        Err err

                                            Err err ->
                                                Err err

                        _ ->
                            Err (NotAUnion newCtx (Source.TypeNamed typeName))

                Ok t ->
                    Err (NotAUnion newCtx t)

                Err err ->
                    Err err

        Source.EBinary op left right ->
            case ( inferExprType ctx left, inferExprType ctx right ) of
                ( Ok tLeft, Ok tRight ) ->
                    case op of
                        Source.Eq ->
                            if typesEqual ctx tLeft tRight then
                                Ok Source.TypeBool
                            else
                                Err (TypeMismatch newCtx tLeft tRight)

                        Source.NotEq ->
                            if typesEqual ctx tLeft tRight then
                                Ok Source.TypeBool
                            else
                                Err (TypeMismatch newCtx tLeft tRight)

                        Source.GreaterThan ->
                            if not (typesEqual ctx tLeft Source.TypeNumber) then
                                Err (TypeMismatch { ctx | currentPos = left.pos } Source.TypeNumber tLeft)
                            else if not (typesEqual ctx tRight Source.TypeNumber) then
                                Err (TypeMismatch { ctx | currentPos = right.pos } Source.TypeNumber tRight)
                            else
                                Ok Source.TypeBool

                        Source.LessThan ->
                            if not (typesEqual ctx tLeft Source.TypeNumber) then
                                Err (TypeMismatch { ctx | currentPos = left.pos } Source.TypeNumber tLeft)
                            else if not (typesEqual ctx tRight Source.TypeNumber) then
                                Err (TypeMismatch { ctx | currentPos = right.pos } Source.TypeNumber tRight)
                            else
                                Ok Source.TypeBool

                        Source.GreaterOrEqual ->
                            if not (typesEqual ctx tLeft Source.TypeNumber) then
                                Err (TypeMismatch { ctx | currentPos = left.pos } Source.TypeNumber tLeft)
                            else if not (typesEqual ctx tRight Source.TypeNumber) then
                                Err (TypeMismatch { ctx | currentPos = right.pos } Source.TypeNumber tRight)
                            else
                                Ok Source.TypeBool

                        Source.LessOrEqual ->
                            if not (typesEqual ctx tLeft Source.TypeNumber) then
                                Err (TypeMismatch { ctx | currentPos = left.pos } Source.TypeNumber tLeft)
                            else if not (typesEqual ctx tRight Source.TypeNumber) then
                                Err (TypeMismatch { ctx | currentPos = right.pos } Source.TypeNumber tRight)
                            else
                                Ok Source.TypeBool

                        Source.Add ->
                            if not (typesEqual ctx tLeft Source.TypeNumber) then
                                Err (TypeMismatch { ctx | currentPos = left.pos } Source.TypeNumber tLeft)
                            else if not (typesEqual ctx tRight Source.TypeNumber) then
                                Err (TypeMismatch { ctx | currentPos = right.pos } Source.TypeNumber tRight)
                            else
                                Ok Source.TypeNumber

                        Source.Sub ->
                            if not (typesEqual ctx tLeft Source.TypeNumber) then
                                Err (TypeMismatch { ctx | currentPos = left.pos } Source.TypeNumber tLeft)
                            else if not (typesEqual ctx tRight Source.TypeNumber) then
                                Err (TypeMismatch { ctx | currentPos = right.pos } Source.TypeNumber tRight)
                            else
                                Ok Source.TypeNumber

                        Source.Mul ->
                            if not (typesEqual ctx tLeft Source.TypeNumber) then
                                Err (TypeMismatch { ctx | currentPos = left.pos } Source.TypeNumber tLeft)
                            else if not (typesEqual ctx tRight Source.TypeNumber) then
                                Err (TypeMismatch { ctx | currentPos = right.pos } Source.TypeNumber tRight)
                            else
                                Ok Source.TypeNumber

                ( Err err, _ ) ->
                    Err err

                ( _, Err err ) ->
                    Err err

        Source.EIf cond then_ else_ ->
            case inferExprType ctx cond of
                Ok Source.TypeBool ->
                    case ( inferExprType ctx then_, inferExprType ctx else_ ) of
                        ( Ok tThen, Ok tElse ) ->
                            if typesEqual ctx tThen tElse then
                                Ok tThen
                            else
                                Err (TypeMismatch newCtx tThen tElse)

                        ( Err err, _ ) ->
                            Err err

                        ( _, Err err ) ->
                            Err err

                Ok t ->
                    Err (TypeMismatch { ctx | currentPos = cond.pos } Source.TypeBool t)

                Err err ->
                    Err err

        Source.EIfNot cond then_ else_ ->
            case inferExprType ctx cond of
                Ok Source.TypeBool ->
                    case ( inferExprType ctx then_, inferExprType ctx else_ ) of
                        ( Ok tThen, Ok tElse ) ->
                            if typesEqual ctx tThen tElse then
                                Ok tThen
                            else
                                Err (TypeMismatch newCtx tThen tElse)

                        ( Err err, _ ) ->
                            Err err

                        ( _, Err err ) ->
                            Err err

                Ok t ->
                    Err (TypeMismatch { ctx | currentPos = cond.pos } Source.TypeBool t)

                Err err ->
                    Err err

        Source.ETransition t ->
            case ctx.machine of
                Just machine ->
                    case Dict.get t.to machine.states of
                        Just stateDef ->
                            let
                                dataErrors =
                                    checkTransitionData ctx t.to stateDef.data t.data

                                commonErrors =
                                    case t.common of
                                        Just commonUpdates ->
                                            checkTransitionData ctx "common" machine.common commonUpdates

                                        Nothing ->
                                            []

                                allErrors =
                                    dataErrors ++ commonErrors
                            in
                            if List.isEmpty allErrors then
                                Ok (Source.TypeRawHoon "any")

                            else
                                -- Returning the first error for simplicity in inferExprType
                                -- though we usually want to collect all. 
                                -- The checkMachine function collects all.
                                case List.head allErrors of
                                    Just err ->
                                        Err err

                                    Nothing ->
                                        Ok (Source.TypeRawHoon "any")

                        Nothing ->
                            Err (TransitionToUnknownState newCtx t.to)

                Nothing ->
                    Ok (Source.TypeRawHoon "any")

        Source.ERawHoon _ ->
            Ok (Source.TypeRawHoon "any")


instantiate : Context -> List String -> List Source.TypeRef -> List Source.LocatedExpr -> Result Error (Dict String Source.TypeRef)
instantiate ctx typeArgs expected actual =
    let
        unifyAll es as_ bindings =
            case ( es, as_ ) of
                ( [], [] ) ->
                    Ok bindings

                ( e :: restE, a :: restA ) ->
                    case inferExprType ctx a of
                        Ok actualType ->
                            case unify ctx typeArgs e actualType bindings of
                                Ok nextBindings ->
                                    unifyAll restE restA nextBindings

                                Err err ->
                                    Err err

                        Err err ->
                            Err err

                _ ->
                    Ok bindings
    in
    unifyAll expected actual Dict.empty


unify : Context -> List String -> Source.TypeRef -> Source.TypeRef -> Dict String Source.TypeRef -> Result Error (Dict String Source.TypeRef)
unify ctx typeArgs expected actual bindings =
    case ( expected, actual ) of
        ( Source.TypeNamed name, _ ) ->
            if List.member name typeArgs then
                case Dict.get name bindings of
                    Just existing ->
                        if typesEqual ctx existing actual then
                            Ok bindings

                        else
                            Err (GenericConflict { ctx | currentPos = ctx.currentPos } name existing actual)

                    Nothing ->
                        Ok (Dict.insert name actual bindings)

            else if typesEqual ctx expected actual then
                Ok bindings

            else
                Err (TypeMismatch { ctx | currentPos = ctx.currentPos } expected actual)

        ( Source.TypeList e1, Source.TypeList e2 ) ->
            unify ctx typeArgs e1 e2 bindings

        ( Source.TypePair h1 t1, Source.TypePair h2 t2 ) ->
            unify ctx typeArgs h1 h2 bindings
                |> Result.andThen (unify ctx typeArgs t1 t2)

        ( Source.TypeMap k1 v1, Source.TypeMap k2 v2 ) ->
            unify ctx typeArgs k1 k2 bindings
                |> Result.andThen (unify ctx typeArgs v1 v2)

        ( Source.TypeUnit e1, Source.TypeUnit e2 ) ->
            unify ctx typeArgs e1 e2 bindings

        _ ->
            if typesEqual ctx expected actual then
                Ok bindings

            else
                Err (TypeMismatch { ctx | currentPos = ctx.currentPos } expected actual)


substitute : Dict String Source.TypeRef -> Source.TypeRef -> Source.TypeRef
substitute bindings tr =
    case tr of
        Source.TypeNamed name ->
            Dict.get name bindings |> Maybe.withDefault tr

        Source.TypeList inner ->
            Source.TypeList (substitute bindings inner)

        Source.TypePair a b ->
            Source.TypePair (substitute bindings a) (substitute bindings b)

        Source.TypeMap k v ->
            Source.TypeMap (substitute bindings k) (substitute bindings v)

        Source.TypeUnit inner ->
            Source.TypeUnit (substitute bindings inner)

        Source.TypeQuip a b ->
            Source.TypeQuip (substitute bindings a) (substitute bindings b)

        _ ->
            tr


checkBuiltin : Context -> String -> List Source.LocatedExpr -> Result Error Source.TypeRef
checkBuiltin ctx name args =
    let
        pos =
            ctx.currentPos
    in
    if name == "first" then
        case args of
            [ arg ] ->
                case inferExprType ctx arg of
                    Ok tr ->
                        case resolveType ctx tr of
                            Source.TypeList t ->
                                Ok t

                            _ ->
                                Err (TypeMismatch { ctx | currentPos = arg.pos } (Source.TypeList Source.TypeNumber) tr)

                    Err err ->
                        Err err

            _ ->
                Err (ArityMismatch ctx "first" 1 (List.length args))

    else if name == "rest" then
        case args of
            [ arg ] ->
                case inferExprType ctx arg of
                    Ok tr ->
                        case resolveType ctx tr of
                            Source.TypeList t ->
                                Ok (Source.TypeList t)

                            _ ->
                                Err (TypeMismatch { ctx | currentPos = arg.pos } (Source.TypeList Source.TypeNumber) tr)

                    Err err ->
                        Err err

            _ ->
                Err (ArityMismatch ctx "rest" 1 (List.length args))

    else if name == "prepend" then
        case args of
            [ _, list ] ->
                inferExprType ctx list

            _ ->
                Err (ArityMismatch ctx "prepend" 2 (List.length args))

    else if name == "pure" then
        case args of
            [ arg ] ->
                case inferExprType ctx arg of
                    Ok t ->
                        Ok (Source.TypeQuip Source.TypeCard t)

                    Err err ->
                        Err err

            _ ->
                Err (ArityMismatch ctx "pure" 1 (List.length args))

    else if name == "cell" then
        case args of
            [ a, b ] ->
                case ( inferExprType ctx a, inferExprType ctx b ) of
                    ( Ok ta, Ok tb ) ->
                        Ok (Source.TypePair ta tb)

                    _ ->
                        Err (UnknownName ctx "cell args")

            _ ->
                Err (ArityMismatch ctx "cell" 2 (List.length args))

    else if name == "unit" then
        case args of
            [ arg ] ->
                case inferExprType ctx arg of
                    Ok t ->
                        Ok (Source.TypeUnit t)

                    Err err ->
                        Err err

            [] ->
                Ok (Source.TypeRawHoon "any")

            _ ->
                Err (ArityMismatch ctx "unit" 1 (List.length args))

    else if name == "length" then
        case args of
            [ arg ] ->
                case resolveType ctx (Result.withDefault Source.TypeNumber (inferExprType ctx arg)) of
                    Source.TypeList _ ->
                        Ok Source.TypeNumber

                    _ ->
                        Err (TypeMismatch { ctx | currentPos = arg.pos } (Source.TypeList Source.TypeNumber) Source.TypeNumber)

            _ ->
                Err (ArityMismatch ctx "length" 1 (List.length args))

    else if name == "append" then
        case args of
            [ list, _ ] ->
                inferExprType ctx list

            _ ->
                Err (ArityMismatch ctx "append" 2 (List.length args))

    else if name == "map" then
        case args of
            [ list, _ ] ->
                inferExprType ctx list

            _ ->
                Err (ArityMismatch ctx "map" 2 (List.length args))

    else if name == "fold" then
        Ok (Source.TypeRawHoon "any")

    else if name == "give" then
        Ok (Source.TypeCard)

    else if name == "init" then
        Ok (Source.TypeRawHoon "any")

    else if name == "my" then
        Ok (Source.TypeMap Source.TypeNumber Source.TypeNumber)

    else if name == "recurse" then
        Ok (Source.TypeRawHoon "any")

    else if name == "scry" then
        case args of
            [ _, _ ] ->
                Ok (Source.TypeRawHoon "any")

            _ ->
                Err (ArityMismatch ctx "scry" 2 (List.length args))

    else if name == "get" then
        case args of
            [ coll, _ ] ->
                case inferExprType ctx coll of
                    Ok tr ->
                        case resolveType ctx tr of
                            Source.TypeMap _ v ->
                                Ok (Source.TypeUnit v)

                            _ ->
                                Ok (Source.TypeRawHoon "any")

                    Err err ->
                        Err err

            _ ->
                Err (ArityMismatch ctx "get" 2 (List.length args))

    else if name == "put" then
        case args of
            [ coll, _, _ ] ->
                inferExprType ctx coll

            _ ->
                Err (ArityMismatch ctx "put" 3 (List.length args))

    else if name == "has" then
        case args of
            [ _, _ ] ->
                Ok Source.TypeBool

            _ ->
                Err (ArityMismatch ctx "has" 2 (List.length args))

    else if name == "nock" then
        case args of
            [ _ ] ->
                Ok (Source.TypeRawHoon "any")

            _ ->
                Err (ArityMismatch ctx "nock" 1 (List.length args))

    else
        Err (UnknownFunction ctx name)


checkArgs : Context -> List Source.TypeRef -> List Source.LocatedExpr -> Result Error ()
checkArgs ctx expected actual =
    case ( expected, actual ) of
        ( [], [] ) ->
            Ok ()

        ( e :: es, a :: as_ ) ->
            case inferExprType ctx a of
                Ok actualType ->
                    if typesEqual ctx actualType e then
                        checkArgs ctx es as_

                    else
                        Err (TypeMismatch { ctx | currentPos = a.pos } e actualType)

                Err err ->
                    Err err

        _ ->
            Ok ()


resolveType : Context -> Source.TypeRef -> Source.TypeRef
resolveType ctx tr =
    case tr of
        Source.TypeNamed "any" ->
            Source.TypeRawHoon "any"

        Source.TypeNamed name ->
            case Dict.get name ctx.types of
                Just (Source.Alias inner) ->
                    resolveType ctx inner

                _ ->
                    tr

        _ ->
            tr


dropCarets : String -> String
dropCarets s =
    if String.startsWith "^" s then
        dropCarets (String.dropLeft 1 s)

    else
        s


extractLiteral : Source.ValueOrExpr -> Source.LiteralValue
extractLiteral ve =
    case ve of
        Source.Literal val ->
            val

        _ ->
            Source.LitNumber "0"


inferLiteralType : Context -> Maybe Source.TypeRef -> Source.LiteralValue -> Source.TypeRef
inferLiteralType ctx expected val =
    case val of
        Source.LitNumber _ ->
            Source.TypeNumber

        Source.LitText _ ->
            Source.TypeText

        Source.LitBool _ ->
            Source.TypeBool

        Source.LitList list ->
            case expected of
                Just tr ->
                    case resolveType ctx tr of
                        Source.TypePair a b ->
                            case list of
                                [ la, lb ] ->
                                    Source.TypePair (inferLiteralType ctx (Just a) la) (inferLiteralType ctx (Just b) lb)

                                _ ->
                                    Source.TypeList (inferListElements ctx list)

                        _ ->
                            Source.TypeList (inferListElements ctx list)

                _ ->
                    Source.TypeList (inferListElements ctx list)

        Source.LitRecord typeName _ ->
            Source.TypeNamed typeName

        Source.LitVariant typeName _ _ ->
            Source.TypeNamed typeName

        Source.LitObject _ ->
            case expected of
                Just tr ->
                    case resolveType ctx tr of
                        Source.TypeNamed name ->
                            case Dict.get name ctx.types of
                                Just (Source.Record _) ->
                                    Source.TypeNamed name

                                _ ->
                                    Source.TypeRawHoon "any"

                        _ ->
                            Source.TypeRawHoon "any"

                Nothing ->
                    Source.TypeRawHoon "any"


inferListElements : Context -> List Source.LiteralValue -> Source.TypeRef
inferListElements ctx list =
    case list of
        [] ->
            Source.TypeNumber

        x :: _ ->
            inferLiteralType ctx Nothing x


typesEqual : Context -> Source.TypeRef -> Source.TypeRef -> Bool
typesEqual ctx a b =
    let
        ra =
            resolveType ctx a

        rb =
            resolveType ctx b
    in
    case ( ra, rb ) of
        ( Source.TypeRawHoon "any", _ ) ->
            True

        ( _, Source.TypeRawHoon "any" ) ->
            True
            
        ( Source.TypeRawHoon r1, Source.TypeRawHoon r2 ) ->
            r1 == r2

        ( Source.TypeNamed n1, Source.TypeRawHoon r2 ) ->
            n1 == r2

        ( Source.TypeRawHoon r1, Source.TypeNamed n2 ) ->
            r1 == n2

        ( Source.TypeNumber, Source.TypeNat ) ->
            True

        ( Source.TypeNat, Source.TypeNumber ) ->
            True

        ( Source.TypeNamed n1, Source.TypeNamed n2 ) ->
            n1 == n2

        ( Source.TypeMap k1 v1, Source.TypeMap k2 v2 ) ->
            typesEqual ctx k1 k2 && typesEqual ctx v1 v2

        ( Source.TypeSet t1, Source.TypeSet t2 ) ->
            typesEqual ctx t1 t2

        ( Source.TypeUnit t1, Source.TypeUnit t2 ) ->
            typesEqual ctx t1 t2

        ( Source.TypeList t1, Source.TypeList t2 ) ->
            typesEqual ctx t1 t2

        ( Source.TypePair v1 v2, Source.TypePair v3 v4 ) ->
            typesEqual ctx v1 v3 && typesEqual ctx v2 v4

        _ ->
            ra == rb


typeRefToString : Source.TypeRef -> String
typeRefToString tr =
    case tr of
        Source.TypeNumber ->
            "number"

        Source.TypeNat ->
            "nat"

        Source.TypeText ->
            "text"

        Source.TypeBool ->
            "bool"

        Source.TypeList t ->
            "list<" ++ typeRefToString t ++ ">"

        Source.TypePair v1 v2 ->
            "pair<" ++ typeRefToString v1 ++ ", " ++ typeRefToString v2 ++ ">"

        Source.TypeQuip v1 v2 ->
            "quip<" ++ typeRefToString v1 ++ ", " ++ typeRefToString v2 ++ ">"

        Source.TypeCard ->
            "card"

        Source.TypeUnit t ->
            typeRefToString t ++ "?"

        Source.TypeMap k v ->
            "map<" ++ typeRefToString k ++ ", " ++ typeRefToString v ++ ">"

        Source.TypeSet t ->
            "set<" ++ typeRefToString t ++ ">"

        Source.TypeNamed s ->
            s

        Source.TypeRawHoon s ->
            "raw-hoon<" ++ s ++ ">"


findUnbound : List String -> Dict String Source.TypeRef -> Maybe String
findUnbound args bindings =
    case args of
        [] ->
            Nothing
            
        arg :: rest ->
            if Dict.member arg bindings then
                findUnbound rest bindings
            else
                Just arg

errorToString : Error -> String
errorToString err =
    case err of
        UnknownName ctx name ->
            formatError ctx ("Unknown name: " ++ name)

        UnknownType ctx name ->
            formatError ctx ("Unknown type: " ++ name)

        UnknownFunction ctx name ->
            formatError ctx ("Unknown function: " ++ name)

        ArityMismatch ctx name expected actual ->
            formatError ctx ("Arity mismatch for " ++ name ++ ": expected " ++ String.fromInt expected ++ ", got " ++ String.fromInt actual)

        TypeMismatch ctx expected actual ->
            formatError ctx ("Type mismatch: expected " ++ typeRefToString expected ++ ", got " ++ typeRefToString actual)

        NotARecord ctx t ->
            formatError ctx ("Type " ++ typeRefToString t ++ " is not a record")

        NotAUnion ctx t ->
            formatError ctx ("Type " ++ typeRefToString t ++ " is not a union")

        MissingField ctx typeName field ->
            formatError ctx ("Type " ++ typeName ++ " does not have field: " ++ field)

        UnknownVariant ctx typeName variantName ->
            formatError ctx ("Union " ++ typeName ++ " does not have variant: " ++ variantName)

        UnknownPokeRoute ctx route ->
            formatError ctx ("Unknown poke route: " ++ route)

        MissingTestSubject ctx name ->
            formatError ctx ("Missing test subject: " ++ name)

        GenericConflict ctx name expected actual ->
            formatError ctx ("Generic type parameter '" ++ name ++ "' bound to conflicting types: " ++ typeRefToString expected ++ " and " ++ typeRefToString actual)

        UnboundGeneric ctx name ->
            formatError ctx ("Cannot infer type for generic parameter '" ++ name ++ "'. It is not used in the input arguments.")

        TransitionToUnknownState ctx state ->
            formatError ctx ("Transition to unknown state: " ++ state)

        MissingStateData ctx state field ->
            formatError ctx ("Missing data fields for state " ++ state ++ ": " ++ field)

        NonExhaustiveMatch ctx variant ->
            formatError ctx ("Non-exhaustive patterns for variant match: " ++ variant)


formatError : Context -> String -> String
formatError ctx msg =
    let
        pathStr =
            String.join "." ctx.path

        pos =
            ctx.currentPos
    in
    "In " ++ pathStr ++ " at line " ++ String.fromInt pos.line ++ ", col " ++ String.fromInt pos.col ++ ": " ++ msg
