#define _GNU_SOURCE
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include <linux/input-event-codes.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>
#include "pointer.h"
#include "keyboard.h"
static struct zwlr_virtual_pointer_manager_v1 *manager;
static struct zwp_virtual_keyboard_manager_v1 *keymanager;
static struct wl_seat *seat;
static void caps(void*d,struct wl_seat*s,uint32_t c){(void)d;(void)s;(void)c;}
static void seatname(void*d,struct wl_seat*s,const char*n){(void)d;(void)s;(void)n;}
static const struct wl_seat_listener seatlistener={caps,seatname};
static void global(void*d,struct wl_registry*r,uint32_t n,const char*i,uint32_t v){
 (void)d;
 if(!strcmp(i,"zwlr_virtual_pointer_manager_v1"))manager=wl_registry_bind(r,n,&zwlr_virtual_pointer_manager_v1_interface,v<2?v:2);
 if(!strcmp(i,"zwp_virtual_keyboard_manager_v1"))keymanager=wl_registry_bind(r,n,&zwp_virtual_keyboard_manager_v1_interface,1);
 if(!strcmp(i,"wl_seat")&&!seat){seat=wl_registry_bind(r,n,&wl_seat_interface,1);wl_seat_add_listener(seat,&seatlistener,0);}
}
static void removed(void*d,struct wl_registry*r,uint32_t n){(void)d;(void)r;(void)n;}
static const struct wl_registry_listener listener={global,removed};
static uint32_t stamp(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return (uint32_t)(t.tv_sec*1000+t.tv_nsec/1000000);}
int main(int argc,char**argv){
 if(argc!=3||!*argv[1]||!*argv[2]||strchr(argv[1],'/')||strchr(argv[2],'/')||!strcmp(argv[1],argv[2]))return 2;
 char privatepath[4096],parentpath[4096];const char*runtime=getenv("XDG_RUNTIME_DIR");if(!runtime)return 2;
 snprintf(privatepath,sizeof privatepath,"%s/%s",runtime,argv[1]);snprintf(parentpath,sizeof parentpath,"%s/%s",runtime,argv[2]);struct stat a,b;
 if(stat(privatepath,&a)||stat(parentpath,&b)||!S_ISSOCK(a.st_mode)||!S_ISSOCK(b.st_mode)||(a.st_dev==b.st_dev&&a.st_ino==b.st_ino))return 2;
 struct wl_display*display=wl_display_connect(argv[1]);if(!display)return 3;
 struct wl_registry*r=wl_display_get_registry(display);wl_registry_add_listener(r,&listener,0);wl_display_roundtrip(display);
 if(!manager||!keymanager||!seat){puts("UNAVAILABLE virtual input");return 77;}
 struct zwlr_virtual_pointer_v1*p=zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager,seat);
 struct zwp_virtual_keyboard_v1*k=zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(keymanager,seat);
 struct xkb_context*context=xkb_context_new(XKB_CONTEXT_NO_FLAGS);struct xkb_rule_names names={.layout="us"};
 struct xkb_keymap*map=xkb_keymap_new_from_names(context,&names,XKB_KEYMAP_COMPILE_NO_FLAGS);if(!map)return 4;
 char*text=xkb_keymap_get_as_string(map,XKB_KEYMAP_FORMAT_TEXT_V1);int fd=memfd_create("alis-native-test-keymap",MFD_CLOEXEC);size_t size=strlen(text)+1;
 if(fd<0||ftruncate(fd,size)||write(fd,text,size)!=(ssize_t)size)return 4;
 zwp_virtual_keyboard_v1_keymap(k,WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1,fd,size);close(fd);free(text);xkb_keymap_unref(map);xkb_context_unref(context);
 wl_display_roundtrip(display);puts("READY private compositor input");fflush(stdout);
 char line[200];unsigned x,y,w,h,button,state;unsigned down=0;int keydown=0;
 while(fgets(line,sizeof line,stdin)){
  if(sscanf(line,"M %u %u %u %u",&x,&y,&w,&h)==4&&w&&h&&x<=w&&y<=h)zwlr_virtual_pointer_v1_motion_absolute(p,stamp(),x,y,w,h);
  else if(sscanf(line,"B %u %u",&button,&state)==2&&(button==BTN_LEFT||button==BTN_RIGHT)&&state<=1){zwlr_virtual_pointer_v1_button(p,stamp(),button,state);down=state?button:0;}
  else if(sscanf(line,"K %u",&state)==1&&state<=1){zwp_virtual_keyboard_v1_key(k,stamp(),KEY_ESC,state);keydown=state;}
  else break;
  zwlr_virtual_pointer_v1_frame(p);if(wl_display_roundtrip(display)<0)break;puts("ACK");fflush(stdout);
 }
 if(down)zwlr_virtual_pointer_v1_button(p,stamp(),down,0);
 if(keydown)zwp_virtual_keyboard_v1_key(k,stamp(),KEY_ESC,0);
 zwlr_virtual_pointer_v1_frame(p);zwlr_virtual_pointer_v1_destroy(p);zwp_virtual_keyboard_v1_destroy(k);zwlr_virtual_pointer_manager_v1_destroy(manager);wl_proxy_destroy((struct wl_proxy*)keymanager);wl_seat_destroy(seat);wl_registry_destroy(r);wl_display_flush(display);wl_display_disconnect(display);return 0;
}
