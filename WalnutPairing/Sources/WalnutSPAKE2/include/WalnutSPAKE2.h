#ifndef WALNUT_SPAKE2_H
#define WALNUT_SPAKE2_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct spake2_ctx_st WalnutSPAKE2;

WalnutSPAKE2 *walnut_spake2_new(bool client,
                               const uint8_t *local_id, size_t local_id_length,
                               const uint8_t *peer_id, size_t peer_id_length);
void walnut_spake2_free(WalnutSPAKE2 *context);
bool walnut_spake2_generate(WalnutSPAKE2 *context, const uint8_t *password,
                            size_t password_length, uint8_t *message, size_t message_length);
bool walnut_spake2_finish(WalnutSPAKE2 *context, const uint8_t *peer_message,
                          size_t peer_length, uint8_t *key, size_t key_length);

#ifdef __cplusplus
}
#endif

#endif
