{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The HTTP side: which path is which decision, and the server that runs them.
--
-- Routes are data. 'routes' says, for a path, which 'Endpoint's there are,
-- and 'app' is their interpreter: it picks the one whose method matches,
-- reads what that endpoint says to read, and runs its decision on SQLite.
--
-- An endpoint's method is its constructor, and 'Get' holds a decision whose
-- type ends in 'Reading. So a GET has nothing it could change state with:
-- the type says so, not whoever reviews the next route.
--
-- @
-- routes env user ["api", "save"] =
--   [ Get (saveJson \<$\> whereIs user)
--   , Put 1024 saveShape (fmap saveJson . savePosition user)
--   ]
-- @
module Mba.Http (
  Env (..),
  app,
)
where

import Data.Aeson (Value, object, (.=))
import Data.Bifunctor (first)
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8)
import Network.HTTP.Types (Method, hContentType, methodGet, methodPut, status200)
import Network.Wai (Application, Request, Response, pathInfo, requestMethod, responseLBS)

import Mba.Auth (userOf)
import Mba.Decision (Decision, Phase (..), UserId)
import Mba.Decision qualified as D
import Mba.Http.Body (readJson)
import Mba.Http.Json
import Mba.Http.Refusal (refused)
import Mba.Http.Static (static)
import Mba.Looks (drawingById, lookOf)
import Mba.Map (MapId (..))
import Mba.Maps (mapById)
import Mba.Refusal (Refusal (..))
import Mba.Saves (savePosition, whereIs)
import Mba.Sqlite (Db)
import Mba.Sqlite qualified as Sqlite

data Env = Env
  { envDb :: !Db
  , envMigrationsApplied :: !Int
  -- ^ Reported by @/api/health@, so a boot that migrated shows from outside.
  , envWebRoot :: !FilePath
  , envAdminRoot :: !FilePath
  }

-- | What can be done at a path: one constructor per method.
data Endpoint where
  -- | Reads, and answers.
  Get :: Decision Refusal 'Reading 'Reading Value -> Endpoint
  -- | JSON that was derived and serialized when the skin was stored.
  GetStored :: Decision Refusal 'Reading 'Reading Text -> Endpoint
  -- | Takes a JSON body of at most so many bytes and of a shape (or says
  -- where it is not: @$.position.x@), and runs a decision that settles.
  Put ::
    Int -> (Value -> Either Text a) -> (a -> Decision Refusal 'Reading 'Settled Value) -> Endpoint

methodOf :: Endpoint -> Method
methodOf Get{} = methodGet
methodOf GetStored{} = methodGet
methodOf Put{} = methodPut

-- | The routing table.
routes :: Env -> UserId -> [Text] -> [Endpoint]
routes env user path = case path of
  ["api", "health"] -> [Get (D.pure (health env))]
  ["api", "save"] ->
    [ Get (saveJson <$> whereIs user)
    , Put 1024 saveShape (fmap saveJson . savePosition user)
    ]
  ["api", "maps", mid] -> [Get (mapJson <$> mapById (MapId mid))]
  ["api", "appearance"] -> [Get (appearanceJson <$> lookOf user)]
  ["api", "skins", sid] -> [GetStored (drawingById sid)]
  _ -> []

health :: Env -> Value
health env = object ["status" .= ("ok" :: Text), "migrationsApplied" .= envMigrationsApplied env]

-- | Under @/api@, a path or a method with no endpoint is 404 — TS 版's Hono
-- answers 404 for both, not 405. Everything else is a file of the SPAs.
app :: Env -> Application
app env req respond =
  respond =<< case pathInfo req of
    "api" : _ -> case filter ((== requestMethod req) . methodOf) (routes env (userOf req) (pathInfo req)) of
      endpoint : _ -> serve (envDb env) endpoint req
      [] -> pure (refused NotFound)
    _ -> static (envWebRoot env) (envAdminRoot env) req

-- | One equation per endpoint.
serve :: Db -> Endpoint -> Request -> IO Response
serve db (Get d) _ = answered <$> Sqlite.query db d
serve db (GetStored d) _ =
  either
    refused
    (responseLBS status200 [(hContentType, "application/json")] . LBS.fromStrict . encodeUtf8)
    <$> Sqlite.query db d
serve db (Put limit shape d) req = do
  body <- readJson limit req
  case body >>= first Malformed . shape of
    Left r -> pure (refused r)
    Right input -> answered <$> Sqlite.perform db (d input)

answered :: Either Refusal Value -> Response
answered = either refused (json status200)
