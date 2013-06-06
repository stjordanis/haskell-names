{-# LANGUAGE DeriveDataTypeable, DeriveFunctor, DeriveFoldable,
             DeriveTraversable #-}
module Language.Haskell.Modules.Types where

import Language.Haskell.Exts.Annotated
import Data.Typeable
import Data.Data
import Data.Monoid
import Data.Lens.Common
import qualified Data.Set as Set
import {-# SOURCE #-} qualified Language.Haskell.Modules.GlobalSymbolTable as Global
import Distribution.Package (PackageId)
import Distribution.Text
import Data.Foldable as F
import Data.Traversable
import Text.Printf

type SymFixity = (Assoc (), Int)

data SymValueInfo name
    = SymValue       { sv_origName :: name, sv_fixity :: Maybe SymFixity }
    | SymMethod      { sv_origName :: name, sv_fixity :: Maybe SymFixity, sv_className :: name }
    | SymSelector    { sv_origName :: name, sv_fixity :: Maybe SymFixity, sv_typeName :: name }
    | SymConstructor { sv_origName :: name, sv_fixity :: Maybe SymFixity, sv_typeName :: name }
    deriving (Eq, Ord, Show, Data, Typeable, Functor, Foldable, Traversable)

data SymTypeInfo name
    = SymType        { st_origName :: name, st_fixity :: Maybe SymFixity }
    | SymData        { st_origName :: name, st_fixity :: Maybe SymFixity }
    | SymNewType     { st_origName :: name, st_fixity :: Maybe SymFixity }
    | SymTypeFam     { st_origName :: name, st_fixity :: Maybe SymFixity }
    | SymDataFam     { st_origName :: name, st_fixity :: Maybe SymFixity }
    | SymClass       { st_origName :: name, st_fixity :: Maybe SymFixity }
    deriving (Eq, Ord, Show, Data, Typeable, Functor, Foldable, Traversable)

class HasOrigName i where
  origName :: i n -> n

instance HasOrigName SymValueInfo where
  origName = sv_origName

instance HasOrigName SymTypeInfo where
  origName = st_origName

-- | The set of symbols (entities) exported by a single module. Contains
-- the sets of value-level and type-level entities.
data Symbols = Symbols (Set.Set (SymValueInfo OrigName)) (Set.Set (SymTypeInfo OrigName))
  deriving (Eq, Ord, Show, Data, Typeable)

instance Monoid Symbols where
  mempty = Symbols mempty mempty
  mappend (Symbols s1 t1) (Symbols s2 t2) =
    Symbols (s1 `mappend` s2) (t1 `mappend` t2)

valSyms :: Lens Symbols (Set.Set (SymValueInfo OrigName))
valSyms = lens (\(Symbols vs _) -> vs) (\vs (Symbols _ ts) -> Symbols vs ts)

tySyms :: Lens Symbols (Set.Set (SymTypeInfo OrigName))
tySyms = lens (\(Symbols _ ts) -> ts) (\ts (Symbols vs _) -> Symbols vs ts)

mkVal :: SymValueInfo OrigName -> Symbols
mkVal i = Symbols (Set.singleton i) mempty

mkTy :: SymTypeInfo OrigName -> Symbols
mkTy i = Symbols mempty (Set.singleton i)

type NameS = String
type ModuleNameS = String

-- | Possibly qualified name. If the name is not qualified,
-- 'ModuleNameS' is the empty string.
data GName = GName ModuleNameS NameS
  deriving (Eq, Ord, Show, Data, Typeable)

ppGName :: GName -> String
ppGName (GName mod name) = printf "%s.%s" mod name

-- | Qualified name, where 'ModuleNameS' points to the module where the
-- name was originally defined. The module part is never empty.
--
-- Also contains name and version of the package where it was defined. If
-- it's 'Nothing', then the entity is defined in the \"current\" package.
data OrigName = OrigName
  { origPackage :: Maybe PackageId
  , origGName :: GName
  }
  deriving (Eq, Ord, Show, Data, Typeable)

ppOrigName :: OrigName -> String
ppOrigName (OrigName mbPkg gname) =
  maybe "" (\pkgid -> printf "%s:" $ display pkgid) mbPkg ++
  ppGName gname

data Scoped l = Scoped (NameInfo l) l
  deriving (Functor, Foldable, Traversable, Show, Typeable, Data, Eq, Ord)

data NameInfo l
    = GlobalValue (SymValueInfo OrigName)
    | GlobalType  (SymTypeInfo  OrigName)
    | LocalValue  SrcLoc
    | TypeVar     SrcLoc
    | Binder
    | Import      Global.Table
    | ImportPart  Symbols
    | Export      Symbols
    | None
    | ScopeError  (Error l)
    deriving (Functor, Foldable, Traversable, Show, Typeable, Data, Eq, Ord)

data Error l
  = ENotInScope (QName l) -- FIXME annotate with namespace (types/values)
  | EAmbiguous (QName l) [OrigName]
  | ETypeAsClass (QName l)
  | EClassAsType (QName l)
  | ENotExported
      (Maybe (Name l)) -- optional parent, e.g. Bool in Bool(Right)
      (Name l)         -- the name which is not exported
      (ModuleName l)
  | EModNotFound (ModuleName l)
  | EExportConflict [(NameS, [ExportSpec l])]
  | EInternal String
  deriving (Data, Typeable, Show, Functor, Foldable, Traversable, Eq, Ord)

ppError :: (Show l, SrcInfo l) => Error l -> String
ppError e =
  case e of
    ENotInScope qn -> printf "%s: not in scope: %s\n"
      (ppLoc qn)
      (prettyPrint qn)
    EAmbiguous qn names ->
      printf "%s: ambiguous name %s\nIt may refer to:\n"
        (ppLoc qn)
        (prettyPrint qn)
      ++
        F.concat (map (printf "  %s\n" . ppOrigName) names)
    EModNotFound mod ->
      printf "%s: module not found: %s\n"
        (ppLoc mod)
        (prettyPrint mod)
    ENotExported mbParent name mod ->
      printf "%s: %s does not export %s\n"
        (ppLoc name)
        (prettyPrint mod)
        (prettyPrint name)
        -- FIXME: make use of mbParent
    _ -> printf "%s\n" $ show e

  where
    ppLoc :: (Annotated a, SrcInfo l) => a l -> String
    ppLoc = prettyPrint . getPointLoc . ann

instance (SrcInfo l) => SrcInfo (Scoped l) where
    toSrcInfo l1 ss l2 = Scoped None $ toSrcInfo l1 ss l2
    fromSrcInfo = Scoped None . fromSrcInfo
    getPointLoc = getPointLoc . sLoc
    fileName = fileName . sLoc
    startLine = startLine . sLoc
    startColumn = startColumn . sLoc

sLoc :: Scoped l -> l
sLoc (Scoped _ l) = l
