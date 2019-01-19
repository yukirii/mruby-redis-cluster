/*
** mrb_rediscluster.c - RedisCluster class
**
** Copyright (c) Yuki Kirii 2019
**
** See Copyright Notice in LICENSE
*/

#include "mruby.h"
#include "mruby/array.h"
#include "mruby/data.h"
#include "mruby/numeric.h"
#include "mruby/string.h"
#include "mrb_rediscluster.h"
#include "mrb_redis_ext.h"
#include <hiredis/hiredis.h>
#include <mruby/error.h>
#include <mruby/redis.h>
#include <string.h>

#define DONE mrb_gc_arena_restore(mrb, 0);

typedef struct {
  char *str;
  int len;
} mrb_rediscluster_data;

static const struct mrb_data_type mrb_rediscluster_data_type = {
  "mrb_rediscluster_data", mrb_free,
};

static mrb_value mrb_redis_cluster(mrb_state *mrb, mrb_value self)
{
  const char *argv[2];
  size_t lens[2];
  int argc = mrb_redis_create_command_str(mrb, "cluster", argv, lens);
  ReplyHandlingRule rule = DEFAULT_REPLY_HANDLING_RULE;
  return mrb_redis_execute_command(mrb, self, argc, argv, lens, &rule);
}

void mrb_mruby_redis_cluster_gem_init(mrb_state *mrb)
{
  struct RClass *redis;
  struct RClass *rediscluster;

  redis = mrb_define_class(mrb, "Redis", mrb->object_class);
  mrb_define_method(mrb, redis, "cluster", mrb_redis_cluster, MRB_ARGS_REQ(1));

  rediscluster = mrb_define_class(mrb, "RedisCluster", mrb->object_class);

  DONE;
}

void mrb_mruby_redis_cluster_gem_final(mrb_state *mrb)
{
}
