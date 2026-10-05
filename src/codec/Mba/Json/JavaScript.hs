{-# LANGUAGE OverloadedStrings #-}

-- | JSON size as JavaScript reserializes parsed JSON. Object order has no
-- effect on byte count. Numbers first round to IEEE doubles, strings use
-- JSON.stringify's short escapes for backspace and form feed.
--
-- @
-- jsonBytes (Number 1e20) == 21
-- @
module Mba.Json.JavaScript (jsonBytes, utf16Length, jsNumber) where

import Data.Aeson (Value (..))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Char (ord)
import Data.Foldable (toList)
import Data.List (sortOn)
import Data.Scientific (toRealFloat)
import Data.Text (Text)
import Data.Text qualified as T
import Numeric (floatToDigits)

utf16Length :: Text -> Int
utf16Length = T.foldl' (\n c -> n + if ord c > 0xffff then 2 else 1) 0

jsonBytes :: Value -> Int
jsonBytes Null = 4
jsonBytes (Bool True) = 4
jsonBytes (Bool False) = 5
jsonBytes (Number n) = length (jsNumber (toRealFloat n))
jsonBytes (String s) = stringBytes s
jsonBytes (Array xs) = separated (map jsonBytes (toList xs))
jsonBytes (Object xs) = separated [stringBytes (Key.toText k) + 1 + jsonBytes v | (k, v) <- KeyMap.toList xs]

separated :: [Int] -> Int
separated sizes = 2 + sum sizes + max 0 (length sizes - 1)

stringBytes :: Text -> Int
stringBytes = (2 +) . T.foldl' (\n c -> n + size c) 0
 where
  size c
    | c `elem` ['"', '\\', '\b', '\f', '\n', '\r', '\t'] = 2
    | ord c < 0x20 = 6
    | ord c < 0x80 = 1
    | ord c < 0x800 = 2
    | ord c < 0x10000 = 3
    | otherwise = 4

jsNumber :: Double -> String
jsNumber n
  | isInfinite n || isNaN n = "null"
  | n == 0 = "0"
  | n < 0 = '-' : jsNumber (-n)
  | decimalPoint > 0 && decimalPoint <= 21 =
      take decimalPoint (digits <> repeat '0')
        <> if count > decimalPoint then '.' : drop decimalPoint digits else ""
  | decimalPoint <= 0 && decimalPoint > -6 = "0." <> replicate (-decimalPoint) '0' <> digits
  | otherwise =
      take 1 digits
        <> (if count > 1 then '.' : drop 1 digits else "")
        <> "e"
        <> (if decimalPoint > 0 then "+" else "")
        <> show (decimalPoint - 1)
 where
  (digits, decimalPoint) = shortest n
  count = length digits

-- | Choose the shortest decimal that rounds back to the same IEEE value,
-- then the nearest one (ties go to an even coefficient). floatToDigits alone
-- chooses a longer spelling at some inclusive rounding boundaries, e.g. 1e23.
-- Its exponent is still a useful starting point, including a possible carry.
shortest :: Double -> (String, Int)
shortest n = search 1
 where
  (_, exponent10) = floatToDigits 10 n
  exact = toRational n
  search precision =
    let power = exponent10 - precision
        scale = 10 ^^ power :: Rational
        nearest = round (exact / scale) :: Integer
        candidates = sortOn (\c -> (abs (fromInteger c * scale - exact), odd c)) [nearest - 1, nearest, nearest + 1]
        matches c = c > 0 && (fromRational (fromInteger c * scale) :: Double) == n
     in case filter matches candidates of
          coefficient : _ ->
            let raw = show coefficient
                significant = reverse (dropWhile (== '0') (reverse raw))
             in (significant, length raw + power)
          [] -> search (precision + 1)
