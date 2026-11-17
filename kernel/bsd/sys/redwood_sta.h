#ifndef _SYS_REDWOOD_STA_H_
#define _SYS_REDWOOD_STA_H_

#include <sys/hakios.sta.h>

#define REDWOOD_STA_ELEMENTS_MOST HAKIOS_STA_ELEMENTS_MOST
#define redwood_sta_bss           hakios_sta_bss
#define redwood_sta_scan          hakios_sta_scan
#define redwood_sta_join          hakios_sta_join
#define redwood_sta_state         hakios_sta_state
#define redwood_sta_ops           hakios_sta_ops
#define redwood_sta_attach        hakios_sta_attach
#define redwood_sta_lost          hakios_sta_lost

#endif /* _SYS_REDWOOD_STA_H_ */
