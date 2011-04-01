module Display.Curses
  (displayId, startup, shutdown,
   display, nextEvent, setBG, setFG, defaultAttr, Session) where

import UI.HSCurses.Curses as C hiding (setBold, Attr)
import qualified UI.HSCurses.CursesHelper as C
import Data.List as L
import Data.Map as M
import Data.Char
import qualified Data.ByteString as BS
import Control.Monad
import Data.Maybe

import Geometry
import qualified Keys as K (Key(..), keyTranslate)
import qualified Color

displayId = "curses"

data Session =
  Session
    { win :: Window,
      styles :: Map (Color.Color, Color.Color) C.CursesStyle }

startup :: (Session -> IO ()) -> IO ()
startup k =
  do
    C.start
    cursSet CursorInvisible
    let s = [ ((f, b), C.Style (toFColor f) (toBColor b))
            | f <- [minBound..maxBound],
              -- No more color combinations possible: 16*4, 64 is max.
              b <- Color.legalBG ]
    nr <- colorPairs
    when (nr < L.length s) $
      C.end >>
      error ("Terminal has too few color pairs (" ++ show nr ++ "). Giving up.")
    let (ks, vs) = unzip s
    ws <- C.convertStyles vs
    let styleMap = M.fromList (zip ks ws)
    k (Session C.stdScr styleMap)

shutdown :: Session -> IO ()
shutdown w = C.end

display :: Area -> Session -> (Loc -> (Attr, Char)) -> String -> String -> IO ()
display ((y0,x0),(y1,x1)) (Session { win = w, styles = s }) f msg status =
  do
    -- let defaultStyle = C.defaultCursesStyle
    -- Terminals with white background require this:
    let defaultStyle = s ! (Color.defFG, Color.defBG)
        canonical (c, d) = (fromMaybe Color.defFG c, fromMaybe Color.defBG d)
    C.erase
    C.setStyle defaultStyle
    mvWAddStr w 0 0 (toWidth (x1 - x0 + 1) msg)  -- TODO: bytestring as in vty?
    mvWAddStr w (y1+2) 0 (toWidth (x1 - x0 + 1) status)
    sequence_ [ C.setStyle (findWithDefault defaultStyle (canonical a) s)
                >> mvWAddStr w (y+1) x [c]
              | x <- [x0..x1], y <- [y0..y1], let (a,c) = f (y,x) ]
    refresh

toWidth :: Int -> String -> String
toWidth n x = take n (x ++ repeat ' ')

keyTranslate :: C.Key -> Maybe K.Key
keyTranslate e =
  case e of
    C.KeyChar '\ESC' -> Just K.Esc
    C.KeyExit        -> Just K.Esc
    C.KeyChar '\n'   -> Just K.Return
    C.KeyChar '\r'   -> Just K.Return
    C.KeyEnter       -> Just K.Return
    C.KeyChar '\t'   -> Just K.Tab
    C.KeyUp          -> Just K.Up
    C.KeyDown        -> Just K.Down
    C.KeyLeft        -> Just K.Left
    C.KeyRight       -> Just K.Right
    C.KeyHome        -> Just K.Home
    C.KeyPPage       -> Just K.PgUp
    C.KeyEnd         -> Just K.End
    C.KeyNPage       -> Just K.PgDn
    C.KeyBeg         -> Just K.Begin
    C.KeyB2          -> Just K.Begin
    C.KeyClear       -> Just K.Begin
    -- No KP_ keys in hscurses and they do not seem actively maintained.
    -- For now, movement keys are more important than hero selection:
    C.KeyChar c
      | c `elem` ['1'..'9'] -> Just (K.KP c)
      | otherwise           -> Just (K.Char c)
    _                -> Nothing
--  _                -> Just (K.Dbg $ show e)

nextEvent :: Session -> IO K.Key
nextEvent session =
  do
    e <- C.getKey refresh
    maybe (nextEvent session) return (keyTranslate e)

type Attr = (Maybe Color.Color, Maybe Color.Color)

setFG c (_, b) = (Just c, b)
setBG c (f, _) = (f, Just c)
defaultAttr = (Nothing, Nothing)

toFColor :: Color.Color -> C.ForegroundColor
toFColor Color.Black     = C.BlackF
toFColor Color.Red       = C.DarkRedF
toFColor Color.Green     = C.DarkGreenF
toFColor Color.Yellow    = C.BrownF
toFColor Color.Blue      = C.DarkBlueF
toFColor Color.Magenta   = C.PurpleF
toFColor Color.Cyan      = C.DarkCyanF
toFColor Color.White     = C.WhiteF
toFColor Color.BrBlack   = C.GreyF
toFColor Color.BrRed     = C.RedF
toFColor Color.BrGreen   = C.GreenF
toFColor Color.BrYellow  = C.YellowF
toFColor Color.BrBlue    = C.BlueF
toFColor Color.BrMagenta = C.MagentaF
toFColor Color.BrCyan    = C.CyanF
toFColor Color.BrWhite   = C.BrightWhiteF

toBColor :: Color.Color -> C.BackgroundColor
toBColor Color.Black     = C.BlackB
toBColor Color.Red       = C.DarkRedB
toBColor Color.Green     = C.DarkGreenB
toBColor Color.Yellow    = C.BrownB
toBColor Color.Blue      = C.DarkBlueB
toBColor Color.Magenta   = C.PurpleB
toBColor Color.Cyan      = C.DarkCyanB
toBColor Color.White     = C.WhiteB
toBColor _               = C.BlackB  -- a limitation of curses
