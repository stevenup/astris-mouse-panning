#ifndef ASTRIS_MOUSE_CALLBACKS_H
#define ASTRIS_MOUSE_CALLBACKS_H

#include <stdint.h>
#include <stdbool.h>

// 由 AstrisMouse.swift 通过 @_cdecl 实现，仅供 interpose.c 调用。
bool am_on_stick_axis(int32_t controller, int32_t stick, float x, float y);
void am_on_button_pressed(int32_t controller, int32_t button, int32_t pressed);
void am_before_connect_controller(const char *id);
void am_on_connect_controller(const char *id, const char *name, int32_t handle);
void am_on_disconnect_controller(const char *id);
bool am_on_keyboard_key_pressed(int32_t key, int32_t pressed);
void am_before_stop_emulation(void);
// 返回 malloc 出来的替换 JSON（调用方 free），不需要改写时返回 NULL
char *am_rewrite_options(const char *json);
void am_bootstrap(void);

#endif
