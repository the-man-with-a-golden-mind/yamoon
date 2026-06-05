module Source.StandardLibrary exposing (standardNatives)

import Dict exposing (Dict)
import Source.Ast exposing (NativeDef, TypeRef(..))


standardNatives : Dict String NativeDef
standardNatives =
    Dict.fromList
        [ ( "ja"
          , { type_args = [ "K", "V" ]
            , input = [ ( "data", TypeMap (TypeNamed "K") (TypeNamed "V") ) ]
            , output = TypeRawHoon "ja-door"
            }
          )
        , ( "json"
          , { type_args = []
            , input = [ ( "val", TypeRawHoon "json" ) ]
            , output = TypeText
            }
          )
        , ( "html"
          , { type_args = []
            , input = [ ( "text", TypeText ) ]
            , output = TypeRawHoon "manx"
            }
          )
        , ( "mimes"
          , { type_args = []
            , input = [ ( "ext", TypeText ), ( "data", TypeRawHoon "octs" ) ]
            , output = TypeRawHoon "mime"
            }
          )
        , ( "enjs"
          , { type_args = [ "T" ]
            , input = [ ( "val", TypeNamed "T" ) ]
            , output = TypeRawHoon "json"
            }
          )
        , ( "dejs"
          , { type_args = [ "T" ]
            , input = [ ( "val", TypeRawHoon "json" ) ]
            , output = TypeNamed "T"
            }
          )
        , ( "ethereum"
          , { type_args = []
            , input = [ ( "ship", TypeRawHoon "ship" ) ]
            , output = TypeRawHoon "eth-door"
            }
          )
        , ( "clay"
          , { type_args = []
            , input = [ ( "ship", TypeRawHoon "ship" ) ]
            , output = TypeRawHoon "clay-door"
            }
          )
        , ( "sha256"
          , { type_args = [ "T" ]
            , input = [ ( "data", TypeNamed "T" ) ]
            , output = TypeRawHoon "atom"
            }
          )
        , ( "base64"
          , { type_args = []
            , input = [ ( "data", TypeText ) ]
            , output = TypeText
            }
          )
        , ( "math"
          , { type_args = []
            , input = [ ( "x", TypeNumber ) ]
            , output = TypeNumber
            }
          )
        , ( "snag"
          , { type_args = [ "T" ]
            , input = [ ( "index", TypeNumber ), ( "lst", TypeList (TypeNamed "T") ) ]
            , output = TypeUnit (TypeNamed "T")
            }
          )
        ]
