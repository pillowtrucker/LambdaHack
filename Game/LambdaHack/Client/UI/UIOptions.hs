{-# LANGUAGE DeriveGeneric #-}
-- | UI client options.
module Game.LambdaHack.Client.UI.UIOptions
  ( UIOptions(..), mkUIOptions, applyUIOptions
  ) where

import Prelude ()

import Game.LambdaHack.Common.Prelude

import           Control.DeepSeq
import           Data.Binary
import qualified Data.Ini as Ini
import qualified Data.Ini.Reader as Ini
import qualified Data.Ini.Types as Ini
import qualified Data.Map.Strict as M
import           Game.LambdaHack.Client.ClientOptions
import           GHC.Generics (Generic)
import           System.FilePath
import           Text.Read

import           Game.LambdaHack.Client.UI.HumanCmd
import qualified Game.LambdaHack.Client.UI.Key as K
import           Game.LambdaHack.Common.File
import qualified Game.LambdaHack.Common.Kind as Kind
import           Game.LambdaHack.Common.Misc
import           Game.LambdaHack.Content.RuleKind

-- | Fully typed contents of the UI config file.
data UIOptions = UIOptions
  { -- commands
    uCommands      :: [(K.KM, CmdTriple)]
    -- hero names
  , uHeroNames     :: [(Int, (Text, Text))]
    -- ui
  , uVi            :: Bool  -- ^ the option for Vi keys takes precendence
  , uLaptop        :: Bool  -- ^ because the laptop keys are the default
  , uGtkFontFamily :: Text
  , uSdlFontFile   :: Text
  , uSdlTtfSizeAdd :: Int
  , uSdlFonSizeAdd :: Int
  , uFontSize      :: Int
  , uColorIsBold   :: Bool
  , uHistoryMax    :: Int
  , uMaxFps        :: Int
  , uNoAnim        :: Bool
  , uRunStopMsgs   :: Bool
  , uCmdline       :: [String]
  }
  deriving (Show, Generic)

instance NFData UIOptions

instance Binary UIOptions

parseConfig :: Ini.Config -> UIOptions
parseConfig cfg =
  let uCommands =
        let mkCommand (ident, keydef) =
              case stripPrefix "Cmd_" ident of
                Just _ ->
                  let (key, def) = read keydef
                  in (K.mkKM key, def :: CmdTriple)
                Nothing -> error $ "wrong macro id" `showFailure` ident
            section = Ini.allItems "extra_commands" cfg
        in map mkCommand section
      uHeroNames =
        let toNumber (ident, nameAndPronoun) =
              case stripPrefix "HeroName_" ident of
                Just n -> (read n, read nameAndPronoun)
                Nothing -> error $ "wrong hero name id" `showFailure` ident
            section = Ini.allItems "hero_names" cfg
        in map toNumber section
      getOption :: forall a. Read a => String -> a
      getOption optionName =
        let lookupFail :: forall b. String -> b
            lookupFail err =
              error $ "config file access failed"
                      `showFailure` (err, optionName, cfg)
            s = fromMaybe (lookupFail "") $ Ini.getOption "ui" optionName cfg
        in either lookupFail id $ readEither s
      uVi = getOption "movementViKeys_hjklyubn"
      -- The option for Vi keys takes precendence,
      -- because the laptop keys are the default.
      uLaptop = not uVi && getOption "movementLaptopKeys_uk8o79jl"
      uGtkFontFamily = getOption "gtkFontFamily"
      uSdlFontFile = getOption "sdlFontFile"
      uSdlTtfSizeAdd = getOption "sdlTtfSizeAdd"
      uSdlFonSizeAdd = getOption "sdlFonSizeAdd"
      uFontSize = getOption "fontSize"
      uColorIsBold = getOption "colorIsBold"
      uHistoryMax = getOption "historyMax"
      uMaxFps = max 1 $ getOption "maxFps"
      uNoAnim = getOption "noAnim"
      uRunStopMsgs = getOption "runStopMsgs"
      uCmdline = words $ getOption "overrideCmdline"
  in UIOptions{..}

-- | Read and parse UI config file.
mkUIOptions :: Kind.COps -> Bool -> IO UIOptions
mkUIOptions Kind.COps{corule} benchmark = do
  let stdRuleset = Kind.stdRuleset corule
      cfgUIName = rcfgUIName stdRuleset
      sUIDefault = rcfgUIDefault stdRuleset
      cfgUIDefault = either (error . ("" `showFailure`)) id
                     $ Ini.parse sUIDefault
  dataDir <- appDataDir
  let userPath = dataDir </> cfgUIName
  cfgUser <- if benchmark then return Ini.emptyConfig else do
    cpExists <- doesFileExist userPath
    if not cpExists
      then return Ini.emptyConfig
      else do
        sUser <- readFile userPath
        return $! either (error . ("" `showFailure`)) id $ Ini.parse sUser
  let cfgUI = M.unionWith M.union cfgUser cfgUIDefault  -- user cfg preferred
      conf = parseConfig cfgUI
  -- Catch syntax errors in complex expressions ASAP,
  return $! deepseq conf conf

applyUIOptions :: Kind.COps -> UIOptions -> ClientOptions -> ClientOptions
applyUIOptions Kind.COps{corule} uioptions soptions =
  let stdRuleset = Kind.stdRuleset corule
  in (\opts -> opts {sgtkFontFamily =
        sgtkFontFamily opts `mplus` Just (uGtkFontFamily uioptions)}) .
     (\opts -> opts {sdlFontFile =
        sdlFontFile opts `mplus` Just (uSdlFontFile uioptions)}) .
     (\opts -> opts {sdlTtfSizeAdd =
        sdlTtfSizeAdd opts `mplus` Just (uSdlTtfSizeAdd uioptions)}) .
     (\opts -> opts {sdlFonSizeAdd =
        sdlFonSizeAdd opts `mplus` Just (uSdlFonSizeAdd uioptions)}) .
     (\opts -> opts {sfontSize =
        sfontSize opts `mplus` Just (uFontSize uioptions)}) .
     (\opts -> opts {scolorIsBold =
        scolorIsBold opts `mplus` Just (uColorIsBold uioptions)}) .
     (\opts -> opts {smaxFps =
        smaxFps opts `mplus` Just (uMaxFps uioptions)}) .
     (\opts -> opts {snoAnim =
        snoAnim opts `mplus` Just (uNoAnim uioptions)}) .
     (\opts -> opts {stitle =
        stitle opts `mplus` Just (rtitle stdRuleset)}) .
     (\opts -> opts {sfontDir =
        sfontDir opts `mplus` Just (rfontDir stdRuleset)})
     $ soptions
