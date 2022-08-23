// SPDX-License-Identifier: GPL-2.0-only

#ifndef __HOST_H__
#define __HOST_H__

#include <stdint.h>

/**
 * Swap a given page and store it's metadata in encrypted form
 *
 * @param addr host stage1 address being swapped
 * @param paddr host physical address data is on
 * @return zero on success, negative errno otherwise
 */
int host_swap_page(uint64_t addr, uint64_t paddr);

/**
 * Restore a given page from swap and decrypt it
 *
 * @param addr host stage1 address being swapped
 * @param paddr host physical address data is on
 * @return zero on success, negative errno otherwise
 */
int host_restore_swap_page(uint64_t addr, uint64_t paddr);

#endif
