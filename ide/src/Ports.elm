port module Ports exposing (..)

import Json.Decode as Decode


port toEditor : { action : String, data : Decode.Value } -> Cmd msg


port fromEditor : (Decode.Value -> msg) -> Sub msg
