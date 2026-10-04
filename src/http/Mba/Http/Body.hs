{-# LANGUAGE MultiWayIf #-}

-- | Reading a request body: at most so many bytes, and JSON.
--
-- The limit is what stops the server from holding an arbitrarily large body
-- in memory, so it is applied before reading, not after: at once when the
-- request says how long it is, and as soon as it is passed when it does not
-- (a chunked body). A limit checked after parsing cannot do that job.
module Mba.Http.Body (readJson) where

import Data.Aeson (Value, eitherDecodeStrict)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Network.Wai (Request, RequestBodyLength (..), getRequestBodyChunk, requestBodyLength)

import Mba.Refusal (Refusal (..))

readJson :: Int -> Request -> IO (Either Refusal Value)
readJson limit req = case requestBodyLength req of
  KnownLength n | n > fromIntegral limit -> pure (Left (BodyTooLarge limit))
  _ -> (>>= decode) <$> readUpTo 0 []
 where
  readUpTo :: Int -> [ByteString] -> IO (Either Refusal ByteString)
  readUpTo n chunks = do
    chunk <- getRequestBodyChunk req
    let n' = n + BS.length chunk
    if
      | BS.null chunk -> pure (Right (BS.concat (reverse chunks)))
      | n' > limit -> pure (Left (BodyTooLarge limit))
      | otherwise -> readUpTo n' (chunk : chunks)
  decode = first (const BadJson) . eitherDecodeStrict
