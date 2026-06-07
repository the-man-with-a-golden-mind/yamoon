module LanguageFeaturesTest exposing (..)

import Compiler.Lower as Lower
import Compiler.Macro as Macro
import Compiler.Typecheck as Typecheck
import Expect
import Hoon.Pretty as Pretty
import Source.Ast as Source
import Source.Decode as Decode
import Test exposing (..)


suite : Test
suite =
    describe "Full Pipeline Language Features"
        [ describe "Bindings Golden Tests"
            [ test "Let and Set" <|
                \_ ->
                    let
                        json = """
{
  "module": "test",
  "functions": {
    "f": {
      "input": { "x": "number" },
      "output": "number",
      "return": {
        "set": { "x": "x + 1" },
        "in": {
          "let": { "y": "x * 2" },
          "in": "y"
        }
      }
    }
  }
}
"""
                        expected = "\n\n|%\n  ++  f\n    |=  x=@ud\n      =.  x  (add x 1)\n      =+  y=(mul x 2)\n      y\n--"
                    in
                    runPipeline json |> Expect.equal (Ok expected)
            , test "Loop" <|
                \_ ->
                    let
                        json = """
{
  "module": "test",
  "functions": {
    "f": {
      "output": "number",
      "return": {
        "loop": {
          "args": { "i": "0", "acc": "0" },
          "return": {
            "if": "i == 10",
            "then": "acc",
            "else": {
              "set": { "i": "i + 1", "acc": "acc + i" },
              "in": "recurse()"
            }
          }
        }
      }
    }
  }
}
"""
                    in
                    runPipeline json |> Expect.ok
            ]
        , describe "Assertions and Unless"
            [ test "Assert and Unless" <|
                \_ ->
                    let
                        json = """
{
  "module": "test",
  "functions": {
    "f": {
      "input": { "b": "bool" },
      "output": "number",
      "return": {
        "assert": "b",
        "in": {
          "unless": "b",
          "in": 42
        }
      }
    }
  }
}
"""
                    in
                    runPipeline json |> Expect.ok
            ]
        , describe "Native Library Golden Tests"
            [ test "Sha256" <|
                \_ ->
                    let
                        json = """
{
  "module": "test",
  "functions": {
    "hash": {
      "input": { "t": "text" },
      "output": "raw-hoon<atom>",
      "return": "sha256(t)"
    }
  }
}
"""
                    in
                    runPipeline json |> Expect.ok
            ]
        , describe "Complex Types and Variants"
            [ test "Union and Match" <|
                \_ ->
                    let
                        json = """
{
  "module": "test",
  "types": {
    "Shape": {
      "kind": "union",
      "variants": {
        "Circle": { "radius": "number" },
        "Square": { "side": "number" }
      }
    }
  },
  "functions": {
    "area": {
      "input": { "s": "Shape" },
      "output": "number",
      "return": {
        "match": "s",
        "cases": {
          "Circle": "radius * radius",
          "Square": "side * side"
        }
      }
    }
  }
}
"""
                    in
                    runPipeline json |> Expect.ok
            ]
        , describe "Casting"
            [ test "Simple Cast" <|
                \_ ->
                    let
                        json = """
{
  "module": "test",
  "functions": {
    "f": {
      "input": { "n": "number" },
      "output": "nat",
      "return": {
        "cast": "nat",
        "value": "n"
      }
    }
  }
}
"""
                    in
                    runPipeline json |> Expect.ok
            ]
        , describe "Jets"
            [ test "Jetted Function Lowering" <|
                \_ ->
                    let
                        json = """
{
  "module": "test",
  "functions": {
    "dec": {
      "input": { "x": "number" },
      "output": "number",
      "jet": "dec",
      "return": "x - 1"
    }
  }
}
"""
                        expected = "\n\n|%\n  ++  dec\n    ~%  %dec  ..  |=(x=@ud (sub x 1))\n--"
                    in
                    runPipeline json |> Expect.equal (Ok expected)
            ]
        ]


runPipeline : String -> Result String String
runPipeline json =
    case Decode.decode json of
        Ok program ->
            let
                expanded =
                    Macro.expand program
            in
            case Typecheck.check expanded of
                Ok () ->
                    let
                        hoonAst =
                            Lower.lower expanded

                        hoonCode =
                            Pretty.render expanded.options hoonAst
                    in
                    Ok hoonCode

                Err errs ->
                    Err (String.join "\n" errs)

        Err err ->
            Err err
