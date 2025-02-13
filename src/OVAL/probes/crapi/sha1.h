/*
 * Copyright 2010 Red Hat Inc., Durham, North Carolina.
 * All Rights Reserved.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *
 * Authors:
 *      "Daniel Kopecek" <dkopecek@redhat.com>
 */
#pragma once
#ifndef CRAPI_SHA1_H
#define CRAPI_SHA1_H

#include <stddef.h>

#ifdef OPENSCAP_ENABLE_SHA1

void *crapi_sha1_init (void *dst, void *size);
int   crapi_sha1_update (void *ctxp, void *bptr, size_t blen);
int   crapi_sha1_fini (void *ctxp);
void  crapi_sha1_free (void *ctxp);

int crapi_sha1_fd (int fd, void *dst, size_t *size);

#endif /* OPENSCAP_ENABLE_SHA1 */

#endif /* CRAPI_SHA1_H */
