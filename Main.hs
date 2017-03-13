{-# LANGUAGE TupleSections #-}

module Main where

import Control.Lens
import Control.Monad.Reader
import qualified Data.ByteString.Char8 as BS
import Data.Ini
import Data.Ratio as Ratio
import Data.Map as M
import Data.Text as T hiding (head)
import Data.Time
import Network.IRC.Client hiding (instanceConfig)
import Safe
import System.Exit
import System.Posix.Files
import Zn.Bot
import Zn.Commands
import Zn.Data.Ini

initHandler :: Ini -> StatefulBot ()
initHandler conf = do
    stateful (use bootTime) >>= send . Privmsg (parameter conf "master") . Right . pack . show
    send . Privmsg "nickserv" . Right $ "id " `append` (parameter conf "pass")
    mapM_ (send . Join) . T.split (== ',') $ parameter conf "chans"

instanceConfig :: Ini -> InstanceConfig BotState
instanceConfig config = defaultInstanceConfig nick' & (handlers %~ (handlerList ++))
    where
        nick' = parameter config "user"
        handlerList = [cmdHandler]

connection :: Ini -> ConnectionConfig BotState
connection ini = conn &
    (onconnect .~ initHandler ini) . (flood .~ (fromRational $ 1 Ratio.% 2))

    where
        conn = plainConnection host port
        host = (BS.pack . unpack $ parameter ini "irchost")
        port = (maybe (error "cannot parse ircport") id . readMay . unpack $ parameter ini "ircport")

main = do
    configFound <- fileExist "zn.rc"
    when (not configFound) $ do
        putStrLn "# no conf found\n$ cp zn.rc{.sample,}"
        exitFailure

    conf <- either error id <$> readIniFile "zn.rc"
    state <- load =<< BotState <$> getCurrentTime <*> pure conf <*> pure M.empty

    saveState state
    runClient (connection conf) (instanceConfig conf) state
