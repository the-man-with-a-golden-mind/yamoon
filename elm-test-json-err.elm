module Main exposing (..)
import Json.Decode as Decode exposing (Error(..))

findSyntaxError : Error -> Maybe String
findSyntaxError err =
    case err of
        Field _ e -> findSyntaxError e
        Index _ e -> findSyntaxError e
        OneOf errors ->
            List.filterMap findSyntaxError errors |> List.head
        Failure msg _ ->
            if String.startsWith "Invalid expression:" msg || String.startsWith "Syntax error" msg then
                Just msg
            else
                Nothing
