MRuby::Gem::Specification.new('mruby-redis-cluster') do |spec|
  spec.license = 'MIT'
  spec.authors = 'Yuki Kirii'
  spec.summary = 'Client library for Redis Cluster based on mruby-redis'
  spec.version = '0.0.1'

  # dependency - mruby-metaprog
  spec.add_dependency 'mruby-metaprog', core: 'mruby-metaprog'

  # dependency - mruby-metaprog
  spec.add_dependency 'mruby-random', core: 'mruby-random'

  # dependency - mruby-string-ext
  spec.add_dependency 'mruby-string-ext', core: 'mruby-string-ext'

  # dependency - mruby-redis
  spec.add_dependency 'mruby-redis', github: 'matsumoto-r/mruby-redis'

  # dependency - mruby-logger
  spec.add_dependency 'mruby-logger', github: 'katzer/mruby-logger'

  # test dependency - mruby-mock
  spec.add_test_dependency 'mruby-mock', github: 'iij/mruby-mock'
end
