#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint mopro_flutter.podspec` to validate before publishing.
#

Pod::Spec.new do |s|
  s.name             = 'mopro_flutter'
  s.version          = '0.0.1'
  s.summary          = 'Mopro Flutter plugin — Groth16 + Barretenberg proving.'
  s.description      = <<-DESC
  Flutter plugin that wraps the Deimos proving bindings. Groth16 (plus
  RISC0/Cairo-M/ProveKit) and Barretenberg are each vendored as a separate
  XCFramework so their UniFFI scaffolding does not collide at Swift link time.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'

  # Vendor both frameworks
  s.vendored_frameworks = 'Frameworks/MoproGroth16Bindings.xcframework', 'Frameworks/MoproBarretenbergBindings.xcframework'
  s.preserve_paths = 'Frameworks/MoproGroth16Bindings.xcframework/**/*', 'Frameworks/MoproBarretenbergBindings.xcframework/**/*'

  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/Frameworks/MoproGroth16Bindings.xcframework/ios-arm64/Headers/deimos_groth16" "$(PODS_TARGET_SRCROOT)/Frameworks/MoproBarretenbergBindings.xcframework/ios-arm64/Headers/deimos_barretenberg"',
    'OTHER_SWIFT_FLAGS' => '-Xcc -fmodule-map-file="$(PODS_TARGET_SRCROOT)/Frameworks/MoproGroth16Bindings.xcframework/ios-arm64/Headers/deimos_groth16/module.modulemap" -Xcc -fmodule-map-file="$(PODS_TARGET_SRCROOT)/Frameworks/MoproBarretenbergBindings.xcframework/ios-arm64/Headers/deimos_barretenberg/module.modulemap"'
  }
  s.swift_version = '5.0'
end
