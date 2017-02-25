/// certificate-based public-key cryptography using ECC-secp256r1
// - this unit is a part of the freeware Synopse mORMot framework,
// licensed under a MPL/GPL/LGPL tri-license; version 1.18
unit SynEcc;

(*
    This file is part of Synopse framework.

    Synopse framework. Copyright (C) 2017 Arnaud Bouchez
      Synopse Informatique - https://synopse.info

  *** BEGIN LICENSE BLOCK *****
  Version: MPL 1.1/GPL 2.0/LGPL 2.1

  The contents of this file are subject to the Mozilla Public License Version
  1.1 (the "License"); you may not use this file except in compliance with
  the License. You may obtain a copy of the License at
  http://www.mozilla.org/MPL

  Software distributed under the License is distributed on an "AS IS" basis,
  WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
  for the specific language governing rights and limitations under the License.

  The Original Code is Synopse framework.

  The Initial Developer of the Original Code is Arnaud Bouchez.

  Portions created by the Initial Developer are Copyright (C) 2017
  the Initial Developer. All Rights Reserved.

  Contributor(s):
   - Kenneth MacKay (easy-ecc source code)

  Alternatively, the contents of this file may be used under the terms of
  either the GNU General Public License Version 2 or later (the "GPL"), or
  the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
  in which case the provisions of the GPL or the LGPL are applicable instead
  of those above. If you wish to allow use of your version of this file only
  under the terms of either the GPL or the LGPL, and not to allow others to
  use your version of this file under the terms of the MPL, indicate your
  decision by deleting the provisions above and replace them with the notice
  and other provisions required by the GPL or the LGPL. If you do not delete
  the provisions above, a recipient may use your version of this file under
  the terms of any one of the MPL, the GPL or the LGPL.

  ***** END LICENSE BLOCK *****

  
  Using secp256r1 curve from "simple and secure ECDH and ECDSA library"
  Copyright (c) 2013, Kenneth MacKay - BSD 2-clause license
  https://github.com/esxgx/easy-ecc

  *** BEGIN LICENSE BLOCK *****
  Copyright (c) 2013, Kenneth MacKay
  All rights reserved.

  Redistribution and use in source and binary forms, with or without modification,
  are permitted provided that the following conditions are met:
   * Redistributions of source code must retain the above copyright notice, this
     list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above copyright notice,
     this list of conditions and the following disclaimer in the documentation
     and/or other materials provided with the distribution.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
  ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  ***** END LICENSE BLOCK *****

  Version 1.18
  - first public release, corresponding to mORMot Framework 1.18

  TODO:
  - secure sign-then-crypt by signing the destination name with the plain content
    to avoid "Surreptitious Forwarding" (reuse of the plain content to another
    recipier) - see http://world.std.com/~dtd/sign_encrypt/sign_encrypt7.html

*)

{$I Synopse.inc} // define HASINLINE USETYPEINFO CPU32 CPU64 OWNNORMTOUPPER

interface

uses
  {$ifdef MSWINDOWS}
  Windows, // for CriticalSection API inling
  {$else}  // for GetFileSize emulated API
  {$ifdef KYLIX3}
  SynKylix,
  {$endif}
  {$ifdef FPC}
  SynFPCLinux,
  {$endif}
  {$endif MSWINDOWS}
  SysUtils,
  Classes,
  Contnrs,
  SynCommons,
  SynCrypto;


{ *********** low-level ECC secp256r1 ECDSA and ECDH functions *********** }

{$ifdef CPUINTEL}

  {$ifndef BSD}
  {$define ECC_AVAILABLE}
  {$endif}

  {$ifdef CPUX86}
    {$ifdef KYLIX3}
      {$define ECC_32ASM}     // gcc -g -O1 -c ecc.c
    {$else}
      {$ifdef BSD}
        {.$define ECC_32ASM}    // gcc -g -O1 -c ecc.c
      {$else}
        {.$define ECC_32ASM}    // gcc -g -O1 -c ecc.c
        {.$define ECC_O1}       // gcc -g -O1 -c ecc.c
        {$define ECC_O2}        // gcc -g -O2 -c ecc.c
        {.$define ECC_O3}       // gcc -g -O3 -c ecc.c
      {$endif}
    {$endif KYLIX}
  {$endif CPUX86}

  {$ifdef CPUX64}
    {.$define ECC_O1}       // gcc -g -O1 -c ecc.c
    {$define ECC_O2}        // gcc -g -O2 -c ecc.c
    {.$define ECC_O3}       // gcc -g -O3 -c ecc.c
  {$endif CPUX64}

{$endif CPUINTEL}

const
  /// equals true if the ECDSA/ECDH cryptographic functions are available
  // - only CPUINTEL is supported by now, i.e. x86/x64
  // - other CPUs, like ARM, would have false here, as all ECC functions return
  ecc_available = {$ifdef ECC_AVAILABLE}true{$else}false{$endif};

  /// the size of the 256-bit memory structure used for secp256r1
  // - map 32 bytes of memory
  ECC_BYTES = sizeof(THash256);

type
  /// store a public key for ECC secp256r1 cryptography
  // - use ecc_make_key() to generate such a key
  // - stored in compressed form with its standard byte header, i.e. each
  // public key consumes 33 bytes of memory
  TECCPublicKey = array[0..ECC_BYTES] of byte;
  /// store a private key for ECC secp256r1 cryptography
  // - use ecc_make_key() to generate such a key
  // - stored in compressed form, i.e. each private key consumes 33 bytes of memory
  TECCPrivateKey = array[0..ECC_BYTES-1] of byte;

  /// store a 256-bit hash, as expected by ECC secp256r1 cryptography
  // - see e.g. ecdsa_sign() and ecdsa_verify() functions
  TECCHash = THash256;
  /// store a signature, as generated by ECC secp256r1 cryptography
  // - see e.g. ecdsa_sign() and ecdsa_verify() functions
  // - contains ECDSA's R and S integers
  // - each ECC signature consumes 64 bytes of memory
  TECCSignature = array[0..(ECC_BYTES*2)-1] of byte;

  /// store an encryption key, as generated by ECC secp256r1 cryptography
  // - is a 256-bit / 32-bytes buffer, fitting as source for AES-256 encoding
  // - use ecdh_shared_secret() to compute such a key from public/private keys
  TECCSecretKey = THash256;

  PECCPublicKey = ^TECCPublicKey;
  PECCPrivateKey = ^TECCPrivateKey;
  PECCHash = ^TECCHash;
  PECCSignature = ^TECCSignature;
  PECCSecretKey = ^TECCSecretKey;

{$ifdef ECC_32ASM}
var
  /// create a public/private key pair for further ECC cryptographic process
  // - using secp256r1 curve, i.e. NIST P-256, or OpenSSL prime256v1
  // - returns true if the key pair was generated successfully in pub/priv
  // - returns false if an error occurred
  ecc_make_key: function(out pub: TECCPublicKey; out priv: TECCPrivateKey): boolean; cdecl;

  /// compute an ECDH shared secret given your secret key and someone else's public key
  // - using secp256r1 curve, i.e. NIST P-256, or OpenSSL prime256v1
  // - Note: it is recommended that you hash the result of ecdh_shared_secret
  // before using it for symmetric encryption or HMAC
  // - returns true if the shared secret was generated successfully in secret
  // - returns false if an error occurred
  ecdh_shared_secret: function(const pub: TECCPublicKey; const priv: TECCPrivateKey;
    out secret: TECCSecretKey): boolean; cdecl;

  /// generate an ECDSA signature for a given hash value
  // - using secp256r1 curve, i.e. NIST P-256, or OpenSSL prime256v1
  // - returns true if the signature generated successfully in sign
  // - returns false if an error occurred
  ecdsa_sign: function(const priv: TECCPrivateKey; const hash: TECCHash;
    out sign: TECCSignature): boolean; cdecl;

  /// verify an ECDSA signature
  // - using secp256r1 curve, i.e. NIST P-256, or OpenSSL prime256v1
  // - returns true if the signature is valid
  // - returns false if it is invalid
  ecdsa_verify: function(const pub: TECCPublicKey; const hash: TECCHash;
    const sign: TECCSignature): boolean; cdecl;

{$else}

/// create a public/private key pair
// - using secp256r1 curve, i.e. NIST P-256, or OpenSSL prime256v1
// - directly low-level access to the statically linked easy-ecc library function
// - returns true if the key pair was generated successfully in pub/priv
// - returns false if an error occurred, or if ecc_available=false
// - this function is thread-safe and does not perform any memory allocation
function ecc_make_key(out pub: TECCPublicKey; out priv: TECCPrivateKey): boolean; cdecl;

/// compute a shared secret given your secret key and someone else's public key
// - using secp256r1 curve, i.e. NIST P-256, or OpenSSL prime256v1
// - directly low-level access to the statically linked easy-ecc library function
// - note: it is recommended that you hash the result of ecdh_shared_secret
// before using it for symmetric encryption or HMAC
// - returns true if the shared secret was generated successfully in secret
// - returns false if an error occurred, or if ecc_available=false
// - this function is thread-safe and does not perform any memory allocation
function ecdh_shared_secret(const pub: TECCPublicKey; const priv: TECCPrivateKey;
  out secret: TECCSecretKey): boolean; cdecl;

/// generate an ECDSA signature for a given hash value
// - using secp256r1 curve, i.e. NIST P-256, or OpenSSL prime256v1
// - directly low-level access to the statically linked easy-ecc library function
// - returns true if the signature generated successfully in sign
// - returns false if an error occurred, or if ecc_available=false
// - this function is thread-safe and does not perform any memory allocation
function ecdsa_sign(const priv: TECCPrivateKey; const hash: TECCHash;
  out sign: TECCSignature): boolean; cdecl;

/// verify an ECDSA signature
// - using secp256r1 curve, i.e. NIST P-256, or OpenSSL prime256v1
// - directly low-level access to the statically linked easy-ecc library function
// - returns true if the signature is valid
// - returns false if sign is invalid, or if ecc_available=false
// - this function is thread-safe and does not perform any memory allocation
function ecdsa_verify(const pub: TECCPublicKey; const hash: TECCHash;
  const sign: TECCSignature): boolean; cdecl;

{$endif ECC_32ASM}



{ *********** middle-level certificate-based public-key cryptography *********** }

type
  /// used to identify a TECCCertificate
  // - could be generated by TAESPRNG.Fill() method
  TECCCertificateID = type THash128;

  /// used to identify a TECCCertificate issuer
  // - could be generated by AsciiToBaudot(), with truncation to 16 bytes
  // (up to 25 Ascii-7 characters)
  TECCCertificateIssuer = type THash128;

  /// used to store a date in a TECCCertificate
  // - i.e. 16-bit number of days since 1 August 2016
  // - use NowECCDate, ECCDate(), ECCToDateTime() or ECCText() functions
  TECCDate = word;

  PECCCertificateID = ^TECCCertificateID;
  PECCCertificateIssuer = ^TECCCertificateIssuer;
  PECCDate = ^TECCDate;

  /// the certification information of a TECCCertificate
  // - as stored in TECCCertificateContent.Signed
  // - defined in a separate record, to be digitaly signed in the Signature field
  // - map TECCCertificate.Version 1 of the binary format
  // - "self-signed" certificates may be used as "root" certificates in the
  // TECCCertificateChain list
  TECCCertificateSigned = packed record
    /// when this certificate was generated
    IssueDate: TECCDate;
    /// certificate valid not before
    ValidityStart: TECCDate;
    /// certificate valid not after
    ValidityEnd: TECCDate;
    /// a genuine identifier for this certificate
    // - is used later on to validate other certificates in chain
    Serial: TECCCertificateID;
    /// identify the certificate issuer
    // - is either geniune random bytes, or some Baudot-encoded text
    Issuer: TECCCertificateIssuer;
    /// genuine identifier of the authority certificate used for signing
    // - should be used to retrieve the associated PublicKey used to compute
    // the Signature field
    // - may equal Serial, if was self-signed
    AuthoritySerial: TECCCertificateID;
    /// identify the authoritify issuer used for signing
    // - is either geniune random bytes, or some Baudot-encoded text
    // - may equal Issuer, if was self-signed
    AuthorityIssuer: TECCCertificateIssuer;
    /// the ECDSA secp256r1 public key of this certificate
    // - may be used later on for signing or key derivation
    PublicKey: TECCPublicKey;
  end;

  /// store a TECCCertificate binary buffer for ECC secp256r1 cryptography
  // - i.e. a certificate public key, with its ECDSA signature 
  // - would be stored in 173 bytes
  TECCCertificateContent = packed record
    /// the TECCCertificate format version
    Version: word;
    /// the certification information, digitaly signed in the Signature field
    Signed: TECCCertificateSigned;
    /// SHA-256 + ECDSA secp256r1 signature of the Certificate record
    Signature: TECCSignature;
    /// FNV-1a checksum of all previous fields
    // - we use fnv32 and not crc32c here to avoid colision with crc64c hashing
    // - avoiding to compute slow ECDSA verification in case of corrumption,
    // due e.g. to unexpected transmission/bug/fuzzing
    // - should be the very last field in the record
    CRC: cardinal;
  end;
  /// points to a TECCCertificate binary buffer for ECC secp256r1 cryptography
  PECCCertificateContent = ^TECCCertificateContent;

  /// store a TECCSignatureCertified binary buffer for ECDSA secp256r1 signature
  // - i.e. the digital signature of some content
  TECCSignatureCertifiedContent = packed record
    /// the TECCSignatureCertificated format version
    Version: word;
    /// when this signature was generated
    Date: TECCDate;
    /// genuine identifier of the authority certificate used for signing
    // - should be used to retrieve the associated PublicKey used to compute
    // the Signature field
    AuthoritySerial: TECCCertificateID;
    /// identify the authoritify issuer used for signing
    // - is either geniune random bytes, or some Baudot-encoded text
    AuthorityIssuer: TECCCertificateIssuer;
    /// SHA-256 + ECDSA secp256r1 digital signature of the content
    Signature: TECCSignature;
  end;
  /// points to a TECCSignatureCertified buffer for ECDSA secp256r1 signature
  PECCSignatureCertifiedContent = ^TECCSignatureCertifiedContent;

  /// the known algorithms implemented in ECIES encryption
  // - supports AES 256-bit encryption with safe block modes (weack ECB mode
  // is not available) - or AES 128-bit if needed (e.g. for regulatory issues)
  // - safe HMAC SHA-256 is used as Message Authentication Code algorithm
  // - optional SynLZ compression can be enabled
  TECIESAlgo = (
    ecaUnknown,
    ecaPBKDF2_HMAC_SHA256_AES256_CFB,
    ecaPBKDF2_HMAC_SHA256_AES256_CBC,
    ecaPBKDF2_HMAC_SHA256_AES256_OFB,
    ecaPBKDF2_HMAC_SHA256_AES256_CTR,
    ecaPBKDF2_HMAC_SHA256_AES256_CFB_SYNLZ,
    ecaPBKDF2_HMAC_SHA256_AES256_CBC_SYNLZ,
    ecaPBKDF2_HMAC_SHA256_AES256_OFB_SYNLZ,
    ecaPBKDF2_HMAC_SHA256_AES256_CTR_SYNLZ,
    ecaPBKDF2_HMAC_SHA256_AES128_CFB_SYNLZ,
    ecaPBKDF2_HMAC_SHA256_AES128_CBC_SYNLZ,
    ecaPBKDF2_HMAC_SHA256_AES128_OFB_SYNLZ,
    ecaPBKDF2_HMAC_SHA256_AES128_CTR_SYNLZ,
    ecaPBKDF2_HMAC_SHA256_AES128_CFB,
    ecaPBKDF2_HMAC_SHA256_AES128_CBC,
    ecaPBKDF2_HMAC_SHA256_AES128_OFB,
    ecaPBKDF2_HMAC_SHA256_AES128_CTR);

  /// binary header of a .synecc file, encrypted via ECC secp256r1
  // - as generated by TECCCertificate.Encrypt/EncryptFile, and decoded by
  // TECCCertificateSecret.Decrypt
  // - a sign-then-encrypt pattern may have been implemented for additional safety
  TECIESHeader = packed record
    /// contains 'SynEccEncrypted'#26
    // - so every .synecc file starts with those characters as signature
    magic: THash128;
    /// TECCCertificate.Issuer of the recipient public key used for encryption
    // - is either geniune random bytes, or some Baudot-encoded text
    rec: TECCCertificateIssuer;
    /// TECCCertificate.Serial of the recipient public key used for encryption
    recid: TECCCertificateID;
    /// the size of the plain content (may be compressed before encryption)
    size: cardinal;
    /// when this encryption was performed
    date: TECCDate;
    /// optional timestamp, in Unix seconds since 1970, of the source file
    unixts: cardinal;
    /// actual encryption algorithm used
    algo: TECIESAlgo;
    /// the genuine random public key used for encryption
    rndpub: TECCPublicKey;
    /// optional ECDSA secp256r1 digital signature of the plain content
    sign: TECCSignatureCertifiedContent;
    /// the Message Authentication Code of the encrypted content
    hmac: THash256;
    /// a crc32c hash of the header (excluding this field)
    crc: cardinal;
  end;
  /// points to the binary header of a .synecc encrypted file
  PECIESHeader = ^TECIESHeader;

  /// indicate the validity state of a ECDSA signature against a certificate
  // - as returned by low-level ECCVerify() function, and
  // TECCSignatureCertified.Verify, TECCCertificateChain.IsValid or
  // TECCCertificateChain.IsSigned methods
  // - see also ECC_VALIDSIGN constant
  TECCValidity = (
    ecvUnknown,
    ecvValidSigned, ecvValidSelfSigned,
    ecvNotSupported, ecvBadParameter, ecvCorrupted,
    ecvInvalidDate, ecvUnknownAuthority, ecvDeprecatedAuthority,
    ecvInvalidSignature);

  /// the error codes returned by TECCCertificateSecret.Decrypt()
  // - see also ECC_VALIDDECRYPT constant
  TECCDecrypt = (
    ecdDecrypted, ecdDecryptedWithSignature,
    ecdNoContent, ecdCorrupted, ecdInvalidSerial, ecdNoPrivateKey,
    ecdInvalidMAC, ecdDecryptError, ecdWriteFileError);

type
  /// the Authentication schemes recognized by TECDHEProtocol
  // - specifying the authentication allows a safe one-way handshake
  TECDHEAuth = (authMutual, authServer, authClient);
  /// set of Authentication schemes recognized by TECDHEProtocolServer
  TECDHEAuths = set of TECDHEAuth;
  /// the Key Derivation Functions recognized by TECDHEProtocol
  // - used to compute the EF secret and MAC secret from shared ephemeral secret
  // - only HMAC SHA-256 safe algorithm is proposed currently
  TECDHEKDF = (kdfHmacSha256);
  /// the Encryption Functions recognized by TECDHEProtocol
  // - all supported AES chaining blocks have their 128-bit and 256-bit flavours
  // - default efAesCrc128 will use the dedicated TAESCFBCRC class, i.e.
  // AES-CFB encryption with on-the-fly 256-bit CRC computation of the plain and
  // encrypted blocks, and AES-encryption of the CRC to ensure cryptographic
  // level message authentication and integrity - associated TECDHEMAC
  // property should be macDuringEF
  // - other values will define TAESCFB/TAESOFB/TAESCTR/TAESCBC in 128-bit or
  // 256-bit mode, in conjunction with a TECDHEMAC setting
  // - AES-NI hardware acceleration will be used, if available
  // - of course, weack ECB mode is not available
  TECDHEEF = (efAesCrc128, efAesCfb128, efAesOfb128, efAesCtr128, efAesCbc128,
              efAesCrc256, efAesCfb256, efAesOfb256, efAesCtr256, efAesCbc256);
  /// the Message Authentication Codes recognized by TECDHEProtocol
  // - default macDuringEF (680MB/s for efAesCrc128 with SSE4.2 and AES-NI)
  // means that no separated MAC is performed, but done during encryption step:
  // only supported by efAesCrc128 or efAesCrc256 (may be a future AES-GCM) 
  // - macHmacSha256 is the safest, but slow, especially when used as MAC for
  // AES-NI accellerated encryption (110MB/s with efAesCfb128, to be compared
  // with macDuringEF, which produces a similar level of MAC)
  // - macHmacCrc256c and macHmacCrc32c are faster (550-650MB/s with efAesCfb128),
  // and prevent transmission errors but not message integrity or authentication
  // since composition of two crcs is a multiplication by a polynomial - see
  // http://mslc.ctf.su/wp/boston-key-party-ctf-2016-hmac-crc-crypto-5pts
  // - macNone (800MB/s, which is the speed of AES-NI encryption itself for a
  // random set of small messages) won't check errors, but only replay attacks
  TECDHEMAC = (macDuringEF, macHmacSha256, macHmacCrc256c, macHmacCrc32c, macNone);
                
  /// defines one protocol Algorithm recognized by TECDHEProtocol
  // - only safe and strong parameters are allowed, and the default values
  // (i.e. all fields set to 0) will ensure a very good combination
  // - in current implementation, there is no negociation between nodes:
  // client and server should have the very same algorithm
  TECDHEAlgo = packed record
    /// the current Authentication scheme
    auth: TECDHEAuth;
    /// the current Key Derivation Function
    kdf: TECDHEKDF;
    /// the current Encryption Function
    ef: TECDHEEF;
    /// the current Message Authentication Code
    mac: TECDHEMAC;
  end;
  /// points to one protocol Algorithm recognized by TECDHEProtocol
  PECDHEAlgo = ^TECDHEAlgo;

  /// the binary handshake message, sent by client to server
  // - the frame will always have the same fixed size of 290 bytes (i.e. 388
  // base64-encoded chars, which could be transmitted in a HTTP header),
  // for both mutual or unilateral authentication
  // - ephemeral keys may be included for perfect forward security
  TECDHEFrameClient = packed record
    /// expected algorithm used
    algo: TECDHEAlgo;
    /// a client-generated random seed
    RndA: THash128;
    /// client public key, with its certificate
    // - may be zero, in case of unilateral authentication (algo=authServer)
    QCA: TECCCertificateContent;
    /// client-generated ephemeral public key
    // - may be zero, in case of unilateral authentication (algo=authClient)
    QE: TECCPublicKey;
    /// SHA-256 + ECDSA secp256r1 signature of the previous fields, computed
    // with the client private key
    // - i.e. ECDSASign(dA,sha256(algo|RndA|QCA|QE))
    // - may be zero, in case of unilateral authentication (algo=authServer)
    Sign: TECCSignature;
  end;

  /// the binary handshake message, sent back from server to client
  // - the frame will always have the same fixed size of 306 bytes (i.e. 408
  // base64-encoded chars, which could be transmitted in a HTTP header),
  // for both mutual or unilateral authentication
  // - ephemeral keys may be included for perfect forward security
  TECDHEFrameServer = packed record
    /// algorithm used by the server
    algo: TECDHEAlgo;
    /// client-generated random seed
    RndA: THash128;
    /// a server-generated random seed
    RndB: THash128;
    /// server public key, with its certificate
    // - may be zero, in case of unilateral authentication (algo=authClient)
    QCB: TECCCertificateContent;
    /// server-generated ephemeral public key
    // - may be zero, in case of unilateral authentication (algo=authServer)
    QF: TECCPublicKey;
    /// SHA-256 + ECDSA secp256r1 signature of the previous fields, computed
    // with the server private key
    // - i.e. ECDSASign(dB,sha256(algo|RndA|RndB|QCB|QF))
    // - may be zero, in case of unilateral authentication (algo=authClient)
    Sign: TECCSignature;
  end;

const
  /// TECCValidity results indicating a valid digital signature
  ECC_VALIDSIGN = [ecvValidSigned, ecvValidSelfSigned];

  /// TECCDecrypt results indicating a valid decryption process
  ECC_VALIDDECRYPT = [ecdDecrypted, ecdDecryptedWithSignature];


/// returns the current UTC date, as a TECCDate integer value
// - i.e. 16-bit number of days since 1 August 2016
function NowECCDate: TECCDate;
  {$ifdef HASINLINE}inline;{$endif}

/// convert a supplied TDateTime value into a TECCDate integer value
// - i.e. 16-bit number of days since 1 August 2016
// - returns 0 if the supplied value is invalid, i.e. out of range
function ECCDate(const DateTime: TDateTime): TECCDate;

/// convert a supplied a TECCDate integer value into a TDateTime value
// - i.e. 16-bit number of days since 1 August 2016
function ECCToDateTime(ECCDate: TECCDate): TDateTime;
  {$ifdef HASINLINE}inline;{$endif}

/// convert a supplied a TECCDate integer value into a ISO-8601 text value
// - i.e. 16-bit number of days since 1 August 2016
function ECCText(ECCDate: TECCDate; Expanded: boolean=true): RawUTF8; overload;
  {$ifdef HASINLINE}inline;{$endif}

/// convert a supplied TECCCertificateIssuer binary buffer into proper text
// - returns Ascii-7 text if was stored using Baudot encoding
// - or returns hexadecimal values, if it was 16 bytes of random binary
function ECCText(const Issuer: TECCCertificateIssuer): RawUTF8; overload;

/// convert some Ascii-7 text into a TECCCertificateIssuer binary buffer
// - using Emile Baudot encoding
// - returns TRUE on Text truncation to fit into the 16 bytes
function ECCIssuer(const Text: RawUTF8; out Issuer: TECCCertificateIssuer): boolean;

/// convert a supplied TECCCertificateID binary buffer into proper text
// - returns hexadecimal values, or '' if the ID is filled with zeros
function ECCText(const ID: TECCCertificateID): RawUTF8; overload;

/// convert a supplied hexadecimal buffer into a TECCCertificateID binary buffer
// - returns TRUE if the supplied Text was a valid hexadecimal buffer
function ECCID(const Text: RawUTF8; out ID: TECCCertificateID): boolean;

/// fast check of the binary buffer storage of a certificate
// - ensure content.CRC has the expected value, using FNV-1a checksum
// - does not validate the certificate against the certificates chain, nor
// perform any ECC signature: use TECCCertificateChain.IsValid instead
function ECCCheck(const content: TECCCertificateContent): boolean; overload;

/// fast check if the binary buffer storage of a certificate was self-signed
// - a self-signed certificate will have its AuthoritySerial/AuthorityIssuer
// fields matching Serial/Issuer
function ECCSelfSigned(const content: TECCCertificateContent): boolean;

/// fast check of the binary buffer storage of a signature
// - just check that the date and authority are set
function ECCCheck(const content: TECCSignatureCertifiedContent): boolean; overload;

/// convert a supplied base-64 text into a TECCSignatureCertifiedContent binary buffer
function ECCSign(const base64: RawUTF8; out content: TECCSignatureCertifiedContent): boolean;

/// convert a supplied TECCSignatureCertifiedContent binary buffer into proper text
// - returns base-64 encoded text, or '' if the signature was filled with zeros
function ECCText(const sign: TECCSignatureCertifiedContent): RawUTF8; overload;

/// convert a supplied TECCSignature binary buffer into proper text
// - returns base-64 encoded text, or '' if the signature was filled with zeros
function ECCText(const sign: TECCSignature): RawUTF8; overload;

/// low-level verification of a TECCSignatureCertifiedContent binary buffer
// - will verify all internal signature fields according to a supplied authority,
// then will perform the ECDSA verification of the supplied 256-bit hash with
// the authority public key
// - as used by TECCSignatureCertified.Verify and TECCCertificateChain.IsValid
function ECCVerify(const sign: TECCSignatureCertifiedContent;
  const hash: THash256; const auth: TECCCertificateContent): TECCValidity;

/// validate the binary header of a .synecc file buffer, encrypted via ECC secp256r1
// - will check against the expected layout, and values stored (e.g. crc)
// - returns true if head is a valid .synecc header, false otherwise
function ECIESHeader(const head: TECIESHeader): boolean; overload;

/// extract the binary header of a .synecc file buffer, encrypted via ECC secp256r1
// - match the format generated by TECCCertificate.Encrypt/EncryptFile
// - returns true on success, false otherwise
function ECIESHeader(const encrypted: RawByteString; out head: TECIESHeader): boolean; overload;

/// extract the binary header of a .synecc file, encrypted via ECC secp256r1
// - match the format generated by TECCCertificate.Encrypt/EncryptFile
// - returns true on success, false otherwise
// - if rawencryptedfile is specified, will also create such a file with the
// raw encrypted content (i.e. excluding the encryptedfile header)
function ECIESHeaderFile(const encryptedfile: TFileName; out head: TECIESHeader;
  const rawencryptedfile: TFileName=''): boolean;

/// convert the binary header of a .synecc file buffer into a JSON object
// - returns '' if the header is not a valid .synecc file
function ECIESHeaderText(const head: TECIESHeader): RawUTF8; overload;

/// convert the header of a .synecc file into a JSON object
// - returns '' if the header is not a valid .synecc file
// - if rawencryptedfile is specified, will also create such a file with the
// raw encrypted content (i.e. excluding the encryptedfile header)
function ECIESHeaderText(const encryptedfile: TFileName;
  const rawencryptedfile: TFileName=''): RawUTF8; overload;


{ *********** high-level certificate-based public-key cryptography *********** }

const
  DEFAULT_ECCROUNDS = 60000;

type
  /// exception class associated with this SynEcc unit
  EECCException = class(ESynException);

  TECCSignatureCertified = class;

  /// a public certificate using ECC secp256r1 cryptography
  // - implements a custom binary format, with validation period, and chaining
  // - could be used for safe data signing, and authentication
  // - in fact, Base64 published property is enough to persist this instance:
  // but consider also ToBase64/FromBase64/LoadFromStream/SaveToStream methods
  TECCCertificate = class(TSynPersistent)
  protected
    fContent: TECCCertificateContent;
    fStoreOnlyPublicKey: boolean;
    function GetAuthorityIssuer: RawUTF8;
    function GetAuthoritySerial: RawUTF8;
    function GetIssueDate: RawUTF8;
    function GetIssuer: RawUTF8;
    function GetSerial: RawUTF8;
    function GetValidityEnd: RawUTF8;
    function GetValidityStart: RawUTF8;
    function GetIsSelfSigned: boolean;
    function InternalLoad(const data: RawByteString): boolean; virtual;
    function InternalSave: RawByteString; virtual;
    procedure SetBase64(const base64: RawUTF8);
  public
    /// initialize this certificate
    constructor Create; override;
    /// initialize this certificate from a supplied certificate binary
    // - will raise an EECCException if the supplied binary is incorrect
    constructor CreateFrom(const binary: TECCCertificateContent); virtual;
    /// initialize this certificate from a supplied base-64 encoded binary
    // - will raise an EECCException if the supplied base64 is incorrect
    constructor CreateFromBase64(const base64: RawUTF8); virtual;
    /// initialize this certificate from a set of potential inputs
    // - will first search from a .public file name, base-64 encoded binary,
    // or a serial number which be used to search for a local .public file
    // (as located by ECCKeyFileFind)
    // - will raise an EECCException if no supplied media is correct
    constructor CreateFromAuth(const AuthPubKey: TFileName;
      const AuthBase64, AuthSerial: RawUTF8); virtual;
    /// the certification information, digitaly signed in the Signature field
    property Signed: TECCCertificateSigned read fContent.Signed;
    /// SHA-256 + ECDSA secp256r1 signature of the Certificate record
    property Signature: TECCSignature read fContent.Signature;
    /// persist the certificate as some base-64 encoded binary
    // - will use SaveToStream serialization
    function ToBase64: RawUTF8;
    /// retrieve the certificate from some base-64 encoded binary
    // - will use LoadFromStream serialization
    // - returns true on success, false otherwise
    function FromBase64(const base64: RawUTF8): boolean;
    /// retrieve the certificate from the "Base64": JSON entry of a .public file
    // - will use FromBase64/LoadFromStream serialization
    // - returns true on success, false otherwise
    function FromFile(const filename: TFileName): boolean;
    /// retrieve the certificate from a set of potential inputs
    // - will first search from a .public file name, base-64 encoded binary,
    // or a serial number which be used to search for a local .public file in
    // the current folder or ECCKeyFileFolder (as located by ECCKeyFileFind)
    // - returns true on success, false otherwise
    function FromAuth(const AuthPubKey: TFileName;
      const AuthBase64, AuthSerial: RawUTF8): boolean;
    /// persist only the public certificate as some base-64 encoded binary
    // - will follow TECCCertificate.SaveToStream/ToBase64 serialization,
    // even when called from a TECCCertificateSecret instance
    // - could be used to safely publish the public information of a newly
    // created certificate
    function PublicToBase64: RawUTF8;
    /// persist the certificate as some binary
    // - returns true on success (i.e. this class stores a certificate),
    // false otherwise
    function SaveToStream(Stream: TStream): boolean;
    /// retrieve the certificate from some base-64 encoded binary
    // - returns true on success, false otherwise
    function LoadFromStream(Stream: TStream): boolean;
    /// fast check of the binary buffer storage of this certificate
    // - ensure Content.CRC has the expected value, using FNV-1a checksum
    // - does not validate the certificate against the certificates chain, nor
    // perform any ECC signature: use TECCCertificateChain.IsValid instead
    function CheckCRC: boolean;
    /// encrypt using the ECIES scheme, using this public certificate as key,
    // via AES-256-CFB/PKCS7 over PBKDF2_HMAC_SHA256, and HMAC_SHA256
    // - returns the encrypted content, in the .synecc optimized format
    // - optional salt information used for PBKDF2 or HMAC can be customized
    // - ecaUnknown algorithm will use either ecaPBKDF2_HMAC_SHA256_AES256_CFB
    // or ecaPBKDF2_HMAC_SHA256_AES256_CFB_SYNLZ depending if the supplied
    // contain is compressible or not - but you may force another algorithm
    // - you can optionally associate an ECDSA secp256r1 digital signature,
    // and a timestamp which may be used when re-creating a decyphered file
    // - use TECCCertificateSecret.Decrypt to uncypher the resulting content
    function Encrypt(const Plain: RawByteString;
      Signature: TECCSignatureCertified=nil; FileDateTime: TDateTime=0;
      const KDFSalt: RawUTF8='salt'; KDFRounds: integer=DEFAULT_ECCROUNDS;
      const MACSalt: RawUTF8='hmac'; MACRounds: integer=100;
      Algo: TECIESAlgo=ecaUnknown): RawByteString;
    /// encrypt a file using the ECIES scheme, using this public certificate as
    // key,via AES-256-CFB/PKCS7 over PBKDF2_HMAC_SHA256, and HMAC_SHA256
    // - by default, will create a FileToCrypt.synecc encrypted file
    // - ecaUnknown algorithm will use either ecaPBKDF2_HMAC_SHA256_AES256_CFB
    // or ecaPBKDF2_HMAC_SHA256_AES256_CFB_SYNLZ depending if the supplied
    // contain is compressible or not - but you may force another algorithm
    // - any available .sign ECDSA secp256r1 digital signature file will be
    // recognized and embedded to the resulting .synecc content
    // - optional salt information used for PBKDF2 can be customized, to lock
    // the encryted file with the supplied password
    function EncryptFile(const FileToCrypt: TFileName; const DestFile: TFileName='';
      const Salt: RawUTF8='salt'; SaltRounds: integer=DEFAULT_ECCROUNDS;
      Algo: TECIESAlgo=ecaUnknown; IncludeSignFile: boolean=true): boolean;
    {$ifndef NOVARIANTS}
    /// returns a TDocVariant object of all published properties of this instance
    // - excludes the Base64 property content if withBase64 is set to false
    function ToVariant(withBase64: boolean=true): variant;
    {$endif}
    /// low-level access to the binary buffer used ECC secp256r1 cryptography
    // - you should not use this property, but other methods
    property Content: TECCCertificateContent read fContent write fContent;
  published
    /// the TECCCertificate format version
    // - currently equals 1
    property Version: word read fContent.Version;
    /// the genuine identifier of this certificate, as hexadecimal text
    property Serial: RawUTF8 read GetSerial;
    /// identify the certificate issuer, as text
    property Issuer: RawUTF8 read GetIssuer;
    /// when this certificate was generated, as ISO-8601 text
    property IssueDate: RawUTF8 read GetIssueDate;
    /// valid not before this date, as ISO-8601 text
    property ValidityStart: RawUTF8 read GetValidityStart;
    /// valid not after this date, as ISO-8601 text
    property ValidityEnd: RawUTF8 read GetValidityEnd;
    /// hexadecimal text of the authority certificate identifier used for signing
    property AuthoritySerial: RawUTF8 read GetAuthoritySerial;
    /// identify the authoritify issuer used for signing, as text
    property AuthorityIssuer: RawUTF8 read GetAuthorityIssuer;
    /// if this certificate has been signed by itself
    // - a self-signed certificate will have its AuthoritySerial/AuthorityIssuer
    // fields matching Serial/Issuer, and should be used as "root" certificates
    property IsSelfSigned: boolean read GetIsSelfSigned;
    /// base-64 encoded text of the whole certificate binary information
    // - only the public part of the certificate will be shown: any private key
    // of a TECCCertificateSecret instance would be trimmed
    property Base64: RawUTF8 read PublicToBase64 write SetBase64;
  end;

  /// used to store a list of TECCCertificate instances
  // - e.g. in TECCCertificateChain.Items
  // - TJSONSerializer.RegisterObjArrayForJSON done in dddInfraApps and not
  // in this unit to avoid dependency to mORMot.pas
  TECCCertificateObjArray = array of TECCCertificate;

  /// a public/private certificate using ECC secp256r1 cryptography
  // - will store TECCCertificate public and associated private secret key
  // - implements a custom binary format, with validation period, and chaining
  // - could be used for safe data signing via SignToBase64/SignFile, and
  // authentication / key derivation
  // - allows optional anti-forensic diffusion during storage via AFSplitStripes
  TECCCertificateSecret = class(TECCCertificate)
  protected
    fPrivateKey: TECCPrivateKey;
    fAFSplitStripes: integer;
    function InternalLoad(const data: RawByteString): boolean; override;
    function InternalSave: RawByteString; override;
  public
    /// generate a new certificate, signed using the supplied Authority
    // - if Authority is nil, will generate a self-signed certificate
    // - the supplied Issuer name would be stored using AsciiToBaudot(),
    // truncated to the Issuer buffer size, i.e. 16 bytes - if Issuer is '',
    // TAESPRNG.Fill() will be used
    // - you may specify some validity time range, if needed
    // - would take around 4 ms under a 32-bit compiler, and 1 ms under 64-bit
    constructor CreateNew(Authority: TECCCertificateSecret; const IssuerText: RawUTF8='';
      ExpirationDays: integer=0; StartDate: TDateTime=0);
    /// create a certificate with its private secret key from a password-protected
    // secure binary buffer
    // - perform all reverse steps from SaveToSecureBinary() method
    // - will raise an EECCException if the supplied Binary is incorrect
    constructor CreateFromSecureBinary(const Binary: RawByteString; const PassWord: RawUTF8;
      PBKDF2Rounds: integer=DEFAULT_ECCROUNDS; AES: TAESAbstractClass=nil); overload;
    /// create a certificate with its private secret key from a password-protected
    // secure binary buffer
    // - may be used on a constant array in executable, created via SaveToSource()
    // - perform all reverse steps from SaveToSecureBinary() method
    // - will raise an EECCException if the supplied Binary is incorrect
    constructor CreateFromSecureBinary(Data: pointer; Len: integer; const PassWord: RawUTF8;
      PBKDF2Rounds: integer=DEFAULT_ECCROUNDS; AES: TAESAbstractClass=nil); overload;
    /// create a certificate with its private secret key from an encrypted
    // secure .private binary file and its associated password
    // - perform all reverse steps from SaveToSecureFile() method
    // - will raise an EECCException if the supplied file is incorrect
    constructor CreateFromSecureFile(const FileName: TFileName; const PassWord: RawUTF8;
      PBKDF2Rounds: integer=DEFAULT_ECCROUNDS; AES: TAESAbstractClass=nil); overload;
    /// create a certificate with its private secret key from an encrypted
    // secure .private binary file stored in a given folder
    // - overloaded constructor retrieving the file directly from its folder
    // - perform all reverse steps from SaveToSecureFile() method
    // - will raise an EECCException if the supplied file is incorrect
    constructor CreateFromSecureFile(const FolderName: TFileName;
      const Serial, PassWord: RawUTF8; PBKDF2Rounds: integer=DEFAULT_ECCROUNDS;
      AES: TAESAbstractClass=nil); overload;
    /// finalize the instance
    destructor Destroy; override;
    /// returns TRUE if the private secret key is not filled with zeros
    function HasSecret: boolean;
    /// computes the 'Serial.private' file name of this certificate
    // - as used by SaveToSecureFile()
    function SaveToSecureFileName(FileNumber: integer=0): TFileName;
    /// backup the private secret key into an encrypted .private binary file
    // - you should keep all your private keys in a safe dedicated folder
    // - filename will be the certificate hexadecimal as 'Serial.private'
    // - will use anti-forensic diffusion of the private key (64 stripes = 2KB)
    // - then AES-256-CFB encryption (or the one specified in AES parameter) will
    // be performed from PBKDF2_HMAC_SHA256 derivation of an user-supplied password
    function SaveToSecureFile(const PassWord: RawUTF8; const DestFolder: TFileName;
      AFStripes: integer=64; PBKDF2Rounds: integer=DEFAULT_ECCROUNDS; AES: TAESAbstractClass=nil;
      NoHeader: boolean=false): boolean;
    /// backup the private secret key into several encrypted -###.private binary files
    // - secret sharing can be used to store keys at many different places, e.g.
    // on several local or remote drives, and therefore enhance privacy and safety
    // - it will use anti-forensic diffusion of the private key to distribute it
    // into pieces, in a manner that a subset of files can not regenerate the key:
    // as a result, a compromission of one sub-file won't affect the secret key
    // - filename will be the certificate hexadecimal as 'Serial-###.private'
    // - AES-256-CFB encryption (or the one specified in AES parameter) will be
    // performed from PBKDF2_HMAC_SHA256 derivation of an user-supplied password
    function SaveToSecureFiles(const PassWord: RawUTF8; const DestFolder: TFileName;
      DestFileCount: integer; AFStripes: integer=64; PBKDF2Rounds: integer=DEFAULT_ECCROUNDS;
      AES: TAESAbstractClass=nil; NoHeader: boolean=false): boolean;
    /// read a private secret key from an encrypted .private binary file
    // - perform all reverse steps from SaveToSecureFile() method
    // - returns TRUE on success, FALSE otherwise
    function LoadFromSecureFile(const FileName: TFileName; const PassWord: RawUTF8;
      PBKDF2Rounds: integer=DEFAULT_ECCROUNDS; AES: TAESAbstractClass=nil): boolean;
    /// backup the private secret key into an encrypted secure binary buffer
    // - you should keep all your private keys in a safe place
    // - will use anti-forensic diffusion of the private key (64 stripes = 2KB)
    // - then AES-256-CFB encryption (or the one specified in AES parameter) will
    // be performed from PBKDF2_HMAC_SHA256 derivation of an user-supplied password
    function SaveToSecureBinary(const PassWord: RawUTF8; AFStripes: integer=64;
      PBKDF2Rounds: integer=DEFAULT_ECCROUNDS; AES: TAESAbstractClass=nil; NoHeader: boolean=false): RawByteString;
    /// backup the private secret key into an encrypted source code constant
    // - may be used to integrate some private keys within an executable
    // - if ConstName='', _HEXASERIAL will be used, from 24 first chars of Serial
    // - the password may also be included as ConstName_PASS associated constant,
    // and as ConstName_CYPH in TSynPersistentWithPassword/TECCCertificateSecretSetting
    // encrypted format
    function SaveToSource(const ConstName, Comment, PassWord: RawUTF8;
      IncludePassword: boolean=true; AFStripes: integer=0; PBKDF2Rounds: integer=100;
      AES: TAESAbstractClass=nil; IncludeRaw: boolean=true): RawUTF8;
    /// read a private secret key from an encrypted secure binary buffer
    // - perform all reverse steps from SaveToSecureBinary() method
    // - returns TRUE on success, FALSE otherwise
    function LoadFromSecureBinary(const Binary: RawByteString; const PassWord: RawUTF8;
      PBKDF2Rounds: integer=DEFAULT_ECCROUNDS; AES: TAESAbstractClass=nil): boolean; overload;
    /// read a private secret key from an encrypted secure binary buffer
    // - perform all reverse steps from SaveToSecureBinary() method
    // - returns TRUE on success, FALSE otherwise
    function LoadFromSecureBinary(Data: pointer; Len: integer; const PassWord: RawUTF8;
      PBKDF2Rounds: integer=DEFAULT_ECCROUNDS; AES: TAESAbstractClass=nil): boolean; overload;
  public
    /// compute a base-64 encoded signature of some digital content
    // - memory buffer will be hashed using SHA-256, then will be signed using
    // ECDSA over the private secret key of this certificate instance
    // - you could later on verify this text signature according to the public
    // key of this certificate, calling TECCCertificateChain.IsSigned()
    // - create internally a temporary TECCSignatureCertified instance
    function SignToBase64(Data: pointer; Len: integer): RawUTF8; overload;
    /// compute a base-64 encoded signature of some digital content hash
    // - signature will be certified by private secret key of this instance
    // - you could later on verify this text signature according to the public
    // key of this certificate, calling TECCCertificateChain.IsSigned()
    // - supplied hash is likely to be from SHA-256, but could be e.g. crc256c
    // - create internally a temporary TECCSignatureCertified instance
    function SignToBase64(const Hash: THash256): RawUTF8; overload;
    {$ifndef NOVARIANTS}
    /// compute a .sign digital signature of any file
    // - SHA-256/ECDSA digital signature is included in a JSON document
    // - you can set some additional metadata information for the "meta": field
    // - will raise an EECCException if FileToSign does not exist
    // - returns the .sign file name, which is in fact FileToSign+'.sign'
    // - use TECCSignatureCertifiedFile class to load and validate such files
    function SignFile(const FileToSign: TFileName;
      const MetaNameValuePairs: array of const): TFileName;
    {$endif}
    /// decrypt using the ECIES scheme, using this private certificate as key,
    // via AES-256-CFB/PKCS7 over PBKDF2_HMAC_SHA256, and HMAC_SHA256
    // - expects TECCCertificate.Crypt() cyphered content with its public key
    // - returns the decrypted content, or '' in case of failure
    // - optional shared information used for PBKDF2 or HMAC can be customized
    // - optionally, you can retrieve the sign-then-encrypt ECDSA secp256r1
    // signature stored in the header (to be checked via TECCCertificateChain
    // IsSigned method), and/or the associated file timestamp
    function Decrypt(const Encrypted: RawByteString; out Decrypted: RawByteString;
      Signature: PECCSignatureCertifiedContent=nil; FileDateTime: PDateTime=nil;
      const KDFSalt: RawUTF8='salt'; KDFRounds: integer=DEFAULT_ECCROUNDS;
      const MACSalt: RawUTF8='hmac'; MACRounds: integer=100): TECCDecrypt;
    /// decrypt a file using the ECIES scheme, using this private certificate as
    // key, via AES-256-CFB/PKCS7 over PBKDF2_HMAC_SHA256, and HMAC_SHA256
    // - makes the reverse operation of TECCCertificate.EncryptFile method
    // - by default, will erase the (.synecc) extension to FileToDecrypt name
    // - optional salt information used for PBKDF2 can be customized, to unlock
    // the encryted file with the supplied password
    // - optionally, you can retrieve the sign-then-encrypt ECDSA secp256r1
    // signature stored in the header for TECCCertificateChain.IsSigned()
    function DecryptFile(const FileToDecrypt: TFileName; const DestFile: TFileName='';
      const Salt: RawUTF8='salt'; SaltRounds: integer=DEFAULT_ECCROUNDS;
      Signature: PECCSignatureCertifiedContent=nil): TECCDecrypt;
  public
    /// how many anti-forensic diffusion stripes are used for private key storage
    // - default is 0, meaning no diffusion, i.e. 32 bytes of storage space
    // - you may set e.g. to 32 to activate safe diffusion to 1KB of storage
    // for ToBase64/SaveToStream methods
    // - is modified temporarly by SaveToSecure() method
    property AFSplitStripes: integer read fAFSplitStripes;
    /// disable private secret key storage in SaveToStream()
    // - default is false, i.e. the private secret key will be serialized
    // - you may set TRUE here so that SaveToStream() would store only the
    // public certificate, as expected by a TECCCertificate class
    // - is used e.g. by PublicToBase64 method to trim the private information
    property StoreOnlyPublicKey: boolean read fStoreOnlyPublicKey write fStoreOnlyPublicKey;
  end;

  /// a ECDSA secp256r1 digital signature of some content, signed by an authority
  TECCSignatureCertified = class(TSynPersistent)
  protected
    fContent: TECCSignatureCertifiedContent;
    function GetAuthorityIssuer: RawUTF8;
    function GetAuthoritySerial: RawUTF8;
    function GetDate: RawUTF8;
  public
    /// initialize this signature
    constructor Create; override;
    /// compute a new signature of some digital content
    // - memory buffer will be hashed using SHA-256, then will be signed using
    // ECDSA over the private secret key of the supplied Authority certificate
    constructor CreateNew(Authority: TECCCertificateSecret;
      Data: pointer; Len: integer); overload;
    /// compute a new signature of some digital content hash
    // - supplied hash is likely to be from SHA-256, but could be e.g. crc256c
    // - the hash will be signed using ECDSA over the private secret key of
    // the supplied Authority certificate
    constructor CreateNew(Authority: TECCCertificateSecret;
      const Hash: THash256); overload;
    /// initialize this signature from a supplied binary
    // - will raise an EECCException if the supplied binary content is incorrect
    constructor CreateFrom(const binary: TECCSignatureCertifiedContent;
      NoException: boolean=false);
    /// initialize this signature from a supplied base-64 encoded binary
    // - will raise an EECCException if the supplied base64 is incorrect
    constructor CreateFromBase64(const base64: RawUTF8;
      NoException: boolean=false);
    /// initialize this signature from the "sign": field of a JSON .sign file
    // - will raise an EECCException if the supplied file is incorrect
    constructor CreateFromFile(const signfilename: TFileName;
      NoException: boolean=false);
    /// fast check of the binary buffer storage of this signature
    // - performs basic checks, avoiding any void date, authority or signature
    // - use Verify() or TECCCertificateChain.IsSigned() methods for full
    // digital signature validation
    function Check: boolean;
    /// check if this digital signature matches a given data hash
    // - will check internal properties of the certificate (e.g. validity dates),
    // and validate the stored ECDSA signature according to the public key of
    // the supplied signing authority
    // - supplied hash is likely to be from SHA-256, but could be e.g. crc256c
    // - this method is thread-safe, and not blocking
    function Verify(Authority: TECCCertificate;
      const hash: THash256): TECCValidity; overload;
    /// check if this digital signature matches a given memory buffer
    // - will check internal properties of the certificate (e.g. validity dates),
    // and validate the stored ECDSA signature according to the public key of
    // the supplied signing authority
    // - will compute and verify the SHA-256 hash of the supplied data
    // - this method is thread-safe, and not blocking
    function Verify(Authority: TECCCertificate;
      Data: pointer; Len: integer): TECCValidity; overload;
    /// persist the signature as some base-64 encoded binary
    function ToBase64: RawUTF8;
    {$ifndef NOVARIANTS}
    /// returns a TDocVariant object of all published properties of this instance
    function ToVariant: variant; virtual;
    {$endif}
    /// retrieve the signature from some base-64 encoded binary
    // - returns true on success, false otherwise
    function FromBase64(const base64: RawUTF8): boolean;
    /// retrieve the signature from the "sign": field of a JSON .sign file
    // - returns true on success, false otherwise
    function FromFile(const signfilename: TFileName): boolean;
    /// save the ECDSA signature into a ASN.1's binary DER buffer
    // - note that DER content only stores the ECDSA digital signature, so
    // all certification information is lost
    function SaveToDERBinary: RawByteString;
    /// save the ECDSA signature into a ASN.1's binary DER file
    // - note that DER content only stores the ECDSA digital signature, so
    // all certification information is lost - consider using
    // TECCSignatureCertifiedFile instead
    // - returns TRUE on success, FALSE otherwise
    function SaveToDERFile(const FileName: TFileName): boolean;
    /// low-level access to the binary buffer used ECDSA secp256r1 cryptography
    // - you should not use this property, but other methods
    property Content: TECCSignatureCertifiedContent read fContent write fContent;
  published
    /// the TECCSignatureCertified format version
    // - currently equals 1
    property Version: word read fContent.Version;
    /// when this signature was generated, as ISO-8601 text
    property Date: RawUTF8 read GetDate;
    /// hexadecimal text of the authority certificate identifier used for signing
    property AuthoritySerial: RawUTF8 read GetAuthoritySerial;
    /// identify the authoritify issuer used for signing, as text
    property AuthorityIssuer: RawUTF8 read GetAuthorityIssuer;
  end;

  {$ifndef NOVARIANTS}
  /// handle a .sign file content as generated by TECCCertificateSecret.SignFile
  // - JSON document of a SHA-256/ECDSA secp256r1 digital signature
  TECCSignatureCertifiedFile = class(TECCSignatureCertified)
  protected
    fLowLevelInfo: TDocVariantData;
    fMD5Digest: TMD5Digest;
    fSha256Digest: TSHA256Digest;
    fMetaData: variant;
    fSize: integer;
    fMD5: RawUTF8;
    fSHA256: RawUTF8;
  public
    /// read a .sign digital signature file
    // - as previously generated by TECCCertificateSecret.SignFile
    // - will append '.sign' to aFileName, if it does not match this extension
    // - returns true on success, false otherwise
    function FromFile(const aFileName: TFileName): boolean;
    /// read a .sign digital signature JSON content
    // - as previously generated by TECCCertificateSecret.SignFile
    // - returns true on success, false otherwise
    function FromFileJson(const aFileContent: RawUTF8): boolean;
    /// low-level access to the whole JSON document members
    property LowLevelInfo: TDocVariantData read fLowLevelInfo;
    /// the MD5 binary signature as stored in the .sign file
    property MD5Digest: TMD5Digest read fMD5Digest;
    /// the SHA-256 binary signature as stored in the .sign file
    property Sha256Digest: TSHA256Digest read fSha256Digest;
  published
    /// the meta data document as stored in the .sign file
    property MetaData: variant read fMetaData;
    /// the signed file size in bytes, as stored in the .sign file
    property Size: integer read fSize;
    /// the MD5 hexadecimal signature as stored in the .sign file
    property MD5: RawUTF8 read fMD5;
    /// the SHA-256 hexadecimal signature as stored in the .sign file
    property SHA256: RawUTF8 read fSHA256;
  end;
  {$endif NOVARIANTS}

  /// manage PKI certificates using ECC secp256r1 cryptography
  // - will implement a simple and efficient public-key infrastructure (PKI),
  // based on JSON objects or even plain base-64 encoded JSON strings
  // - consider using TECCCertificateChainFile from mORMot.pas if you want
  // to use convenient human-readable JSON serialization in files
  TECCCertificateChain = class(TSynPersistentLocked)
  protected
    fItems: TECCCertificateObjArray;
    fIsValidCached: boolean;
    fIsValidCacheCount: integer;
    fIsValidCache: TInt64DynArray;
    function GetCount: integer;
    function InternalAdd(cert: TECCCertificate; expected: TECCValidity): integer;
    procedure SetIsValidCached(const Value: boolean);
    function IndexBySerial(const Serial: TECCCertificateID): integer;
  public
    /// initialize the certificate store from some JSON array of strings
    // - the serialization format is just a JSON array of base-64 encoded
    // certificates (with only public keys) - so diverse from CreateFromFile()
    // - will call LoadFromJson(), and raise EECCException on any error
    constructor CreateFromJson(const json: RawUTF8);
    /// initialize the certificate store from an array of base-64 encoded strings
    // - a TRawUTF8DynArray value is very convenient when storing the
    // certificates chain as part of JSON settings, e.g. TDDDAppSettings
    // - will call LoadFromArray(), and raise EECCException on any error
    constructor CreateFromArray(const values: TRawUTF8DynArray);
    /// finalize the certificate store
    destructor Destroy; override;
    /// delete all stored certificates
    // - this method is thread-safe, calling Safe.Lock/Unlock
    procedure Clear;
    /// search for a certificate from its hexadecimal text identifier
    // - this method is not thread-safe, unless you use Safe.Lock/Unlock
    function GetBySerial(const Serial: RawUTF8): TECCCertificate; overload;
    /// search for a certificate from its binary identifier
    // - this method is not thread-safe, unless you use Safe.Lock/Unlock
    function GetBySerial(const Serial: TECCCertificateID): TECCCertificate; overload;
    /// search for a certificate binary content from its binary identifier
    // - returns TRUE if the Serial identifier was found, FALSE otherwise
    // - this method is thread-safe, since it will make a private copy of the content
    function GetBySerial(const Serial: TECCCertificateID;
      out Content: TECCCertificateContent): boolean; overload;
    /// search for a certificate public key from its binary identifier
    // - returns TRUE if the Serial identifier was found, FALSE otherwise
    // - this method is thread-safe, since it will make a private copy of the key
    function GetBySerial(const Serial: TECCCertificateID;
      out PublicKey: TECCPublicKey): boolean; overload;
    /// check if the certificate is valid, against known certificates chain
    // - will check internal properties of the certificate (e.g. validity dates),
    // and validate the stored ECDSA signature according to the public key of
    // the associated signing authority (which should be stored in Items[])
    // - consider setting IsValidCached property to TRUE to reduce resource use
    // - this method is thread-safe, and not blocking
    function IsValid(cert: TECCCertificate): TECCValidity; overload;
    /// check if the certificate is valid, against known certificates chain
    // - will check internal properties of the certificate (e.g. validity dates,
    // unless ignoreDate=TRUE), and validate the stored ECDSA signature
    // according to the public key of the associated signing authority (which
    // should be valid, and stored in Items[])
    // - consider setting IsValidCached property to TRUE to reduce resource use
    // - this method is thread-safe, and not blocking
    function IsValid(const content: TECCCertificateContent;
      ignoreDate: boolean=false): TECCValidity; overload;
    /// check all stored certificates and their authorization chain
    // - returns nil if all items were valid
    // - returns the list of any invalid instances
    // - do not free the returned items, since they are reference to Items[]
    function ValidateItems: TECCCertificateObjArray;
    /// check if the digital signature is recognized by the stored certificates
    // - will check that sign.AuthoritySerial is part of the Items[] list
    // - this method won't perform the ECDSA verification: use IsSigned() instead
    // - this method is thread-safe, and not blocking
    function IsAuthorized(sign: TECCSignatureCertified): boolean; overload;
    /// check if the digital signature is recognized by the stored certificates
    // - will check that sign.AuthoritySerial is part of the Items[] list
    // - this method won't perform the ECDSA verification: use IsSigned() instead
    // - this method is thread-safe, and not blocking
    function IsAuthorized(const sign: TECCSignatureCertifiedContent): boolean; overload;
    /// check if the digital signature is recognized by the stored certificates
    // - will check that the supplied base64 encoded text is a ECC signature,
    // and that its AuthoritySerial is part of the Items[] list
    // - this method won't perform the ECDSA verification: use IsSigned() instead
    // - this method is thread-safe, and not blocking
    function IsAuthorized(const base64sign: RawUTF8): boolean; overload;
    /// check if the digital signature of a given data hash is valid
    // - will check internal properties of the certificate (e.g. validity dates),
    // and validate the stored ECDSA signature according to the public key of
    // the associated signing authority (which should be stored in Items[])
    // - supplied hash is likely to be from SHA-256, but could be e.g. crc256c
    // - this method is thread-safe, and not blocking
    function IsSigned(sign: TECCSignatureCertified; const hash: THash256): TECCValidity; overload;
    /// check if the digital signature of a given memory buffer is valid
    // - if sign is a TECCSignatureCertifiedFile, the Size, MD5 and SHA256 fields
    // stored in the .sign file content will be checked against the supplied data
    // before ECDSA signature, and would return ecvCorrupted on error
    // - it will then check internal properties of the certificate (e.g. validity
    // dates), and validate the stored SHA-256/ECDSA signature according to the
    // public key of the associated signing authority (stored in Items[])
    // - this method is thread-safe, and not blocking
    function IsSigned(sign: TECCSignatureCertified; Data: pointer; Len: integer): TECCValidity; overload;
    /// check if the digital signature of a given data hash is valid
    // - will check internal properties of the certificate (e.g. validity dates),
    // and validate the stored ECDSA signature according to the public key of
    // the associated signing authority (which should be stored in Items[])
    // - supplied hash is likely to be from SHA-256, but could be e.g. crc256c
    // - this method is thread-safe, and not blocking
    function IsSigned(const sign: TECCSignatureCertifiedContent;
      const hash: THash256): TECCValidity; overload;
    /// check if the digital signature of a given memory buffer is valid
    // - will check internal properties of the certificate (e.g. validity dates),
    // and validate the stored ECDSA signature according to the public key of
    // the associated signing authority (which should be stored in Items[])
    // - will compute and verify the SHA-256 hash of the supplied data
    // - this method is thread-safe, and not blocking
    function IsSigned(const sign: TECCSignatureCertifiedContent;
      Data: pointer; Len: integer): TECCValidity; overload;
    /// verify the base-64 encoded digital signature of a given hash
    // - will check internal properties of the certificate (e.g. validity dates),
    // and validate the stored ECDSA signature according to the public key of
    // the associated signing authority (which should be stored in Items[])
    // - supplied hash is likely to be from SHA-256, but could be e.g. crc256c
    // - this method is thread-safe, and not blocking
    function IsSigned(const base64sign: RawUTF8;
      const hash: THash256): TECCValidity; overload;
    /// verify the base-64 encoded digital signature of a given memory buffer
    // - will check internal properties of the certificate (e.g. validity dates),
    // and validate the stored ECDSA signature according to the public key of
    // the associated signing authority (which should be stored in Items[])
    // - will compute and verify the SHA-256 hash of the supplied data
    // - this method is thread-safe, and not blocking
    function IsSigned(const base64sign: RawUTF8;
      Data: pointer; Len: integer): TECCValidity; overload;
    /// register a certificate in the internal certificate chain
    // - returns the index of the newly inserted certificate
    // - returns -1 on error, e.g. if the certificate was not valid, or its
    // serial was already part of the internal list
    // - any self-signed certificate will be rejected: use AddSelfSigned() instead
    // - this method is thread-safe
    function Add(cert: TECCCertificate): integer;
    /// register a self-signed certificate in the internal certificate chain
    // - a self-signed certificate will have its AuthoritySerial/AuthorityIssuer
    // fields matching Serial/Issuer, and should be used as "root" certificates
    // - returns -1 on error, e.g. if the certificate was not valid,
    // not self-signed or its serial was already part of the internal list
    // - this method is thread-safe
    function AddSelfSigned(cert: TECCCertificate): integer;
    /// save the whole certificates chain as an array of base-64 encoded content
    // - each certificate would be stored via PublicToBase64() into a RawUTF8
    // - any private key would be trimmed from the output: private secret keys
    // should NOT be kept in the main chain, in which only public keys will appear
    function SaveToArray: TRawUTF8DynArray;
    /// load a certificates chain from an array of base-64 encoded content
    // - follows SaveToArray format
    // - would create only TECCCertificate instances with their public keys,
    // since no private key, therefore no TECCCertificateSecret is expected
    function LoadFromArray(const values: TRawUTF8DynArray): boolean;
    /// save the whole certificates chain as a JSON array
    // - each certificate would be stored via PublicToBase64() into a JSON string
    // - any private key would be trimmed from the output JSON: private secret
    // keys should NOT be kept in the main chain, in which only public keys
    // should appear
    function SaveToJson: RawUTF8;
    /// load a certificates chain from a JSON array of strings
    // - follows SaveToJson format, i.e. base-64 encoded strings
    // - would create only TECCCertificate instances with their public keys,
    // since no private key, therefore no TECCCertificateSecret is expected
    function LoadFromJson(const json: RawUTF8): boolean;
  {$ifndef NOVARIANTS}
  public
    /// initialize the certificate store from some JSON-serialized .ca file
    // - the file would store plain verbose information of all certificates,
    // i.e. base-64 full information (containing only public keys) and also
    // high-level published properties of all stored certificates (e.g. Serial)
    // - as such, this file format is more verbose than CreateFromJson/SaveToJson
    // and may be convenient for managing certificates with a text/json editor
    // - you may use SaveToFile() method to create such JSON file
    // - will call LoadFromFile(), and raise EECCException on any error
    constructor CreateFromFile(const jsonfile: TFileName);
    /// initialize the certificate store from an array of .public file names
    // - raise EECCException on any error when reading a .public file
    constructor CreateFromFiles(const files: array of TFileName);
    /// save the whole certificates chain as a JSON object, matching .ca format
    // - is in fact the human-friendly JSON serialization of this instance
    // - would store plain verbose information of all certificates,
    // i.e. base-64 full information (containing only public keys) and also
    // high-level published properties of all stored certificates (e.g. Serial)
    // - as such, .ca file format is more verbose than CreateFromJson/SaveToJson
    // and may be convenient for managing certificates with a text/json editor
    function SaveToFileVariant: variant;
    /// save the whole certificates chain as a JSON content, matching .ca format
    // - is in fact the human-friendly JSON serialization of this instance
    // - would store plain verbose information of all certificates,
    // i.e. base-64 full information (containing only public keys) and also
    // high-level published properties of all stored certificates (e.g. Serial)
    // - as such, .ca file format is more verbose than CreateFromJson/SaveToJson
    // and may be convenient for managing certificates with a text/json editor
    function SaveToFileContent: RawUTF8;
    /// load a certificates chain from some JSON-serialized .ca file content
    // - you may use SaveToFileContent method to create such JSON content
    // - would create only TECCCertificate instances with their public keys,
    // since no private key, therefore no TECCCertificateSecret is expected
    function LoadFromFileContent(const cajsoncontent: RawUTF8): boolean;
    /// save the whole certificates chain as a .ca JSON file
    // - is in fact the human-friendly JSON serialization of this instance
    // - the .ca file would store plain verbose information of all certificates,
    // i.e. base-64 full information (containing only public keys) and also
    // high-level published properties of all stored certificates (e.g. Serial)
    // - as such, this file format is more verbose than CreateFromJson/SaveToJson
    // and may be convenient for managing certificates with a text/json editor
    function SaveToFile(const jsonfile: TFileName): boolean;
    /// load a certificates chain from some JSON-serialized .ca file
    // - you may use SaveToFile() method to create such JSON file
    // - would create only TECCCertificate instances with their public keys,
    // since no private key, therefore no TECCCertificateSecret is expected
    // - if jsonfile is not in the current folder, will try ECCKeyFileFolder
    function LoadFromFile(const jsonfile: TFileName): boolean;
  {$endif NOVARIANTS}
  {$ifndef DELPHI5OROLDER}
  published
  {$endif}
    /// low-level access to the internal certificates chain
    // - thread-safe process may be done using
    // ! Safe.Lock; try ... finally Safe.Unlock; end;
    property Items: TECCCertificateObjArray read fItems;
    /// how many certificates are currently stored in the certificates chain
    property Count: integer read GetCount;
    /// if the IsValid() calls should maintain a cache of all valid certificates
    // - will use a naive but very efficient crc64c hashing of previous contents
    // - since ecdsa_verify() is very demanding, such a cache may have a huge
    // speed benefit if the certificates are about to be supplied several times
    // - is disabled by default, for paranoid safety
    property IsValidCached: boolean read fIsValidCached write SetIsValidCached;
  end;

  /// abstract ECDHE secure protocol with unilateral or mutual authentication
  // - inherited TECDHEProtocolClient and TECDHEProtocolServer
  // classes will implement a secure client/server transmission, with a one-way
  // handshake and asymmetric encryption
  // - will validate ECDSA signatures using certificates of the associated PKI
  // - will create an ephemeral ECC key pair for perfect forward security
  // - will use ECDH to compute a shared ephemeral session on both sides,
  // for AES-128 or AES-256 encryption, and HMAC with anti-replay - default
  // algorithm will use fast and safe AES-CFB 128-bit encryption, with efficient
  // AES-CRC 256-bit MAC, and full hardware accelleration on Intel CPUs
  TECDHEProtocol = class(TInterfacedObjectLocked, IProtocol)
  protected
    fPKI: TECCCertificateChain;
    fPrivate: TECCCertificateSecret;
    fAlgo: TECDHEAlgo;
    fEFSalt: RawByteString;
    fMACSalt: RawByteString;
    fOwned: set of (ownPKI, ownPrivate);
    fCertificateValidity: TECCValidity;
    fRndA,fRndB: THash128;
    fAES: array[boolean] of TAESAbstract;
    fkM: array[boolean] of THash256;
    // contains inc(PInt64(@aKey)^) to maintain RX/TX sequence number
    procedure SetKey(aEncrypt: boolean);
    procedure ComputeMAC(aEncrypt: boolean; aEncrypted: pointer; aLen: integer;
      out aMAC: THash256);
    function Verify(frame: PByteArray; len: integer; const QC: TECCCertificateContent;
      out res: TProtocolResult): boolean;
    procedure Sign(frame: PByteArray; len: integer; out QC: TECCCertificateContent);
    procedure SharedSecret(sA,sB: PHash256);
  public
    /// initialize the ECDHE protocol with a PKI and a private secret key
    // - if aPKI is not set, the certificates won't be validated and the protocol
    // will allow self-signed credentials
    // - aPrivate should always be set for mutual or unilateral authentication
    // - will implement unilateral authentication if aPrivate=nil for this end
    constructor Create(aAuth: TECDHEAuth; aPKI: TECCCertificateChain;
      aPrivate: TECCCertificateSecret); reintroduce; overload; virtual;
    /// will create another instance of this communication protocol
    constructor CreateFrom(aAnother: TECDHEProtocol); virtual;
    /// initialize the communication by exchanging some client/server information
    // - this method should be overriden with the proper implementation
    function ProcessHandshake(const MsgIn: RawUTF8; out MsgOut: RawUTF8): TProtocolResult; virtual; abstract;
    /// creates a new TECDHEProtocolClient or TECDHEProtocolServer from a text key
    // - expected layout is values separated by ; with at least a=... pair
    // - if needed, you can specify p=... as the password file name (searching
    // for first matching unique file name with .private extension in the
    // current directory of in ECCKeyFileFolder), and pw=...;pr=... for the
    // associated password protection (password content and rounds)
    // - optional ca=..;a=..;k=..;e=..;m=.. switches will match PKI, Auth, KDF,
    // EF and MAC properties of this class instance (triming left lowercase chars)
    // - global value set by FromKeySetCA() is used as PKI, unless ca=.. is set
    // (as a .ca file name, or as ca=base64,base64 or ca="base64","base64")
    // - a full text key with default values may be:
    // $ a=mutual;k=hmacsha256;e=aescrc128;m=duringef;p=34a2;pw=passwordFor34a2;
    // $ pr=60000;ca=websockets
    // - returns nil if aKey does not match this format, i.e. has no p=..,pw=..
    class function FromKey(const aKey: RawUTF8; aServer: boolean): TECDHEProtocol;
    /// defines the default PKI instance to be used by FromKey
    // - used if the ca=... property is not set in the aKey value
    class procedure FromKeySetCA(aPKI: TECCCertificateChain);
    /// computes a TSynPersistentWithPassword key expected by FromKey
    // - the .private key file name, and its associated password/rounds should
    // be specified, but for unilateral authentication on the other side
    // - pki should be a .ca file name, 'base64,base64' or '"base64","base64"'
    // - result of this method can be stored directly in a .settings file,
    // to enable the TECDHEProtocol safe protocol for transmission
    class function FromKeyCompute(const privkey, privpassword: RawUTF8;
      privrounds: integer=DEFAULT_ECCROUNDS; const pki: RawUTF8=''; auth: TECDHEAuth=authMutual;
      kdf: TECDHEKDF=kdfHmacSha256; ef: TECDHEEF=efAesCrc128;
      mac: TECDHEMAC=macDuringEF; customkey: cardinal=0): RawUTF8;  
    /// finalize the instance
    // - also erase all temporary secret keys, for safety
    destructor Destroy; override;
    /// encrypt a message on one side, ready to be transmitted to the other side
    // - will use the Encryption Function EF, according to the shared secret key
    // - this method is thread-safe
    procedure Encrypt(const aPlain: RawByteString; out aEncrypted: RawByteString); virtual;
    /// decrypt a message on one side, as transmitted from the other side
    // - will use the Encryption Function EF, according to the shared secret key
    // - returns sprInvalidMAC in case of wrong aEncrypted input (e.g. packet
    // corruption, MiM or Replay attacks attempts)
    // - this method is thread-safe
    function Decrypt(const aEncrypted: RawByteString; out aPlain: RawByteString): TProtocolResult; virtual;
    /// check for any transmission error of the supplied encrypted text
    // - returns sprSuccess if the stored CRC of the encrypted flow matches
    // - returns sprInvalidMAC in case of wrong aEncrypted input
    // - is only implemented for MAC=macDuringEF, otherwise returns sprUnsupported
    // - to be called before Decrypt(), since this later method will change the
    // internal kM[false] sequence number 
    function CheckError(const aEncrypted: RawByteString): TProtocolResult; virtual;
    /// will create another instance of this communication protocol
    function Clone: IProtocol;
    /// shared public-key infrastructure, used to validate exchanged certificates
    // - will be used for authenticity validation of ECDSA signatures
    property PKI: TECCCertificateChain read fPKI;
    /// the current Authentication scheme
    // - this value on client side should match server's Authorized
    // - this value on server side may change if the client forced another mode
    property Auth: TECDHEAuth read fAlgo.auth;
    /// the current Key Derivation Function
    // - this value should match on both client and server sides
    property KDF: TECDHEKDF read fAlgo.kdf write fAlgo.kdf;
    /// the current salt, used by the Key Derivation Function KDF to compute the
    // key supplied to the Encryption Function EF
    // - equals 'ecdhesalt' by default
    // - this value should match on both client and server sides
    property EFSalt: RawByteString read fEFSalt write fEFSalt;
    /// the current Encryption Function
    // - this value should match on both client and server sides
    property EF: TECDHEEF read fAlgo.ef write fAlgo.ef;
    /// the current salt, used by the Key Derivation Function KDF to compute the
    // key supplied to the Message Authentication Code MAC
    // - equals 'ecdhemac' by default
    // - this value should match on both client and server sides
    property MACSalt: RawByteString read fMACSalt write fMACSalt;
    /// the current Message Authentication Code
    // - this value should match on both client and server sides
    property MAC: TECDHEMAC read fAlgo.mac write fAlgo.mac;
    /// after handshake, contains the information about the other side
    // public key certificate validity, against the shared PKI
    property CertificateValidity: TECCValidity read fCertificateValidity;
  end;

  /// meta-class of the TECDHEProtocol type
  TECDHEProtocolClass = class of TECDHEProtocol;

  /// implements ECDHE secure protocol on client side
  TECDHEProtocolClient = class(TECDHEProtocol)
  protected
    fdE: TECCPrivateKey;
  public
    /// initialize the ECDHE protocol on the client side
    // - will check that aAuth is compatible with the supplied aPKI/aPrivate
    constructor Create(aAuth: TECDHEAuth; aPKI: TECCCertificateChain;
      aPrivate: TECCCertificateSecret); override;
    /// generate the authentication frame sent from the client
    procedure ComputeHandshake(out aClient: TECDHEFrameClient);
    /// validate the authentication frame sent back by the server
    function ValidateHandshake(const aServer: TECDHEFrameServer): TProtocolResult;
    /// initialize the client communication
    // - if MsgIn is '', will call ComputeHandshake
    // - if MsgIn is set, will call ValidateHandshake
    function ProcessHandshake(const MsgIn: RawUTF8; out MsgOut: RawUTF8): TProtocolResult; override;
  end;

  /// implements ECDHE secure protocol on server side
  TECDHEProtocolServer = class(TECDHEProtocol)
  protected
    fAuthorized: TECDHEAuths;
  public
    /// initialize the ECDHE protocol on the client side
    // - will check that aAuth is compatible with the supplied aPKI/aPrivate
    constructor Create(aAuth: TECDHEAuth; aPKI: TECCCertificateChain;
      aPrivate: TECCCertificateSecret); override;
    /// will create another instance of this communication protocol
    constructor CreateFrom(aAnother: TECDHEProtocol); override;
    /// generate the authentication frame corresponding to the client request
    // - may change Auth property if the Client requested another authentication
    // scheme, allowed in Authorized setting and compatible with fPrivate
    function ComputeHandshake(const aClient: TECDHEFrameClient;
      out aServer: TECDHEFrameServer): TProtocolResult;
    /// initialize the server communication
    // - will call ComputeHandshake
    function ProcessHandshake(const MsgIn: RawUTF8; out MsgOut: RawUTF8): TProtocolResult; override;
    /// the Authentication Schemes allowed by this server
    // - by default, only the aAuth value specified to Create is allowed
    // - you can set e.g. [authMutual,authServer] for a weaker pattern
    property Authorized: TECDHEAuths read fAuthorized write fAuthorized;
  end;

{$ifndef NOVARIANTS}

  /// implements JSON Web Tokens using 'ES256' algorithm
  // - i.e. ECDSA using the P-256 curve and the SHA-256 hash algorithm
  // - as defined in http://tools.ietf.org/html/rfc7518 paragraph 3.4
  // - since ECDSA signature and verification is CPU consumming (under x86, it
  // takes 2.5 ms, but only 0.3 ms on x64) you may enable CacheTimeoutSeconds
  TJWTES256 = class(TJWTAbstract)
  protected
    fCertificate: TECCCertificate;
    fOwnCertificate: boolean;
    function ComputeSignature(const payload64: RawUTF8): RawUTF8; override;
    procedure CheckSignature(var JWT: TJWTContent; const payload64: RawUTF8;
      const signature: RawByteString); override;
  public
    /// initialize the JWT processing instance using ECDSA P-256 algorithm
    // - the supplied set of claims are expected to be defined in the JWT payload
    // - the supplied ECC certificate should be a TECCCertificate storing the
    // public key needed for Verify(), or a TECCCertificateSecret storing also
    // the private key required by Compute()
    // - aCertificate is owned by this instance if property OwnCertificate is true
    // - aAudience are the allowed values for the jrcAudience claim
    // - aExpirationMinutes is the deprecation time for the jrcExpirationTime claim
    // - aIDIdentifier and aIDObfuscationKey are passed to a
    // TSynUniqueIdentifierGenerator instance used for jrcJwtID claim
    constructor Create(aCertificate: TECCCertificate; aClaims: TJWTClaims;
      const aAudience: array of RawUTF8; aExpirationMinutes: integer=0;
      aIDIdentifier: TSynUniqueIdentifierProcess=0; aIDObfuscationKey: RawUTF8=''); reintroduce;
    /// finalize the instance
    destructor Destroy; override;
    /// access to the associated TECCCertificate instance
    // - which may be a TECCCertificateSecret for Compute() private key
    property Certificate: TECCCertificate read fCertificate;
    /// if the associated TECCCertificate is to be owned by this instance
    property OwnCertificate: boolean read fOwnCertificate write fOwnCertificate;
  end;

{$endif NOVARIANTS}

const
  /// file extension of the JSON file storing a TECCCertificate public key
  ECCCERTIFICATEPUBLIC_FILEEXT = '.public';
  /// file extension of the binary encrypted file storing a private key
  // - as generated by TECCCertificateSecret.SaveToSecureFile method
  ECCCERTIFICATESECRET_FILEEXT = '.private';
  /// file extension of the JSON file storing a digital signature of a file
  // - by convention, this .sign extension is appended to the original file name
  // - as generated by TECCCertificateSecret.SignFile, and loaded by the
  // TECCSignatureCertifiedFile class
  ECCCERTIFICATESIGN_FILEEXT = '.sign';
  /// file extension of the JSON file storing a certificate authorities chain
  // - as generated by mORMot.pas TECCCertificateChainFile.SaveToFile()
  // and loaded by TECCCertificateChain.LoadFromFile
  ECCCERTIFICATES_FILEEXT = '.ca';
  /// file extension of the ECIES encrypted file
  // - with optional digital signature of the plain content
  // - as generated by TECCCertificate.Encrypt/EncryptFile, and decoded via
  // TECCCertificateSecret.Decrypt
  ENCRYPTED_FILEEXT = '.synecc';

/// search the single .public or .private file starting with the supplied file name
// - as used in the ECC.dpr command-line sample project
// - returns true and set the full file name of the matching file
// - returns false is there is no match, or more than one matching file
// - will also search in ECCKeyFileFolder, if the supplied folder is not enough 
function ECCKeyFileFind(var TruncatedFileName: TFileName; privkey: boolean): boolean;

/// search the single .public or .private file used to crypt a given content
// - match the format generated by TECCCertificate.Encrypt/EncryptFile
// - returns true on success, false otherwise
// - will also search in ECCKeyFileFolder, if the current folder is not enough 
function ECIESKeyFileFind(const encrypted: RawByteString; out keyfile: TFileName;
  privkey: boolean=true): boolean;

/// retrieve the private local folder used to store .public or .private files
// - it is better to store all you key files in a single place, for easier
// and safer management
// - under Windows, returns 'C:\Users\username\AppData\Local\Synopse\Keys\'
// - under Linux, returns '$HOME/.synopse/keys/'
function ECCKeyFileFolder: TFileName;


function ToText(val: TECCValidity): PShortString; overload;
function ToText(res: TECCDecrypt): PShortString; overload;
function ToText(algo: TECIESAlgo): PShortString; overload;
function ToText(algo: TECDHEAuth): PShortString; overload;
function ToText(algo: TECDHEKDF): PShortString; overload;
function ToText(algo: TECDHEEF): PShortString; overload;
function ToText(algo: TECDHEMAC): PShortString; overload;


implementation

uses Math;


{ *********** low-level ECC secp256r1 ECDSA and ECDH functions *********** }

{
  Benchmark of all available x86/32-bit variants, compiled with MinGW-W64 5.2.0

  gcc -g -O2 -c ecc.c
  d:\dev\tools\objconv.exe -fomf -nd -nu- ecc.o
  del eccwin32O2.o
  ren ecc.o SynEccWin32O2.o
  del eccwin32O2.obj
  ren ecc.obj SynEccWin32O2.obj

  Win32 ECC_32ASM
  - ecc_make_key: 1,000 assertions passed  2.38s
  - ecdsa_sign: 1,000 assertions passed  2.44s
  - ecdsa_verify: 1,000 assertions passed  2.96s
  - ecdh_shared_secret: 2,997 assertions passed  5.08s
  Total failed: 0 / 5,997  - ECC cryptography PASSED  12.88s

  Linux32 (Kylix) ECC_32ASM
  - ecc_make_key: 1,000 assertions passed  2.36s
  - ecdsa_sign: 1,000 assertions passed  2.44s
  - ecdsa_verify: 1,000 assertions passed  2.95s
  - ecdh_shared_secret: 2,997 assertions passed  5.07s
  Total failed: 0 / 5,997  - ECC cryptography PASSED  12.84s

  Win32 ECC_O1 (eccwin32O1.obj = 10480 bytes)
  - ecc_make_key: 1,000 assertions passed  2.34s
  - ecdsa_sign: 1,000 assertions passed  2.42s
  - ecdsa_verify: 1,000 assertions passed  2.91s
  - ecdh_shared_secret: 2,997 assertions passed  4.98s
  Total failed: 0 / 5,997  - ECC cryptography PASSED  12.67s

  Win32 ECC_O2 (eccwin32O2.obj = 16700 bytes)
  - ecc_make_key: 1,000 assertions passed  2.16s
  - ecdsa_sign: 1,000 assertions passed  2.20s
  - ecdsa_verify: 1,000 assertions passed  2.66s
  - ecdh_shared_secret: 2,997 assertions passed  4.58s
  Total failed: 0 / 5,997  - ECC cryptography PASSED  11.63s

  Win32 ECC_O3 (eccwin32O3.obj = 66798 bytes)
  - ecc_make_key: 1,000 assertions passed  2.17s
  - ecdsa_sign: 1,000 assertions passed  2.20s
  - ecdsa_verify: 1,000 assertions passed  2.65s
  - ecdh_shared_secret: 2,997 assertions passed  4.59s
  Total failed: 0 / 5,997  - ECC cryptography PASSED  11.64s

  -> conclusion: under Win32, ECC_O2 is used, and ECC_32ASM for Kylix+FPC
     time is around 2-3 ms for each operation (i.e. 400-500/sec)


  Benchmark of all available x64/64-bit variants, compiled with MinGW-W64 5.2.0

  Win64 ECC_O1 (eccwin64O1.o = 45765 bytes)
  - ecc_make_key: 1,000 assertions passed  601.37ms
  - ecdsa_sign: 1,000 assertions passed  622.23ms
  - ecdsa_verify: 1,000 assertions passed  758.28ms
  - ecdh_shared_secret: 2,997 assertions passed  1.26s
  Total failed: 0 / 5,997  - ECC cryptography PASSED  3.32s

  Win64 ECC_O2 (eccwin64O2.o = 84779 bytes)
  - ecc_make_key: 1,000 assertions passed  573.09ms
  - ecdsa_sign: 1,000 assertions passed  588.86ms
  - ecdsa_verify: 1,000 assertions passed  712.31ms
  - ecdh_shared_secret: 2,997 assertions passed  1.20s
  Total failed: 0 / 5,997  - ECC cryptography PASSED  3.16s

  Win64 ECC_O3 (eccwin64O3.o = 204775 bytes)
  - access violation at startup (due to .o linking error by Delphi)

  -> conclusion: under Win64, ECC_O2 is used
     time is around 0.5-0.6 ms for each operation (i.e. 2000/sec)
     x64 is four time faster than x86 for such arithmetic tasks :)

}

{$ifdef ECC_AVAILABLE}

function getRandomNumber(dest: pointer): integer; cdecl;
  {$ifdef FPC}public name{$ifdef Win32}'_getRandomNumber'{$else}'getRandomNumber'{$endif};{$endif}
begin
  TAESPRNG.Fill(dest,ECC_BYTES);
  result := 1;
end;

{$ifdef ECC_32ASM}

{$I SynEcc32asm.inc}

{$else}

{$ifdef CPUX86}
  {$ifdef FPC}
    {$ifdef MSWINDOWS}
      {$ifdef ECC_O1}
        {$L fpc-win32\eccwin32O1.o}
      {$endif}
      {$ifdef ECC_O2}
        {$L fpc-win32\eccwin32O2.o}
      {$endif}
      {$ifdef ECC_O3}
        {$L fpc-win32\eccwin32O3.o}
      {$endif}
    {$else}
      {$ifdef ECC_O1}
        {$L fpc-linux32/ecclin32O1.o}
      {$endif}
      {$ifdef ECC_O2}
        {$L fpc-linux32/ecclin32O2.o}
      {$endif}
      {$ifdef ECC_O3}
        {$L fpc-linux32/ecclin32O3.o}
      {$endif}
    {$endif MSWINDOWS}
  {$else}
    {$ifdef ECC_O1}
      {$L SynEcc32O1.obj}
    {$endif}
    {$ifdef ECC_O2}
      {$L SynEcc32O2.obj}
    {$endif}
    {$ifdef ECC_O3}
      {$L SynEcc32O3.obj}
    {$endif}
  {$endif FPC}
{$endif CPUX86}

{$ifdef CPUX64}
  {$ifdef MSWINDOWS} // same .o format under Win64 for Delphi and FPC :)
  {$ifdef ECC_O1}
    {$L SynEcc64O1.o}
  {$endif}
  {$ifdef ECC_O2}
    {$L SynEcc64O2.o}
  {$endif}
  {$ifdef ECC_O3}
    {$L SynEcc64O3.o}
  {$endif}
  {$else}
  {$ifdef FPC}
    {$ifdef ECC_O1}
      {$L fpc-linux64/ecclin64O1.o}
    {$endif}
    {$ifdef ECC_O2}
      {$L fpc-linux64/ecclin64O2.o}
    {$endif}
    {$ifdef ECC_O3}
      {$L fpc-linux64/ecclin64O3.o}
    {$endif}
  {$endif FPC}
  {$endif MSWINDOWS}
{$endif CPUX64}

function ecc_make_key; external;
function ecdh_shared_secret; external;
function ecdsa_sign; external;
function ecdsa_verify; external;

{$endif ECC_32ASM}

{$else ECC_AVAILABLE}

// currently no .o file available under ARM -> stub functions returning 0 (error)

function ecc_make_key(out pub: TECCPublicKey; out priv: TECCPrivateKey): boolean;
begin
  result := false;
end;

function ecdh_shared_secret(const pub: TECCPublicKey; const priv: TECCPrivateKey;
  out secret: TECCSecretKey): boolean;
begin
  result := false;
end;

function ecdsa_sign(const priv: TECCPrivateKey; const hash: TECCHash;
  out sign: TECCSignature): boolean;
begin
  result := false;
end;

function ecdsa_verify(const pub: TECCPublicKey; const hash: TECCHash;
  const sign: TECCSignature): boolean;
begin
  result := false;
end;

{$endif ECC_AVAILABLE}



{ *********** middle-level certificate-based public-key cryptography *********** }

const
  // Mon, 01 Aug 2016 encoded as COM/TDateTime value
  ECC_DELTA = 42583;

function NowECCDate: TECCDate;
begin
  result := Trunc(NowUTC) - ECC_DELTA;
end;

function ECCDate(const DateTime: TDateTime): TECCDate;
var now: integer;
begin
  if DateTime=0 then
    result := 0 else begin
    now := Trunc(DateTime) - ECC_DELTA;
    if cardinal(now)>high(TECCDate) then
      result := 0 else
      result := now;
  end;
end;

function ECCToDateTime(ECCDate: TECCDate): TDateTime;
begin
  if ECCDate=0 then
    result := 0 else
    result := ECCDate + ECC_DELTA;
end;

function ECCText(ECCDate: TECCDate; Expanded: boolean): RawUTF8;
begin
  if ECCDate=0 then
    result := '' else
    result := DateToIso8601(ECCDate + ECC_DELTA, Expanded);
end;

function ECCText(const Issuer: TECCCertificateIssuer): RawUTF8;
var tmp: array[0..sizeof(Issuer)] of byte;
begin
  if IsZero(THash128(Issuer)) then
    result := '' else begin
    PAESBlock(@tmp)^ := TAESBlock(Issuer);
    tmp[sizeof(Issuer)] := 0; // add a trailing #0 as expected for trailing bits
    result := BaudotToAscii(@tmp,sizeof(Issuer));
    if result='' then
      result := SynCommons.BinToHex(@Issuer,sizeof(Issuer));
  end;
end;

function ECCIssuer(const Text: RawUTF8; out Issuer: TECCCertificateIssuer): boolean;
var baudot: RawByteString;
    len: integer;
begin
  FillZero(THash128(Issuer));
  baudot := AsciiToBaudot(Text);
  len := length(baudot);
  result := len>sizeof(Issuer);
  if result then // truncated
    len := sizeof(Issuer);
  MoveFast(pointer(baudot)^,Issuer,len);
end;

function ECCText(const ID: TECCCertificateID): RawUTF8;
begin
  if IsZero(THash128(ID)) then
    result := '' else
    result := AESBlockToString(TAESBlock(ID));
end;

function ECCID(const Text: RawUTF8; out ID: TECCCertificateID): boolean;
begin
  if length(Text)<>sizeof(ID)*2 then
    result := false else
    result := SynCommons.HexToBin(pointer(Text),@ID,sizeof(ID));
end;

function ECCCheck(const content: TECCCertificateContent): boolean;
begin
  with content.Signed do
    if (IssueDate=0) or (IssueDate=65535) or
       IsZero(THash128(Serial)) or IsZero(THash128(Issuer)) or
       IsZero(THash128(AuthoritySerial)) or IsZero(THash128(AuthorityIssuer)) or
       IsZero(@PublicKey,sizeof(PublicKey)) or
       IsZero(@content.Signature,sizeof(content.Signature)) then
      result := false else
      result := (content.Version in [1]) and
                (fnv32(0,@content,sizeof(content)-4)=content.CRC);
end;

function ECCCheckDate(const content: TECCCertificateContent): boolean;
var now: TECCDate;
begin
  now := NowECCDate;
  with content.Signed do
    result := (IssueDate<=now) and
              ((ValidityStart=0) or (ValidityStart<=now)) and
              ((ValidityEnd=0) or (ValidityEnd>=now));
end;

function ECCSelfSigned(const content: TECCCertificateContent): boolean;
begin
  with content.Signed do
    result := IsEqual(THash128(AuthoritySerial),THash128(Serial)) and
              IsEqual(THash128(AuthorityIssuer),THash128(Issuer)) and
              not IsZero(THash128(Serial));
end;

function ECCCheck(const content: TECCSignatureCertifiedContent): boolean;
begin
  result := (content.Version in [1]) and (content.Date<>0) and
    not IsZero(THash128(content.AuthoritySerial)) and
    not IsZero(THash128(content.AuthorityIssuer)) and
    not IsZero(@content.Signature,sizeof(content.Signature));
end;

function ECCSign(const base64: RawUTF8; out content: TECCSignatureCertifiedContent): boolean;
begin
  result := Base64ToBin(pointer(base64),@content,length(base64),sizeof(content),false);
end;

function ECCText(const sign: TECCSignatureCertifiedContent): RawUTF8; overload;
begin
  if ECCCheck(sign) then
    result := BinToBase64(@sign,sizeof(sign)) else
    result := '';
end;

function ECCText(const sign: TECCSignature): RawUTF8; overload;
begin
  if IsZero(@sign,sizeof(sign)) then
    result := '' else
    result := BinToBase64(@sign,sizeof(sign));
end;

function ECCVerify(const sign: TECCSignatureCertifiedContent;
  const hash: THash256; const auth: TECCCertificateContent): TECCValidity;
begin
  if not ecc_available then
    result := ecvNotSupported else
  if IsZero(hash) then
    result := ecvBadParameter else
  if not ECCCheck(sign) then
    result := ecvCorrupted else
  if sign.Date>NowECCDate then
    result := ecvInvalidDate else
  if not ECCCheck(auth) then
    result := ecvUnknownAuthority else
  if not ECCCheckDate(auth) then
    result := ecvDeprecatedAuthority else
  if not ecdsa_verify(auth.Signed.PublicKey,hash,sign.Signature) then
    result := ecvInvalidSignature else
  if ECCSelfSigned(auth) then
    result := ecvValidSelfSigned else
    result := ecvValidSigned;
end;

const
  ECIES_MAGIC: array[0..15] of AnsiChar = 'SynEccEncrypted'#26;
  ECIES_NOSYNLZ: array[ecaPBKDF2_HMAC_SHA256_AES256_CFB_SYNLZ..
    ecaPBKDF2_HMAC_SHA256_AES128_CTR_SYNLZ] of TECIESAlgo = (
      ecaPBKDF2_HMAC_SHA256_AES256_CFB, ecaPBKDF2_HMAC_SHA256_AES256_CBC,
      ecaPBKDF2_HMAC_SHA256_AES256_OFB, ecaPBKDF2_HMAC_SHA256_AES256_CTR,
      ecaPBKDF2_HMAC_SHA256_AES128_CFB, ecaPBKDF2_HMAC_SHA256_AES128_CBC,
      ecaPBKDF2_HMAC_SHA256_AES128_OFB, ecaPBKDF2_HMAC_SHA256_AES128_CTR);
  ECIES_AES: array[ecaPBKDF2_HMAC_SHA256_AES256_CFB..
    ecaPBKDF2_HMAC_SHA256_AES128_CTR] of TAESAbstractClass = (
      TAESCFB, TAESCBC, TAESOFB, TAESCTR, TAESCFB, TAESCBC, TAESOFB, TAESCTR,
      TAESCFB, TAESCBC, TAESOFB, TAESCTR, TAESCFB, TAESCBC, TAESOFB, TAESCTR);
  ECIES_AESSIZE: array[ecaPBKDF2_HMAC_SHA256_AES256_CFB..
    ecaPBKDF2_HMAC_SHA256_AES128_CTR] of integer = (
      256, 256, 256, 256, 256, 256, 256, 256,
      128, 128, 128, 128, 128, 128, 128, 128);

function ECIESHeader(const head: TECIESHeader): boolean;
begin
  result := IsEqual(head.magic,THash128(ECIES_MAGIC)) and
    (head.Algo in [Low(ECIES_AES)..High(ECIES_AES)]) and
    (head.crc=crc32c(PCardinal(@head.hmac)^,@head,sizeof(head)-sizeof(head.crc)));
end;

function ECIESHeader(const encrypted: RawByteString; out head: TECIESHeader): boolean;
begin
  result := (length(encrypted)>sizeof(head)) and ECIESHeader(PECIESHeader(encrypted)^);
  if result then
    head := PECIESHeader(encrypted)^;
end;

function ECIESHeaderFile(const encryptedfile: TFileName; out head: TECIESHeader;
  const rawencryptedfile: TFileName): boolean;
var F: THandle;
    len: integer;
    tmp: RawByteString;
begin
  result := false;
  if encryptedfile='' then
    exit;
  F := FileOpen(encryptedfile,fmOpenRead or fmShareDenyNone);
  if PtrInt(F)<0 then
    exit;
  if FileRead(F,head,sizeof(head))=sizeof(head) then
    result := ECIESHeader(head);
  if result and (rawencryptedfile<>'') then begin
    len := GetFileSize(F,nil)-sizeof(head);
    SetLength(tmp,len);
    if FileRead(F,pointer(tmp)^,len)<>len then
      result := false else
      result := FileFromString(tmp,rawencryptedfile);
  end;
  FileClose(F);
end;

function ECIESHeaderText(const head: TECIESHeader): RawUTF8;
var s: variant;
{$ifdef NOVARIANTS}
begin
  s := ECCText(head.sign);
{$else}
    sign: TECCSignatureCertified;
begin
  sign := TECCSignatureCertified.CreateFrom(head.sign,true);
  try
    if sign.Check then begin
      s := sign.ToVariant;
      TDocVariantData(s).AddValueFromText('ECDSA',ECCText(head.sign.Signature));
    end;
  finally
    sign.Free;
  end;
{$endif}
  with head do
    result := JSONEncode(['Date',ECCText(date), 'Size',size,
      'Recipient',ECCText(rec), 'RecipientSerial',ECCText(recid),
      'FileTime',DateTimeToIso8601Text(UnixTimeToDateTime(unixts)),
      'Algorithm',ToText(algo)^,
      'RandomPublicKey',SynCommons.BinToHex(@rndpub,sizeof(rndpub)),
      'HMAC',SHA256DigestToString(hmac), 'Signature',s]);
end;

function ECIESHeaderText(const encryptedfile,rawencryptedfile: TFileName): RawUTF8; overload;
var h: TECIESHeader;
begin
  if ECIESHeaderFile(encryptedfile,h,rawencryptedfile) then
    result := ECIESHeaderText(h) else
    result := '';
end;


{ *********** high-level certificate-based public-key cryptography *********** }

function ToText(val: TECCValidity): PShortString;
begin
  result := GetEnumName(TypeInfo(TECCValidity),ord(val));
end;

function ToText(res: TECCDecrypt): PShortString;
begin
  result := GetEnumName(TypeInfo(TECCDecrypt),ord(res));
end;

function ToText(algo: TECIESAlgo): PShortString;
begin
  result := GetEnumName(TypeInfo(TECIESAlgo),ord(algo));
end;

function ToText(algo: TECDHEAuth): PShortString;
begin
  result := GetEnumName(TypeInfo(TECDHEAuth),ord(algo));
end;

function ToText(algo: TECDHEKDF): PShortString;
begin
  result := GetEnumName(TypeInfo(TECDHEKDF),ord(algo));
end;

function ToText(algo: TECDHEEF): PShortString;
begin
  result := GetEnumName(TypeInfo(TECDHEEF),ord(algo));
end;

function ToText(algo: TECDHEMAC): PShortString;
begin
  result := GetEnumName(TypeInfo(TECDHEMAC),ord(algo));
end;


var
  _ECCKeyFileFolder: TFileName;

function ECCKeyFileFolder: TFileName;
begin
  if _ECCKeyFileFolder='' then begin
    _ECCKeyFileFolder := GetSystemPath(spUserData)+
      {$ifdef MSWINDOWS}'Synopse\Keys\'{$else}'.synopse/keys/'{$endif};
    if not DirectoryExists(_ECCKeyFileFolder) then
      CreateDir(_ECCKeyFileFolder); // always create this folder
  end;
  result := _ECCKeyFileFolder;
end;

function ECCKeyFileFind(var TruncatedFileName: TFileName; privkey: boolean): boolean;
var match: TFindFilesDynArray;
    ext,mask: TFileName;
begin
  match := nil; // to please Kylix
  if privkey then
    ext := ECCCERTIFICATESECRET_FILEEXT else
    ext := ECCCERTIFICATEPUBLIC_FILEEXT;
  result := true;
  if FileExists(TruncatedFileName) then
    exit;
  if FileExists(TruncatedFileName+ext) then begin
    TruncatedFileName := TruncatedFileName+ext;
    exit;
  end;
  mask := ExtractFileName(TruncatedFileName)+'*'+ext;
  match := FindFiles(ExtractFilePath(TruncatedFileName),mask);
  if length(match)<>1 then
    match := FindFiles(ECCKeyFileFolder,mask);
  if length(match)<>1 then
    result := false else
    TruncatedFileName := match[0].Name;
end;

function ECIESKeyFileFind(const encrypted: RawByteString; out keyfile: TFileName;
  privkey: boolean): boolean;
var head: TECIESHeader;
begin
  result := ECIESHeader(encrypted,head);
  if result then begin
    keyfile := UTF8ToString(ECCText(head.recid));
    result := ECCKeyFileFind(keyfile,privkey);
  end;
end;


{ TECCCertificate }

constructor TECCCertificate.Create;
begin
  inherited Create;
  fContent.Version := 1;
end;

constructor TECCCertificate.CreateFrom(const binary: TECCCertificateContent);
begin
  Create;
  fContent := binary;
  if not ECCCheck(fContent) then
    raise EECCException.CreateUTF8('Invalid %.CreateFrom',[self]);
end;

constructor TECCCertificate.CreateFromBase64(const base64: RawUTF8);
begin
  Create;
  if not FromBase64(base64) then
    raise EECCException.CreateUTF8('Invalid %.CreateFromBase64',[self]);
end;

constructor TECCCertificate.CreateFromAuth(const AuthPubKey: TFileName;
  const AuthBase64, AuthSerial: RawUTF8);
begin
  Create;
  if not FromAuth(AuthPubKey,AuthBase64,AuthSerial) then
    raise EECCException.CreateUTF8('Invalid %.CreateFromAuth',[self]);
end;

function TECCCertificate.GetAuthorityIssuer: RawUTF8;
begin
  result := ECCText(fContent.Signed.AuthorityIssuer);
end;

function TECCCertificate.GetAuthoritySerial: RawUTF8;
begin
  result := ECCText(fContent.Signed.AuthoritySerial);
end;

function TECCCertificate.GetIssueDate: RawUTF8;
begin
  result := ECCText(fContent.Signed.IssueDate);
end;

function TECCCertificate.GetIssuer: RawUTF8;
begin
  result := ECCText(fContent.Signed.Issuer);
end;

function TECCCertificate.GetSerial: RawUTF8;
begin
  result := ECCText(fContent.Signed.Serial);
end;

function TECCCertificate.GetValidityEnd: RawUTF8;
begin
  result := ECCText(fContent.Signed.ValidityEnd);
end;

function TECCCertificate.GetValidityStart: RawUTF8;
begin
  result := ECCText(fContent.Signed.ValidityStart);
end;

function TECCCertificate.GetIsSelfSigned: boolean;
begin
  result := (self<>nil) and ECCSelfSigned(fContent);
end;

function TECCCertificate.CheckCRC: boolean;
begin
  result := (self<>nil) and ECCCheck(fContent);
end;

function TECCCertificate.FromBase64(const base64: RawUTF8): boolean;
var st: TRawByteStringStream;
begin
  if base64='' then
    result := false else begin
    st := TRawByteStringStream.Create(Base64ToBinSafe(base64));
    try
      result := LoadFromStream(st) and ECCCheck(fContent);
    finally
      st.Free;
    end;
  end;
end;

function TECCCertificate.FromFile(const filename: TFileName): boolean;
var json: RawUTF8;
    fn: TFileName;
begin
  if ExtractFileExt(filename)='' then
    fn := filename+ECCCERTIFICATEPUBLIC_FILEEXT else
    fn := filename;
  json := StringFromFile(fn);
  if json='' then
    result := false else
    result := FromBase64(JSONDecode(json,'Base64',nil,true));
end;

function TECCCertificate.FromAuth(const AuthPubKey: TFileName;
  const AuthBase64, AuthSerial: RawUTF8): boolean;
var authfilename: TFileName;
begin
  result := true;
  if FromFile(AuthPubKey) or FromBase64(AuthBase64) then
    exit;
  if AuthSerial<>'' then begin
    authfilename := UTF8ToString(AuthSerial);
    if ECCKeyFileFind(authfilename,false) and FromFile(authfilename) then
      exit;
  end;
  result := false;
end;

procedure TECCCertificate.SetBase64(const base64: RawUTF8);
begin
  FromBase64(base64);
end;

function TECCCertificate.ToBase64: RawUTF8;
var st: TRawByteStringStream;
begin
  st := TRawByteStringStream.Create;
  try
    if SaveToStream(st) then
      result := BinToBase64(st.DataString);
  finally
    st.Free;
  end;
end;

function TECCCertificate.PublicToBase64: RawUTF8;
var sav: boolean;
begin
  sav := fStoreOnlyPublicKey;
  fStoreOnlyPublicKey := true;
  result := ToBase64;
  fStoreOnlyPublicKey := sav;
end;

function TECCCertificate.LoadFromStream(Stream: TStream): boolean;
begin
  result := (Stream.Read(fContent,sizeof(fContent))=sizeof(fContent)) and
    InternalLoad(ReadStringFromStream(Stream,524288));
end;

function TECCCertificate.SaveToStream(Stream: TStream): boolean;
begin
  result := CheckCRC and
    (Stream.Write(fContent,sizeof(fContent))=sizeof(fContent)) and
    WriteStringToStream(Stream,InternalSave);
end;

function TECCCertificate.InternalLoad(const data: RawByteString): boolean;
begin
  result := true;
end;

function TECCCertificate.InternalSave: RawByteString;
begin
  result := '';
end;

{$ifdef ISDELPHI20062007}
  {$WARNINGS OFF} // circument Delphi 2007 false positive warning
{$endif}

function TECCCertificate.Encrypt(const Plain: RawByteString;
  Signature: TECCSignatureCertified; FileDateTime: TDateTime;
  const KDFSalt: RawUTF8; KDFRounds: integer;
  const MACSalt: RawUTF8; MACRounds: integer; Algo: TECIESAlgo): RawByteString;
var rndpriv: TECCPrivateKey;
    head: TECIESHeader;
    secret, dec, enc: RawByteString;
    aeskey, mackey: THash256;
begin
  result := '';
  if Plain='' then
    exit;
  if not CheckCRC then
    raise EECCException.CreateUTF8('%.Encrypt: no public key',[self]);
  if Algo=ecaUnknown then // use safest algorithm by default
    if IsContentCompressed(pointer(Plain),length(Plain)) then
      Algo := ecaPBKDF2_HMAC_SHA256_AES256_CFB else
      Algo := ecaPBKDF2_HMAC_SHA256_AES256_CFB_SYNLZ;
  if not (Algo in [Low(ECIES_AES)..High(ECIES_AES)]) then
    raise EECCException.CreateUTF8('%.Encrypt: unsupported %',[self,ToText(Algo)^]);
  try
    head.magic := THash128(ECIES_MAGIC);
    head.rec := fContent.Signed.Issuer;
    head.recid := fContent.Signed.Serial;
    head.size := length(Plain);
    head.date := NowECCDate;
    head.unixts := DateTimeToUnixTime(FileDateTime);
    if Signature.Check then
      head.sign := Signature.fContent else
      FillcharFast(head.sign,sizeof(head.sign),255); // Version=255=not signed
    if not ecc_make_key(head.rndpub,rndpriv) then
      raise EECCException.CreateUTF8('%.Encrypt: ecc_make_key failure',[self]);
    SetLength(secret,sizeof(TECCSecretKey));
    if not ecdh_shared_secret(fContent.Signed.PublicKey,rndpriv,PECCSecretKey(secret)^) then
      raise EECCException.CreateUTF8('%.Encrypt: ecdh_shared_secret failure',[self]);
    PBKDF2_HMAC_SHA256(secret,KDFSalt,KDFRounds,aeskey,'salt');
    if Algo in [low(ECIES_NOSYNLZ)..high(ECIES_NOSYNLZ)] then begin
      dec := SynLZCompress(Plain);
      if length(dec)>length(Plain) then begin // SynLZ was inefficient
        FillZero(dec);
        dec := Plain;
        Algo := ECIES_NOSYNLZ[Algo];
      end;
    end else
      dec := Plain;
    head.Algo := Algo;
    enc := ECIES_AES[Algo].SimpleEncrypt( // encrypt with PKCS7 padding
      dec,aeskey,ECIES_AESSIZE[Algo],true,true);
    PBKDF2_HMAC_SHA256(secret,MACSalt,MACRounds,mackey,'hmac');
    HMAC_SHA256(mackey,enc,head.hmac); // HMAC of the encrypted content
    head.crc := crc32c(PCardinal(@head.hmac)^,@head,sizeof(head)-sizeof(head.crc));
    SetLength(result,sizeof(head)+length(enc));
    PECIESHeader(result)^ := head;
    MoveFast(pointer(enc)^,PByteArray(result)[sizeof(head)],length(enc));
  finally
    FillZero(aeskey);
    FillZero(mackey);
    FillcharFast(rndpriv,sizeof(rndpriv),0);
    if dec<>Plain then
      FillZero(dec);
    FillZero(secret);
  end;
end;

{$ifdef ISDELPHI20062007}
  {$WARNINGS ON} // circument Delphi 2007 false positive warning
{$endif}

function TECCCertificate.EncryptFile(const FileToCrypt, DestFile: TFileName;
  const Salt: RawUTF8; SaltRounds: integer; Algo: TECIESAlgo; IncludeSignFile: boolean): boolean;
var plain,encrypted: RawByteString;
    cert: TECCSignatureCertified;
    dest: TFileName;
    filetime: TDateTime;
begin
  plain := StringFromFile(FileToCrypt);
  if plain='' then
    raise EECCException.CreateUTF8('File not found: "%"',[FileToCrypt]);
  if DestFile='' then
    dest := FileToCrypt+ENCRYPTED_FILEEXT else
    dest := DestFile;
  filetime := FileAgeToDateTime(FileToCrypt);
  try
    if IncludeSignFile then
      cert := TECCSignatureCertified.CreateFromFile(FileToCrypt,true) else
      cert := nil;
    try
      encrypted := Encrypt(plain,cert,filetime,Salt,SaltRounds,'hmac',100,Algo);
      if encrypted='' then
        result := false else
        result := FileFromString(encrypted,dest);
    finally
      cert.Free;
    end;
  finally
    FillZero(plain);
  end;
end;

{$ifndef NOVARIANTS}
function TECCCertificate.ToVariant(withBase64: boolean): variant;
begin
  result := _ObjFast(['Version',Version,'Serial',Serial,'Issuer',Issuer,
    'IssueDate',IssueDate,'ValidityStart',ValidityStart,'ValidityEnd',ValidityEnd,
    'AuthoritySerial',AuthoritySerial,'AuthorityIssuer',AuthorityIssuer,
    'IsSelfSigned',IsSelfSigned]);
  if withBase64 then
    TDocVariantData(result).AddValue('Base64',RawUTF8ToVariant(ToBase64));
end;
{$endif}


{ TECCCertificateSecret }

constructor TECCCertificateSecret.CreateNew(Authority: TECCCertificateSecret;
  const IssuerText: RawUTF8; ExpirationDays: integer; StartDate: TDateTime);
var priv: TECCPrivateKey;
    now: TECCDate;
    sha: TSHA256;
    hash: TSHA256Digest;
begin
  Create;
  if ecc_available then
  try
    now := NowECCDate;
    with fContent.Signed do begin
      IssueDate := now;
      if ExpirationDays>0 then begin
        if StartDate=0 then
          ValidityStart := now else
          ValidityStart := ECCDate(StartDate);
        ValidityEnd := ValidityStart+ExpirationDays;
      end;
      TAESPRNG.Fill(TAESBlock(Serial));
      if IssuerText='' then
        TAESPRNG.Fill(TAESBlock(Issuer)) else
        ECCIssuer(IssuerText,Issuer);
      if not ecc_make_key(PublicKey,fPrivateKey) then
        raise EECCException.CreateUTF8('%.CreateNew: ecc_make_key?',[self]);
      if Authority=nil then begin
        AuthoritySerial := Serial;
        AuthorityIssuer := Issuer;
        priv := fPrivateKey; // self-signing
      end else begin
        AuthoritySerial := Authority.fContent.Signed.Serial;
        AuthorityIssuer := Authority.fContent.Signed.Issuer;
        priv := Authority.fPrivateKey;
      end;
    end;
    sha.Full(@fContent.Signed,sizeof(TECCCertificateSigned),hash);
    if not ecdsa_sign(priv,hash,fContent.Signature) then
      raise EECCException.CreateUTF8('%.CreateNew: ecdsa_sign?',[self]);
    fContent.CRC := fnv32(0,@fContent,sizeof(fContent)-4);
  finally
    FillZero(THash256(priv));
  end;
end;

constructor TECCCertificateSecret.CreateFromSecureBinary(
  const Binary: RawByteString; const PassWord: RawUTF8;
  PBKDF2Rounds: integer; AES: TAESAbstractClass);
begin
  CreateFromSecureBinary(pointer(Binary),length(Binary),PassWord,PBKDF2Rounds,AES);
end;

constructor TECCCertificateSecret.CreateFromSecureBinary(Data: pointer;
  Len: integer; const PassWord: RawUTF8; PBKDF2Rounds: integer;
  AES: TAESAbstractClass);
begin
  Create;
  if not LoadFromSecureBinary(Data,Len,PassWord,PBKDF2Rounds,AES) then
    raise EECCException.CreateUTF8('Invalid %.CreateFromSecureBinary',[self]);
end;

constructor TECCCertificateSecret.CreateFromSecureFile(
  const FileName: TFileName; const PassWord: RawUTF8;
  PBKDF2Rounds: integer; AES: TAESAbstractClass);
begin
  Create;
  if not LoadFromSecureFile(FileName,PassWord,PBKDF2Rounds,AES) then
    raise EECCException.CreateUTF8('Invalid %.CreateFromSecureFile("%")',
      [self,FileName]);
end;

constructor TECCCertificateSecret.CreateFromSecureFile(
  const FolderName: TFileName; const Serial, PassWord: RawUTF8;
  PBKDF2Rounds: integer; AES: TAESAbstractClass);
begin
  CreateFromSecureFile(IncludeTrailingPathDelimiter(FolderName)+UTF8ToString(Serial),
    PassWord,PBKDF2Rounds,AES);
end;

destructor TECCCertificateSecret.Destroy;
begin
  FillZero(THash256(fPrivateKey));
  inherited Destroy;
end;

function TECCCertificateSecret.InternalLoad(const data: RawByteString): boolean;
begin
  result := fStoreOnlyPublicKey or TAESPRNG.AFUnsplit(data,fPrivateKey,sizeof(fPrivateKey));
end;

function TECCCertificateSecret.InternalSave: RawByteString;
begin
  if fStoreOnlyPublicKey then
    result := '' else
    result := TAESPRNG.Main.AFSplit(fPrivateKey,sizeof(fPrivateKey),fAFSplitStripes);
end;

function TECCCertificateSecret.HasSecret: boolean;
begin
  result := (self<>nil) and not IsZero(THash256(fPrivateKey));
end;

const
  PRIVKEY_MAGIC: array[0..15] of AnsiChar = 'SynEccPrivatKey'#26;
  PRIVKEY_SALTSIZE = 16; // 128-bit is enough, since it is transmitted as clear

function TECCCertificateSecret.SaveToSecureBinary(const PassWord: RawUTF8;
  AFStripes, PBKDF2Rounds: integer; AES: TAESAbstractClass; NoHeader: boolean): RawByteString;
var pksav: boolean;
    stsav, head: integer;
    st: TRawByteStringStream;
    salt, enc: RawByteString;
    aeskey: TAESKey;
    a: TAESAbstract;
    e: PAnsiChar absolute result;
begin
  result := '';
  if AES=nil then
    AES := TAESCFB;
  pksav := fStoreOnlyPublicKey;
  stsav := fAFSplitStripes;
  try
    fStoreOnlyPublicKey := false;
    fAFSplitStripes := AFStripes;
    salt := TAESPRNG.Fill(PRIVKEY_SALTSIZE);
    st := TRawByteStringStream.Create;
    try
      if SaveToStream(st) then begin
        PBKDF2_HMAC_SHA256(PassWord,salt,PBKDF2Rounds,aeskey);
        a := AES.Create(aeskey,256);
        try
          enc := a.EncryptPKCS7(st.DataString,true);
          // result := PRIVKEY_MAGIC+salt+enc; fails under FPC :(
          if NoHeader then
            head := 0 else
            head := sizeof(PRIVKEY_MAGIC);
          SetLength(result,head+PRIVKEY_SALTSIZE+length(enc));
          MoveFast(PRIVKEY_MAGIC,e[0],head);
          XorBlock16(pointer(salt),@e[head],@PRIVKEY_MAGIC);
          MoveFast(pointer(enc)^,e[head+PRIVKEY_SALTSIZE],length(enc));
        finally
          a.Free;
        end;
      end;
    finally
      FillcharFast(pointer(st.DataString)^,length(st.DataString),0);
      st.Free;
    end;
  finally
    fStoreOnlyPublicKey := pksav;
    fAFSplitStripes := stsav;
    FillZero(aeskey);
  end;
end;

function TECCCertificateSecret.SaveToSecureFileName(FileNumber: integer): TFileName;
var tmp: RawUTF8;
begin
  if self=nil then
    result := '' else begin
    if FileNumber>0 then
      FormatUTF8('%-%',[Serial,UInt3DigitsToShort(FileNumber)],tmp) else
      tmp := Serial;
    result := UTF8ToString(tmp)+ECCCERTIFICATESECRET_FILEEXT;
  end;
end;

function TECCCertificateSecret.SaveToSecureFile(const PassWord: RawUTF8;
  const DestFolder: TFileName; AFStripes, PBKDF2Rounds: integer;
  AES: TAESAbstractClass; NoHeader: boolean): boolean;
begin
  if (self=nil) or not DirectoryExists(DestFolder) then
    result := false else
    result := FileFromString(SaveToSecureBinary(PassWord,AFStripes,PBKDF2Rounds,AES,NoHeader),
      IncludeTrailingPathDelimiter(DestFolder)+SaveToSecureFileName);
end;

function TECCCertificateSecret.SaveToSecureFiles(const PassWord: RawUTF8;
  const DestFolder: TFileName; DestFileCount, AFStripes, PBKDF2Rounds: integer;
  AES: TAESAbstractClass; NoHeader: boolean): boolean;
var diff,one: RawByteString;
    head,index,pos,difflen,onechunk,onelen: integer;
    o: PAnsiChar absolute one;
    dest: TFileName;
begin
  if DestFileCount=1 then begin
    result := SaveToSecureFile(PassWord,DestFolder,AFStripes,PBKDF2Rounds,AES,NoHeader);
    exit;
  end;
  result := false;
  dest := IncludeTrailingPathDelimiter(DestFolder);
  if (self=nil) or (DestFileCount<=0) or not DirectoryExists(dest) then
    exit;
  if DestFileCount>255 then
    DestFileCount := 255;
  diff := SaveToSecureBinary(PassWord,AFStripes*DestFileCount,PBKDF2Rounds,AES,true);
  difflen := length(diff);
  onechunk := difflen div DestFileCount;
  if NoHeader then
    head := 0 else
    head := sizeof(PRIVKEY_MAGIC);
  pos := 0;
  for index := 1 to DestFileCount do begin
    if index<DestFileCount then
      onelen := onechunk else
      onelen := difflen-pos;
    SetLength(one,head+2+onelen);
    MoveFast(PRIVKEY_MAGIC,PByteArray(one)^[0],head);
    PByteArray(one)^[head] := index;
    PByteArray(one)^[head+1] := DestFileCount;
    MoveFast(PByteArray(diff)[pos],PByteArray(one)^[head+2],onelen);
    inc(pos,onelen);
    if not FileFromString(one,SaveToSecureFileName(index)) then
      exit;
  end;
  result := true;
end;

function TECCCertificateSecret.LoadFromSecureBinary(const Binary: RawByteString;
  const PassWord: RawUTF8; PBKDF2Rounds: integer; AES: TAESAbstractClass): boolean;
begin
  result := LoadFromSecureBinary(pointer(Binary),length(Binary),PassWord,PBKDF2Rounds,AES);
end;

function TECCCertificateSecret.LoadFromSecureBinary(Data: pointer; Len: integer;
  const PassWord: RawUTF8; PBKDF2Rounds: integer; AES: TAESAbstractClass): boolean;
var salt,decrypted: RawByteString;
    st: TRawByteStringStream;
    aeskey: TAESKey;
    head: integer;
    a: TAESAbstract;
begin
  result := false;
  dec(Len,PRIVKEY_SALTSIZE);
  if (self=nil) or (Len<=sizeof(PRIVKEY_MAGIC)+sizeof(TAESBlock)) then
    exit;
  if IsEqual(THash128(PRIVKEY_MAGIC),PHash128(Data)^) then begin
    dec(len,16);
    head := 16;
  end else
    head := 0; // was with NoHeader=true (e.g. SaveToSource)
  if Len and AESBlockMod<>0 then
    exit;
  SetString(salt,PAnsiChar(Data)+head,PRIVKEY_SALTSIZE);
  try
    XorBlock16(pointer(salt),@PRIVKEY_MAGIC);
    PBKDF2_HMAC_SHA256(PassWord,salt,PBKDF2Rounds,aeskey);
    if AES=nil then
      AES := TAESCFB;
    a := AES.Create(aeskey,256);
    try
      decrypted := a.DecryptPKCS7Buffer(PAnsiChar(Data)+head+PRIVKEY_SALTSIZE,Len,true);
      if decrypted='' then
        exit;
    finally
      a.Free;
    end;
    st := TRawByteStringStream.Create(decrypted);
    try
      if LoadFromStream(st) then
        result := not IsZero(THash256(fPrivateKey));
    finally
      st.Free;
    end;
  finally
    FillZero(decrypted);
    FillZero(aeskey);
  end;
end;

function TECCCertificateSecret.LoadFromSecureFile(
  const FileName: TFileName; const PassWord: RawUTF8;
  PBKDF2Rounds: integer; AES: TAESAbstractClass): boolean;
var FN: TFileName;
begin
  if ExtractFileExt(FileName)='' then
    FN := FileName+ECCCERTIFICATESECRET_FILEEXT else
    FN := FileName;
  result := LoadFromSecureBinary(StringFromFile(FN),PassWord,PBKDF2Rounds,AES);
end;

function TECCCertificateSecret.SaveToSource(const ConstName, Comment, PassWord: RawUTF8;
  IncludePassword: boolean; AFStripes, PBKDF2Rounds: integer; AES: TAESAbstractClass;
  IncludeRaw: boolean): RawUTF8;
var data: RawByteString;
    name,suffix: RawUTF8;
begin
  result := '';
  if (self=nil) or (Password='') then
    exit;
  data := SaveToSecureBinary(Password,AFStripes,PBKDF2Rounds,AES,true); // NoHeader=true
  if data='' then
    exit;
  if ConstName='' then
    name := '_'+copy(Serial,1,24) else
    name := UpperCase(ConstName);
  if IncludePassword then
    suffix := FormatUTF8('  %_PASS = %;'#13#10'  %_CYPH = ''%'';'#13#10,
      [name,QuotedStr(PassWord),name,TSynPersistentWithPassword.ComputePassword(PassWord)]);
  if ConstName<>'' then
    suffix := FormatUTF8('  %_SERIAL = ''%'';'#13#10'%',[name,Serial,suffix]);
  suffix := FormatUTF8('  %_ROUNDS = %;'#13#10'%',[name,PBKDF2Rounds,suffix]);
  if IncludeRaw then
    suffix := FormatUTF8('  %_RAW = ''%'';'#13#10'%',[name,
      SynCommons.BinToHex(@fPrivateKey,sizeof(fPrivateKey)),suffix]);
  result := BinToSource(name,Comment,pointer(data),length(data),16,suffix)
end;

function TECCCertificateSecret.SignToBase64(Data: pointer; Len: integer): RawUTF8;
begin
  if (Data=nil) or (Len<0) then
    result := '' else
    result := SignToBase64(SHA256Digest(Data,Len));
end;

function TECCCertificateSecret.SignToBase64(const Hash: THash256): RawUTF8;
var sign: TECCSignatureCertified;
begin
  result := '';
  if (self=nil) or IsZero(Hash) then
    exit;
  sign := TECCSignatureCertified.CreateNew(self,Hash);
  try
    result := sign.ToBase64;
  finally
    sign.Free;
  end;
end;

{$ifndef NOVARIANTS}
function TECCCertificateSecret.SignFile(const FileToSign: TFileName;
  const MetaNameValuePairs: array of const): TFileName;
var content: RawByteString;
    sign: RawUTF8;
    doc, meta: TDocVariantData;
    sha: TSHA256Digest;
begin
  content := StringFromFile(FileToSign);
  if content='' then
    raise EECCException.CreateUTF8('%.SignFile: "%" not found',[self,FileToSign]);
  sha := SHA256Digest(pointer(content),length(content));
  sign := SignToBase64(sha);
  meta.InitObject(['name',ExtractFileName(FileToSign),
    'date',DateTimeToIso8601Text(FileAgeToDateTime(FileToSign))],JSON_OPTIONS_FAST);
  meta.AddNameValuesToObject(MetaNameValuePairs);
  doc.InitObject([
    'meta',variant(meta), 'size',length(content), 'md5',MD5(content),
    'sha256',SHA256DigestToString(sha), 'sign',sign],JSON_OPTIONS_FAST);
  result := FileToSign+ECCCERTIFICATESIGN_FILEEXT;
  FileFromString(doc.ToJSON('','',jsonHumanReadable),result);
end;
{$endif}

function TECCCertificateSecret.Decrypt(
  const Encrypted: RawByteString; out Decrypted: RawByteString;
  Signature: PECCSignatureCertifiedContent; FileDateTime: PDateTime;
  const KDFSalt: RawUTF8; KDFRounds: integer;
  const MACSalt: RawUTF8; MACRounds: integer): TECCDecrypt;
var head: TECIESHeader;
    data: PAnsiChar;
    datalen: integer;
    secret,enc,dec: RawByteString;
    aeskey, mackey: THash256;
    hmac: THash256;
begin
  result := ecdCorrupted;
  datalen := length(Encrypted)-sizeof(TECIESHeader);
  if (datalen<=0) or not ECIESHeader(Encrypted,head) then
    exit;
  data := @PByteArray(Encrypted)[sizeof(TECIESHeader)];
  if CheckCRC and HasSecret then
  try
    if not IsEqual(THash128(head.recid),THash128(fContent.Signed.Serial)) then begin
      result := ecdInvalidSerial;
      exit;
    end;
    SetLength(secret,sizeof(TECCSecretKey));
    if not ecdh_shared_secret(head.rndpub,fPrivateKey,PECCSecretKey(secret)^) then
      exit;
    PBKDF2_HMAC_SHA256(secret,MACSalt,MACRounds,mackey,'hmac');
    HMAC_SHA256(@mackey,data,sizeof(mackey),datalen,hmac);
    result := ecdInvalidMAC;
    if not IsEqual(hmac,head.hmac) then
      exit;
    PBKDF2_HMAC_SHA256(secret,KDFSalt,KDFRounds,aeskey,'salt');
    SetString(enc,data,datalen);
    dec := ECIES_AES[head.Algo].SimpleEncrypt(
      enc,aeskey,ECIES_AESSIZE[head.Algo],false,true);
    if head.Algo in [low(ECIES_NOSYNLZ)..high(ECIES_NOSYNLZ)] then
      SynLZDecompress(pointer(dec),length(dec),Decrypted) else
      Decrypted := dec;
    result := ecdDecryptError;
    if cardinal(length(Decrypted))<>head.size then
       exit;
    if FileDateTime<>nil then
      if head.unixts = 0 then
        FileDateTime^ := 0 else
        FileDateTime^ := UnixTimeToDateTime(head.unixts);
    if (Signature<>nil) and ECCCheck(head.sign) then begin
      result := ecdDecryptedWithSignature;
      Signature^ := head.sign;
    end else
      result := ecdDecrypted;
  finally
    FillZero(aeskey);
    FillZero(mackey);
    FillZero(secret);
    if dec<>Decrypted then
      FillZero(dec);
  end else
    result := ecdNoPrivateKey;
end;

function TECCCertificateSecret.DecryptFile(const FileToDecrypt,
  DestFile: TFileName; const Salt: RawUTF8; SaltRounds: integer;
  Signature: PECCSignatureCertifiedContent): TECCDecrypt;
var content,plain: RawByteString;
    dest: TFileName;
    filetime: TDateTime;
begin
  content := StringFromFile(FileToDecrypt);
  result := ecdNoContent;
  if content<>'' then
  try
    result := ecdNoPrivateKey;
    if not CheckCRC then
      exit;
    if DestFile='' then
      dest := GetFileNameWithoutExt(FileToDecrypt) else
      dest := DestFile;
    result := Decrypt(content,plain,Signature,@filetime,Salt,SaltRounds);
    if result in ECC_VALIDDECRYPT then
      if not FileFromString(plain,dest,false,filetime) then
        result := ecdWriteFileError;
  finally
    FillZero(plain);
  end;
end;


{ TECCSignatureCertified }

constructor TECCSignatureCertified.Create;
begin
  inherited Create;
  fContent.Version := 1;
end;

constructor TECCSignatureCertified.CreateFrom(
  const binary: TECCSignatureCertifiedContent; NoException: boolean);
begin
  Create;
  if ECCCheck(binary) then
    fContent := binary else
    if not NoException then
      raise EECCException.CreateUTF8('Invalid %.CreateFrom',[self]);
end;

constructor TECCSignatureCertified.CreateFromBase64(const base64: RawUTF8;
  NoException: boolean);
begin
  Create;
  if not FromBase64(base64) then
    if not NoException then
      raise EECCException.CreateUTF8('Invalid %.CreateFromBase64',[self]);
end;

constructor TECCSignatureCertified.CreateFromFile(const signfilename: TFileName;
  NoException: boolean);
begin
  Create;
  if not FromFile(signfilename) then
    if not NoException then
      raise EECCException.CreateUTF8('Invalid %.CreateFromFile("%")',
        [self,signfilename]);
end;

constructor TECCSignatureCertified.CreateNew(
  Authority: TECCCertificateSecret; Data: pointer; Len: integer);
begin
  CreateNew(Authority,SHA256Digest(Data,Len));
end;

constructor TECCSignatureCertified.CreateNew(
  Authority: TECCCertificateSecret; const Hash: THash256);
begin
  Create;
  if not Authority.HasSecret then
    raise EECCException.CreateUTF8('%.CreateNew: secret=0 %',[self,Authority]);
  if IsZero(Hash) then
    raise EECCException.CreateUTF8('%.CreateNew(Hash=0)',[self]);
  fContent.Date := NowECCDate;
  fContent.AuthoritySerial := Authority.Content.Signed.Serial;
  fContent.AuthorityIssuer := Authority.Content.Signed.Issuer;
  if not ecdsa_sign(Authority.fPrivateKey,Hash,fContent.Signature) then
    raise EECCException.CreateUTF8('%.CreateNew: ecdsa_sign?',[self]);
end;

function TECCSignatureCertified.GetAuthorityIssuer: RawUTF8;
begin
  result := ECCText(fContent.AuthorityIssuer);
end;

function TECCSignatureCertified.GetAuthoritySerial: RawUTF8;
begin
  result := ECCText(fContent.AuthoritySerial);
end;

function TECCSignatureCertified.GetDate: RawUTF8;
begin
  result := ECCText(fContent.Date);
end;

function TECCSignatureCertified.FromBase64(const base64: RawUTF8): boolean;
begin
  result := (self<>nil) and
    Base64ToBin(pointer(base64),@fContent,length(base64),sizeof(fContent),false) and
    ECCCheck(fContent);
end;

function TECCSignatureCertified.FromFile(const signfilename: TFileName): boolean;
var json: RawUTF8;
begin
  if FileExists(signfilename+ECCCERTIFICATESIGN_FILEEXT) then
    json := StringFromFile(signfilename+ECCCERTIFICATESIGN_FILEEXT) else
    json := StringFromFile(signfilename);
  if json='' then
    result := false else
    result := FromBase64(JSONDecode(json,'sign',nil,true));
end;

function TECCSignatureCertified.ToBase64: RawUTF8;
begin
  result := BinToBase64(@fContent,sizeof(fContent));
end;

{$ifndef NOVARIANTS}
function TECCSignatureCertified.ToVariant: variant;
begin
  result := _ObjFast(['Version',Version,'Date',Date,
    'AuthoritySerial',AuthoritySerial,'AuthorityIssuer',AuthorityIssuer]);
end;
{$endif}

function TECCSignatureCertified.Check: boolean;
begin
  result := (self<>nil) and ECCCheck(fContent);
end;

function TECCSignatureCertified.Verify(Authority: TECCCertificate;
  const hash: THash256): TECCValidity;
begin
  if self=nil then
    result := ecvBadParameter else
  if not Authority.CheckCRC then
    result := ecvUnknownAuthority else
    result := ECCVerify(fContent,hash,Authority.fContent);
end;

function TECCSignatureCertified.Verify(Authority: TECCCertificate;
  Data: pointer; Len: integer): TECCValidity;
begin
  result := Verify(Authority,SHA256Digest(Data,Len));
end;

function TECCSignatureCertified.SaveToDERBinary: RawByteString;
const DER_SEQUENCE = $30;
      DER_INTEGER  = $02;
var RPrefix,SPrefix: integer;
    P: PByteArray;
begin
  if not Check then begin
    result := '';
    exit;
  end;
  RPrefix := fContent.Signature[0] shr 7; // DER_INTEGER are two's complement
  SPrefix := fContent.Signature[ECC_BYTES] shr 7;
  SetLength(result,RPrefix+SPrefix+(ECC_BYTES*2+6));
  P := pointer(result);
  P[0] := DER_SEQUENCE;
  P[1] := RPrefix+SPrefix+(ECC_BYTES*2+4);
  P[2] := DER_INTEGER;
  P[3] := ECC_BYTES+RPrefix;
  P[4] := $00; // prepend 0 for negative number (if RPrefix=1)
  inc(PByte(P),4+RPrefix);
  MoveFast(fContent.Signature[0],P[0],ECC_BYTES);
  inc(PByte(P),ECC_BYTES);
  P[0] := DER_INTEGER;
  P[1] := ECC_BYTES+SPrefix;
  P[2] := $00;
  MoveFast(fContent.Signature[ECC_BYTES],P[2+SPrefix],ECC_BYTES);
end;

function TECCSignatureCertified.SaveToDERFile(
  const FileName: TFileName): boolean;
begin
  if not Check then
    result := false else
    result := FileFromString(SaveToDERBinary, FileName);
end;


{$ifndef NOVARIANTS}

{ TECCSignatureCertifiedFile }

function TECCSignatureCertifiedFile.FromFile(const aFileName: TFileName): boolean;
var json: RawUTF8;
begin
  if SameText(ExtractFileExt(aFileName),ECCCERTIFICATESIGN_FILEEXT) then
    json := StringFromFile(aFileName) else
    json := StringFromFile(aFileName+ECCCERTIFICATESIGN_FILEEXT);
  result := FromFileJson(json);
end;

function TECCSignatureCertifiedFile.FromFileJson(const aFileContent: RawUTF8): boolean;
begin
  fLowLevelInfo.Clear;
  fLowLevelInfo.InitJSON(aFileContent);
  fSize := fLowLevelInfo.I['size'];
  fMetaData := fLowLevelInfo.GetValueOrEmpty('meta'); // Value[] makes GPF
  fMD5 := fLowLevelInfo.U['md5'];
  fSHA256 := fLowLevelInfo.U['sha256'];
  result := (fSize>0) and (_Safe(fMetaData)^.Kind<>dvArray) and
    MD5StringToDigest(fMD5,fMD5Digest) and
    SHA256StringToDigest(fSHA256,fSha256Digest) and
    FromBase64(fLowLevelInfo.U['sign']);
end;

{$endif NOVARIANTS}


{ TECCCertificateChain }

constructor TECCCertificateChain.CreateFromJson(const json: RawUTF8);
begin
  Create;
  if not LoadFromJson(json) then
    raise EECCException.CreateUTF8('Invalid %.CreateFromJson',[self]);
end;

constructor TECCCertificateChain.CreateFromArray(const values: TRawUTF8DynArray);
begin
  Create;
  if not LoadFromArray(values) then
    raise EECCException.CreateUTF8('Invalid %.CreateFromArray',[self]);
end;

destructor TECCCertificateChain.Destroy;
begin
  ObjArrayClear(fItems);
  inherited;
end;

function TECCCertificateChain.IsValid(cert: TECCCertificate): TECCValidity;
begin
  if (self=nil) or (cert=nil) then
    result := ecvBadParameter else
    result := IsValid(cert.Content);
end;

function TECCCertificateChain.IsValid(const content: TECCCertificateContent;
  ignoreDate: boolean): TECCValidity;
var auth: TECCCertificateContent;
    sha: TSHA256;
    hash: TSHA256Digest;
    crc: Int64;
begin
  if not ecc_available then begin
    result := ecvNotSupported;
    exit;
  end;
  result := ecvCorrupted;
  if not ECCCheck(content) then
    exit;
  if not ignoreDate then begin
    result := ecvInvalidDate;
    if not ECCCheckDate(content) then
      exit;
  end;
  if ECCSelfSigned(content) then
    result := ecvValidSelfSigned else
    result := ecvValidSigned;
  if fIsValidCached then begin
    crc := crc64c(@content,sizeof(content));
    fSafe.Lock;
    try
      if Int64ScanExists(pointer(fIsValidCache),fIsValidCacheCount,crc) then
        exit;
    finally
      fSafe.Unlock;
    end;
  end else
    crc := 0;
  if result=ecvValidSelfSigned then
    auth.Signed.PublicKey := content.Signed.PublicKey else
    if not GetBySerial(content.Signed.AuthoritySerial,auth) then begin
      result := ecvUnknownAuthority;
      exit;
    end else
    if not ECCCheckDate(auth) then begin
      result := ecvDeprecatedAuthority;
      exit;
    end;
  sha.Full(@content.Signed,sizeof(content.Signed),hash);
  if ecdsa_verify(auth.Signed.PublicKey,hash,content.Signature) then begin
    fSafe.Lock;
    try
      if fIsValidCached and (crc<>0) then
        AddInt64(fIsValidCache,fIsValidCacheCount,crc);
    finally
      fSafe.Unlock;
    end;
  end else
    result := ecvInvalidSignature;
end;

function TECCCertificateChain.IndexBySerial(const Serial: TECCCertificateID): integer;
var ser: THash128Rec absolute Serial;
begin
  if (self<>nil) and ((ser.Lo<>0) or (ser.Hi<>0)) then begin
    for result := 0 to length(fItems)-1 do
      with PHash128Rec(@fItems[result].Signed.Serial)^ do
        {$ifdef CPU64}
        if (ser.Lo=Lo) and (ser.Hi=Hi) then
        {$else}
        if (ser.i0=i0) and (ser.i1=i1) and (ser.i2=i2) and (ser.i3=i3) then
        {$endif}
          exit;
  end;
  result := -1;
end;

function TECCCertificateChain.GetBySerial(const Serial: TECCCertificateID): TECCCertificate;
var i: integer;
begin
  i := IndexBySerial(Serial);
  if i<0 then
    result := nil else
    result := fItems[i];
end;

function TECCCertificateChain.GetBySerial(const Serial: RawUTF8): TECCCertificate;
var id: TECCCertificateID;
begin
  if ECCID(Serial,id) then
    result := GetBySerial(id) else
    result := nil;
end;

function TECCCertificateChain.GetBySerial(const Serial: TECCCertificateID;
  out Content: TECCCertificateContent): boolean;
var cert: TECCCertificate;
begin
  fSafe.Lock;
  try
    cert := GetBySerial(Serial);
    if cert<>nil then begin
      Content := cert.Content;
      result := true;
    end else
      result := false;
  finally
    fSafe.UnLock;
  end;
end;

function TECCCertificateChain.GetBySerial(const Serial: TECCCertificateID;
  out PublicKey: TECCPublicKey): boolean;
var cert: TECCCertificate;
begin
  fSafe.Lock;
  try
    cert := GetBySerial(Serial);
    if cert<>nil then begin
      PublicKey := cert.Content.Signed.PublicKey;
      result := true;
    end else
      result := false;
  finally
    fSafe.UnLock;
  end;
end;

procedure TECCCertificateChain.SetIsValidCached(const Value: boolean);
begin
  if fIsValidCached=Value then
    exit;
  fSafe.Lock;
  try
    fIsValidCached := Value;
    if not Value then begin
      fIsValidCache := nil;
      fIsValidCacheCount := 0;
    end;
  finally
    fSafe.UnLock;
  end;
end;

function TECCCertificateChain.InternalAdd(cert: TECCCertificate;
  expected: TECCValidity): integer;
begin
  result := -1;
  if (self=nil) or (cert=nil) or
     (IsValid(cert.fContent,true)<>expected) then
    exit;
  fSafe.Lock;
  try
    if IndexBySerial(cert.Signed.Serial)<0 then
      result := ObjArrayAdd(fItems,cert);
  finally
    fSafe.UnLock;
  end;
end;

function TECCCertificateChain.Add(cert: TECCCertificate): integer;
begin
  result := InternalAdd(cert,ecvValidSigned);
end;

function TECCCertificateChain.AddSelfSigned(cert: TECCCertificate): integer;
begin
  result := InternalAdd(cert,ecvValidSelfSigned);
end;

procedure TECCCertificateChain.Clear;
begin
  fSafe.Lock;
  try
    ObjArrayClear(fItems);
    fIsValidCacheCount := 0;
    fIsValidCache := nil;
  finally
    fSafe.UnLock;
  end;
end;

function TECCCertificateChain.GetCount: integer;
begin
  if self=nil then
    result := 0 else
    result := length(fItems);
end;

function TECCCertificateChain.IsAuthorized(sign: TECCSignatureCertified): boolean;
begin
  if (self<>nil) and (sign<>nil) then
    result := IsAuthorized(sign.Content) else
    result := false;
end;

function TECCCertificateChain.IsAuthorized(
  const sign: TECCSignatureCertifiedContent): boolean;
var content: TECCCertificateContent;
begin
  result := GetBySerial(sign.AuthoritySerial, content) and
    IsEqual(THash128(content.Signed.AuthorityIssuer), THash128(sign.AuthorityIssuer));
end;

function TECCCertificateChain.IsAuthorized(const base64sign: RawUTF8): boolean;
var sign: TECCSignatureCertifiedContent;
begin
  if ECCSign(base64sign,sign) then
    result := IsAuthorized(sign) else
    result := false;
end;

function TECCCertificateChain.IsSigned(sign: TECCSignatureCertified;
  Data: pointer; Len: integer): TECCValidity;
var hash: TSHA256Digest;
begin
  if (self<>nil) and (sign<>nil) and (Data<>nil) and (Len>0) then begin
    hash := SHA256Digest(Data,Len);
    {$ifndef NOVARIANTS}
    if sign.InheritsFrom(TECCSignatureCertifiedFile) then
      with TECCSignatureCertifiedFile(sign) do
        if (Size<>Len) or not IsEqual(hash,Sha256Digest) or
           not IsEqual(MD5Buf(Data^,Len),MD5Digest) then begin
          result := ecvCorrupted;
          exit;
        end;
    {$endif}
    result := IsSigned(sign.Content,hash);
  end else
    result := ecvBadParameter;
end;

function TECCCertificateChain.IsSigned(sign: TECCSignatureCertified;
  const hash: THash256): TECCValidity;
begin
  if (self<>nil) and (sign<>nil) then
    result := IsSigned(sign.Content,hash) else
    result := ecvBadParameter;
end;

function TECCCertificateChain.IsSigned(const sign: TECCSignatureCertifiedContent;
  Data: pointer; Len: integer): TECCValidity;
begin
  if (Data=nil) or (Len<=0) then
    result := ecvBadParameter else
    result := IsSigned(sign,SHA256Digest(Data,Len));
end;

function TECCCertificateChain.IsSigned(const base64sign: RawUTF8;
  const hash: THash256): TECCValidity;
var sign: TECCSignatureCertifiedContent;
begin
  if ECCSign(base64sign,sign) then
    result := IsSigned(sign,hash) else
    result := ecvBadParameter;
end;

function TECCCertificateChain.IsSigned(const base64sign: RawUTF8;
  Data: pointer; Len: integer): TECCValidity;
var sign: TECCSignatureCertifiedContent;
begin
  if ECCSign(base64sign,sign) then
    result := IsSigned(sign,Data,Len) else
    result := ecvBadParameter;
end;

function TECCCertificateChain.IsSigned(const sign: TECCSignatureCertifiedContent;
  const hash: THash256): TECCValidity;
var auth: TECCCertificateContent;
begin
  if self=nil then
    result := ecvBadParameter else
  if not GetBySerial(sign.AuthoritySerial,auth) then
    result := ecvUnknownAuthority else
    result := ECCVerify(sign,hash,auth);
end;

function TECCCertificateChain.SaveToJson: RawUTF8;
begin
  result := JSONEncodeArrayUTF8(SaveToArray);
end;

function TECCCertificateChain.SaveToArray: TRawUTF8DynArray;
var i: integer;
begin
  fSafe.Lock;
  try
    SetLength(result,length(fItems));
    for i := 0 to high(result) do
      result[i] := fItems[i].PublicToBase64;
  finally
    fSafe.UnLock;
  end;
end;

function TECCCertificateChain.LoadFromJson(const json: RawUTF8): boolean;
var values: TRawUTF8DynArray;
    tmp: TSynTempBuffer; // private copy
begin
  tmp.Init(json);
  result := (DynArrayLoadJSON(values,tmp.buf,TypeInfo(TRawUTF8DynArray))<>nil) and
    LoadFromArray(values);
  tmp.Done;
end;

function TECCCertificateChain.LoadFromArray(const values: TRawUTF8DynArray): boolean;
var i: integer;
begin
  result := false;
  if self=nil then
    exit;
  fSafe.Lock;
  try
    Clear;
    SetLength(fItems,length(values));
    for i := 0 to high(values) do begin
      fItems[i] := TECCCertificate.Create;
      if not fItems[i].FromBase64(values[i]) then begin
        ObjArrayClear(fItems);
        exit;
      end;
    end;
  finally
    fSafe.UnLock;
  end;
  result := true;
end;

function TECCCertificateChain.ValidateItems: TECCCertificateObjArray;
var i: integer;
begin
  result := nil;
  if self=nil then
    exit;
  fSafe.Lock;
  try
    for i := 0 to high(fItems) do
      if not (IsValid(fItems[i]) in ECC_VALIDSIGN) then
        ObjArrayAdd(result,fItems[i]);
  finally
    fSafe.UnLock;
  end;
end;

{$ifndef NOVARIANTS} // uses TDocVariantData for JSON serialization

constructor TECCCertificateChain.CreateFromFile(const jsonfile: TFileName);
begin
  Create;
  if not LoadFromFile(jsonfile) then
    raise EECCException.CreateUTF8('Invalid %.CreateFromFile("%")',[self,jsonfile]);
end;

constructor TECCCertificateChain.CreateFromFiles(const files: array of TFileName);
var i: integer;
    auth: TECCCertificate;
begin
  Create;
  for i := 0 to high(files) do begin
    auth := TECCCertificate.Create;
    try
      if auth.FromFile(files[i]) then begin
        ObjArrayAdd(fItems,auth);
        auth := nil;
      end else
        raise EECCException.CreateUTF8('%.CreateFromFiles: invalid "%"',[self,files[i]]);
    finally
      auth.Free;
    end;
  end;
end;

function TECCCertificateChain.SaveToFileVariant: variant;
var pub64,items: TDocVariantData;
    i,n: integer;
begin
  fSafe.Lock;
  try
    n := length(fItems);
    pub64.InitFast(n,dvArray);
    items.InitFast(n,dvArray);
    for i := 0 to n-1 do begin
      pub64.AddItem(RawUTF8ToVariant(fItems[i].PublicToBase64));
      items.AddItem(fItems[i].ToVariant(false));
    end;
    result := _ObjFast(['PublicBase64',variant(pub64),'Items',variant(items)]);
  finally
    fSafe.UnLock;
  end;
end;

function TECCCertificateChain.SaveToFileContent: RawUTF8;
begin
  VariantSaveJSON(SaveToFileVariant,twJSONEscape,result);
end;

function TECCCertificateChain.LoadFromFileContent(const cajsoncontent: RawUTF8): boolean;
var doc: TDocVariantData;
    values: TRawUTF8DynArray;
begin
  result := false;
  if doc.InitJSON(cajsoncontent,JSON_OPTIONS_FAST) then begin
    doc.GetAsDocVariantSafe('PublicBase64')^.ToRawUTF8DynArray(values);
    result := LoadFromArray(values);
  end;
end;

function GetChainFileName(const jsonfile: TFileName): TFileName;
begin
  if ExtractFileExt(jsonfile)='' then
    result := jsonfile+ECCCERTIFICATES_FILEEXT else
    result := jsonfile;
end;

function TECCCertificateChain.SaveToFile(const jsonfile: TFileName): boolean;
var json: RawUTF8;
begin
  if (Count=0) or (jsonfile='') then
    result := false else begin
    json := SaveToFileContent;
    result := JSONBufferReformatToFile(pointer(json),GetChainFileName(jsonfile));
  end;
end;

function TECCCertificateChain.LoadFromFile(const jsonfile: TFileName): boolean;
var json: RawUTF8;
    fn: TFileName;
begin
  fn := GetChainFileName(jsonfile);
  json := StringFromFile(fn);
  if json='' then
    json := StringFromFile(ECCKeyFileFolder+fn);
  if json='' then
    result := false else
    result := LoadFromFileContent(json);
end;

{$endif NOVARIANTS}


{ TECDHEProtocol }

constructor TECDHEProtocol.Create(aAuth: TECDHEAuth; aPKI: TECCCertificateChain;
  aPrivate: TECCCertificateSecret);
var res: TECCValidity;
begin
  if not ecc_available then
    raise EECCException.CreateUTF8('%.Create but ECC not supported',[self]);
  if (aPKI<>nil) and (aPrivate<>nil) then begin
    res := aPKI.IsValid(aPrivate);
    if not (res in ECC_VALIDSIGN) then
      raise EECCException.CreateUTF8('%.Create failed: aPKI.IsValid(%)=%',
        [self,aPrivate.Serial,ToText(res)^]);
  end;
  inherited Create;
  fAlgo.auth := aAuth;
  fPKI := aPKI;
  fPrivate := aPrivate;
  fEFSalt := 'ecdhesalt';
  fMACSalt := 'ecdhemac';
end;

constructor TECDHEProtocol.CreateFrom(aAnother: TECDHEProtocol);
begin
  Create(aAnother.fAlgo.auth,aAnother.fPKI,aAnother.fPrivate);
  fEFSalt := aAnother.fEFSalt;
  fMACSalt := aAnother.fMACSalt;
end;

var
  _FromKeySetCA: TECCCertificateChain;
  _FromKeySetCARefCount: integer;

destructor TECDHEProtocol.Destroy;
begin
  if fAES[true]<>fAES[false] then
    fAES[true].Free; // occurs only for TAESCBC
  fAES[false].Free;
  FillZero(fkM[false]);
  FillZero(fkM[true]);
  if fPKI<>nil then
    if ownPKI in fOwned then
      fPKI.Free else
    if (fPKI=_FromKeySetCA) and (_FromKeySetCARefCount>0) then
      dec(_FromKeySetCARefCount);
  if ownPrivate in fOwned then
    fPrivate.Free;
  inherited Destroy;
end;

class procedure TECDHEProtocol.FromKeySetCA(aPKI: TECCCertificateChain);
begin
  if _FromKeySetCA<>nil then
    if _FromKeySetCARefCount>0 then
      raise EECCException.CreateUTF8('%.FromKeySetCA: % is still used by % instance(s)',
        [self,_FromKeySetCA,_FromKeySetCARefCount]) else
    _FromKeySetCA.Free;
  _FromKeySetCA := aPKI;
end;

class function TECDHEProtocol.FromKey(const aKey: RawUTF8; aServer: boolean): TECDHEProtocol;
const CL: array[boolean] of TECDHEProtocolClass = (
  TECDHEProtocolServer, TECDHEProtocolClient);
var sw: TSynNameValue;
    pw,c: RawUTF8;
    fn: TFileName;
    algo: TECDHEAlgo;
    ca: TECCCertificateChain;
    chain: TRawUTF8DynArray;
    priv: TECCCertificateSecret;
    i,pr: integer;
begin
  result := nil;
  if not IdemPChar(pointer(aKey),'A=') then
    exit;
  // a=mutual;k=hmacsha256;e=aescrc128;m=duringef;p=34a2;pw=password;pr=60000;ca=..
  sw.InitFromCSV(pointer(aKey),'=',';');
  if not sw.ValueEnum('a',TypeInfo(TECDHEAuth),algo.auth) then
    exit; // mandatory parameter
  sw.ValueEnum('k',TypeInfo(TECDHEKDF),algo.kdf);
  sw.ValueEnum('e',TypeInfo(TECDHEEF),algo.ef);
  sw.ValueEnum('m',TypeInfo(TECDHEEF),algo.mac);
  // compute ca: TECCCertificateChain
  ca := nil;
  c := sw.Str['ca'];
  if c<>'' then begin
    ca := TECCCertificateChain.Create;
    {$ifndef NOVARIANTS}
    fn := UTF8ToString(c);
    if not ca.LoadFromFile(fn) then
    {$endif NOVARIANTS} begin
      CSVToRawUTF8DynArray(c,',','',chain);
      for i := 0 to high(chain) do
        chain[i] := UnQuoteSQLString(chain[i]);
      if ca.LoadFromArray(chain) then
        ca.IsValidCached := true else // for faster Clone process
        FreeAndnil(ca);
    end;
  end;
  if (ca=nil) and (_FromKeySetCA<>nil) then begin
    ca := _FromKeySetCA;
    inc(_FromKeySetCARefCount);
  end;
  // compute priv: TECCCertificateSecret
  priv := nil;
  fn := UTF8ToString(sw.Str['p']);
  pw := sw.Str['pw'];
  pr := sw.ValueInt('pr',60000); // DEFAULT_ECCROUNDS may change
  if (fn<>'') and (pw<>'') and ECCKeyFileFind(fn,true) then
    priv := TECCCertificateSecret.CreateFromSecureFile(fn,pw,pr);
  result := CL[aServer].Create(algo.auth,ca,priv);
  result.KDF := algo.kdf;
  result.EF := algo.ef;
  result.MAC := algo.mac;
  if (ca<>nil) and (ca<>_FromKeySetCA) then
    include(result.fOwned,ownPKI);
  if priv<>nil then
    include(result.fOwned,ownPrivate);
end;

class function TECDHEProtocol.FromKeyCompute(const privkey,privpassword: RawUTF8;
  privrounds: integer; const pki: RawUTF8; auth: TECDHEAuth; kdf: TECDHEKDF;
  ef: TECDHEEF; mac: TECDHEMAC; customkey: cardinal): RawUTF8;
begin
  FormatUTF8('a=%',[ord(auth)],result);
  if kdf<>low(kdf) then
    result := result+';k='+TrimLeftLowerCaseShort(ToText(kdf));
  if ef<>low(ef) then
    result := result+';e='+TrimLeftLowerCaseShort(ToText(ef));
  if mac<>low(mac) then
    result := result+';m='+TrimLeftLowerCaseShort(ToText(mac));
  result := lowercase(result);
  if pki<>'' then
    result := result+';ca='+pki;
  if privkey<>'' then begin
    result := FormatUTF8('%;p=%;pw=%',[result,privkey,privpassword]);
    if privrounds<>60000 then // DEFAULT_ECCROUNDS may change
      result := FormatUTF8('%;pr=%',[result,privrounds]);
  end;
  result := TSynPersistentWithPassword.ComputePassword(result,customkey);
end;

const
  ED: array[boolean] of string[7] = ('Decrypt','Encrypt');

procedure TECDHEProtocol.SetKey(aEncrypt: boolean);
begin
  if fAES[aEncrypt]=nil then
    raise EECCException.CreateUTF8('%.% with no handshake',[self,ED[aEncrypt]]);
  fAES[aEncrypt].IV := PHash128(@fkM[aEncrypt])^; // kM is a CTR -> IV unicity
  if fAlgo.mac=macDuringEF then
    if not fAES[aEncrypt].MACSetNonce(fkM[aEncrypt]) then
      raise EECCException.CreateUTF8('%.%: macDuringEF not available in %/%',
        [self,ED[aEncrypt],ToText(fAlgo.ef)^,fAES[aEncrypt]]);
end;

procedure TECDHEProtocol.ComputeMAC(aEncrypt: boolean;
  aEncrypted: pointer; aLen: integer; out aMAC: THash256);
var i,c: cardinal;
begin
  case fAlgo.mac of
    macDuringEF:
      if not fAES[aEncrypt].MACGetLast(aMac) then // computed during EF process
        raise EECCException.CreateUTF8('%.%: macDuringEF not available in %/%',
          [self,ED[aEncrypt],ToText(fAlgo.ef)^,fAES[aEncrypt]]);
    macHmacCrc256c:
      HMAC_CRC256C(@fkM[aEncrypt],aEncrypted,sizeof(THash256),aLen,aMAC);
    macHmacSha256:
      HMAC_SHA256(@fkM[aEncrypt],aEncrypted,sizeof(THash256),aLen,aMAC);
    macHmacCrc32c: begin
      c := HMAC_CRC32C(@fkM[aEncrypt],aEncrypted,sizeof(THash256),aLen);
      for i := 0 to 7 do
        PCardinalArray(@aMac)^[i] := c; // naive 256-bit diffusion
    end;
    macNone:
      crc256c(@fkM[aEncrypt],sizeof(THash256),aMAC); // replay attack only
    else
      raise EECCException.CreateUTF8('%.%: ComputeMAC %?',
        [self,ED[aEncrypt],ToText(fAlgo.mac)^]);
  end;
  inc(PInt64(@fkM[aEncrypt])^); // 64-bit sequence number against replay attacks
end;

procedure TECDHEProtocol.Encrypt(const aPlain: RawByteString;
  out aEncrypted: RawByteString);
var len: integer;
    mac: PHash256;
begin
  fSafe.Lock;
  try
    SetKey(true);
    len := fAES[true].EncryptPKCS7Length(length(aPlain),false);
    SetString(aEncrypted,nil,len+sizeof(THash256));
    fAES[true].EncryptPKCS7Buffer(Pointer(aPlain),pointer(aEncrypted),
      length(aPlain),len,false);
    mac := @PByteArray(aEncrypted)[len];
    ComputeMac(true,pointer(aEncrypted),len,mac^);
  finally
    fSafe.UnLock;
  end;
end;

function TECDHEProtocol.Decrypt(const aEncrypted: RawByteString;
  out aPlain: RawByteString): TProtocolResult;
var P: PAnsiChar absolute aEncrypted;
    len: integer;
    mac: THash256;
begin
  result := sprInvalidMAC;
  len := length(aEncrypted)-sizeof(THash256);
  if len<=0 then
    exit;
  fSafe.Lock;
  try
    SetKey(false);
    aPlain := fAES[false].DecryptPKCS7Buffer(P,len,false);
    if aPlain='' then begin
      inc(PInt64(@fkM[false])^); // don't compute MAC, but increase sequence
      exit;
    end;
    ComputeMac(false,P,len,mac);
    if IsEqual(mac,PHash256(P+len)^) then
      result := sprSuccess;
  finally
    fSafe.Unlock;
  end;
end;

function TECDHEProtocol.CheckError(const aEncrypted: RawByteString): TProtocolResult;
begin
  if fAlgo.mac<>macDuringEF then begin
    result := sprUnsupported;
    exit;
  end;
  fSafe.Lock;
  try
    SetKey(false);
    if fAES[false].MACCheckError(pointer(aEncrypted),length(aEncrypted)) then
      result := sprSuccess else
      result := sprInvalidMAC;
  finally
    fSafe.Unlock;
  end;
end;

procedure TECDHEProtocol.SharedSecret(sA,sB: PHash256);
const
  AES_CLASS: array[TECDHEEF] of TAESAbstractClass = (
  // efAesCrc, efAesCfb, efAesOfb, efAesCtr, efAesCbc
    TAESCFBCRC, TAESCFB, TAESOFB, TAESCTR, TAESCBC,
    TAESCFBCRC, TAESCFB, TAESOFB, TAESCTR, TAESCBC);
  AES_BITS: array[TECDHEEF] of integer = (
    128, 128, 128, 128, 128, 256, 256, 256, 256, 256);
var secret: THash256;
  procedure ComputeSecret(const salt: RawByteString);
  var hmac: THMAC_SHA256;
  begin
    hmac.Init(pointer(salt),length(salt));
    if fAlgo.auth<>authServer then
      hmac.Update(sA^);
    if fAlgo.auth<>authClient then
      hmac.Update(sB^);
    hmac.Update(fRndA);
    hmac.Update(fRndB);
    hmac.Done(secret);
  end;
begin
  if fAES[false]<>nil then
    raise EECCException.CreateUTF8('%.SharedSecret already called',[self]);
  if fAlgo.kdf<>kdfHmacSha256 then
    raise EECCException.CreateUTF8('%.SharedSecret %?',[self,ToText(fAlgo.kdf)^]);
  try
    ComputeSecret(fEFSalt);
    fAES[false] := AES_CLASS[fAlgo.ef].Create(secret,AES_BITS[fAlgo.ef]);
    fAES[true] := fAES[false].CloneEncryptDecrypt;
    ComputeSecret(fMACSalt);
    fkM[false] := secret; // first 128-bit also used as AES IV
    fkM[true] := secret;
  finally
    FillZero(secret);
  end;
end;

function TECDHEProtocol.Verify(frame: PByteArray; len: integer;
  const QC: TECCCertificateContent; out res: TProtocolResult): boolean;
var hash: TSHA256Digest;
    sha: TSHA256;
begin
  result := false;
  res := sprInvalidCertificate;
  if fPKI<>nil then begin
    fCertificateValidity := fPKI.IsValid(QC);
    if not (fCertificateValidity in ECC_VALIDSIGN) then
      exit;
  end else
    if not ECCCheck(QC) then
      exit;
  dec(len,sizeof(TECCSignature)); // Sign at the latest position
  sha.Full(frame,len,hash);
  res := sprInvalidSignature;
  if not ecdsa_verify(QC.Signed.PublicKey,hash,PECCSignature(@frame[len])^) then
    exit;
  res := sprSuccess;
  result := true;
end;

procedure TECDHEProtocol.Sign(frame: PByteArray; len: integer;
  out QC: TECCCertificateContent);
var hash: TSHA256Digest;
    sha: TSHA256;
begin
  QC := fPrivate.fContent;
  dec(len,sizeof(TECCSignature)); // Sign at the latest position
  sha.Full(frame,len,hash);
  if not ecdsa_sign(fPrivate.fPrivateKey,hash,PECCSignature(@frame[len])^) then
    raise EECCException.CreateUTF8('%.Sign: ecdsa_sign',[self]);
end;

function TECDHEProtocol.Clone: IProtocol;
begin
  result := TECDHEProtocolClass(ClassType).CreateFrom(self);
end;


{ TECDHEProtocolClient }

constructor TECDHEProtocolClient.Create(aAuth: TECDHEAuth;
  aPKI: TECCCertificateChain; aPrivate: TECCCertificateSecret);
begin
  if (aAuth<>authServer) and not aPrivate.CheckCRC then
    raise EECCException.CreateUTF8('%.Create: need valid Private Key for %',
      [self,ToText(aAuth)^]) else
  inherited;
end;

procedure TECDHEProtocolClient.ComputeHandshake(out aClient: TECDHEFrameClient);
begin
  if fAES[false]<>nil then
    raise EECCException.CreateUTF8('%.ComputeHandshake already called',[self]);
  FillCharFast(aClient,sizeof(aClient),0);
  aClient.algo := fAlgo;
  TAESPRNG.Main.FillRandom(fRndA);
  aClient.RndA := fRndA;
  if fAlgo.auth<>authClient then
    if not ecc_make_key(aClient.QE,fdE) then
      raise EECCException.CreateUTF8('%.ComputeHandshake: ecc_make_key?',[self]);
  if fAlgo.auth<>authServer then
    Sign(@aClient,sizeof(aClient),aClient.QCA);
end;

function TECDHEProtocolClient.ValidateHandshake(const aServer: TECDHEFrameServer): TProtocolResult;
var sA,sB: THash256;
begin
  result := sprUnexpectedAlgorithm;
  if cardinal(aServer.algo)<>cardinal(fAlgo) then
    exit;
  result := sprBadRequest;
  if IsZero(fRndA) or not IsEqual(aServer.RndA,fRndA) or
     IsZero(aServer.RndB) or IsEqual(aServer.RndA,aServer.RndB) then
    exit;
  fRndB := aServer.RndB;
  if fAlgo.auth<>authClient then
    if not Verify(@aServer,sizeof(aServer),aServer.QCB,result) then
      exit;
  try
    result := sprInvalidEphemeralKey;
    if fAlgo.auth<>authServer then
      if not ecdh_shared_secret(aServer.QF,fPrivate.fPrivateKey,sA) then
        exit;
    result := sprInvalidPublicKey;
    if fAlgo.auth<>authClient then
      if not ecdh_shared_secret(aServer.QCB.Signed.PublicKey,fdE,sB) then
        exit;
    SharedSecret(@sA,@sB);
  finally
    FillZero(sA);
    FillZero(sB);
    FillZero(THash256(fdE));
  end;
  result := sprSuccess;
end;

function TECDHEProtocolClient.ProcessHandshake(const MsgIn: RawUTF8;
  out MsgOut: RawUTF8): TProtocolResult;
var out1: TECDHEFrameClient;
    in2: TECDHEFrameServer;
begin
  if MsgIn='' then begin
    ComputeHandshake(out1);
    MsgOut := BinToBase64(@out1,SizeOf(out1));
    result := sprSuccess;
  end else
    if Base64ToBin(Pointer(MsgIn),@in2,length(MsgIn),sizeof(in2),false) then
      result := ValidateHandshake(in2) else
      result := sprBadRequest;
end;


{ TECDHEProtocolServer }

constructor TECDHEProtocolServer.Create(aAuth: TECDHEAuth;
  aPKI: TECCCertificateChain; aPrivate: TECCCertificateSecret);
begin
  if (aAuth<>authClient) and not aPrivate.CheckCRC then
    raise EECCException.CreateUTF8('%.Create: need valid Private Key for %',
      [self,ToText(aAuth)^]);
  inherited;
  include(fAuthorized,aAuth); // conservative default
end;

constructor TECDHEProtocolServer.CreateFrom(aAnother: TECDHEProtocol);
begin
  inherited CreateFrom(aAnother);
  fAuthorized := (aAnother as TECDHEProtocolServer).fAuthorized;
end;

function TECDHEProtocolServer.ComputeHandshake(const aClient: TECDHEFrameClient;
  out aServer: TECDHEFrameServer): TProtocolResult;
var dF: TECCPrivateKey;
    sA,sB: THash256;
begin
  result := sprUnexpectedAlgorithm;
  if cardinal(aClient.algo)<>cardinal(fAlgo) then begin
    if not (aClient.algo.auth in fAuthorized) or
       (aClient.algo.kdf<>fAlgo.kdf) or (aClient.algo.ef<>fAlgo.ef) or
       (aClient.algo.mac<>fAlgo.mac) then
      exit;
    if (aClient.algo.auth<>authClient) and not fPrivate.CheckCRC then
      exit;
    fAlgo.auth := aClient.algo.auth; // client forced another mode
  end;
  result := sprBadRequest;
  if IsZero(aClient.RndA) then
    exit;
  fRndA := aClient.RndA;
  if fAlgo.auth<>authServer then
    if not Verify(@aClient,sizeof(aClient),aClient.QCA,result) then
      exit;
  FillCharFast(aServer,sizeof(aServer),0);
  aServer.algo := fAlgo;
  aServer.RndA := fRndA;
  TAESPRNG.Main.FillRandom(fRndB);
  aServer.RndB := fRndB;
  if fAlgo.auth<>authServer then
    if not ecc_make_key(aServer.QF,dF) then
      raise EECCException.CreateUTF8('%.ComputeHandshake: ecc_make_key?',[self]);
  try
    result := sprInvalidPublicKey;
    if fAlgo.auth<>authServer then
      if not ecdh_shared_secret(aClient.QCA.Signed.PublicKey,dF,sA) then
        exit;
    result := sprInvalidEphemeralKey;
    if fAlgo.auth<>authClient then
      if not ecdh_shared_secret(aClient.QE,fPrivate.fPrivateKey,sB) then
        exit;
    SharedSecret(@sA,@sB);
  finally
    FillZero(sA);
    FillZero(sB);
    FillZero(THash256(dF));
  end;
  if fAlgo.auth<>authClient then
    Sign(@aServer,sizeof(aServer),aServer.QCB);
  result := sprSuccess;
end;

function TECDHEProtocolServer.ProcessHandshake(const MsgIn: RawUTF8;
  out MsgOut: RawUTF8): TProtocolResult;
var in1: TECDHEFrameClient;
    out1: TECDHEFrameServer;
begin
  if Base64ToBin(Pointer(MsgIn),@in1,length(MsgIn),sizeof(in1),false) then begin
    result := ComputeHandshake(in1,out1);
    MsgOut := BinToBase64(@out1,SizeOf(out1));
  end else
    result := sprBadRequest;
end;


{$ifndef NOVARIANTS}

{ TJWTES256 }

constructor TJWTES256.Create(aCertificate: TECCCertificate;
  aClaims: TJWTClaims; const aAudience: array of RawUTF8;
  aExpirationMinutes: integer; aIDIdentifier: TSynUniqueIdentifierProcess;
  aIDObfuscationKey: RawUTF8);
begin
  if not aCertificate.CheckCRC then
    raise EJWTException.CreateUTF8('%.Create(aCertificate?)',[self]);
  inherited Create('ES256',aClaims,aAudience,aExpirationMinutes,
    aIDIdentifier,aIDObfuscationKey);
  fCertificate := aCertificate;
end;

destructor TJWTES256.Destroy;
begin
  if fOwnCertificate then
    fCertificate.Free;
  inherited;
end;

procedure TJWTES256.CheckSignature(var JWT: TJWTContent;
  const payload64: RawUTF8; const signature: RawByteString);
var sha: TSHA256;
    hash: TSHA256Digest;
begin
  JWT.result := jwtInvalidSignature;
  if length(signature)<>sizeof(TECCSignature) then
    exit;
  sha.Full(pointer(payload64),length(payload64),hash);
  if ecdsa_verify(fCertificate.fContent.Signed.PublicKey,hash,PECCSignature(signature)^) then
    JWT.result := jwtValid;
end;

function TJWTES256.ComputeSignature(const payload64: RawUTF8): RawUTF8;
var sha: TSHA256;
    hash: TSHA256Digest;
    sign: TECCSignature;
begin
  if not fCertificate.InheritsFrom(TECCCertificateSecret) or
     not TECCCertificateSecret(fCertificate).HasSecret then
    raise EECCException.CreateUTF8('%.ComputeSignature expects % (%) to hold '+
      'a private key',[self,fCertificate,fCertificate.Serial]);
  sha.Full(pointer(payload64),length(payload64),hash);
  if not ecdsa_sign(TECCCertificateSecret(fCertificate).fPrivateKey,hash,sign) then
    raise EECCException.CreateUTF8('%.ComputeSignature: ecdsa_sign failed',[self]);
  result := BinToBase64URI(@sign,sizeof(sign));
end;

{$endif NOVARIANTS}

initialization
  assert(sizeof(TECCCertificateContent)=173); // on all platforms and compilers
  assert(sizeof(TECDHEFrameClient)=290);
  assert(sizeof(TECDHEFrameServer)=306);
  {$ifdef ECC_32ASM}
  pointer(@ecc_make_key) := pointer(@_ecc_make_key);
  pointer(@ecdh_shared_secret) := pointer(@_ecdh_shared_secret);
  pointer(@ecdsa_sign) := pointer(@_ecdsa_sign);
  pointer(@ecdsa_verify) := pointer(@_ecdsa_verify);
  {$endif ECC_32ASM}
end.

