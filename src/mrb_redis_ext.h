/*
** mrb_redis_ext.h - Redis class extention
**
** See Copyright Notice in mrb_redis_ext.c
*/

#ifndef MRB_REDIS_EXT_H
#define MRB_REDIS_EXT_H

#include <hiredis/hiredis.h>

#define CREATE_REDIS_COMMAND_ARG1(argv, lens, cmd, arg1)                                                               \
  argv[0] = cmd;                                                                                                       \
  argv[1] = RSTRING_PTR(arg1);                                                                                         \
  lens[0] = strlen(cmd);                                                                                               \
  lens[1] = RSTRING_LEN(arg1)

#define DEFAULT_REPLY_HANDLING_RULE                                                                                    \
  {                                                                                                                    \
    .status_to_symbol = FALSE, .integer_to_bool = FALSE, .emptyarray_to_nil = FALSE, .return_exception = FALSE,        \
  }

typedef struct ReplyHandlingRule {
  mrb_bool status_to_symbol;
  mrb_bool integer_to_bool;
  mrb_bool emptyarray_to_nil;
  mrb_bool return_exception;
} ReplyHandlingRule;

static inline mrb_value mrb_redis_get_reply(redisReply *reply, mrb_state *mrb, const ReplyHandlingRule *rule);
static inline int mrb_redis_create_command_noarg(mrb_state *mrb, const char *cmd, const char **argv, size_t *lens);
static inline int mrb_redis_create_command_str(mrb_state *mrb, const char *cmd, const char **argv, size_t *lens);
static inline mrb_value mrb_redis_get_ary_reply(redisReply *reply, mrb_state *mrb, const ReplyHandlingRule *rule);
static inline redisContext *mrb_redis_get_context(mrb_state *mrb, mrb_value self);
static inline mrb_value mrb_redis_execute_command(mrb_state *mrb, mrb_value self, int argc, const char **argv,
                                                  const size_t *lens, const ReplyHandlingRule *rule);

#endif
