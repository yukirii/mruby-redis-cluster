/*
** mrb_rediscluster.c - RedisCluster class
**
** Copyright (c) Yuki Kirii 2019
**
** See Copyright Notice in LICENSE
**
** This source code contains functinos copied from mrb_redis:
**
** mrb_redis - redis class for mruby
**
** Copyright (c) mod_mruby developers 2012-
**
** Permission is hereby granted, free of charge, to any person obtaining
** a copy of this software and associated documentation files (the
** "Software"), to deal in the Software without restriction, including
** without limitation the rights to use, copy, modify, merge, publish,
** distribute, sublicense, and/or sell copies of the Software, and to
** permit persons to whom the Software is furnished to do so, subject to
** the following conditions:
**
** The above copyright notice and this permission notice shall be
** included in all copies or substantial portions of the Software.
**
** THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
** EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
** MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
** IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
** CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
** TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
** SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
**
** [ MIT license: http://www.opensource.org/licenses/mit-license.php ]
*/

#include "mruby.h"
#include "mruby/array.h"
#include "mruby/data.h"
#include "mruby/numeric.h"
#include "mruby/string.h"
#include "mrb_rediscluster.h"
#include <hiredis/hiredis.h>
#include <mruby/error.h>
#include <mruby/redis.h>
#include <string.h>

#define DONE mrb_gc_arena_restore(mrb, 0);

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

static inline mrb_value mrb_redis_get_reply(redisReply *reply, mrb_state *mrb, const ReplyHandlingRule *rule)
{
  switch (reply->type) {
  case REDIS_REPLY_STRING:
    return mrb_str_new(mrb, reply->str, reply->len);
    break;
  case REDIS_REPLY_ARRAY:
    return mrb_redis_get_ary_reply(reply, mrb, rule);
    break;
  case REDIS_REPLY_INTEGER: {
    if (rule->integer_to_bool)
      return mrb_bool_value(reply->integer);
    else if (FIXABLE(reply->integer))
      return mrb_fixnum_value(reply->integer);
    else
      return mrb_float_value(mrb, reply->integer);
  } break;
  case REDIS_REPLY_NIL:
    return mrb_nil_value();
    break;
  case REDIS_REPLY_STATUS: {
    if (rule->status_to_symbol) {
      mrb_sym status = mrb_intern(mrb, reply->str, reply->len);
      return mrb_symbol_value(status);
    } else {
      return mrb_str_new(mrb, reply->str, reply->len);
    }
  } break;
  case REDIS_REPLY_ERROR: {
    mrb_value err = mrb_str_new(mrb, reply->str, reply->len);
    mrb_value exc = mrb_exc_new_str(mrb, E_REDIS_REPLY_ERROR, err);
    if (rule->return_exception) {
      return exc;
    } else {
      freeReplyObject(reply);
      mrb_exc_raise(mrb, exc);
    }
  } break;
  default:
    freeReplyObject(reply);
    mrb_raise(mrb, E_REDIS_ERROR, "unknown reply type");
  }
}

static inline mrb_value mrb_redis_get_ary_reply(redisReply *reply, mrb_state *mrb, const ReplyHandlingRule *rule)
{
  if (rule->emptyarray_to_nil && reply->elements == 0) {
    return mrb_nil_value();
  }
  mrb_value ary = mrb_ary_new_capa(mrb, reply->elements);
  int ai = mrb_gc_arena_save(mrb);
  size_t element_couter;
  for (element_couter = 0; element_couter < reply->elements; element_couter++) {
    mrb_value element = mrb_redis_get_reply(reply->element[element_couter], mrb, rule);
    mrb_ary_push(mrb, ary, element);
    mrb_gc_arena_restore(mrb, ai);
  }
  return ary;
}

static inline int mrb_redis_create_command_noarg(mrb_state *mrb, const char *cmd, const char **argv, size_t *lens)
{
  argv[0] = cmd;
  lens[0] = strlen(cmd);
  return 1;
}
static inline int mrb_redis_create_command_str(mrb_state *mrb, const char *cmd, const char **argv, size_t *lens)
{
  mrb_value str1;
  mrb_get_args(mrb, "S", &str1);
  CREATE_REDIS_COMMAND_ARG1(argv, lens, cmd, str1);
  return 2;
}

static inline redisContext *mrb_redis_get_context(mrb_state *mrb, mrb_value self)
{
  redisContext *context = DATA_PTR(self);
  if (!context) {
    mrb_raise(mrb, E_REDIS_ERR_CLOSED, "connection is already closed or not initialized yet.");
  }
  return context;
}

static inline mrb_value mrb_redis_execute_command(mrb_state *mrb, mrb_value self, int argc, const char **argv,
                                                  const size_t *lens, const ReplyHandlingRule *rule)
{
  mrb_value ret;
  redisReply *reply;
  redisContext *context = mrb_redis_get_context(mrb, self);

  reply = redisCommandArgv(context, argc, argv, lens);
  if (!reply) {
    mrb_raise(mrb, E_REDIS_ERROR, "could not read reply");
  }

  ret = mrb_redis_get_reply(reply, mrb, rule);
  freeReplyObject(reply);
  return ret;
}


static mrb_value mrb_redis_cluster(mrb_state *mrb, mrb_value self)
{
  const char *argv[2];
  size_t lens[2];
  int argc = mrb_redis_create_command_str(mrb, "cluster", argv, lens);
  ReplyHandlingRule rule = DEFAULT_REPLY_HANDLING_RULE;
  return mrb_redis_execute_command(mrb, self, argc, argv, lens, &rule);
}

static mrb_value mrb_redis_asking(mrb_state *mrb, mrb_value self)
{
  const char *argv[1];
  size_t lens[1];
  int argc = mrb_redis_create_command_noarg(mrb, "asking", argv, lens);
  ReplyHandlingRule rule = DEFAULT_REPLY_HANDLING_RULE;
  return mrb_redis_execute_command(mrb, self, argc, argv, lens, &rule);
}

void mrb_mruby_redis_cluster_gem_init(mrb_state *mrb)
{
  struct RClass *redis;

  redis = mrb_define_class(mrb, "Redis", mrb->object_class);
  mrb_define_method(mrb, redis, "cluster", mrb_redis_cluster, MRB_ARGS_REQ(1));
  mrb_define_method(mrb, redis, "asking", mrb_redis_asking, MRB_ARGS_NONE());

  DONE;
}

void mrb_mruby_redis_cluster_gem_final(mrb_state *mrb)
{
}
