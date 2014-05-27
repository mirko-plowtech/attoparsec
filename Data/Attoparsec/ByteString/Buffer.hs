-- |
-- Module      :  Data.Attoparsec.ByteString.Buffer
-- Copyright   :  Bryan O'Sullivan 2007-2014
-- License     :  BSD3
--
-- Maintainer  :  bos@serpentine.com
-- Stability   :  experimental
-- Portability :  GHC
--
-- An immutable buffer that supports cheap appends.

-- A Buffer is divided into an immutable read-only zone, followed by a
-- mutable area that we've preallocated, but not yet written to.
--
-- We overallocate at the end of a Buffer so that we can cheaply
-- append.  Since a user of an existing Buffer cannot see past the end
-- of its immutable zone into the data that will change during an
-- append, this is safe.
--
-- Once we run out of space at the end of a Buffer, we do the usual
-- doubling of the buffer size.

module Data.Attoparsec.ByteString.Buffer
    (
      Buffer
    , buffer
    , unbuffer
    , length
    , unsafeIndex
    , substring
    , unsafeDrop
    ) where

import Control.Exception (assert)
import Data.ByteString.Internal (ByteString(..), memcpy, nullForeignPtr)
import Data.Attoparsec.Internal.Fhthagn (inlinePerformIO)
import Data.List (foldl1')
import Data.Monoid (Monoid(..))
import Data.Word (Word8)
import Foreign.ForeignPtr (ForeignPtr, withForeignPtr)
import Foreign.Ptr (plusPtr)
import Foreign.Storable (peekByteOff)
import GHC.ForeignPtr (mallocPlainForeignPtrBytes)
import Prelude hiding (length)

data Buffer = Buf {
      _fp  :: {-# UNPACK #-} !(ForeignPtr Word8)
    , _off :: {-# UNPACK #-} !Int
    , _len :: {-# UNPACK #-} !Int
    , _cap :: {-# UNPACK #-} !Int
    }

instance Show Buffer where
    showsPrec p = showsPrec p . unbuffer

-- | The initial 'Buffer' has no mutable zone, so we can avoid all
-- copies in the (hopefully) common case of no further input being fed
-- to us.
buffer :: ByteString -> Buffer
buffer (PS fp off len) = Buf fp off len len

unbuffer :: Buffer -> ByteString
unbuffer (Buf fp off len _cap) = PS fp off len

instance Monoid Buffer where
    mempty = Buf nullForeignPtr 0 0 0

    mappend (Buf _ _ _ 0) b = b
    mappend a (Buf _ _ _ 0) = a
    mappend (Buf fp0 off0 len0 cap0) (Buf fp1 off1 len1 _cap1) =
      inlinePerformIO . withForeignPtr fp0 $ \ptr0 ->
        withForeignPtr fp1 $ \ptr1 -> do
          let newlen = len0 + len1
          if newlen <= cap0
            then do
              memcpy (ptr0 `plusPtr` (off0+len0))
                     (ptr1 `plusPtr` off1)
                     (fromIntegral len1)
              return (Buf fp0 off0 newlen cap0)
            else do
              let newcap = newlen * 2
              fp <- mallocPlainForeignPtrBytes newcap
              withForeignPtr fp $ \ptr -> do
                memcpy ptr (ptr0 `plusPtr` off0) (fromIntegral len0)
                memcpy (ptr `plusPtr` len0) (ptr1 `plusPtr` off1)
                       (fromIntegral len1)
              return (Buf fp 0 newlen newcap)

    mconcat [] = mempty
    mconcat xs = foldl1' mappend xs

length :: Buffer -> Int
length (Buf _ _ len _) = len
{-# INLINE length #-}

unsafeIndex :: Buffer -> Int -> Word8
unsafeIndex (Buf fp off len _cap) i = assert (i >= 0 && i < len) .
    inlinePerformIO . withForeignPtr fp $ flip peekByteOff (off+i)
{-# INLINE unsafeIndex #-}

substring :: Int -> Int -> Buffer -> ByteString
substring s l (Buf fp off len _cap) =
  assert (s >= 0 && s <= len) .
  assert (l >= 0 && l <= len-s) $
  PS fp (off+s) l
{-# INLINE substring #-}

unsafeDrop :: Int -> Buffer -> ByteString
unsafeDrop s (Buf fp off len _cap) =
  assert (s >= 0 && s <= len) $
  PS fp (off+s) (len-s)
{-# INLINE unsafeDrop #-}
