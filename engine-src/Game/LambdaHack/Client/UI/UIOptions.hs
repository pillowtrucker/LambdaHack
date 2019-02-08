{-# LANGUAGE DeriveGeneric #-}
-- | UI client options.
module Game.LambdaHack.Client.UI.UIOptions
  ( UIOptions(..)
  ) where

import Prelude ()

import Game.LambdaHack.Core.Prelude

import Control.DeepSeq
import Data.Binary
import GHC.Generics (Generic)

import           Game.LambdaHack.Client.UI.HumanCmd
import qualified Game.LambdaHack.Client.UI.Key as K
import           Game.LambdaHack.Client.UI.Msg
import qualified Game.LambdaHack.Definition.Color as Color

-- | Options that affect the UI of the client.
data UIOptions = UIOptions
  { -- commands
    uCommands           :: [(K.KM, CmdTriple)]
    -- hero names
  , uHeroNames          :: [(Int, (Text, Text))]
    -- ui
  , uVi                 :: Bool  -- ^ the option for Vi keys takes precendence
  , uLaptop             :: Bool  -- ^ because the laptop keys are the default
  , uGtkFontFamily      :: Text
  , uSdlFontFile        :: Text
  , uSdlScalableSizeAdd :: Int
  , uSdlBitmapSizeAdd   :: Int
  , uScalableFontSize   :: Int
  , uHistoryMax         :: Int
  , uMaxFps             :: Int
  , uNoAnim             :: Bool
  , uRunStopMsgs        :: Bool
  , uhpWarningPercent   :: Int
      -- ^ HP percent at which warning is emitted.
  , uMessageColors      :: Maybe [(MsgClass, Color.Color)]
  , uCmdline            :: [String]
      -- ^ Hardwired commandline arguments to process.
  }
  deriving (Show, Generic)

instance NFData UIOptions

instance Binary UIOptions