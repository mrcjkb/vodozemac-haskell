{-# LANGUAGE TemplateHaskell, QuasiQuotes #-}

module Vodozemac.Curve25519PublicKey 
  ( Curve25519PublicKey
  , toBase64
  , fromBase64
  ) where


import Data.ByteString (ByteString)
import Data.ByteString.Unsafe qualified as ByteString
import Foreign.Marshal
import Foreign.Ptr
import Foreign.Storable
import Language.Rust.Inline
import Language.Rust.Inline.TH
import Language.Rust.Quote (ty)
import Prelude


newtype Curve25519PublicKey
  = Curve25519PublicKey (Ptr ())

mkStorable [t| Storable Curve25519PublicKey |]

extendContext basic
extendContext pointers
extendContext libc
setCrateRoot 
  [ ("vodozemac", "0.8.1")
  , ("serde_json", "1.0.132")
  , ("libc", "*")
  ]
extendContext (singleton [ty| Curve25519PublicKey |] [t| Curve25519PublicKey |])

[rust|
extern crate vodozemac;
extern crate libc;

use std::ffi::CString;
use vodozemac::*;
|]

toBase64 :: Curve25519PublicKey -> ByteString
toBase64 key = unsafeLocalState . with key $ \keyPtr -> do
  let cStr = [rust|
    *mut libc::c_char {
      let key: &mut Curve25519PublicKey = unsafe { &mut *$(keyPtr: *mut Curve25519PublicKey) };
      let b64 = key.to_base64();
      CString::new(b64.into_bytes()).unwrap().into_raw()
    }
  |]
  len <- lengthArray0 0 cStr
  let freeCString = [rustIO|
    () {
      let cstring = unsafe { CString::from_raw($(cStr: *mut libc::c_char)) };
      drop(cstring);
    }
  |]
  ByteString.unsafePackCStringFinalizer (castPtr cStr) len freeCString

fromBase64 :: ByteString -> Curve25519PublicKey
fromBase64 = undefined

