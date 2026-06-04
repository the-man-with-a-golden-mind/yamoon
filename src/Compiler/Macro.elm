module Compiler.Macro exposing (expand, expandExpr)

import Dict exposing (Dict)
import Set exposing (Set)
import Source.Ast as Source


expand : Source.Program -> Source.Program
expand prog =
    let
        macros =
            prog.macros

        expandedConstants =
            Dict.map (\_ tve -> { tve | value = expandValueOrExpr macros tve.value }) prog.constants

        expandedFunctions =
            Dict.map (\_ def -> { def | body = expandLocated macros Set.empty Dict.empty def.body }) prog.functions

        expandedPokes =
            Dict.map (\_ def -> { def | body = expandLocated macros Set.empty Dict.empty def.body }) prog.pokes

        expandedScries =
            Dict.map (\_ def -> { def | body = expandLocated macros Set.empty Dict.empty def.body }) prog.scries

        expandedTests =
            Dict.map (\_ def -> expandTest macros def) prog.tests
    in
    { prog
        | constants = expandedConstants
        , functions = expandedFunctions
        , pokes = expandedPokes
        , scries = expandedScries
        , onLoad = Maybe.map (expandLocated macros Set.empty Dict.empty) prog.onLoad
        , watches = Dict.map (\_ le -> expandLocated macros Set.empty Dict.empty le) prog.watches
        , tests = expandedTests
    }


expandTest : Dict String Source.MacroDef -> Source.TestDef -> Source.TestDef
expandTest macros testDef =
    case testDef of
        Source.UnitTest data ->
            Source.UnitTest data -- literals don't need expansion

        Source.ScenarioTest data ->
            Source.ScenarioTest { data | steps = List.map (expandScenarioStep macros) data.steps }

        Source.MigrationTest data ->
            Source.MigrationTest data


expandScenarioStep : Dict String Source.MacroDef -> Source.ScenarioStep -> Source.ScenarioStep
expandScenarioStep _ step =
    -- Actions currently only contain literals
    step


expandValueOrExpr : Dict String Source.MacroDef -> Source.ValueOrExpr -> Source.ValueOrExpr
expandValueOrExpr macros ve =
    case ve of
        Source.Literal val ->
            Source.Literal val

        Source.Computed le ->
            Source.Computed (expandLocated macros Set.empty Dict.empty le)

        Source.RawHoon s ->
            Source.RawHoon s


expandLocated : Dict String Source.MacroDef -> Set String -> Dict String Source.LocatedExpr -> Source.LocatedExpr -> Source.LocatedExpr
expandLocated macros visited bindings le =
    { pos = le.pos, expr = expandExpr macros visited bindings le.expr }


expandExpr : Dict String Source.MacroDef -> Set String -> Dict String Source.LocatedExpr -> Source.Expr -> Source.Expr
expandExpr macros visited bindings expr =
    case expr of
        Source.ENumber s ->
            Source.ENumber s

        Source.EText s ->
            Source.EText s

        Source.EInterpolated fragments ->
            Source.EInterpolated (List.map (expandLocated macros visited bindings) fragments)

        Source.EBool b ->
            Source.EBool b

        Source.EName name ->
            case Dict.get name bindings of
                Just replacement ->
                    replacement.expr

                Nothing ->
                    Source.EName name

        Source.EField e field ->
            Source.EField (expandLocated macros visited bindings e) field

        Source.EList list ->
            Source.EList (List.map (expandLocated macros visited bindings) list)

        Source.ECall name args ->
            let
                expandedArgs =
                    List.map (expandLocated macros visited bindings) args
            in
            case Dict.get name macros of
                Just macroDef ->
                    if Set.member name visited then
                        Source.ERawHoon (":: circular macro detected: " ++ name)

                    else
                        let
                            newBindings =
                                List.map2 (\argName argExpr -> ( argName, argExpr )) macroDef.args expandedArgs
                                    |> Dict.fromList

                            newVisited =
                                Set.insert name visited

                            expansion =
                                expandLocated macros newVisited newBindings macroDef.expand
                        in
                        expansion.expr

                Nothing ->
                    Source.ECall name expandedArgs

        Source.ERecord typeName fields ->
            Source.ERecord typeName (Dict.map (\_ e -> expandLocated macros visited bindings e) fields)

        Source.EVariant typeName variantName fields ->
            Source.EVariant typeName variantName (Dict.map (\_ e -> expandLocated macros visited bindings e) fields)

        Source.EDict fields ->
            Source.EDict (Dict.map (\_ e -> expandLocated macros visited bindings e) fields)

        Source.ERune r args ->
            Source.ERune r (List.map (expandLocated macros visited bindings) args)

        Source.ELoop loopArgs body ->
            Source.ELoop (Dict.map (\_ e -> expandLocated macros visited bindings e) loopArgs) (expandLocated macros visited bindings body)

        Source.ELet name val body ->
            Source.ELet name (expandLocated macros visited bindings val) (expandLocated macros visited bindings body)

        Source.ESet name val body ->
            Source.ESet name (expandLocated macros visited bindings val) (expandLocated macros visited bindings body)

        Source.EAssert cond body ->
            Source.EAssert (expandLocated macros visited bindings cond) (expandLocated macros visited bindings body)

        Source.EUnless cond body ->
            Source.EUnless (expandLocated macros visited bindings cond) (expandLocated macros visited bindings body)

        Source.ECast t e ->
            Source.ECast t (expandLocated macros visited bindings e)

        Source.EMatch target cases mDefault ->
            Source.EMatch (expandLocated macros visited bindings target) (Dict.map (\_ e -> expandLocated macros visited bindings e) cases) (Maybe.map (expandLocated macros visited bindings) mDefault)

        Source.EBinary op left right ->
            Source.EBinary op (expandLocated macros visited bindings left) (expandLocated macros visited bindings right)

        Source.EIf cond then_ else_ ->
            Source.EIf (expandLocated macros visited bindings cond) (expandLocated macros visited bindings then_) (expandLocated macros visited bindings else_)

        Source.EIfNot cond then_ else_ ->
            Source.EIfNot (expandLocated macros visited bindings cond) (expandLocated macros visited bindings then_) (expandLocated macros visited bindings else_)

        Source.ERawHoon s ->
            Source.ERawHoon s
