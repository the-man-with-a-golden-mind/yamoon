module Main exposing (main)

import Browser
import Dict exposing (Dict)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Ports
import Url exposing (Url)


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }



-- MODEL


type alias Flags =
    { apiUrl : String }


type alias Model =
    { apiUrl : String
    , tree : List FileNode
    , selectedPath : Maybe String
    , content : String
    , hoonOutput : Maybe String
    , error : Maybe String
    , theme : Theme
    , syntaxTheme : SyntaxTheme
    }


type Theme
    = Light
    | Dark


type SyntaxTheme
    = VS
    | VSDark
    | HCBlack
    | Solarized
    | Monokai


type FileNode
    = File { name : String, path : String }
    | Directory { name : String, path : String, children : List FileNode, open : Bool }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { apiUrl = flags.apiUrl
      , tree = []
      , selectedPath = Nothing
      , content = ""
      , hoonOutput = Nothing
      , error = Nothing
      , theme = Light
      , syntaxTheme = VS
      }
    , getTree flags.apiUrl
    )



-- UPDATE


type Msg
    = GotTree (Result Http.Error (List FileNode))
    | GotFile (Result Http.Error String)
    | SelectPath String
    | ToggleDir String
    | EditorChanged String
    | Compile
    | GotCompile (Result Http.Error CompileResponse)
    | Save
    | GotSave (Result Http.Error String)
    | SetTheme Theme
    | SetSyntaxTheme SyntaxTheme


type alias CompileResponse =
    { success : Bool
    , hoon : Maybe String
    , error : Maybe String
    }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotTree (Ok tree) ->
            ( { model | tree = tree }, Cmd.none )

        GotTree (Err err) ->
            ( { model | error = Just ("Failed to load project tree: " ++ httpErrorToString err) }, Cmd.none )

        SelectPath path ->
            ( { model | selectedPath = Just path }
            , getFile model.apiUrl path
            )

        GotFile (Ok content) ->
            ( { model | content = content }
            , Ports.toEditor { action = "setContent", data = Encode.string content }
            )

        GotFile (Err err) ->
            ( { model | error = Just ("Failed to load file: " ++ httpErrorToString err) }, Cmd.none )

        ToggleDir path ->
            ( { model | tree = toggleDirInList path model.tree }, Cmd.none )

        EditorChanged content ->
            ( { model | content = content }, Cmd.none )

        Compile ->
            ( { model | error = Nothing, hoonOutput = Nothing }
            , compile model.apiUrl model.content
            )

        GotCompile (Ok res) ->
            if res.success then
                ( { model | hoonOutput = res.hoon }, Cmd.none )

            else
                ( { model | error = res.error }, Cmd.none )

        GotCompile (Err err) ->
            ( { model | error = Just ("Compilation request failed: " ++ httpErrorToString err) }, Cmd.none )

        Save ->
            case model.selectedPath of
                Just path ->
                    ( model, saveFile model.apiUrl path model.content )

                Nothing ->
                    ( model, Cmd.none )

        GotSave (Ok _) ->
            ( model, Cmd.none )

        GotSave (Err err) ->
            ( { model | error = Just ("Failed to save file: " ++ httpErrorToString err) }, Cmd.none )

        SetTheme theme ->
            let
                newSyntax =
                    case theme of
                        Light ->
                            VS

                        Dark ->
                            VSDark
            in
            ( { model | theme = theme, syntaxTheme = newSyntax }
            , Ports.toEditor { action = "setTheme", data = Encode.string (syntaxThemeToString newSyntax) }
            )

        SetSyntaxTheme syntax ->
            ( { model | syntaxTheme = syntax }
            , Ports.toEditor { action = "setTheme", data = Encode.string (syntaxThemeToString syntax) }
            )


httpErrorToString : Http.Error -> String
httpErrorToString err =
    case err of
        Http.BadUrl s ->
            "Bad URL: " ++ s

        Http.Timeout ->
            "Timeout"

        Http.NetworkError ->
            "Network Error (Is the server running?)"

        Http.BadStatus status ->
            "Bad Status: " ++ String.fromInt status

        Http.BadBody body ->
            "Bad Body: " ++ body


syntaxThemeToString : SyntaxTheme -> String
syntaxThemeToString theme =
    case theme of
        VS ->
            "vs"

        VSDark ->
            "vs-dark"

        HCBlack ->
            "hc-black"

        Solarized ->
            "solarized"

        Monokai ->
            "monokai"


subscriptions : Model -> Sub Msg
subscriptions _ =
    Ports.fromEditor
        (\val ->
            case Decode.decodeValue (Decode.field "content" Decode.string) val of
                Ok content ->
                    EditorChanged content

                Err _ ->
                    EditorChanged "" -- should not happen
        )



-- VIEW


view : Model -> Html Msg
view model =
    let
        themeClasses =
            case model.theme of
                Light ->
                    "bg-white text-gray-900"

                Dark ->
                    "bg-gray-900 text-white"
    in
    div [ class ("flex w-full h-screen overflow-hidden font-sans " ++ themeClasses) ]
        [ viewSidebar model
        , viewMain model
        ]


viewSidebar : Model -> Html Msg
viewSidebar model =
    let
        s =
            case model.theme of
                Light ->
                    { bg = "bg-gray-100", border = "border-gray-300", hover = "hover:bg-gray-200", text = "text-gray-900" }

                Dark ->
                    { bg = "bg-gray-800", border = "border-gray-700", hover = "hover:bg-gray-700", text = "text-white" }
    in
    div [ class ("w-64 border-r flex flex-col " ++ s.bg ++ " " ++ s.border ++ " " ++ s.text) ]
        [ div [ class ("p-4 border-b flex justify-between items-center " ++ s.border) ]
            [ h1 [ class "text-lg font-bold" ] [ text "Yamoon" ]
            , div [ class "flex gap-2" ]
                [ button [ class ("p-1 rounded " ++ s.hover), onClick Save, title "Save" ] [ text "💾" ]
                , viewThemeToggle model s.hover
                ]
            ]
        , div [ class ("p-4 border-b space-y-2 " ++ s.border) ]
            [ label [ class "text-xs font-bold uppercase tracking-wider opacity-50" ] [ text "Syntax Theme" ]
            , select
                [ class ("w-full p-1 text-sm rounded border " ++ s.bg ++ " " ++ s.border)
                , onInput (stringToSyntaxTheme >> SetSyntaxTheme)
                ]
                [ option [ value "vs", selected (model.syntaxTheme == VS) ] [ text "Classic Light" ]
                , option [ value "vs-dark", selected (model.syntaxTheme == VSDark) ] [ text "Classic Dark" ]
                , option [ value "hc-black", selected (model.syntaxTheme == HCBlack) ] [ text "High Contrast" ]
                , option [ value "solarized", selected (model.syntaxTheme == Solarized) ] [ text "Solarized" ]
                , option [ value "monokai", selected (model.syntaxTheme == Monokai) ] [ text "Monokai" ]
                ]
            ]
        , div [ class "flex-grow overflow-y-auto p-2" ]
            (List.map (viewNode model s.hover) model.tree)
        ]


stringToSyntaxTheme : String -> SyntaxTheme
stringToSyntaxTheme s =
    case s of
        "vs" ->
            VS

        "vs-dark" ->
            VSDark

        "hc-black" ->
            HCBlack

        "solarized" ->
            Solarized

        "monokai" ->
            Monokai

        _ ->
            VS


viewThemeToggle : Model -> String -> Html Msg
viewThemeToggle model hover =
    case model.theme of
        Light ->
            button [ class ("p-1 rounded " ++ hover), onClick (SetTheme Dark), title "Switch to Dark Mode" ] [ text "🌙" ]

        Dark ->
            button [ class ("p-1 rounded " ++ hover), onClick (SetTheme Light), title "Switch to Light Mode" ] [ text "☀️" ]


viewNode : Model -> String -> FileNode -> Html Msg
viewNode model hover node =
    case node of
        File { name, path } ->
            div
                [ class ("pl-4 py-1 cursor-pointer text-sm truncate rounded " ++ hover)
                , onClick (SelectPath path)
                ]
                [ text ("📄 " ++ name) ]

        Directory { name, path, children, open } ->
            div []
                [ div
                    [ class ("pl-2 py-1 cursor-pointer text-sm font-semibold flex items-center rounded " ++ hover)
                    , onClick (ToggleDir path)
                    ]
                    [ text (if open then "📂 " else "📁 ")
                    , text name
                    ]
                , if open then
                    div [ class ("ml-2 border-l " ++ (case model.theme of
                                                        Light -> "border-gray-300"
                                                        Dark -> "border-gray-600"
                                                     )) ]
                        (List.map (viewNode model hover) children)

                  else
                    text ""
                ]


viewMain : Model -> Html Msg
viewMain model =
    div [ class "flex-grow flex flex-col overflow-hidden" ]
        [ div [ class "flex-grow relative bg-gray-900" ]
            [ div [ id "editor-container", class "absolute inset-0" ] []
            ]
        , viewOutput model
        ]


viewOutput : Model -> Html Msg
viewOutput model =
    let
        s =
            case model.theme of
                Light ->
                    { bg = "bg-gray-50", border = "border-gray-300", text = "text-gray-900" }

                Dark ->
                    { bg = "bg-black", border = "border-gray-700", text = "text-white" }
    in
    div [ class ("h-64 border-t flex flex-col " ++ s.bg ++ " " ++ s.border ++ " " ++ s.text) ]
        [ div [ class ("p-2 border-b flex justify-between items-center " ++ (case model.theme of
                                                                            Light -> "border-gray-200"
                                                                            Dark -> "border-gray-800"
                                                                          )) ]
            [ span [ class "text-xs font-mono text-gray-500 uppercase tracking-widest" ] [ text "Output / Errors" ]
            , button [ class "px-3 py-1 bg-blue-600 hover:bg-blue-700 rounded text-xs font-bold text-white", onClick Compile ] [ text "COMPILE" ]
            ]
        , div [ class "flex-grow overflow-auto p-4 font-mono text-sm" ]
            [ case model.error of
                Just err ->
                    div [ class "space-y-2" ]
                        [ div [ class "text-red-500 font-bold" ] [ text "--- Compilation Failed ---" ]
                        , pre [ class "text-red-400 whitespace-pre-wrap" ] [ text err ]
                        ]

                Nothing ->
                    case model.hoonOutput of
                        Just hoon ->
                            div [ class "space-y-2" ]
                                [ div [ class "text-green-500 font-bold" ] [ text "--- Success ---" ]
                                , pre [ class "text-green-400 whitespace-pre-wrap" ] [ text hoon ]
                                ]

                        Nothing ->
                            span [ class "text-gray-500 italic" ] [ text "Run compile to see Hoon output..." ]
            ]
        ]


toggleDirInList : String -> List FileNode -> List FileNode
toggleDirInList path list =
    List.map (toggleDir path) list


toggleDir : String -> FileNode -> FileNode
toggleDir targetPath node =
    case node of
        File _ ->
            node

        Directory dir ->
            if dir.path == targetPath then
                Directory { dir | open = not dir.open }

            else
                Directory { dir | children = toggleDirInList targetPath dir.children }



-- API


getTree : String -> Cmd Msg
getTree apiUrl =
    Http.get
        { url = apiUrl ++ "/api/tree"
        , expect = Http.expectJson GotTree treeDecoder
        }


getFile : String -> String -> Cmd Msg
getFile apiUrl path =
    Http.get
        { url = apiUrl ++ "/api/file?path=" ++ path
        , expect = Http.expectString GotFile
        }


saveFile : String -> String -> String -> Cmd Msg
saveFile apiUrl path content =
    Http.post
        { url = apiUrl ++ "/api/save"
        , body = Http.jsonBody (Encode.object [ ( "path", Encode.string path ), ( "content", Encode.string content ) ])
        , expect = Http.expectString GotSave
        }


compile : String -> String -> Cmd Msg
compile apiUrl content =
    Http.post
        { url = apiUrl ++ "/api/compile"
        , body = Http.jsonBody (Encode.object [ ( "content", Encode.string content ) ])
        , expect = Http.expectJson GotCompile compileDecoder
        }


treeDecoder : Decoder (List FileNode)
treeDecoder =
    Decode.list nodeDecoder


nodeDecoder : Decoder FileNode
nodeDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\t ->
                case t of
                    "file" ->
                        Decode.map2 (\name path -> File { name = name, path = path })
                            (Decode.field "name" Decode.string)
                            (Decode.field "path" Decode.string)

                    "directory" ->
                        Decode.map3 (\name path children -> Directory { name = name, path = path, children = children, open = False })
                            (Decode.field "name" Decode.string)
                            (Decode.field "path" Decode.string)
                            (Decode.lazy (\_ -> Decode.field "children" treeDecoder))

                    _ ->
                        Decode.fail "Unknown type"
            )


compileDecoder : Decoder CompileResponse
compileDecoder =
    let
        maybeField name decoder =
            Decode.oneOf [ Decode.field name decoder |> Decode.map Just, Decode.succeed Nothing ]
    in
    Decode.map3 CompileResponse
        (Decode.field "success" Decode.bool)
        (maybeField "hoon" Decode.string)
        (maybeField "error" Decode.string)
