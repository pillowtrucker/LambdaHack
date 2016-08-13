{-# LANGUAGE DeriveGeneric, GeneralizedNewtypeDeriving #-}
-- | Weapons, treasure and all the other items in the game.
-- No operation in this module involves the state or any of our custom monads.
module Game.LambdaHack.Common.Item
  ( -- * The @Item@ type
    ItemId, Item(..)
  , seedToAspectsEffects, meanAspectEffects, aspectRecordToList
    -- * Item discovery types
  , ItemKindIx, KindMean(..), DiscoveryKind, ItemSeed
  , ItemAspectEffect(..), AspectRecord(..), DiscoveryEffect
  , ItemFull(..), ItemDisco(..), itemNoDisco, itemNoAE
    -- * Inventory management types
  , ItemTimer, ItemQuant, ItemBag, ItemDict, ItemKnown
  ) where

import Prelude ()

import Game.LambdaHack.Common.Prelude

import qualified Control.Monad.State as St
import Data.Binary
import qualified Data.EnumMap.Strict as EM
import Data.Hashable (Hashable)
import qualified Data.Ix as Ix
import GHC.Generics (Generic)
import System.Random (mkStdGen)

import qualified Game.LambdaHack.Common.Ability as Ability
import qualified Game.LambdaHack.Common.Dice as Dice
import Game.LambdaHack.Common.Flavour
import qualified Game.LambdaHack.Common.Kind as Kind
import Game.LambdaHack.Common.Misc
import Game.LambdaHack.Common.Random
import Game.LambdaHack.Common.Time
import qualified Game.LambdaHack.Content.ItemKind as IK

-- | A unique identifier of an item in the dungeon.
newtype ItemId = ItemId Int
  deriving (Show, Eq, Ord, Enum, Binary)

-- | An index of the kind id of an item. Clients have partial knowledge
-- how these idexes map to kind ids. They gain knowledge by identifying items.
newtype ItemKindIx = ItemKindIx Int
  deriving (Show, Eq, Ord, Enum, Ix.Ix, Hashable, Binary)

data KindMean = KindMean
  { kmKind :: !(Kind.Id IK.ItemKind)
  , kmMean :: !ItemAspectEffect }
  deriving (Show, Eq, Generic)

instance Binary KindMean

-- | The map of item kind indexes to item kind ids.
-- The full map, as known by the server, is a bijection.
type DiscoveryKind = EM.EnumMap ItemKindIx KindMean

-- | A seed for rolling aspects and effects of an item
-- Clients have partial knowledge of how item ids map to the seeds.
-- They gain knowledge by identifying items.
newtype ItemSeed = ItemSeed Int
  deriving (Show, Eq, Ord, Enum, Hashable, Binary)

newtype ItemAspectEffect = ItemAspectEffect {jaspects :: AspectRecord}
  deriving (Show, Eq, Generic)

instance Binary ItemAspectEffect

instance Hashable ItemAspectEffect

data AspectRecord = AspectRecord
  { aUnique      :: !Bool
  , aPeriodic    :: !Bool
  , aTimeout     :: !Int
  , aHurtMelee   :: !Int
  , aHurtRanged  :: !Int
  , aArmorMelee  :: !Int
  , aArmorRanged :: !Int
  , aMaxHP       :: !Int
  , aMaxCalm     :: !Int
  , aSpeed       :: !Int
  , aSight       :: !Int
  , aSmell       :: !Int
  , aShine       :: !Int
  , aNocto       :: !Int
  , aAbility     :: !Ability.Skills
  }
  deriving (Show, Eq, Generic)

instance Binary AspectRecord

instance Hashable AspectRecord

emptyAspectRecord :: AspectRecord
emptyAspectRecord = AspectRecord
  { aUnique      = False
  , aPeriodic    = False
  , aTimeout     = 0
  , aHurtMelee   = 0
  , aHurtRanged  = 0
  , aArmorMelee  = 0
  , aArmorRanged = 0
  , aMaxHP       = 0
  , aMaxCalm     = 0
  , aSpeed       = 0
  , aSight       = 0
  , aSmell       = 0
  , aShine       = 0
  , aNocto       = 0
  , aAbility     = EM.empty
  }

-- | The map of item ids to item aspects and effects.
-- The full map is known by the server.
type DiscoveryEffect = EM.EnumMap ItemId ItemAspectEffect

data ItemDisco = ItemDisco
  { itemKindId :: !(Kind.Id IK.ItemKind)
  , itemKind   :: !IK.ItemKind
  , itemAEmean :: !ItemAspectEffect
  , itemAE     :: !(Maybe ItemAspectEffect)
  }
  deriving Show

data ItemFull = ItemFull
  { itemBase  :: !Item
  , itemK     :: !Int
  , itemTimer :: !ItemTimer
  , itemDisco :: !(Maybe ItemDisco)
  }
  deriving Show

itemNoDisco :: (Item, Int) -> ItemFull
itemNoDisco (itemBase, itemK) =
  ItemFull {itemBase, itemK, itemTimer = [], itemDisco=Nothing}

itemNoAE :: ItemFull -> ItemFull
itemNoAE itemFull@ItemFull{..} =
  let f idisco = idisco {itemAE = Nothing}
      newDisco = fmap f itemDisco
  in itemFull {itemDisco = newDisco}

-- | Game items in actor possesion or strewn around the dungeon.
-- The fields @jsymbol@, @jname@ and @jflavour@ make it possible to refer to
-- and draw an unidentified item. Full information about item is available
-- through the @jkindIx@ index as soon as the item is identified.
data Item = Item
  { jkindIx  :: !ItemKindIx    -- ^ index pointing to the kind of the item
  , jlid     :: !LevelId       -- ^ the level on which item was created
  , jsymbol  :: !Char          -- ^ map symbol
  , jname    :: !Text          -- ^ generic name
  , jflavour :: !Flavour       -- ^ flavour
  , jfeature :: ![IK.Feature]  -- ^ public properties
  , jweight  :: !Int           -- ^ weight in grams, obvious enough
  }
  deriving (Show, Eq, Generic)

instance Hashable Item

instance Binary Item

aspectRecordToList :: AspectRecord -> [IK.Aspect Int]
aspectRecordToList AspectRecord{..} =
  [IK.Unique | aUnique]
  ++ [IK.Periodic | aPeriodic]
  ++ [IK.Timeout aTimeout | aTimeout /= 0]
  ++ [IK.AddHurtMelee aHurtMelee | aHurtMelee /= 0]
  ++ [IK.AddHurtRanged aHurtRanged | aHurtRanged /= 0]
  ++ [IK.AddArmorMelee aArmorMelee | aArmorMelee /= 0]
  ++ [IK.AddArmorRanged aArmorRanged | aArmorRanged /= 0]
  ++ [IK.AddMaxHP aMaxHP | aMaxHP /= 0]
  ++ [IK.AddMaxCalm aMaxCalm | aMaxCalm /= 0]
  ++ [IK.AddSpeed aSpeed | aSpeed /= 0]
  ++ [IK.AddSight aSight | aSight /= 0]
  ++ [IK.AddSmell aSmell | aSmell /= 0]
  ++ [IK.AddShine aShine | aShine /= 0]
  ++ [IK.AddNocto aNocto | aNocto /= 0]
  ++ [IK.AddAbility ab n | (ab, n) <- EM.assocs aAbility, n /= 0]

castAspect :: AbsDepth -> AbsDepth -> AspectRecord -> IK.Aspect Dice.Dice
           -> Rnd AspectRecord
castAspect ldepth totalDepth ar asp =
  case asp of
    IK.Unique -> return $! assert (not $ aUnique ar) $ ar {aUnique = True}
    IK.Periodic -> return $! assert (not $ aPeriodic ar) $ ar {aPeriodic = True}
    IK.Timeout d -> do
      n <- castDice ldepth totalDepth d
      return $! assert (aTimeout ar == 0) $ ar {aTimeout = n}
    IK.AddHurtMelee d -> do  -- TODO: lenses would reduce duplication below
      n <- castDice ldepth totalDepth d
      return $! ar {aHurtMelee = n + aHurtMelee ar}
    IK.AddHurtRanged d -> do
      n <- castDice ldepth totalDepth d
      return $! ar {aHurtRanged = n + aHurtRanged ar}
    IK.AddArmorMelee d -> do
      n <- castDice ldepth totalDepth d
      return $! ar {aArmorMelee = n + aArmorMelee ar}
    IK.AddArmorRanged d -> do
      n <- castDice ldepth totalDepth d
      return $! ar {aArmorRanged = n + aArmorRanged ar}
    IK.AddMaxHP d -> do
      n <- castDice ldepth totalDepth d
      return $! ar {aMaxHP = n + aMaxHP ar}
    IK.AddMaxCalm d -> do
      n <- castDice ldepth totalDepth d
      return $! ar {aMaxCalm = n + aMaxCalm ar}
    IK.AddSpeed d -> do
      n <- castDice ldepth totalDepth d
      return $! ar {aSpeed = n + aSpeed ar}
    IK.AddSight d -> do
      n <- castDice ldepth totalDepth d
      return $! ar {aSight = n + aSight ar}
    IK.AddSmell d -> do
      n <- castDice ldepth totalDepth d
      return $! ar {aSmell = n + aSmell ar}
    IK.AddShine d -> do
      n <- castDice ldepth totalDepth d
      return $! ar {aShine = n + aShine ar}
    IK.AddNocto d -> do
      n <- castDice ldepth totalDepth d
      return $! ar {aNocto = n + aNocto ar}
    IK.AddAbility ab d -> do
      n <- castDice ldepth totalDepth d
      return $! ar {aAbility = Ability.addSkills (EM.singleton ab n)
                                                 (aAbility ar)}

meanAspect :: AspectRecord -> IK.Aspect Dice.Dice
           -> AspectRecord
meanAspect ar asp =
  case asp of
    IK.Unique -> assert (not $ aUnique ar) $ ar {aUnique = True}
    IK.Periodic -> assert (not $ aPeriodic ar) $ ar {aPeriodic = True}
    IK.Timeout d ->
      let n = Dice.meanDice d
      in assert (aTimeout ar == 0) $ ar {aTimeout = n}
    IK.AddHurtMelee d ->
      let n = Dice.meanDice d
      in ar {aHurtMelee = n + aHurtMelee ar}
    IK.AddHurtRanged d ->
      let n = Dice.meanDice d
      in ar {aHurtRanged = n + aHurtRanged ar}
    IK.AddArmorMelee d ->
      let n = Dice.meanDice d
      in ar {aArmorMelee = n + aArmorMelee ar}
    IK.AddArmorRanged d ->
      let n = Dice.meanDice d
      in ar {aArmorRanged = n + aArmorRanged ar}
    IK.AddMaxHP d ->
      let n = Dice.meanDice d
      in ar {aMaxHP = n + aMaxHP ar}
    IK.AddMaxCalm d ->
      let n = Dice.meanDice d
      in ar {aMaxCalm = n + aMaxCalm ar}
    IK.AddSpeed d ->
      let n = Dice.meanDice d
      in ar {aSpeed = n + aSpeed ar}
    IK.AddSight d ->
      let n = Dice.meanDice d
      in ar {aSight = n + aSight ar}
    IK.AddSmell d ->
      let n = Dice.meanDice d
      in ar {aSmell = n + aSmell ar}
    IK.AddShine d ->
      let n = Dice.meanDice d
      in ar {aShine = n + aShine ar}
    IK.AddNocto d ->
      let n = Dice.meanDice d
      in ar {aNocto = n + aNocto ar}
    IK.AddAbility ab d ->
      let n = Dice.meanDice d
      in ar {aAbility = Ability.addSkills (EM.singleton ab n)
                                          (aAbility ar)}

seedToAspectsEffects :: ItemSeed -> IK.ItemKind -> AbsDepth -> AbsDepth
                     -> ItemAspectEffect
seedToAspectsEffects (ItemSeed itemSeed) kind ldepth totalDepth =
  let rollM = foldM (castAspect ldepth totalDepth) emptyAspectRecord
                    (IK.iaspects kind)
      jaspects = St.evalState rollM (mkStdGen itemSeed)
  in ItemAspectEffect{..}

meanAspectEffects :: IK.ItemKind -> ItemAspectEffect
meanAspectEffects kind =
  ItemAspectEffect $ foldl' meanAspect emptyAspectRecord (IK.iaspects kind)

type ItemTimer = [Time]

type ItemQuant = (Int, ItemTimer)

type ItemBag = EM.EnumMap ItemId ItemQuant

-- | All items in the dungeon (including in actor inventories),
-- indexed by item identifier.
type ItemDict = EM.EnumMap ItemId Item

-- | The essential item properties, used for the @ItemRev@ hash table
-- from items to their ids, needed to assign ids to newly generated items.
-- All the other meaningul properties can be derived from the two.
-- Note that @jlid@ is not meaningful; it gets forgotten if items from
-- different levels roll the same random properties and so are merged.
type ItemKnown = (ItemKindIx, ItemAspectEffect)
