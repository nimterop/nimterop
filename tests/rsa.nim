import os
import strutils

import nimterop/[build, cimport]

setDefines(@["cryptoStd"])
getHeader("openssl/crypto.h")

const
  basePath = cryptoPath.parentDir
  FLAGS {.strdefine.} = ""

static:
  cSkipSymbol(@["ERR_load_crypto_strings", "OpenSSLDie"])

cPlugin:
  import strutils

  proc onSymbol*(sym: var Symbol) {.exportc, dynlib.} =
    sym.name = sym.name.strip(chars = {'_'}).replace("__", "_")

    if sym.name in [
      "AES_ENCRYPT", "AES_DECRYPT",
      "BIO_CTRL_PENDING", "BIO_CTRL_WPENDING",
      "BN_F_BNRAND", "BN_F_BNRAND_RANGE",
      "CRYPTO_LOCK", "CRYPTO_NUM_LOCKS", "CRYPTO_THREADID",
      "EVP_CIPHER",
      "OPENSSL_VERSION",
      "PKCS7_ENCRYPT", "PKCS7_STREAM",
      "SSLEAY_VERSION",
      "SSL_TXT_ADH", "SSL_TXT_AECDH", "SSL_TXT_kECDHE"
    ]:
      sym.name = "C_" & sym.name

cOverride:
  proc OPENSSL_die*(assertion: cstring; file: cstring; line: cint) {.importc.}

cImport(@[
  basePath / "rsa.h",
  basePath / "err.h",
], recurse = true, flags = "-f:ast2 -s " & FLAGS)

{.passL: cryptoLPath.}

OpensslInit()
echo $OPENSSL_VERSION_TEXT
