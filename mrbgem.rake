MRuby::Gem::Specification.new('mruby-redis-cluster') do |spec|
  spec.license = 'MIT'
  spec.authors = 'Yuki Kirii'
  spec.summary = 'Client library for Redis Cluster based on mruby-redis'
  spec.version = '0.0.1'

  # for expire test
  require 'open3'

  def run_command env, command
    STDOUT.sync = true
    puts "build: [exec] #{command}"
    Open3.popen2e(env, command) do |stdin, stdout, thread|
      print stdout.read
      fail "#{command} failed" if thread.value != 0
    end
  end

  # dependency - mruby-metaprog
  spec.add_dependency 'mruby-metaprog', core: 'mruby-metaprog'

  # dependency - mruby-metaprog
  spec.add_dependency 'mruby-random', core: 'mruby-random'

  # dependency - mruby-string-ext
  spec.add_dependency 'mruby-string-ext', core: 'mruby-string-ext'

  # dependency - mruby-redis
  spec.add_dependency('mruby-redis', :github => 'matsumoto-r/mruby-redis')
  mrb_redis_dir = File.expand_path("#{build_dir}/../../../mrbgems/mruby-redis")

  # dependency - hiredis
  hiredis_dir = "#{build_dir}/hiredis"
  FileUtils.mkdir_p build_dir

  if ! File.exists? hiredis_dir
    Dir.chdir(build_dir) do
      e = {}
      run_command e, 'git clone git://github.com/redis/hiredis.git'
      # Latest HIREDIS is not compatible for OS X
      run_command e, "git --git-dir=#{hiredis_dir}/.git --work-tree=#{hiredis_dir} checkout v0.13.3" if `uname` =~ /Darwin/
    end
  end

  if ! File.exists? "#{hiredis_dir}/libhiredis.a"
    Dir.chdir hiredis_dir do
      e = {
        'CC' => "#{spec.build.cc.command} #{spec.build.cc.flags.reject {|flag| flag == '-fPIE'}.join(' ')}",
        'CXX' => "#{spec.build.cxx.command} #{spec.build.cxx.flags.join(' ')}",
        'LD' => "#{spec.build.linker.command} #{spec.build.linker.flags.join(' ')}",
        'AR' => spec.build.archiver.command,
        'PREFIX' => hiredis_dir
      }

      run_command e, "make"
      run_command e, "make install"
    end
  end

  # build settings
  spec.linker.flags_before_libraries << "#{hiredis_dir}/lib/libhiredis.a"
  spec.cc.include_paths << "#{hiredis_dir}/include"
  spec.cc.include_paths << "#{mrb_redis_dir}/include"

  # dependency - mruby-logger
  spec.add_dependency 'mruby-logger', :github => 'katzer/mruby-logger'

  # test dependency - mruby-mock
  spec.add_test_dependency 'mruby-mock', :github => 'iij/mruby-mock'
end
