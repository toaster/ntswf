Gem::Specification.new do |s|
  s.author = 'Infopark AG'
  s.description = 'A layer around AWS SWF'
  s.email = 'info@infopark.de'
  s.files = Dir['READ*', 'LIC*', 'lib/**/*']
  s.homepage = 'https://github.com/infopark/ntswf'
  s.license = 'LGPL-3.0'
  s.name = 'ntswf'
  s.platform = Gem::Platform::RUBY
  s.required_ruby_version = '>= 1.9.3'
  s.summary = 'Not That Simple Workflow'
  s.version = '2.1.0'

  s.add_runtime_dependency 'aws-sdk', '~> 1.8'

  s.add_development_dependency 'rspec', '~> 2.14'
end
