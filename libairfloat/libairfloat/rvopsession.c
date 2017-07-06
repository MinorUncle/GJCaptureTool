//
//  rvopsession.c
//  AirFloat
//
//  Copyright (c) 2013, Kristian Trenskow All rights reserved.
//
//  Redistribution and use in source and binary forms, with or
//  without modification, are permitted provided that the following
//  conditions are met:
//
//  Redistributions of source code must retain the above copyright
//  notice, this list of conditions and the following disclaimer.
//  Redistributions in binary form must reproduce the above
//  copyright notice, this list of conditions and the following
//  disclaimer in the documentation and/or other materials provided
//  with the distribution. THIS SOFTWARE IS PROVIDED BY THE
//  COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
//  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
//  PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER
//  OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
//  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
//  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
//  OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
//  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
//  STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
//  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <assert.h>
#include <math.h>

#include <netinet/in.h>

#include "log.h"
#include "mutex.h"
#include "base64.h"
#include "hex.h"
#include "settings.h"
#include "hardware.h"

#include "settings.h"

#include "parameters.h"
#include "dmap.h"

#include "webtools.h"
#include "webserverconnection.h"

#include "dacpclient.h"

#include "crypt.h"
#include "decoder.h"

#include "audioqueue.h"
#include "audiooutput.h"
#include "rvopserver.h"
#include "rtprecorder.h"

#include "rvopsession.h"

#include "HomeKitTLV.h"
#include "TLVUtils.h"
#include "HomeKitPairProtocol.h"
#define MAX(x,y) (x > y ? x : y)


void rvop_server_session_ended(rvop_server_p rs, struct rvop_session_t* session);

struct rvop_rtp_session_t {
    audio_queue_p queue;
    rtp_recorder_p recorder;
    uint32_t session_id;
};

struct rvop_session_t {
    mutex_p mutex;
    bool is_running;
    rvop_server_p server;
    char* password;
    bool ignore_source_volume;
    web_server_connection_p rvop_connection;
    char authentication_digest_nonce[33];
    dacp_client_p dacp_client;
    char* user_agent;
    crypt_aes_p crypt_aes;
    decoder_p decoder;
    struct rvop_rtp_session_t* rtp_session;
    uint32_t rtp_last_session_id;
    struct {
        rvop_session_client_initiated_callback initiated;
        rvop_session_client_started_recording_callback started_recording;
        rvop_session_client_updated_track_info_callback updated_track_info;
        rvop_session_client_updated_track_position_callback updated_track_position;
        rvop_session_client_updated_artwork_callback updated_artwork;
        rvop_session_client_updated_volume_callback updated_volume;
        rvop_session_client_ended_recording_callback ended_recording;
        rvop_session_ended_callback ended;
        struct {
            void* initiated;
            void* started_recording;
            void* updated_track_info;
            void* updated_track_position;
            void* updated_artwork;
            void* updated_volume;
            void* ended_recording;
            void* ended;
        } ctx;
    } callbacks;
    
    unsigned int start_rtp_timestamp;
    double total_length;
};

void recorder_updated_track_position_callback(rtp_recorder_p rr, unsigned int curr, void* ctx) {
    struct rvop_session_t* rs = (struct rvop_session_t*)ctx;
    struct decoder_output_format_t output_format = decoder_get_output_format(rs->decoder);
    
    double srate = (double)output_format.sample_rate;
    if (srate == 0.0) {
        srate = 44100;
    }
    double position = (double)(curr - rs->start_rtp_timestamp) / srate;
    if (rs->callbacks.updated_track_position != NULL && (rs->total_length == 0 || position < rs->total_length)) {
        rs->callbacks.updated_track_position(rs, position, rs->total_length, rs->callbacks.ctx.updated_track_position);
    }
}

bool _rvop_session_check_authentication(struct rvop_session_t* rs, const char* method, const char* uri, const char* authentication_parameter) {
    
    assert(method != NULL && uri != NULL);
    
    bool ret = (rs->password == NULL);
    
    if (ret == false) {
        
        if (authentication_parameter != NULL) {
            
            const char* param_begin = strstr(authentication_parameter, " ") + 1;
            if (param_begin) {
                
                parameters_p parameters = parameters_create(param_begin, strlen(param_begin), parameters_type_http_authentication);
                
                const char* nonce = parameters_value_for_key(parameters, "nonce");
                const char* response = parameters_value_for_key(parameters, "response");
                
                char w_response[strlen(response) + 1];
                strcpy(w_response, response);
                
                // Check if nonce is correct
                if (nonce != NULL && strlen(nonce) == 32 && strcmp(nonce, rs->authentication_digest_nonce) == 0) {
                    
                    const char* username = parameters_value_for_key(parameters, "username");
                    const char* realm =  parameters_value_for_key(parameters, "realm");
                    size_t pw_len = strlen(rs->password);
                    
                    char a1pre[strlen(username) + strlen(realm) + pw_len + 3];
                    sprintf(a1pre, "%s:%s:%s", username, realm, rs->password);
                    
                    char a2pre[strlen(method) + strlen(uri) + 2];
                    sprintf(a2pre, "%s:%s", method, uri);
                    
                    uint16_t a1[16], a2[16];
                    crypt_md5_hash(a1pre, strlen(a1pre), a1, 16);
                    crypt_md5_hash(a2pre, strlen(a2pre), a2, 16);
                    
                    char ha1[33], ha2[33];
                    ha1[32] = ha2[32] = '\0';
                    hex_encode(a1, 16, ha1, 32);
                    hex_encode(a2, 16, ha2, 32);
                    
                    char finalpre[67 + strlen(rs->authentication_digest_nonce)];
                    sprintf(finalpre, "%s:%s:%s", ha1, rs->authentication_digest_nonce, ha2);
                    
                    uint16_t final[16];
                    crypt_md5_hash(finalpre, strlen(finalpre), final, 16);
                    
                    char hfinal[33];
                    hfinal[32] = '\0';
                    hex_encode(final, 16, hfinal, 32);
                    
                    for (int i = 0 ; i < 32 ; i++) {
                        hfinal[i] = tolower(hfinal[i]);
                        w_response[i] = tolower(w_response[i]);
                    }
                    
                    if (strcmp(hfinal, w_response) == 0)
                        ret = true;
                    else
                        log_message(LOG_INFO, "Authentication failure");
                    
                }
                
                parameters_destroy(parameters);
                
            }
            
        } else
            log_message(LOG_INFO, "Authentication header missing");
        
    }
    
    return ret;
    
}

void _rvop_session_get_apple_response(struct rvop_session_t* rs, const char* challenge, size_t challenge_length, char* response, size_t* response_length) {
    
    char decoded_challenge[1000];
    size_t actual_length = base64_decode(challenge, decoded_challenge);
    
    if (actual_length != 16)
        log_message(LOG_ERROR, "Apple-Challenge: Expected 16 bytes - got %d", actual_length);
    
    struct sockaddr* local_end_point = web_server_connection_get_local_end_point(rs->rvop_connection);
    uint64_t hw_identifier = hardware_identifier();
    
    size_t response_size = 32;
    char a_response[48]; // IPv6 responds with 48 bytes
    
    memset(a_response, 0, sizeof(a_response));
    
    if (local_end_point->sa_family == AF_INET6) {
        
        response_size = 48;
        
        memcpy(a_response, decoded_challenge, actual_length);
        memcpy(&a_response[actual_length], &((struct sockaddr_in6*)local_end_point)->sin6_addr, 16);
        memcpy(&a_response[actual_length + 16], &((char*)&hw_identifier)[2], 6);
        
    } else {
        
        memcpy(a_response, decoded_challenge, actual_length);
        memcpy(&a_response[actual_length], &((struct sockaddr_in*)local_end_point)->sin_addr.s_addr, 4);
        memcpy(&a_response[actual_length + 4], &((char*)&hw_identifier)[2], 6);
        
    }
    
    unsigned char clear_response[256];
    memset(clear_response, 0xFF, 256);
    clear_response[0] = 0;
    clear_response[1] = 1;
    clear_response[256 - (response_size + 1)] = 0;
    memcpy(&clear_response[256 - response_size], a_response, response_size);
    
    unsigned char encrypted_response[256];
    size_t size = crypt_apple_private_encrypt(clear_response, 256, encrypted_response, 256);
    
    if (size > 0) {
        
        char* a_encrypted_response;
        size_t a_len = base64_encode(encrypted_response, size, &a_encrypted_response);
        
        if (response != NULL)
            memcpy(response, a_encrypted_response, a_len);
        if (response_length != NULL)
            *response_length = a_len;
        
        free(a_encrypted_response);
        
    } else {
        log_message(LOG_ERROR, "Unable to encrypt Apple response");
        if (response_length != NULL)
            *response_length = 0;
    }
    
}

void _rvop_session_audio_queue_received_audio_callback(audio_queue_p aq, void* ctx) {
    
    struct rvop_session_t* rs = (struct rvop_session_t*)ctx;
    
    if (rs->dacp_client != NULL)
        dacp_client_update_playback_state(rs->dacp_client);
    
}

void _rvop_session_rvop_connection_request_callback(web_server_connection_p connection, web_request_p request, void* ctx) {
    
    struct rvop_session_t* rs = (struct rvop_session_t*)ctx;
    
    
    bool keep_alive = true;
    
    const char* cmd = web_request_get_method(request);
    const char* path = web_request_get_path(request);
    web_headers_p request_headers = web_request_get_headers(request);
    
    web_response_p response = web_response_create();
    web_headers_p response_headers = web_response_get_headers(response);
    
    const char* c_seq = web_headers_value(request_headers, "CSeq");
    
    web_response_set_status(response, 200, "OK");
    
    if (cmd != NULL && path != NULL) {
        
        parameters_p parameters = NULL;
        
        size_t content_length;
        if ((content_length = web_request_get_content(request, NULL, 0)) > 0) {
            
            const char* content_type = web_headers_value(request_headers, "Content-Type");
            
            if (strcmp(content_type, "application/sdp") == 0 || strcmp(content_type, "text/parameters") == 0) {
                
                char* content[content_length];
                
                web_request_get_content(request, content, content_length);
                
                content_length = web_tools_convert_new_lines(content, content_length);
                
                if (strcmp(content_type, "application/sdp") == 0)
                    parameters = parameters_create(content, content_length, parameters_type_sdp);
                else if (strcmp(content_type, "text/parameters") == 0)
                    parameters = parameters_create(content, content_length, parameters_type_text);
                
            }
            
        }
        
        mutex_lock(rs->mutex);
        
        const char *user_agent;
        
        if (rs->user_agent == NULL && (user_agent = web_headers_value(request_headers, "User-Agent")) != NULL) {
            rs->user_agent = (char*)malloc(strlen(user_agent) + 1);
            strcpy(rs->user_agent, user_agent);
        }
        
        struct rvop_rtp_session_t* rtp_session = rs->rtp_session;
        
        mutex_unlock(rs->mutex);
        
        web_headers_set_value(response_headers, "Server", "AirTunes/220.68");
        web_headers_set_value(response_headers, "CSeq",c_seq);
        
        if (_rvop_session_check_authentication(rs, cmd, path, web_headers_value(request_headers, "Authorization"))) {
            if (0 == strcmp(cmd, "POST") && 0 == strcmp(path, "/pair-setup")) {
                
                size_t size;
                uint8_t                     eid;
                const uint8_t *             ptr;
                size_t                      len;
                char *                      tmp;
                size = web_request_get_content(request, NULL, 0);
                const uint8_t src[size] ;
                size = web_request_get_content(request, src, size);
                const uint8_t *end  = src+size;
                
                pairInfo_t** inInfo = malloc(sizeof(pairInfo_t*));
                *inInfo = calloc(1, sizeof(pairInfo_t));
                
                
                printf("src:");
                for (int i = 0; i<size; i++) {
                    printf("%c",((char*)src)[i]);
                }
                
                while( TLVGetNext( src, end, &eid, &ptr, &len, &src ) == kNoErr )
                {
                    tmp = calloc( len + 1, sizeof( uint8_t ) );
                    memcpy( tmp, ptr, len );
                    
                    switch( eid )
                    {
                        case kTLVType_State:
                            printf("Recv: %s", stateDescription[*(uint8_t *)tmp]);
                            free(tmp);
                            break;
                        case kTLVType_Method:
                            printf("Recv: kTLVType_Method: %s", methodDescription[*(uint8_t *)tmp]);
                            free(tmp);
                            break;
                        case kTLVType_User:
                            (*inInfo)->SRPUser = tmp;
                            printf("Recv: kTLVType_User: %s", (*inInfo)->SRPUser);
                            break;
                        default:
                            free( tmp );
                            printf( "Warning: Ignoring unsupported pair setup EID 0x%02X", eid );
                            break;
                    }
                }

                
            }
        } else {
            
            mutex_lock(rs->mutex);
            
            char nonce[16];
            
            for (uint32_t i = 0 ; i < 16 ; i++)
                nonce[i] = (char) rand() % 256;
            
            hex_encode(nonce, 16, rs->authentication_digest_nonce, 32);
            rs->authentication_digest_nonce[32] = '\0';
            
            web_headers_set_value(response_headers, "WWW-Authenticate", "Digest realm=\"rvop\", nonce=\"%s\"", rs->authentication_digest_nonce);
            
            mutex_unlock(rs->mutex);
            
            web_response_set_status(response, 401, "Unauthorized");
            
        }
        
        const char* challenge;
        if ((challenge = web_headers_value(request_headers, "Apple-Challenge"))) {
            
            size_t a_res_size = 1000;
            char a_res[a_res_size];
            
            size_t challenge_length = strlen(challenge);
            char r_challange[challenge_length + 5];
            base64_pad(challenge, challenge_length, r_challange, challenge_length + 5);
            _rvop_session_get_apple_response(rs, r_challange, strlen(r_challange), a_res, &a_res_size);
            
            if (a_res_size > 0) {
                a_res[a_res_size] = '\0';
                web_headers_set_value(response_headers, "Apple-Response", "%s", a_res);
            }
            
        }
        
        web_headers_set_value(response_headers, "Audio-Jack-Status", "connected; type=digital");
        
        if (parameters != NULL)
            parameters_destroy(parameters);
        
    } else
        web_response_set_status(response, 400, "Bad Request");
    
    web_server_connection_send_response(rs->rvop_connection, response, "RTSP/1.0", !keep_alive);
    
    web_response_destroy(response);
    
}

void _rvop_session_rvop_closed_callback(web_server_connection_p connection, void* ctx) {
    
    struct rvop_session_t* rs = (struct rvop_session_t*)ctx;
    
    rvop_session_stop(rs);
    
}

struct rvop_session_t* rvop_session_create(rvop_server_p server, web_server_connection_p connection, settings_p settings) {
    
    struct rvop_session_t* rs = (struct rvop_session_t*)malloc(sizeof(struct rvop_session_t));
    bzero(rs, sizeof(struct rvop_session_t));
    
    rs->server = server;
    rs->rvop_connection = connection;
    rs->total_length = 0;
    rs->start_rtp_timestamp = 0;
    
    const char* password = settings_get_password(settings);
    if (password != NULL && strlen(password) > 0) {
        rs->password = (char*)malloc(strlen(password) + 1);
        strcpy(rs->password, password);
    }
    
    rs->ignore_source_volume = settings_get_ignore_source_volume(settings);
    
    web_server_connection_set_request_callback(rs->rvop_connection, _rvop_session_rvop_connection_request_callback, rs);
    web_server_connection_set_closed_callback(rs->rvop_connection, _rvop_session_rvop_closed_callback, rs);
    
    rs->mutex = mutex_create();
    
    return rs;
    
}

void rvop_session_destroy(struct rvop_session_t* rs) {
    
    mutex_lock(rs->mutex);
    
    if (rs->is_running) {
        mutex_unlock(rs->mutex);
        rvop_session_stop(rs);
        mutex_lock(rs->mutex);
    }
    
    if (rs->password != NULL) {
        free(rs->password);
        rs->password = NULL;
    }
    
    mutex_unlock(rs->mutex);
    
    mutex_destroy(rs->mutex);
    rs->mutex = NULL;
    
    free(rs);
    
}

void rvop_session_start(struct rvop_session_t* rs) {
    
    mutex_lock(rs->mutex);
    
    if (!rs->is_running)
        rs->is_running = true;
    
    mutex_unlock(rs->mutex);
    
}

void rvop_session_stop(struct rvop_session_t* rs) {
    
    bool stopped = false;
    
    mutex_lock(rs->mutex);
    
    if (rs->is_running) {
        
        web_server_connection_close(rs->rvop_connection);
        rs->is_running = false;
        stopped = true;
        
        if (rs->callbacks.ended != NULL) {
            mutex_unlock(rs->mutex);
            rs->callbacks.ended(rs, rs->callbacks.ctx.ended);
            mutex_lock(rs->mutex);
        }
        
    }
    
    if (rs->rtp_session != NULL){
        rtp_recorder_destroy(rs->rtp_session->recorder);
        audio_queue_destroy(rs->rtp_session->queue);
        free(rs->rtp_session);
        rs->rtp_session = NULL;
    }
    
    if (rs->decoder != NULL) {
        decoder_destroy(rs->decoder);
        rs->decoder = NULL;
    }
    
    if (rs->crypt_aes != NULL) {
        crypt_aes_destroy(rs->crypt_aes);
        rs->crypt_aes = NULL;
    }
    
    if (rs->dacp_client != NULL) {
        dacp_client_destroy(rs->dacp_client);
        rs->dacp_client = NULL;
    }
    
    if (rs->user_agent != NULL) {
        free(rs->user_agent);
        rs->user_agent = NULL;
    }
    
    mutex_unlock(rs->mutex);
    
    if (stopped)
        rvop_server_session_ended(rs->server, rs);
    
}

void rvop_session_set_client_initiated_callback(struct rvop_session_t* rs, rvop_session_client_initiated_callback callback, void* ctx) {
    
    rs->callbacks.initiated = callback;
    rs->callbacks.ctx.initiated = ctx;
    
}

void rvop_session_set_client_started_recording_callback(struct rvop_session_t* rs, rvop_session_client_started_recording_callback callback, void* ctx) {
    
    rs->callbacks.started_recording = callback;
    rs->callbacks.ctx.started_recording = ctx;
    
}

void rvop_session_set_client_updated_track_info_callback(struct rvop_session_t* rs, rvop_session_client_updated_track_info_callback callback, void* ctx) {
    
    rs->callbacks.updated_track_info = callback;
    rs->callbacks.ctx.updated_track_info = ctx;
    
}

void rvop_session_set_client_updated_track_position_callback(struct rvop_session_t* rs, rvop_session_client_updated_track_position_callback callback, void* ctx) {
    
    rs->callbacks.updated_track_position = callback;
    rs->callbacks.ctx.updated_track_position = ctx;
    
}

void rvop_session_set_client_updated_artwork_callback(struct rvop_session_t* rs, rvop_session_client_updated_artwork_callback callback, void* ctx) {
    
    rs->callbacks.updated_artwork = callback;
    rs->callbacks.ctx.updated_artwork = ctx;
    
}

void rvop_session_set_client_updated_volume_callback(rvop_session_p rs, rvop_session_client_updated_volume_callback callback, void* ctx) {
    
    rs->callbacks.updated_volume = callback;
    rs->callbacks.ctx.updated_volume = ctx;
    
}

void rvop_session_set_client_ended_recording_callback(struct rvop_session_t* rs, rvop_session_client_ended_recording_callback callback, void* ctx) {
    
    rs->callbacks.ended_recording = callback;
    rs->callbacks.ctx.ended_recording = ctx;
    
}

void rvop_session_set_ended_callback(struct rvop_session_t* rs, rvop_session_ended_callback callback, void* ctx) {
    
    rs->callbacks.ended = callback;
    rs->callbacks.ctx.ended = ctx;
    
}

bool rvop_session_is_recording(struct rvop_session_t* rs) {
    
    mutex_lock(rs->mutex);
    bool ret = (rs->rtp_session != NULL);
    mutex_unlock(rs->mutex);
    
    return ret;
    
}

dacp_client_p rvop_session_get_dacp_client(struct rvop_session_t* rs) {
    
    return rs->dacp_client;
    
}
