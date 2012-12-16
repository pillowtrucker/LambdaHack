{-# LANGUAGE OverloadedStrings #-}
-- | Generic binding of keys to commands, procesing macros,
-- printing command help. No operation in this module
-- involves the 'State' or 'Action' type.
module Game.LambdaHack.Binding
  ( Binding(..), keyHelp,
  ) where

import qualified Data.List as L
import qualified Data.Map as M
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T

import qualified Game.LambdaHack.Command as Command
import qualified Game.LambdaHack.Key as K
import Game.LambdaHack.Msg

-- | Bindings and other information about player commands.
data Binding = Binding
  { kcmd    :: M.Map (K.Key, K.Modifier) (Text, Bool, Command.Cmd)
                                     -- ^ binding keys to commands
  , kmacro  :: M.Map K.Key K.Key      -- ^ macro map
  , kmajor  :: [K.Key]                -- ^ major, most often used, commands
  , kdir    :: [(K.Key, K.Modifier)]  -- ^ direction keys for moving and running
  , krevMap :: M.Map Command.Cmd K.Key
                                     -- ^ map from cmds to their main keys
  }

coImage :: M.Map K.Key K.Key -> K.Key -> [K.Key]
coImage kmacro k =
  let domain = M.keysSet kmacro
  in if k `S.member` domain
     then []
     else k : [ from | (from, to) <- M.assocs kmacro, to == k ]

-- | Produce a set of help screens from the key bindings.
keyHelp :: Binding -> [Overlay]
keyHelp Binding{kcmd, kmacro, kmajor} =
  let
    movBlurb =
      [ "Move throughout the level with numerical keypad or"
      , "the Vi text editor keys (also known as \"Rogue-like keys\"):"
      , ""
      , "               7 8 9          y k u"
      , "                \\|/            \\|/"
      , "               4-5-6          h-.-l"
      , "                /|\\            /|\\"
      , "               1 2 3          b j n"
      , ""
      ,"Run ahead until anything disturbs you, with SHIFT (or CTRL) and a key."
      , "Press keypad '5' or '.' to wait a turn, bracing for blows next turn."
      , "In targeting mode the same keys move the targeting cursor."
      , ""
      , "Search, open and attack, by bumping into walls, doors and monsters."
      , ""
      , "Press SPACE to see the next page, with the list of major commands."
      ]
    majorBlurb =
      [ ""
      , "Commands marked with * take time and are blocked on remote levels."
      , "Press SPACE to see the next page, with the list of minor commands."
      ]
    minorBlurb =
      [ ""
      , "For more playing instructions see file PLAYING.md."
      , "Press SPACE to clear the messages and see the map again."
      ]
    fmt k h = T.replicate 16 " "
              <> T.justifyLeft 15 ' ' k
              <> T.justifyLeft 41 ' ' h
    fmts s  = " " <> T.justifyLeft 71 ' ' s
    blank   = fmt "" ""
    mov     = map fmts movBlurb
    major   = map fmts majorBlurb
    minor   = map fmts minorBlurb
    keyCaption = fmt "keys" "command"
    disp k  = T.concat $ map showT $ coImage kmacro k
    keys l  = [ fmt (disp k) (h <> if timed then "*" else "")
              | ((k, _), (h, timed, _)) <- l, h /= "" ]
    (kcMajor, kcMinor) =
      L.partition ((`elem` kmajor) . fst . fst) (M.toAscList kcmd)
  in
    [ [blank] ++ mov
    , [blank] ++ [keyCaption] ++ keys kcMajor ++ major
    , [blank] ++ [keyCaption] ++ keys kcMinor ++ minor
    ]
