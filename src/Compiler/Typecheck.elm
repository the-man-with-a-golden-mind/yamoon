module Compiler.Typecheck exposing (check)

import Dict exposing (Dict)
import Source.Ast as Source


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

        ctx =
            { types = ctxTypes
            , constants = prog.constants
            , functions = prog.functions
            , localVars = baseLocalVars
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
    , localVars : Dict String Source.TypeRef
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
            { ctx | localVars = newLocalVars, path = ctx.path ++ [ "return" ] }

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
                    Ok (Source.TypeList Source.TypeNumber)

                x :: _ ->
                    inferExprType ctx x |> Result.map Source.TypeList

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

                    else
                        case checkArgs ctx (List.map Tuple.second def.input) args of
                            Ok () ->
                                Ok def.output

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

        Source.EDict _ ->
            Ok Source.TypeNumber

        Source.ERune _ args ->
            let
                _ =
                    List.map (inferExprType ctx) args
            in
            Ok (Source.TypeRawHoon "any")

        Source.ELoop args body ->
            let
                loopCtx =
                    { ctx | localVars = Dict.union (Dict.map (\_ _ -> Source.TypeRawHoon "any") args) ctx.localVars }
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

        Source.EMatch target cases _ ->
            case Dict.values cases of
                [] ->
                    Ok Source.TypeNumber

                x :: _ ->
                    inferExprType ctx x

        Source.EBinary _ left right ->
            let
                _ =
                    inferExprType ctx left

                _ =
                    inferExprType ctx right
            in
            Ok Source.TypeNumber

        Source.EIf _ then_ _ ->
            inferExprType ctx then_

        Source.EIfNot _ then_ _ ->
            inferExprType ctx then_

        Source.ERawHoon _ ->
            Ok Source.TypeNumber


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

        Source.LitObject obj ->
            case expected of
                Just tr ->
                    case resolveType ctx tr of
                        Source.TypeNamed name ->
                            case Dict.get name ctx.types of
                                Just (Source.Record _) ->
                                    Source.TypeNamed name

                                _ ->
                                    Source.TypeNumber

                        _ ->
                            Source.TypeNumber

                Nothing ->
                    Source.TypeNumber


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


formatError : Context -> String -> String
formatError ctx msg =
    let
        pathStr =
            String.join "." ctx.path

        pos =
            ctx.currentPos
    in
    "In " ++ pathStr ++ " at line " ++ String.fromInt pos.line ++ ", col " ++ String.fromInt pos.col ++ ": " ++ msg
