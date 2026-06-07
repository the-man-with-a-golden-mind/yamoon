module StateMachineTest exposing (..)

import Compiler.Lower as Lower
import Compiler.Typecheck as Typecheck
import Dict exposing (Dict)
import Expect
import Hoon.Ast as Hoon
import Source.Ast as Source
import Source.Decode as Decode
import Test exposing (..)


suite : Test
suite =
    describe "State Machine Support"
        [ describe "Parsing"
            [ test "Parses a valid machine definition" <|
                \_ ->
                    let
                        json = """
{
  "module": "test",
  "machine": {
    "initial": { "to": "Idle" },
    "common": { "logs": "list<text>" },
    "states": {
      "Idle": {
        "pokes": {
          "start": {
            "return": {
              "transition": {
                "to": "Running",
                "data": { "count": "0" }
              }
            }
          }
        }
      },
      "Running": {
        "data": { "count": "number" },
        "pokes": {
          "tick": {
            "return": {
              "transition": {
                "to": "Running",
                "data": { "count": "count + 1" }
              }
            }
          }
        }
      }
    }
  }
}
"""
                    in
                    Decode.decode json |> Expect.ok
            ]
        , describe "Typechecking"
            [ test "Fails on transition to unknown state" <|
                \_ ->
                    let
                        prog =
                            { emptyProgram
                                | machine =
                                    Just
                                        { initial = { to = "Idle", data = Dict.empty }
                                        , common = Dict.empty
                                        , states =
                                            Dict.singleton "Idle"
                                                { data = Dict.empty
                                                , pokes = Dict.singleton "start" { mark = Nothing, input = [], body = loc (Source.ETransition { to = "Unknown", data = Dict.empty, common = Nothing }) }
                                                , scries = Dict.empty
                                                , watches = Dict.empty
                                                }
                                        }
                            }
                    in
                    -- This will currently pass (return Ok) because I stubbed Typecheck.elm to return Ok
                    Typecheck.check prog |> Expect.equal (Err [ "In machine.states.Idle.pokes.start.return at line 0, col 0: Transition to unknown state: Unknown" ])
            , test "Fails on missing data for state transition" <|
                \_ ->
                    let
                        prog =
                            { emptyProgram
                                | machine =
                                    Just
                                        { initial = { to = "Idle", data = Dict.empty }
                                        , common = Dict.empty
                                        , states =
                                            Dict.fromList
                                                [ ( "Idle"
                                                  , { data = Dict.empty
                                                    , pokes = Dict.singleton "start" { mark = Nothing, input = [], body = loc (Source.ETransition { to = "Running", data = Dict.empty, common = Nothing }) }
                                                    , scries = Dict.empty
                                                    , watches = Dict.empty
                                                    }
                                                  )
                                                , ( "Running"
                                                  , { data = Dict.singleton "count" Source.TypeNumber
                                                    , pokes = Dict.empty
                                                    , scries = Dict.empty
                                                    , watches = Dict.empty
                                                    }
                                                  )
                                                ]
                                        }
                            }
                    in
                    Typecheck.check prog |> Expect.equal (Err [ "In machine.states.Idle.pokes.start.return at line 0, col 0: Missing data fields for state Running: count" ])
            , test "Succeeds when data and common fields are available in scope" <|
                \_ ->
                    let
                        prog =
                            { emptyProgram
                                | machine =
                                    Just
                                        { initial = { to = "Running", data = Dict.singleton "count" (loc (Source.ENumber "0")) }
                                        , common = Dict.singleton "owner" Source.TypeText
                                        , states =
                                            Dict.singleton "Running"
                                                { data = Dict.singleton "count" Source.TypeNumber
                                                , pokes = Dict.singleton "tick" { mark = Nothing, input = [], body = loc (Source.ETransition { to = "Running", data = Dict.singleton "count" (loc (Source.EBinary Source.Add (loc (Source.EName "count")) (loc (Source.ENumber "1")))), common = Nothing }) }
                                                , scries = Dict.singleton "/owner" { output = Source.TypeText, body = loc (Source.EName "owner") }
                                                , watches = Dict.empty
                                                }
                                        }
                            }
                    in
                    Typecheck.check prog |> Expect.ok
            , test "Fails when transition data type is incorrect" <|
                \_ ->
                    let
                        prog =
                            { emptyProgram
                                | machine =
                                    Just
                                        { initial = { to = "Running", data = Dict.singleton "count" (loc (Source.EText "not a number")) }
                                        , common = Dict.empty
                                        , states =
                                            Dict.singleton "Running"
                                                { data = Dict.singleton "count" Source.TypeNumber
                                                , pokes = Dict.empty
                                                , scries = Dict.empty
                                                , watches = Dict.empty
                                                }
                                        }
                            }
                    in
                    Typecheck.check prog |> Expect.equal (Err [ "In machine.initial at line 0, col 0: Type mismatch: expected number, got text" ])
            , test "Succeeds with common field updates in transition" <|
                \_ ->
                    let
                        prog =
                            { emptyProgram
                                | machine =
                                    Just
                                        { initial = { to = "Idle", data = Dict.empty }
                                        , common = Dict.singleton "status" Source.TypeText
                                        , states =
                                            Dict.fromList
                                                [ ( "Idle"
                                                  , { data = Dict.empty
                                                    , pokes = Dict.singleton "go" { mark = Nothing, input = [], body = loc (Source.ETransition { to = "Idle", data = Dict.empty, common = Just (Dict.singleton "status" (loc (Source.EText "active"))) }) }
                                                    , scries = Dict.empty
                                                    , watches = Dict.empty
                                                    }
                                                  )
                                                ]
                                        }
                            }
                    in
                    Typecheck.check prog |> Expect.ok
            , test "Fails on invalid common field update type" <|
                \_ ->
                    let
                        prog =
                            { emptyProgram
                                | machine =
                                    Just
                                        { initial = { to = "Idle", data = Dict.empty }
                                        , common = Dict.singleton "status" Source.TypeText
                                        , states =
                                            Dict.fromList
                                                [ ( "Idle"
                                                  , { data = Dict.empty
                                                    , pokes = Dict.singleton "go" { mark = Nothing, input = [], body = loc (Source.ETransition { to = "Idle", data = Dict.empty, common = Just (Dict.singleton "status" (loc (Source.ENumber "123"))) }) }
                                                    , scries = Dict.empty
                                                    , watches = Dict.empty
                                                    }
                                                  )
                                                ]
                                        }
                            }
                    in
                    Typecheck.check prog |> Expect.equal (Err [ "In machine.states.Idle.pokes.go.return at line 0, col 0: Type mismatch: expected text, got number" ])
            , test "Fails on transition providing unknown state data field" <|
                \_ ->
                    let
                        prog =
                            { emptyProgram
                                | machine =
                                    Just
                                        { initial = { to = "Idle", data = Dict.singleton "oops" (loc (Source.ENumber "1")) }
                                        , common = Dict.empty
                                        , states =
                                            Dict.singleton "Idle"
                                                { data = Dict.empty
                                                , pokes = Dict.empty
                                                , scries = Dict.empty
                                                , watches = Dict.empty
                                                }
                                        }
                            }
                    in
                    -- Currently checkTransitionData only checks for MISSING fields, not EXTRA fields.
                    -- This is fine for now but I could make it stricter.
                    Typecheck.check prog |> Expect.ok
            ]
        , describe "Lowering"
            [ test "Lowers a simple machine to Hoon arms" <|
                \_ ->
                    let
                        oldOpts =
                            emptyProgram.options

                        prog =
                            { emptyProgram
                                | options = { oldOpts | target = Source.Gall }
                                , machine =
                                    Just
                                        { initial = { to = "Idle", data = Dict.empty }
                                        , common = Dict.singleton "owner" Source.TypeText
                                        , states =
                                            Dict.singleton "Idle"
                                                { data = Dict.empty
                                                , pokes = Dict.singleton "start" { mark = Nothing, input = [], body = loc (Source.ETransition { to = "Running", data = Dict.singleton "count" (loc (Source.ENumber "0")), common = Nothing }) }
                                                , scries = Dict.empty
                                                , watches = Dict.empty
                                                }
                                        }
                            }

                        lowered =
                            Lower.lower prog
                    in
                    -- We just check that it produces the expected arms
                    case lowered of
                        Hoon.HoonModule _ _ arms ->
                            let
                                armNames =
                                    List.map (\(Hoon.HoonArm name _) -> name) arms
                            in
                            Expect.all
                                [ \names -> List.member "state-v0" names |> Expect.equal True
                                , \names -> List.member "initial-state" names |> Expect.equal True
                                , \names -> List.member "on-poke" names |> Expect.equal True
                                , \names -> List.member "idle-start" names |> Expect.equal True
                                ]
                                armNames

                        _ ->
                            Expect.fail "Expected HoonModule"
            ]
        ]


emptyProgram : Source.Program
emptyProgram =
    { moduleName = "test"
    , docs = []
    , options = { textRepresentation = Source.Cord, numberRepresentation = Source.UnsignedDecimal, target = Source.Library, prog_context_types = Dict.empty }
    , imports = []
    , types = Dict.empty
    , macros = Dict.empty
    , native = Dict.empty
    , state = Nothing
    , onLoad = Nothing
    , pokes = Dict.empty
    , watches = Dict.empty
    , scries = Dict.empty
    , constants = Dict.empty
    , functions = Dict.empty
    , tests = Dict.empty
    , machine = Nothing
    }


loc : Source.Expr -> Source.LocatedExpr
loc e =
    { pos = { line = 0, col = 0 }, expr = e }
