#ifndef ASTRIS_MOUSE_BRIDGE_H
#define ASTRIS_MOUSE_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>
#include <notify.h>

// libryujinx.dylib 导出的 C 接口（签名由反汇编确认，Astris 1.0.32）。
// 在本 dylib 内直接调用这些符号 = 调用原始实现（dyld interpose 不影响拦截者自身）。
void    ryujinx_set_controller_stick_axis(int32_t controller, int32_t stick, float x, float y);
void    ryujinx_set_controller_button_pressed(int32_t controller, int32_t button, int32_t pressed);
int32_t ryujinx_connect_controller(const char *id, const char *name);
void    ryujinx_disconnect_controller(const char *id);
void    ryujinx_set_keyboard_key_pressed(int32_t key, int32_t pressed);
int32_t ryujinx_stop_emulation(void);

#endif
