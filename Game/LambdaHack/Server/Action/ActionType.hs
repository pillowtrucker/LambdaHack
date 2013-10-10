{-# LANGUAGE GeneralizedNewtypeDeriving #-}
-- | The main game action monad type implementation. Just as any other
-- component of the library, this implementation can be substituted.
-- This module should not be imported anywhere except in 'Action'
-- to expose the executor to any code using the library.
module Game.LambdaHack.Server.Action.ActionType
  ( ActionSer, executorSer
  ) where

import Control.Concurrent
import Control.Exception (finally)
import Control.Monad
import qualified Control.Monad.IO.Class as IO
import Control.Monad.Trans.State.Strict hiding (State)
import qualified Data.EnumMap.Strict as EM

import Game.LambdaHack.Common.Action
import Game.LambdaHack.Common.ClientCmd
import Game.LambdaHack.Common.State
import Game.LambdaHack.Server.Action.ActionClass
import qualified Game.LambdaHack.Server.Action.Save as Save
import Game.LambdaHack.Server.State
import Game.LambdaHack.Utils.Thread

data SerState = SerState
  { serState  :: !State           -- ^ current global state
  , serServer :: !StateServer     -- ^ current server state
  , serDict   :: !ConnServerDict  -- ^ client-server connection information
  , serToSave :: !Save.ChanSave   -- ^ connection to the save thread
  }

-- | Server state transformation monad.
newtype ActionSer a = ActionSer {runActionSer :: StateT SerState IO a}
  deriving (Monad, Functor)

instance MonadActionRO ActionSer where
  getState    = ActionSer $ gets serState
  getsState f = ActionSer $ gets $ f . serState

instance MonadAction ActionSer where
  modifyState f =
    ActionSer $ modify $ \serS -> serS {serState = f $ serState serS}
  putState    s =
    ActionSer $ modify $ \serS -> serS {serState = s}

instance MonadServer ActionSer where
  getServer      = ActionSer $ gets serServer
  getsServer   f = ActionSer $ gets $ f . serServer
  modifyServer f =
    ActionSer $ modify $ \serS -> serS {serServer = f $ serServer serS}
  putServer    s =
    ActionSer $ modify $ \serS -> serS {serServer = s}
  liftIO         = ActionSer . IO.liftIO
  saveServer     = ActionSer $ do
    s <- gets serState
    ser <- gets serServer
    toSave <- gets serToSave
    -- Wipe out previous candidates for saving.
    IO.liftIO $ void $ tryTakeMVar toSave
    IO.liftIO $ putMVar toSave $ Just (s, ser)

instance MonadConnServer ActionSer where
  getDict      = ActionSer $ gets serDict
  getsDict   f = ActionSer $ gets $ f . serDict
  modifyDict f =
    ActionSer $ modify $ \serS -> serS {serDict = f $ serDict serS}
  putDict    s =
    ActionSer $ modify $ \serS -> serS {serDict = s}

-- | Run an action in the @IO@ monad, with undefined state.
executorSer :: ActionSer () -> IO ()
executorSer m = do
  -- We don't merge this with the other calls to waitForChildren,
  -- because we don't want to wait for clients to exit,
  -- if the server crashes (but we wait for the save to finish).
  childrenServer <- newMVar []
  toSave <- newEmptyMVar
  void $ forkChild childrenServer $ Save.loopSave toSave
  let exe = evalStateT (runActionSer m)
              SerState { serState = emptyState
                       , serServer = emptyStateServer
                       , serDict = EM.empty
                       , serToSave = toSave
                       }
      fin = do
        -- Wait until the last save starts and tell the save thread to end.
        putMVar toSave Nothing
        -- Wait until the save thread ends.
        waitForChildren childrenServer
  exe `finally` fin
