#ifndef __HOMEKITPAIRPROTOCOL_h__
#define __HOMEKITPAIRPROTOCOL_h__

#include "Common.h"
#include "HTTPUtils.h"
#include "MICODefine.h"
#include "MICOSRPServer.h"


typedef enum
{
    eState_M1_VerifyStartRequest      = 1,
    eState_M2_VerifyStartRespond      = 2,
    eState_M3_VerifyFinishRequest     = 3,
    eState_M4_VerifyFinishRespond     = 4,
} HAPairVerifyState_t;

const char * hkdfSetupSalt  =        "Pair-Setup-Salt";
const char * hkdfVerifySalt =        "Pair-Verify-Salt";
const char * hkdfC2AKeySalt =        "Control-Salt";
const char * hkdfA2CKeySalt =        "Control-Salt";

const char * hkdfSetupInfo =        "Pair-Setup-Encryption-Key";
const char * hkdfVerifyInfo =       "Pair-Verify-Encryption-Key";
const char * hkdfC2AInfo =          "Control-Write-Info";
const char * hkdfA2CInfo =          "Control-Read-Info";

const char * AEAD_Nonce_Setup05 =   "PS-Msg05";
const char * AEAD_Nonce_Setup06 =   "PS-Msg06";
const char * AEAD_Nonce_Verify02 =  "PV-Msg02";
const char * AEAD_Nonce_Verify03 =  "PV-Msg03";

const char *stateDescription[7] = {"", "kTLVType_State = M1", "kTLVType_State = M2", "kTLVType_State = M3",
    "kTLVType_State = M4", "kTLVType_State = M5", "kTLVType_State = M6"};

const char *methodDescription[6] = {"Pair state ", "PIN-based pair-setup", "", "MFi+PIN-based pair-setup"
    "", "Pair-verify"};

/*Pair setup info*/
typedef struct _pairInfo_t {
  char              *SRPUser;
  srp_server_t      *SRPServer;
  uint8_t           *SRPControllerPublicKey;
  ssize_t           SRPControllerPublicKeyLen;
  uint8_t           *SRPControllerProof;
  ssize_t           SRPControllerProofLen;
  uint8_t           *HKDF_Key;
  bool              pairListFull;
} pairInfo_t;


/*Pair verify info*/
typedef struct _pairVerifyInfo_t {
  bool                      verifySuccess;
  int                       haPairVerifyState;
  uint8_t                   *pControllerLTPK;
  uint8_t                   *pControllerCurve25519PK;
  uint8_t                   *pAccessoryCurve25519PK;
  uint8_t                   *pAccessoryCurve25519SK;
  uint8_t                   *pSharedSecret;
  uint8_t                   *pHKDFKey;
  uint8_t                   *A2CKey;
  uint8_t                   *C2AKey;
} pairVerifyInfo_t;

void HKSetPassword (char * password);

void HKCleanPairSetupInfo(pairInfo_t **info, mico_Context_t * const inContext);

pairVerifyInfo_t* HKCreatePairVerifyInfo(void);

void HKCleanPairVerifyInfo(pairVerifyInfo_t **verifyInfo);

OSStatus HKPairSetupEngine( int inFd, HTTPHeader_t* inHeader, pairInfo_t** inInfo, mico_Context_t * const inContext );

OSStatus HKPairVerifyEngine( int inFd, HTTPHeader_t* inHeader, pairVerifyInfo_t* inInfo, mico_Context_t * const inContext );

#endif

