{-# LANGUAGE OverloadedStrings #-}

-- | The two built SPAs: the admin one under @/admin@, the player one at the
-- root. One container, one port (TS 版 docs/01).
--
-- A path that names no file is 404, for a page as for the API. Not the SPA's
-- @index.html@: both SPAs keep their screen in the URL's hash, so no path but
-- the root needs one.
--
-- @
-- /             -> web/index.html
-- /assets/a.js  -> web/assets/a.js
-- /admin        -> admin/index.html   (and /admin/ as well)
-- /no-such-page -> 404
-- @
module Mba.Http.Static (static) where

import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Text qualified as T
import Network.HTTP.Types (hContentType, methodGet, status200)
import Network.Wai (Request, Response, pathInfo, requestMethod, responseFile)
import System.Directory (doesDirectoryExist, doesFileExist)
import System.FilePath (takeExtension, (</>))

import Mba.Http.Refusal (refused)
import Mba.Refusal (Refusal (NotFound))

-- | Serves from two directories: the player SPA's build, and the admin one's.
static :: FilePath -> FilePath -> Request -> IO Response
static web admin req
  | requestMethod req /= methodGet = pure (refused NotFound)
  | otherwise = case pathInfo req of
      "admin" : rest -> file admin rest
      rest -> file web rest

-- | A file under the root, or the @index.html@ of a directory under it.
-- Nothing outside the root: a piece that is @..@, or that hides a separator
-- (@%2F@ decodes to one), is refused before the disk is looked at.
file :: FilePath -> [Text] -> IO Response
file root segments
  | any unsafe pieces = pure (refused NotFound)
  | otherwise = do
      let path = foldl (</>) root (map T.unpack pieces)
      isDirectory <- doesDirectoryExist path
      let target = if isDirectory then path </> "index.html" else path
      exists <- doesFileExist target
      pure $
        if exists
          then responseFile status200 [(hContentType, contentType target)] target Nothing
          else refused NotFound
 where
  pieces = filter (not . T.null) segments
  unsafe p = p `elem` [".", ".."] || T.any (`elem` ['/', '\\', '\0']) p

contentType :: FilePath -> ByteString
contentType path = case takeExtension path of
  ".html" -> "text/html; charset=utf-8"
  ".js" -> "text/javascript; charset=utf-8"
  ".css" -> "text/css; charset=utf-8"
  ".svg" -> "image/svg+xml"
  ".png" -> "image/png"
  ".ico" -> "image/x-icon"
  ".json" -> "application/json"
  _ -> "application/octet-stream"
