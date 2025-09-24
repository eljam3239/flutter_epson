Pod::Spec.new do |s|
  s.name             = 'epson_printer_ios'
  s.version          = '0.0.1'
  s.summary          = 'iOS implementation of epson_printer'
  s.homepage         = 'https://github.com/eljam3239/flutter_epson'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Eli James' => 'your.email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Add the Epson frameworks
  s.vendored_frameworks = 'Frameworks/*.xcframework'
  
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end