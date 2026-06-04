module GoldenTest exposing (..)

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
    describe "Full Pipeline Golden Tests"
        [ test "Basic Module Golden Test" <|
            \_ ->
                let
                    input =
                        """
module: test
constants:
  a: 1
functions:
  inc:
    input: { x: number }
    output: number
    return: x + 1
"""
                in
                runPipeline input
                    |> Expect.equal (Ok expectedBasicHoon)
        , test "Macro Expansion Golden Test" <|
            \_ ->
                let
                    input =
                        """
module: test
macros:
  sq:
    args: [x]
    expand: x * x
functions:
  f:
    input: { n: number }
    output: number
    return: sq(n)
"""
                in
                runPipeline input
                    |> Expect.equal (Ok expectedMacroHoon)
        , test "Record and Field Access Golden Test" <|
            \_ ->
                let
                    input =
                        """
module: test
types:
  Point:
    kind: record
    fields: { x: number, y: number }
functions:
  getX:
    input: { p: Point }
    output: number
    return: p.x
"""
                in
                runPipeline input
                    |> Expect.equal (Ok expectedRecordHoon)
        , test "Generic Rune Golden Test" <|
            \_ ->
                let
                    input =
                        """
module: test
functions:
  f:
    input: { val: number }
    output: number
    return:
      rune: "|-"
      args:
        - rune: "?:"
          args:
            - val == 0
            - 42
            - rune: "$@"
              args: []
"""
                in
                runPipeline input
                    |> Expect.equal (Ok expectedRuneHoon)
        ]


runPipeline : String -> Result String String
runPipeline yamlJson =
    case Decode.decode (mockYamlToJson yamlJson) of
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


mockYamlToJson : String -> String
mockYamlToJson s =
    if String.contains "macros" s && String.contains "sq" s then
        """{"module": "test", "macros": {"sq": {"args": ["x"], "expand": "x * x"}}, "functions": {"f": {"input": {"n": "number"}, "output": "number", "return": "sq(n)"}}}"""

    else if String.contains "Point" s then
        """{"module": "test", "types": {"Point": {"kind": "record", "fields": {"x": "number", "y": "number"}}}, "functions": {"getX": {"input": {"p": "Point"}, "output": "number", "return": "p.x"}}}"""

    else if String.contains "$@" s then
        """{"module": "test", "functions": {"f": {"input": [{"val": "number"}], "output": "number", "return": {"rune": "|-", "args": [{"rune": "?:", "args": ["val == 0", 42, {"rune": "$@", "args": []}]}]}}}}"""

    else
        """{"module": "test", "constants": {"a": 1}, "functions": {"inc": {"input": {"x": "number"}, "output": "number", "return": "x + 1"}}}"""


expectedBasicHoon : String
expectedBasicHoon =
    "\n\n|%\n  ++  a\n    1\n  \n  ++  inc\n    |=  x=@ud\n      (add x 1)\n--"


expectedMacroHoon : String
expectedMacroHoon =
    "\n\n|%\n  ++  f\n    |=  n=@ud\n      (mul n n)\n--"


expectedRecordHoon : String
expectedRecordHoon =
    "\n\n|%\n  ++  Point\n    ,[x=@ud y=@ud]\n  \n  ++  getX\n    |=  p=Point\n      x.p\n--"


expectedRuneHoon : String
expectedRuneHoon =
    "\n\n|%\n  ++  f\n    |=  val=@ud\n      |-(?:(=(val 0) 42 $@))\n--"
