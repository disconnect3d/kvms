#include <sys/time.h>
#include <sys/types.h>
#include <string.h>
#include <stdint.h>
#include "helpers.h"

#define SECONDS      1
#define MILLISECONDS 1000
#define MICROSECONDS 1000000
#define NANOSECONDS  1000000000

static struct timeval boot_ts;

int __gettimeofday(struct timeval *tv, void *tz)
{
	uint64_t cntptval_org;
	uint64_t cntfrq_org;
	uint64_t val;

	memset(tv, 0, sizeof(*tv));
	cntfrq_org = read_reg(CNTFRQ_EL0);
	cntptval_org = read_reg(CNTPCT_EL0);

	val = cntptval_org * MICROSECONDS;
	val = val / cntfrq_org;
	tv->tv_usec = val;

	val = cntptval_org * SECONDS;
	val = val / cntfrq_org;
	tv->tv_sec = val;

	return 0;
}

int gettimeofday(struct timeval *tv, void *tz)
{
	__gettimeofday(tv, NULL);

	if (!boot_ts.tv_usec)
		memcpy(&boot_ts, tv, sizeof(boot_ts));

	if (tv->tv_usec < boot_ts.tv_usec)
		memcpy(&boot_ts, tv, sizeof(boot_ts));

	tv->tv_usec -= boot_ts.tv_usec;
	tv->tv_sec  -= boot_ts.tv_sec;

	return 0;
}

int usleep(useconds_t usec)
{
	struct timeval now;
	struct timeval then;
	int r;

	r = gettimeofday(&now, 0);
	if (r)
		return r;

	memcpy(&then, &now, sizeof(struct timeval));
	then.tv_usec += usec;

	while(now.tv_usec < then.tv_usec) {
		wfe();
		r = gettimeofday(&now, 0);
		if (r)
			return r;
	}
	return 0;
}
