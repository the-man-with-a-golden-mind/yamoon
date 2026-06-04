port module Main exposing (main)

import Compiler.Lower as Lower
import Compiler.Macro as Macro
import Compiler.Typecheck as Typecheck
import Hoon.Pretty as Pretty
import Source.Decode as Decode


port requestCompile : (String -> msg) -> Sub msg


port requestTest : (String -> msg) -> Sub msg


port responseSuccess : String -> Cmd msg


port responseError : String -> Cmd msg


type alias Model =
    {}


type Msg
    = OnCompileRequest String
    | OnTestRequest String


main : Program () Model Msg
main =
    Platform.worker
        { init = \_ -> ( {}, Cmd.none )
        , update = update
        , subscriptions = subscriptions
        }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        OnCompileRequest json ->
            case Decode.decode json of
                Ok program ->
                    let
                        expandedProgram =
                            Macro.expand program
                    in
                    case Typecheck.check expandedProgram of
                        Ok () ->
                            let
                                hoonAst =
                                    Lower.lower expandedProgram

                                hoonCode =
                                    Pretty.render expandedProgram.options hoonAst
                            in
                            ( model, responseSuccess hoonCode )

                        Err errors ->
                            ( model, responseError (String.join "\n" errors) )

                Err err ->
                    ( model, responseError err )

        OnTestRequest json ->
            case Decode.decode json of
                Ok program ->
                    let
                        expandedProgram =
                            Macro.expand program
                    in
                    case Typecheck.check expandedProgram of
                        Ok () ->
                            let
                                testAst =
                                    Lower.lowerTests expandedProgram

                                testCode =
                                    Pretty.render expandedProgram.options testAst
                            in
                            ( model, responseSuccess testCode )

                        Err errors ->
                            ( model, responseError (String.join "\n" errors) )

                Err err ->
                    ( model, responseError err )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ requestCompile OnCompileRequest
        , requestTest OnTestRequest
        ]
