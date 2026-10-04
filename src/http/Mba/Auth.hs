{-# LANGUAGE OverloadedStrings #-}

-- | Who is making a request — the one place that is answered.
--
-- There is no real authentication, by design (TS 版 docs/04): one local
-- user, who is also the admin. What matters now is the shape. A 'UserId'
-- comes from here or from nowhere: "Mba.Decision" does not export its
-- constructor, so an id out of a request body cannot decide whose data is
-- read or written. On the day real authentication arrives, this module
-- changes and no route does.
module Mba.Auth (
  localUser,
  userOf,
)
where

import Network.Wai (Request)

import Mba.Decision.Internal (UserId (..))

-- | The single user this app has, until there is a way to tell users apart.
localUser :: UserId
localUser = UserId "local"

userOf :: Request -> UserId
userOf _ = localUser
