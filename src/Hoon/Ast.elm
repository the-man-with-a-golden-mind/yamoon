module Hoon.Ast exposing (..)


type HoonProgram
    = HoonModule (List String) (List HoonDoc) (List HoonArm)
    | HoonTestFile (List String) (List HoonArm)


type alias HoonStateDef =
    { version : Int
    , mold : HoonMold
    }


type HoonDoc
    = HoonComment String


type HoonArm
    = HoonArm String HoonExpr


type HoonExpr
    = HAtom String
    | HCord String
    | HBool Bool
    | HName String
    | HCell HoonExpr HoonExpr
    | HList (List HoonExpr)
    | HCall String (List LocatedHoonExpr)
    | HField LocatedHoonExpr String
    | HCast HoonMold HoonExpr
    | HRune String (List HoonExpr)
    | HLet String HoonExpr HoonExpr
    | HSet String HoonExpr HoonExpr
    | HAssert HoonExpr HoonExpr
    | HUnless HoonExpr HoonExpr
    | HLoop (Maybe LocatedHoonExpr) HoonExpr
    | HMatch LocatedHoonExpr (List ( String, HoonExpr )) (Maybe HoonExpr)
    | HIf HoonExpr HoonExpr HoonExpr
    | HIfNot HoonExpr HoonExpr HoonExpr
    | HGate (List ( String, HoonMold )) HoonExpr
    | HRaw String


type alias LocatedHoonExpr =
    { pos : { line : Int, col : Int }
    , expr : HoonExpr
    }


type HoonMold
    = MAtom
    | MUnsigned
    | MBool
    | MCord
    | MTape
    | MList HoonMold
    | MPair HoonMold HoonMold
    | MRaw String
    | MNamed String
