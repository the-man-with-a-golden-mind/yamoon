module Hoon.Pretty exposing (render)

import Hoon.Ast as Hoon
import Source.Ast as Source


render : Source.Options -> Hoon.HoonProgram -> String
render opts program =
    case program of
        Hoon.HoonModule imports docs arms ->
            let
                renderedImports =
                    String.join "\n" imports

                renderedDocs =
                    List.map renderDoc docs |> String.join "\n"

                renderedArms =
                    List.map renderArm arms |> String.join "\n\n"

                body =
                    case opts.target of
                        Source.Library ->
                            renderedDocs
                                ++ "\n\n|%\n"
                                ++ indent renderedArms
                                ++ "\n--"

                        Source.Gall ->
                            let
                                finalDocs =
                                    if String.isEmpty renderedDocs then
                                        ""

                                    else
                                        "\n" ++ renderedDocs

                                hasOnLoad =
                                    List.any (\(Hoon.HoonArm name _) -> name == "on-load") arms

                                hasOnPoke =
                                    List.any (\(Hoon.HoonArm name _) -> name == "on-poke") arms

                                hasOnWatch =
                                    List.any (\(Hoon.HoonArm name _) -> name == "on-watch") arms

                                hasOnPeek =
                                    List.any (\(Hoon.HoonArm name _) -> name == "on-peek") arms

                                routeArm name hasCustom =
                                    "++  " ++ name ++ "  *  " ++ (if hasCustom then name else name ++ ":def")
                            in
                            "/+  dbug, default-agent"
                                ++ finalDocs
                                ++ "\n\n"
                                ++ "|-  agent:gall\n"
                                ++ "=>\n"
                                ++ "|%  ++  card  card:agent:gall\n"
                                ++ "--\n"
                                ++ "|-  agent:gall\n"
                                ++ "|_  bowl=bowl:gall\n"
                                ++ "+*  this  .\n"
                                ++ "    def   ~(. default-agent this %|)\n"
                                ++ "++  on-init  *  on-init\n"
                                ++ "++  on-save  *  on-save:def\n"
                                ++ (routeArm "on-load" hasOnLoad)
                                ++ "\n"
                                ++ (routeArm "on-poke" hasOnPoke)
                                ++ "\n"
                                ++ (routeArm "on-watch" hasOnWatch)
                                ++ "\n"
                                ++ "++  on-leave *  on-leave:def\n"
                                ++ (routeArm "on-peek" hasOnPeek)
                                ++ "\n"
                                ++ "++  on-agent *  on-agent:def\n"
                                ++ "++  on-arvo  *  on-arvo:def\n"
                                ++ "++  on-fail  *  on-fail:def\n"
                                ++ "--\n\n"
                                ++ "|%  :: user arms\n"
                                ++ indent renderedArms
                                ++ "\n--"
            in
            if String.isEmpty renderedImports then
                body

            else
                renderedImports ++ "\n\n" ++ body

        Hoon.HoonTestFile imports arms ->
            let
                renderedImports =
                    String.join "\n" imports

                renderedArms =
                    List.map renderArm arms |> String.join "\n\n"

                body =
                    "|%  :: test arms\n"
                        ++ indent renderedArms
                        ++ "\n--"
            in
            if String.isEmpty renderedImports then
                body

            else
                renderedImports ++ "\n\n" ++ body


renderDoc : Hoon.HoonDoc -> String
renderDoc (Hoon.HoonComment s) =
    "::  " ++ s


renderArm : Hoon.HoonArm -> String
renderArm (Hoon.HoonArm name expr) =
    "++  " ++ name ++ "\n" ++ indent (renderExpr expr)


renderExpr : Hoon.HoonExpr -> String
renderExpr expr =
    case expr of
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
            "[" ++ renderExpr a ++ " " ++ renderExpr b ++ "]"

        Hoon.HList items ->
            if List.isEmpty items then
                "~"

            else
                "~[" ++ (List.map renderExpr items |> String.join " ") ++ "]"

        Hoon.HCall name args ->
            if name == "=" then
                "=" ++ "(" ++ (List.map (\le -> renderExpr le.expr) args |> String.join " ") ++ ")"

            else if name == "$" then
                "$" ++ "(" ++ (List.map (\le -> renderExpr le.expr) args |> String.join " ") ++ ")"

            else
                "(" ++ name ++ " " ++ (List.map (\le -> renderExpr le.expr) args |> String.join " ") ++ ")"

        Hoon.HField innerExpr field ->
            field ++ "." ++ renderExpr innerExpr.expr

        Hoon.HCast mold innerExpr ->
            "^-  " ++ renderMold mold ++ "\n" ++ indent (renderExpr innerExpr)

        Hoon.HRune r args ->
            if List.isEmpty args then
                r

            else
                let
                    argsStr =
                        List.map renderExpr args
                in
                r ++ "(" ++ String.join " " argsStr ++ ")"

        Hoon.HLet name val body ->
            "=+  " ++ name ++ "=" ++ renderExpr val ++ "\n" ++ renderExpr body

        Hoon.HSet name val body ->
            "=.  " ++ name ++ "  " ++ renderExpr val ++ "\n" ++ renderExpr body

        Hoon.HAssert cond body ->
            "?>  " ++ renderExpr cond ++ "\n" ++ renderExpr body

        Hoon.HUnless cond body ->
            "?<  " ++ renderExpr cond ++ "\n" ++ renderExpr body

        Hoon.HLoop mArgs body ->
            let
                inner =
                    "|-  " ++ renderExpr body
            in
            case mArgs of
                Just args ->
                    "=+  " ++ renderExpr args.expr ++ "\n" ++ inner

                Nothing ->
                    inner

        Hoon.HMatch target cases mDefault ->
            let
                t =
                    renderExpr target.expr

                d =
                    case mDefault of
                        Just def ->
                            renderExpr def

                        Nothing ->
                            "!!"

                renderedCases =
                    cases
                        |> List.map (\( k, v ) -> k ++ "  " ++ renderExpr v)
                        |> String.join "\n"
            in
            "?+  " ++ t ++ "  " ++ d ++ "\n" ++ renderedCases

        Hoon.HIf cond then_ else_ ->
            let
                c =
                    renderExpr cond

                t =
                    renderExpr then_

                e =
                    renderExpr else_
            in
            if String.length c + String.length t + String.length e < 40 && not (String.contains "\n" t) && not (String.contains "\n" e) then
                "?:  " ++ c ++ "  " ++ t ++ "  " ++ e

            else
                "?:  " ++ c ++ "\n" ++ indent t ++ "\n" ++ indent e

        Hoon.HIfNot cond then_ else_ ->
            let
                c =
                    renderExpr cond

                t =
                    renderExpr then_

                e =
                    renderExpr else_
            in
            if String.length c + String.length t + String.length e < 40 && not (String.contains "\n" t) && not (String.contains "\n" e) then
                "?.  " ++ c ++ "  " ++ t ++ "  " ++ e

            else
                "?.  " ++ c ++ "\n" ++ indent t ++ "\n" ++ indent e

        Hoon.HGate inputs body ->
            let
                renderedInputs =
                    case inputs of
                        [] ->
                            "*"

                        [ ( name, mold ) ] ->
                            name ++ "=" ++ renderMold mold

                        _ ->
                            "[" ++ (List.map (\( n, m ) -> n ++ "=" ++ renderMold m) inputs |> String.join " ") ++ "]"
            in
            "|=  " ++ renderedInputs ++ "\n" ++ indent (renderExpr body)

        Hoon.HRaw s ->
            s


renderMold : Hoon.HoonMold -> String
renderMold mold =
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
            "(list " ++ renderMold inner ++ ")"

        Hoon.MPair a b ->
            "[" ++ renderMold a ++ " " ++ renderMold b ++ "]"

        Hoon.MNamed s ->
            s

        Hoon.MRaw s ->
            s


indent : String -> String
indent s =
    s
        |> String.split "\n"
        |> List.map (\line -> "  " ++ line)
        |> String.join "\n"
