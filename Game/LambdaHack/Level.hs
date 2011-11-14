module Game.LambdaHack.Level
  ( Party, SmellTime(..), SmellMap, SecretMap
  , ItemMap, TileMap, Level(..)
  , updateHeroes, updateHeroItem, updateMonsters, updateMonItem
  , updateLMap, updateLRMap, updateIMap
  , updateSmell , at, rememberAt, iat, irememberAt
  , accessible, openable, findLoc, findLocTry, dropItemsAt
  ) where

import Data.Binary
import qualified Data.List as L
import qualified Data.IntMap as IM

import Game.LambdaHack.Utils.Assert
import Game.LambdaHack.Geometry
import Game.LambdaHack.Loc
import Game.LambdaHack.Actor
import Game.LambdaHack.Item
import Game.LambdaHack.Content.TileKind
import Game.LambdaHack.Random
import qualified Game.LambdaHack.Tile as Tile
import qualified Game.LambdaHack.Feature as F
import qualified Game.LambdaHack.Kind as Kind

type Party = IM.IntMap Actor

type PartyItem = IM.IntMap [Item]

newtype SmellTime = SmellTime{smelltime :: Time} deriving Show
instance Binary SmellTime where
  put = put . smelltime
  get = fmap SmellTime get
type SmellMap = IM.IntMap SmellTime

type SecretMap = IM.IntMap Tile.SecretStrength

type ItemMap = IM.IntMap ([Item], [Item])

type TileMap = Kind.Array Loc TileKind

data Level = Level
  { lheroes   :: Party      -- ^ all heroes on the level
  , lheroItem :: PartyItem
  , lxsize    :: X
  , lysize    :: Y
  , lmonsters :: Party      -- ^ all monsters on the level
  , lmonItem  :: PartyItem
  , lsmell    :: SmellMap
  , lsecret   :: SecretMap
  , litem     :: ItemMap
  , lmap      :: TileMap
  , lrmap     :: TileMap
  , lmeta     :: String
  , lstairs   :: (Loc, Loc) -- ^ here the stairs (down, up) from other levels end
  }
  deriving Show

updateLMap :: (TileMap -> TileMap) -> Level -> Level
updateLMap f lvl = lvl { lmap = f (lmap lvl) }

updateLRMap :: (TileMap -> TileMap) -> Level -> Level
updateLRMap f lvl = lvl { lrmap = f (lrmap lvl) }

updateIMap :: (IM.IntMap ([Item], [Item]) ->
               IM.IntMap ([Item], [Item])) -> Level
              -> Level
updateIMap f lvl = lvl { litem = f (litem lvl) }

updateSmell :: (SmellMap -> SmellMap) -> Level -> Level
updateSmell f lvl = lvl { lsmell = f (lsmell lvl) }

updateHeroes :: (Party -> Party) -> Level -> Level
updateHeroes f lvl = lvl { lheroes = f (lheroes lvl) }

updateHeroItem :: (PartyItem -> PartyItem) -> Level -> Level
updateHeroItem f lvl = lvl { lheroItem = f (lheroItem lvl) }

updateMonsters :: (Party -> Party) -> Level -> Level
updateMonsters f lvl = lvl { lmonsters = f (lmonsters lvl) }

updateMonItem :: (PartyItem -> PartyItem) -> Level -> Level
updateMonItem f lvl = lvl { lmonItem = f (lmonItem lvl) }

instance Binary Level where
  put (Level hs hi sx sy ms mi ls le li lm lrm lme lstairs) =
        do
          put hs
          put hi
          put sx
          put sy
          put ms
          put mi
          put ls
          put le
          put (assert
                 (IM.null (IM.filter (\ (is1, is2) ->
                                       L.null is1 && L.null is2) li)
                 `blame` li) li)
          put lm
          put lrm
          put lme
          put lstairs
  get = do
          hs <- get
          hi <- get
          sx <- get
          sy <- get
          ms <- get
          mi <- get
          ls <- get
          le <- get
          li <- get
          lm <- get
          lrm <- get
          lme <- get
          lstairs <- get
          return (Level hs hi sx sy ms mi ls le li lm lrm lme lstairs)

at, rememberAt :: Level -> Loc -> (Kind.Id TileKind)
at         l p = lmap l Kind.! p
rememberAt l p = lrmap l Kind.! p

-- Note: representations with 2 maps leads to longer code and slower 'remember'.
iat, irememberAt :: Level -> Loc -> [Item]
iat         l p = fst $ IM.findWithDefault ([], []) p (litem l)
irememberAt l p = snd $ IM.findWithDefault ([], []) p (litem l)

-- Check whether one location is accessible from the other.
-- Precondition: the two locations are next to each other.
-- Currently only implements that the target location has to be open.
-- TODO: in the future check flying for chasms, swimming for water, etc.
accessible :: Kind.COps -> Level -> Loc -> Loc -> Bool
accessible cops lvl _source target =
  let tgt = lvl `at` target
  in  Tile.isWalkable cops tgt

-- check whether the location contains a door of secrecy level lower than k
openable :: Kind.COps -> Level -> Tile.SecretStrength -> Loc -> Bool
openable cops lvl k target =
  let le = lsecret lvl
      tgt = lvl `at` target
  in Tile.hasFeature cops F.Openable tgt ||
     (Tile.hasFeature cops F.Hidden tgt &&
      le IM.! target < k)

-- Do not scatter items around, it's too much work for the player.
dropItemsAt :: [Item] -> Loc -> Level -> Level
dropItemsAt [] _loc = id
dropItemsAt items loc =
  let joinItems = L.foldl' (\ acc i -> snd (joinItem i acc))
      adj Nothing = Just (items, [])
      adj (Just (i, ri)) = Just (joinItems items i, ri)
  in  updateIMap (IM.alter adj loc)

findLoc :: TileMap -> (Loc -> (Kind.Id TileKind) -> Bool) -> Rnd Loc
findLoc lmap p =
  let search = do
        loc <- randomR $ Kind.bounds lmap
        let tile = lmap Kind.! loc
        if p loc tile
          then return loc
          else search
  in search

findLocTry ::
  Int ->  -- try to pTry only so many times
  TileMap ->
  (Loc -> Kind.Id TileKind -> Bool) ->  -- loop until satisfied
  (Loc -> Kind.Id TileKind -> Bool) ->  -- only try to satisfy k times
  Rnd Loc
findLocTry numTries lmap p pTry =
  let search k = do
        loc <- randomR $ Kind.bounds lmap
        let tile = lmap Kind.! loc
        if p loc tile && pTry loc tile
          then return loc
          else if k > 1
            then search (k - 1)
            else findLoc lmap p
  in assert (numTries > 0) $
     search numTries
