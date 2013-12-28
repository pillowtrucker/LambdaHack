-- | Server and client game state types and operations.
module Game.LambdaHack.Common.State
  ( -- * Basic game state, local or global
    State
    -- * State components
  , sdungeon, sdepth, sactorD, sitemD, sfactionD, stime, scops, shigh
    -- * State operations
  , defStateGlobal, emptyState, localFromGlobal
  , updateDungeon, updateDepth, updateActorD, updateItemD
  , updateFaction, updateTime, updateCOps, getLocalTime
  , isSpawnFaction, isSummonFaction
  ) where

import Data.Binary
import qualified Data.EnumMap.Strict as EM
import Data.Text (Text)

import Game.LambdaHack.Common.Actor
import Game.LambdaHack.Common.Faction
import qualified Game.LambdaHack.Common.HighScore as HighScore
import qualified Game.LambdaHack.Common.Kind as Kind
import Game.LambdaHack.Common.Level
import Game.LambdaHack.Common.Point
import Game.LambdaHack.Common.PointXY
import Game.LambdaHack.Common.Time
import Game.LambdaHack.Content.TileKind
import Game.LambdaHack.Utils.Frequency

-- | View on game state. "Remembered" fields carry a subset of the info
-- in the client copies of the state. Clients never directly change
-- their @State@, but apply atomic actions sent by the server to do so.
data State = State
  { _sdungeon  :: !Dungeon      -- ^ remembered dungeon
  , _sdepth    :: !Int          -- ^ dungeon \'depth\' for items creation, etc.
  , _sactorD   :: !ActorDict    -- ^ remembered actors in the dungeon
  , _sitemD    :: !ItemDict     -- ^ remembered items in the dungeon
  , _sfactionD :: !FactionDict  -- ^ remembered sides still in game
  , _stime     :: !Time         -- ^ global game time
  , _scops     :: Kind.COps     -- ^ remembered content
  , _shigh     :: !HighScore.ScoreTable  -- ^ high score table
  }
  deriving (Show, Eq)

-- TODO: add a flag 'fresh' and when saving levels, don't save
-- and when loading regenerate this level.
unknownLevel :: Kind.Ops TileKind -> Int -> X -> Y
             -> Text -> ([Point], [Point]) -> Int -> Int -> Int
             -> Level
unknownLevel Kind.Ops{ouniqGroup} ldepth lxsize lysize ldesc lstair lclear
             lsecret lhidden =
  let unknownId = ouniqGroup "unknown space"
  in Level { ldepth
           , lprio = EM.empty
           , lfloor = EM.empty
           , ltile = unknownTileMap unknownId lxsize lysize
           , lxsize
           , lysize
           , lsmell = EM.empty
           , ldesc
           , lstair
           , lseen = 0
           , lclear
           , ltime = timeTurn
           , litemNum = 0
           , litemFreq = toFreq "client item freq" []
           , lsecret
           , lhidden
           }

unknownTileMap :: Kind.Id TileKind -> Int -> Int -> TileMap
unknownTileMap unknownId cxsize cysize =
  Kind.replicateA cxsize cysize unknownId

-- | Initial complete global game state.
defStateGlobal :: Dungeon -> Int
               -> FactionDict -> Kind.COps -> HighScore.ScoreTable
               -> State
defStateGlobal _sdungeon _sdepth _sfactionD _scops _shigh =
  State
    { _sactorD = EM.empty
    , _sitemD = EM.empty
    , _stime = timeTurn
    , ..
    }

-- | Initial empty state.
emptyState :: State
emptyState =
  State
    { _sdungeon = EM.empty
    , _sdepth = 0
    , _sactorD = EM.empty
    , _sitemD = EM.empty
    , _sfactionD = EM.empty
    , _stime = timeTurn
    , _scops = undefined
    , _shigh = HighScore.empty
    }

-- TODO: make lstair secret until discovered; use this later on for
-- goUp in targeting mode (land on stairs of on the same location up a level
-- if this set of stsirs is unknown).
-- | Local state created by removing secret information from global
-- state components.
localFromGlobal :: State -> State
localFromGlobal State{_scops=_scops@Kind.COps{cotile}, .. } =
  State
    { _sdungeon =
      EM.map (\Level{..} ->
              unknownLevel cotile ldepth lxsize lysize ldesc lstair lclear
                           lsecret lhidden)
            _sdungeon
    , ..
    }

-- | Update dungeon data within state.
updateDungeon :: (Dungeon -> Dungeon) -> State -> State
updateDungeon f s = s {_sdungeon = f (_sdungeon s)}

-- | Update dungeon depth.
updateDepth :: (Int -> Int) -> State -> State
updateDepth f s = s {_sdepth = f (_sdepth s)}

-- | Update the actor dictionary.
updateActorD :: (ActorDict -> ActorDict) -> State -> State
updateActorD f s = s {_sactorD = f (_sactorD s)}

-- | Update the item dictionary.
updateItemD :: (ItemDict -> ItemDict) -> State -> State
updateItemD f s = s {_sitemD = f (_sitemD s)}

-- | Update faction data within state.
updateFaction :: (FactionDict -> FactionDict) -> State -> State
updateFaction f s = s {_sfactionD = f (_sfactionD s)}

-- | Update global time within state.
updateTime :: (Time -> Time) -> State -> State
updateTime f s = s {_stime = f (_stime s)}

-- | Update content data within state.
updateCOps :: (Kind.COps -> Kind.COps) -> State -> State
updateCOps f s = s {_scops = f (_scops s)}

-- | Get current time from the dungeon data.
getLocalTime :: LevelId -> State -> Time
getLocalTime lid s = ltime $ _sdungeon s EM.! lid

-- | Tell whether the faction can spawn actors.
isSpawnFaction :: FactionId -> State -> Bool
isSpawnFaction fid s = isSpawnFact (_scops s) $ _sfactionD s EM.! fid

-- | Tell whether actors of the faction can be summoned by items, etc..
isSummonFaction :: FactionId -> State -> Bool
isSummonFaction fid s = isSummonFact (_scops s) $ _sfactionD s EM.! fid

sdungeon :: State -> Dungeon
sdungeon = _sdungeon

sdepth :: State -> Int
sdepth = _sdepth

sactorD :: State -> ActorDict
sactorD = _sactorD

sitemD :: State -> ItemDict
sitemD = _sitemD

sfactionD :: State -> FactionDict
sfactionD = _sfactionD

stime :: State -> Time
stime = _stime

scops :: State -> Kind.COps
scops = _scops

shigh :: State -> HighScore.ScoreTable
shigh = _shigh

instance Binary State where
  put State{..} = do
    put _sdungeon
    put _sdepth
    put _sactorD
    put _sitemD
    put _sfactionD
    put _stime
    put _shigh
  get = do
    _sdungeon <- get
    _sdepth <- get
    _sactorD <- get
    _sitemD <- get
    _sfactionD <- get
    _stime <- get
    _shigh <- get
    let _scops = undefined  -- overwritten by recreated cops
    return State{..}
