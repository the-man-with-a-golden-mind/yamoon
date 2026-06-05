module Source.Ast exposing (..)

import Dict exposing (Dict)


type alias Program =
    { moduleName : String
    , docs : List String
    , options : Options
    , imports : List String
    , types : Dict String TypeDef
    , macros : Dict String MacroDef
    , native : Dict String NativeDef
    , state : Maybe StateDef
    , onLoad : Maybe LocatedExpr
    , pokes : Dict String PokeDef
    , watches : Dict String LocatedExpr
    , scries : Dict String ScryDef
    , constants : Dict String TypedValueOrExpr
    , functions : Dict String FunctionDef
    , tests : Dict String TestDef
    }


type alias NativeDef =
    { type_args : List String
    , input : List ( String, TypeRef )
    , output : TypeRef
    }


type alias Options =
    { textRepresentation : TextRepresentation
    , numberRepresentation : NumberRepresentation
    , target : Target
    , prog_context_types : Dict String TypeDef
    }


type Target
    = Library
    | Gall


type alias MacroDef =
    { args : List String
    , expand : LocatedExpr
    }


type alias StateDef =
    { version : Int
    , fields : Dict String TypeRef
    }


type alias PokeDef =
    { mark : Maybe String
    , input : List ( String, TypeRef )
    , body : LocatedExpr
    }


type alias ScryDef =
    { output : TypeRef
    , body : LocatedExpr
    }


type TestDef
    = UnitTest UnitTestData
    | ScenarioTest ScenarioTestData
    | MigrationTest MigrationTestData


type alias UnitTestData =
    { func : String
    , cases : List { input : Dict String LiteralValue, expect : LiteralValue }
    , fuzz : Bool
    }


type alias ScenarioTestData =
    { setup : String
    , steps : List ScenarioStep
    }


type alias ScenarioStep =
    { action : ScenarioAction
    , expect : ScenarioExpect
    }


type ScenarioAction
    = PokeAction { route : String, payload : Dict String LiteralValue }
    | WaitAction { duration : String }


type alias ScenarioExpect =
    { cards : Maybe (List LiteralValue)
    , scries : Dict String LiteralValue
    , state : Maybe (Dict String LiteralValue)
    }


type alias MigrationTestData =
    { fromVersion : Int
    , oldState : String
    , expectState : Dict String LiteralValue
    }


type TextRepresentation
    = Cord
    | Tape


type NumberRepresentation
    = Atom
    | UnsignedDecimal


type TypeDef
    = Record (Dict String TypeRef)
    | Union (Dict String (Maybe (Dict String TypeRef)))
    | Alias TypeRef


type TypeRef
    = TypeNumber
    | TypeNat
    | TypeText
    | TypeBool
    | TypeList TypeRef
    | TypePair TypeRef TypeRef
    | TypeQuip TypeRef TypeRef
    | TypeCard
    | TypeUnit TypeRef
    | TypeMap TypeRef TypeRef
    | TypeSet TypeRef
    | TypeNamed String
    | TypeRawHoon String


type alias TypedValueOrExpr =
    { type_ : Maybe TypeRef
    , value : ValueOrExpr
    }


type ValueOrExpr
    = Literal LiteralValue
    | Computed LocatedExpr
    | RawHoon String


type LiteralValue
    = LitNumber String
    | LitText String
    | LitBool Bool
    | LitList (List LiteralValue)
    | LitObject (Dict String LiteralValue)
    | LitRecord String (Dict String LiteralValue)
    | LitVariant String String (Dict String LiteralValue)


type alias FunctionDef =
    { type_args : List String
    , input : List ( String, TypeRef )
    , output : TypeRef
    , body : LocatedExpr
    }


type alias LocatedExpr =
    { pos : Pos
    , expr : Expr
    }


type alias Pos =
    { line : Int
    , col : Int
    }


type Expr
    = ENumber String
    | EText String
    | EInterpolated (List LocatedExpr)
    | EBool Bool
    | EName String
    | EField LocatedExpr String
    | EList (List LocatedExpr)
    | ECall String (List LocatedExpr)
    | ERecord String (Dict String LocatedExpr)
    | EVariant String String (Dict String LocatedExpr)
    | EDict (Dict String LocatedExpr)
    | ERune String (List LocatedExpr)
    | ELoop (Dict String LocatedExpr) LocatedExpr
    | ELet String LocatedExpr LocatedExpr
    | ESet String LocatedExpr LocatedExpr
    | EAssert LocatedExpr LocatedExpr
    | EUnless LocatedExpr LocatedExpr
    | ECast TypeRef LocatedExpr
    | EMatch LocatedExpr (Dict String LocatedExpr) (Maybe LocatedExpr)
    | EBinary BinaryOp LocatedExpr LocatedExpr
    | EIf LocatedExpr LocatedExpr LocatedExpr
    | EIfNot LocatedExpr LocatedExpr LocatedExpr
    | ERawHoon String


type BinaryOp
    = Add
    | Sub
    | Mul
    | Eq
    | NotEq
    | GreaterThan
    | LessThan
    | GreaterOrEqual
    | LessOrEqual
