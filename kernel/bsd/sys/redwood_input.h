#ifndef _SYS_REDWOOD_INPUT_H_
#define _SYS_REDWOOD_INPUT_H_

#include <sys/hakios.input.h>

#define REDWOOD_TOUCH_DOWN         HAKIOS_TOUCH_DOWN
#define REDWOOD_TOUCH_MOVE         HAKIOS_TOUCH_MOVE
#define REDWOOD_TOUCH_UP           HAKIOS_TOUCH_UP
#define REDWOOD_BUTTON_DOWN        HAKIOS_BUTTON_DOWN
#define REDWOOD_BUTTON_UP          HAKIOS_BUTTON_UP
#define REDWOOD_BUTTON_LOCK        HAKIOS_BUTTON_LOCK
#define REDWOOD_BUTTON_VOLUME_UP   HAKIOS_BUTTON_VOLUME_UP
#define REDWOOD_BUTTON_VOLUME_DOWN HAKIOS_BUTTON_VOLUME_DOWN
#define REDWOOD_BUTTON_HOME        HAKIOS_BUTTON_HOME

#define redwood_touch              hakios_touch
#define redwood_touch_post         hakios_touch_post
#define REDWOOD_CONNSYS_EMI_PHYS   0x51000000u

#endif /* _SYS_REDWOOD_INPUT_H_ */
