#include "WalnutSPAKE2.h"
#include <openssl/curve25519.h>

WalnutSPAKE2 *walnut_spake2_new(bool client,
                               const uint8_t *local_id, size_t local_id_length,
                               const uint8_t *peer_id, size_t peer_id_length) {
    return SPAKE2_CTX_new(client ? spake2_role_alice : spake2_role_bob,
                          local_id, local_id_length, peer_id, peer_id_length);
}

void walnut_spake2_free(WalnutSPAKE2 *context) {
    SPAKE2_CTX_free(context);
}

bool walnut_spake2_generate(WalnutSPAKE2 *context, const uint8_t *password,
                            size_t password_length, uint8_t *message, size_t message_length) {
    size_t written = 0;
    return message_length == SPAKE2_MAX_MSG_SIZE &&
        SPAKE2_generate_msg(context, message, &written, message_length, password, password_length) == 1 &&
        written == message_length;
}

bool walnut_spake2_finish(WalnutSPAKE2 *context, const uint8_t *peer_message,
                          size_t peer_length, uint8_t *key, size_t key_length) {
    size_t written = 0;
    return peer_length == SPAKE2_MAX_MSG_SIZE && key_length == SPAKE2_MAX_KEY_SIZE &&
        SPAKE2_process_msg(context, key, &written, key_length, peer_message, peer_length) == 1 &&
        written == key_length;
}
