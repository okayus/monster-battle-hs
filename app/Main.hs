{-# LANGUAGE OverloadedStrings #-}

-- | The composition root: reads the environment, opens the database, migrates
-- and seeds it, and serves.
--
-- The only place the real clock is read. Everything below is handed it, so
-- the tests can say what time it is. (The real random numbers and ids will be
-- made here too, when the slices that need them arrive.)
module Main (main) where

import Data.Foldable (for_)
import Data.Int (Int64)
import Data.Maybe (fromMaybe)
import Data.Time.Clock.POSIX (getPOSIXTime)
import Network.Wai.Handler.Warp
import System.Directory (createDirectoryIfMissing)
import System.Environment (lookupEnv)
import System.FilePath (takeDirectory)
import System.IO (BufferMode (..), hSetBuffering, stdout)
import System.Posix.Signals (Handler (..), installHandler, sigINT, sigTERM)

import Mba.Auth (localUser)
import Mba.Http (Env (..), app)
import Mba.Sqlite qualified as Sqlite

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  port <- maybe 3000 read <$> lookupEnv "PORT"
  path <- fromMaybe "./data/app.db" <$> lookupEnv "DATABASE_PATH"
  createDirectoryIfMissing True (takeDirectory path)
  db <- Sqlite.open seconds path
  applied <- Sqlite.migrate db "migrations" =<< milliseconds
  Sqlite.seed db localUser =<< seconds

  let env = Env db applied "public/web" "public/admin"
      settings =
        setPort port
          . setHost "0.0.0.0"
          . setInstallShutdownHandler stopOnSignal
          . setGracefulShutdownTimeout (Just 5)
          $ defaultSettings
  putStrLn
    ("listening on 0.0.0.0:" <> show port <> " (db: " <> path <> ", migrations: " <> show applied <> ")")
  runSettings settings (app env)
  Sqlite.close db
  putStrLn "stopped"

-- | In a container this process is PID 1, which gets no default reaction to a
-- signal, and GHC's runtime handles SIGINT but not SIGTERM. Both now close
-- the listening socket: Warp stops accepting, lets the requests in flight
-- finish (5 seconds at most), and 'runSettings' returns.
stopOnSignal :: IO () -> IO ()
stopOnSignal closeSocket =
  for_ [sigTERM, sigINT] $ \signal -> installHandler signal (CatchOnce closeSocket) Nothing

seconds :: IO Int64
seconds = floor <$> getPOSIXTime

milliseconds :: IO Int64
milliseconds = floor . (* 1000) <$> getPOSIXTime
