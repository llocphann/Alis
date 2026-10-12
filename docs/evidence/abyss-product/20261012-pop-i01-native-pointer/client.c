#include <wayland-client.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <time.h>
#include "pointer.h"
static struct zwlr_virtual_pointer_manager_v1 *manager;
static void global(void *data,struct wl_registry *registry,uint32_t name,const char *interface,uint32_t version){
 (void)data;
 if(!strcmp(interface,"zwlr_virtual_pointer_manager_v1"))manager=wl_registry_bind(registry,name,&zwlr_virtual_pointer_manager_v1_interface,version<2?version:2);
}
static void removed(void *data,struct wl_registry *registry,uint32_t name){(void)data;(void)registry;(void)name;}
static const struct wl_registry_listener listener={global,removed};
int main(int argc,char **argv){
 if(argc!=2 || !strcmp(argv[1],"wayland-1")){fprintf(stderr,"Explicit private display required\n");return 2;}
 struct wl_display *display=wl_display_connect(argv[1]);if(!display)return 3;
 struct wl_registry *registry=wl_display_get_registry(display);wl_registry_add_listener(registry,&listener,0);wl_display_roundtrip(display);
 if(!manager){puts("UNAVAILABLE virtual-pointer manager");wl_display_disconnect(display);return 77;}
 struct zwlr_virtual_pointer_v1 *pointer=zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager,0);wl_display_roundtrip(display);puts("READY compositor virtual pointer");fflush(stdout);
 unsigned x,y,w,h;while(scanf("%u %u %u %u",&x,&y,&w,&h)==4){
  struct timespec ts;clock_gettime(CLOCK_MONOTONIC,&ts);uint32_t ms=(uint32_t)(ts.tv_sec*1000+ts.tv_nsec/1000000);
  zwlr_virtual_pointer_v1_motion_absolute(pointer,ms,x,y,w,h);zwlr_virtual_pointer_v1_frame(pointer);if(wl_display_roundtrip(display)<0)break;puts("ACK");fflush(stdout);
 }
 zwlr_virtual_pointer_v1_destroy(pointer);zwlr_virtual_pointer_manager_v1_destroy(manager);wl_registry_destroy(registry);wl_display_flush(display);wl_display_disconnect(display);return 0;
}
